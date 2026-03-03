# MCP Tool Response Examples

## Contents
- [get_interface response](#get_interface-response) — element structure and key fields
- [Reading the room: screen intent recognition](#reading-the-room-screen-intent-recognition) — form, list, settings examples
- [Delta interpretation](#delta-interpretation) — noChange, valuesChanged, elementsChanged, screenChanged
- [Detecting a crash](#detecting-a-crash) — MCP tool error signals
- [Detecting subtle bugs through intent](#detecting-subtle-bugs-through-intent) — context-aware anomaly detection
- [Prediction-driven testing in practice](#prediction-driven-testing-in-practice) — model→predict→validate→investigate cycle
- [Adjustable element values](#adjustable-element-values) — slider/stepper progression
- [Anti-patterns: what NOT to do](#anti-patterns-what-not-to-do) — canonical testing trap, reactive testing trap

---

How to interpret ButtonHeist MCP tool output — and how to use them to drive smart, varied testing.

## get_interface response

This is the JSON output from `get_interface`. Returns an `elements` array and a `tree` array. Each element has:

```json
{
  "identifier": "app.checkout.shippingAddress",
  "label": "Shipping Address",
  "value": "123 Main St",
  "frameX": 16.0,
  "frameY": 280.0,
  "frameWidth": 361.0,
  "frameHeight": 44.0,
  "actions": ["activate"]
}
```

Key fields:
- **identifier**: Stable across runs. Use for targeting when available.
- **label**: Human-readable text. Use for understanding what the element is *and what intent it serves*.
- **value**: Current value for adjustable elements (sliders show "50%", toggles show "0"/"1").
- **frame**: Position and size in points. Use for coordinate-based targeting.
- **actions**: Available accessibility actions. Elements with `["activate"]` are tappable. Elements with `["increment", "decrement"]` are adjustable.

## Reading the room: screen intent recognition

**Before testing individual elements, classify the screen.** Here's what that looks like in practice.

### Example: Recognizing a form

You call `get_interface` and see:
- `"Full Name"` text field (identifier: `profile.nameField`, value: empty)
- `"Email"` text field (identifier: `profile.emailField`, value: empty)
- `"Bio"` text editor (identifier: `profile.bioEditor`, value: empty)
- `"Save Profile"` button (actions: `["activate"]`)
- `"Cancel"` button (actions: `["activate"]`)

**This is a form.** Three text fields + Save + Cancel = data entry screen. Don't just type "Alice" into the name field and `<script>alert(1)</script>` into email. Instead:

1. **Happy path first**: Fill name with `María José García-López`, email with `maria+test@example.com`, bio with a two-line description → tap Save → check what happened (screen change? confirmation? values persisted?)
2. **Submit empty**: Clear all fields → tap Save → does it error? crash? succeed silently?
3. **Partial fill**: Fill only the name → tap Save → does it validate? which fields are required?
4. **Fill then abandon**: Fill all fields → tap Cancel → navigate back → reopen → are the fields empty or preserved?
5. **Then fuzz individual fields**: Name gets `O'Brien-Smith Jr.`, `X Æ A-12`, `信田`, a 200-char name. Email gets `a@b.c`, `user@localhost`, `"quoted"@example.com`. Bio gets 10KB of emoji.

### Example: Recognizing an item list

You call `get_interface` and see:
- An "Add" or "+" button
- Several similar elements with comparable structure (text + accessory views)
- Each item has a checkmark, disclosure indicator, or swipe action
- A count label at the bottom

**This is an item list.** Don't just tap each item independently. Test the lifecycle:

1. **Add → Verify**: Tap the add button → fill whatever form appears → submit → back to list → is the new item there? Does the count label update?
2. **Complete → Verify**: Tap a checkmark on one item → does it change visually? Does the count update?
3. **Delete → Verify**: Swipe or tap delete on another item → does it disappear? Count correct?
4. **Empty state**: Delete all items → what does the screen show? Is the delete button hidden?
5. **Then violate**: Try deleting when empty. Add an item with the same name as an existing one. Tap add then immediately tap delete. Complete an item then try to edit it.

### Example: Recognizing settings with dependencies

You call `get_interface` and see:
- Toggle: `"Enable Notifications"` (value: "1")
- Segmented control: `"Frequency"` with options "Hourly"/"Daily"/"Weekly"
- Toggle: `"Sound"` (value: "1")
- Toggle: `"Vibration"` (value: "0")
- Picker: `"Quiet Hours Start"` (value: "10:00 PM")

**This is a settings screen with dependencies.** The frequency, sound, vibration, and quiet hours probably depend on the notifications toggle. Test the chain:

1. **Verify dependency**: Toggle "Enable Notifications" off → do Frequency/Sound/Vibration/Quiet Hours disappear or become disabled?
2. **Change dependent, then disable parent**: Set Frequency to "Weekly", Sound off, Vibration on → toggle Notifications off → toggle Notifications back on → are the sub-settings preserved (Weekly, Sound off, Vibration on) or reset to defaults?
3. **Persistence**: Change Quiet Hours to "11:00 PM" → navigate away → return → still "11:00 PM"?
4. **Rapid toggle**: Toggle Notifications on/off 20x rapidly → final state matches expected parity?

## Delta interpretation

Every action tool returns an interface delta — here's how each kind maps to intent-driven testing.

### `noChange` — element is inert

```json
{"kind": "noChange"}
```

The element didn't respond. Usually a label or decorative element. **But context matters**: a "Submit" button on a form screen that returns `noChange` is suspicious — it should navigate or show validation errors. That's a potential ANOMALY if you've identified the screen as a form.

### `valuesChanged` — state updated

```json
{
  "kind": "valuesChanged",
  "valueChanges": [
    {"order": 5, "oldValue": "50", "newValue": "60"}
  ]
}
```

A value changed. **Check cross-element effects**: did changing element at order 5 also affect the value of element at order 8? On a settings screen, toggling one setting might silently change another. On a form, filling one field might auto-populate or validate another.

### `elementsChanged` — UI structure shifted

```json
{
  "kind": "elementsChanged",
  "added": [
    {"identifier": "settings.soundToggle", "label": "Sound", "order": 6}
  ],
  "removedOrders": [4]
}
```

Elements appeared or disappeared. **In context**: on a settings screen, this is a dependency reveal (toggling a parent showed child settings). On a list screen, this might be a new item after an add action. On a form, this might be a validation error appearing. The *intent* tells you whether this is expected or anomalous.

### `screenChanged` — navigated somewhere new

```json
{
  "kind": "screenChanged",
  "newInterface": { "elements": [...], "tree": [...] }
}
```

You're on a new screen. The full new interface is included. **Immediately classify it**: Is this the detail view for the list item you just tapped? A confirmation after submitting a form? An error screen? Identify the new screen's intent and plan appropriate tests.

## Detecting a crash

```
Tool: activate(identifier: "deleteButton")
Error: MCP tool returns isError: true with "Connection timed out" or "No devices found"
```

Any MCP tool error (connection error) after previously working = **CRASH**. The app died. Record immediately.

## Detecting subtle bugs through intent

### Behavioral anomalies in context

A screen has 8 elements. You tap `"saveButton"`. Before: `{saveButton, cancelButton, nameField, emailField}`. After: `{cancelButton, nameField, emailField}` — saveButton is GONE.

On a random screen, this is just "element disappeared." But if you've identified this as a **form**, this is a clear ANOMALY: the save button shouldn't vanish after saving. Did the save succeed? Did it fail silently? Was the button supposed to become disabled instead of disappearing?

### Cross-screen inconsistency

You edit an item's title on a detail screen. You go back to the list. The list still shows the old title.

Without intent recognition, you'd never test this — you'd fuzz the detail screen in isolation and the list screen in isolation. **With intent recognition**, you know detail and list are related and you test the full round-trip.

## Prediction-driven testing in practice

### Example: Building a model from what you see

You land on a screen and call `get_interface`. You see a text field, an add button (currently disabled — no actions), a count label showing "0", an empty-state message, and some filter/category buttons.

**Identify intent**: Item list. **Build model**:

```
State: {items: [], count: 0, filter: <first option>, emptyVisible: true}
Coupling: textField.text ↔ addButton.enabled, items.length → countLabel, items.length==0 → emptyLabel.visible
```

**Predict + Act**:

Action 1: Type into the text field
- **Predict**: addButton becomes enabled (gains actions), emptyLabel unchanged, count unchanged
- **Actual**: `valuesChanged` — addButton now has actions. **MATCH**.

Action 2: Activate the add button
- **Predict**: count 0→1, emptyLabel removed, textField cleared, addButton disabled again
- **Actual**: `elementsChanged` — new item element added, emptyLabel removed. `valuesChanged` — count updated, field cleared. **MATCH**.

Action 3: Navigate away then return
- **Predict**: items persist — count still shows 1, the item is still in the list
- **Actual**: count back to 0, empty-state message returned. **VIOLATED**.

**Investigate** (don't just record — probe deeper):
- **Reproduce**: Add another item, navigate away, return. Still empty. Consistent. (2/2)
- **Scope**: Do other screens persist state? Navigate to a different screen (settings, preferences), change something, leave, return. If that persists but the list doesn't — persistence is broken specifically for this screen's data.
- **Reduce**: Is it *all* state or just the items? Check: does the selected filter persist? If not, the entire screen state is ephemeral, not just the items.
- **Finding**: List state not persisted across navigation. Other screen state IS persisted. Confirmed with multiple reproductions.

Action 4: Observe the empty-state message pattern across filters
- **Predict**: If switching between filters shows "No {category} items" for the first two, predict the third follows the same pattern
- **Actual**: Two match the pattern, the third produces a grammatically broken string. **VIOLATED**.

**Investigate**:
- **Boundary**: The pattern works for N-1 filters. Only one breaks. Likely string interpolation without special-casing.
- **Finding**: Empty-state string template breaks for one specific filter value — grammatical error in the interpolated output.

The model made these findings *inevitable*. Predicting persistence meant the navigation bug was caught on first attempt, not by luck. Extrapolating the string pattern across filters caught a localization bug that element-by-element testing would never find.

## Adjustable element values

**Slider before increment**: value "50"
**After increment**: value "60"
**After 5 more increments**: value "100" (stops increasing — hit max)
**After decrement**: value "90"

Track the value progression. If increment past max wraps to 0, that's an ANOMALY. On a **settings screen**, also check: does this slider value affect anything elsewhere?

## Anti-patterns: what NOT to do

### The canonical testing trap

Bad (every session looks identical):
```
Text field "Name" → type "Alice"
Text field "Name" → clear, type "José 🎉"
Text field "Name" → clear, type "AAAA..." (100 chars)
Text field "Email" → type "user@example.com"
Text field "Email" → clear, type "<script>alert(1)</script>"
```

Good (intent-aware, varied, adversarial):
```
Identified screen as: Form (profile editor)
Happy path: Fill Name="María José García-López", Email="maria+test@example.com" → Save → verify
Submit empty: Clear all → Save → check for validation
Name adversarial: "Null", "X Æ A-12", "信田恵子", single char "M", 200-char real name
Email adversarial: "a@b.c", "user@192.168.1.1", "(spaces)@example.com"
Abandon: Fill all → Cancel → reopen → fields cleared?
```

The key difference: the first version picks from a generic list and tests each field in isolation. The second understands what the screen *is* and generates tests that exercise how it's supposed to work — and how it might break.

### The reactive testing trap

Bad (no predictions, no investigation):
```
activate addButton → elementsChanged, new element appeared. Looks fine.
navigate away → screenChanged. OK.
navigate back → screenChanged, list is empty. Hmm, that seems wrong? Filing as anomaly. Moving on.
```

Good (prediction-driven with investigation):
```
Model: items persist across navigation (Persistence prediction)
Predict: navigate away → return → count still shows 1, item still in list
Act: navigate away, return
Validate: count==0, list empty → PREDICTION VIOLATED
Investigate:
  Reproduce: add item, leave, return → still empty (2/2)
  Scope: does other screen state persist? Yes → persistence broken specifically for THIS screen
  Reduce: does filter selection also reset? Yes → entire screen state is ephemeral, not just items
Finding: Screen state not persisted. Other screens ARE persisted. Confirmed 3/3.
```

The first version *might* catch the bug and records a vague anomaly. The second *always* catches it, then probes to understand scope (which screens are affected), consistency (reproduction rate), and extent (all state vs just items).
