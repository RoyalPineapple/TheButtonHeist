# Button Heist: Agent Getting Started Guide

You're an AI agent about to drive an iOS app. This guide teaches you how to use Button Heist effectively — not just the commands, but the mental model behind them.

## Stop Thinking in Pixels

If you've used other iOS automation tools, forget what you learned. Here's what "tap the Sign In button" looks like with a coordinate-based tool:

1. Screenshot the screen
2. Send the screenshot to a vision model
3. The model says "the Sign In button is probably around (207, 443)"
4. Tap at (207, 443) and hope the button is actually there
5. Screenshot again
6. Send the new screenshot to the vision model
7. The model says "the screen looks different, I think it worked"

Here's the same task with Button Heist:

1. `activate` with `heistId: "sign-in-button"`
2. Read the delta: `screen changed → Dashboard`

That's not a simplified version. That's the actual call. One step to act, structured data back telling you exactly what happened. No screenshots, no vision model, no coordinate math, no guessing.

The coordinate approach is sticks and stones — you're looking at a *picture* of a button and estimating where to poke. Button Heist talks to the button directly.

### Why this works

Every iOS app already describes itself through the accessibility layer — the same interface that VoiceOver reads aloud for blind and low-vision users. Every control knows what it is, what it does, what state it's in, and how to interact with it. A button knows it's a button. A text field knows its placeholder, its current value, and that you can type in it. A stepper knows its value is "3" and that it has `increment` and `decrement` actions you can call by name.

Button Heist gives you direct access to this interface. When you call `activate`, you're not tapping at coordinates — you're calling `accessibilityActivate()` on the live UIKit object, the exact same code path VoiceOver uses when a blind user double-taps. When you call `get_interface`, you're not parsing a screenshot — you're reading structured data that the app maintains about itself.

### What this means for you

**Think in elements, not coordinates.** You don't need to know where a button is on screen. You need to know its label or traits, and once you've seen it, its heistId. `{"label": "Sign In", "traits": ["button"]}` hits the right control regardless of screen size, orientation, dynamic type setting, or layout shift. A coordinate that worked on iPhone 16 Pro is wrong on iPhone SE.

**Think in meaning, not appearance.** A vision model looking at pixels can see a switch is blue and on the left side. But it can't see that the switch is disabled, that its value is "1", that it has a trait of `[button]`, or that toggling it will fire a specific accessibility action. You can see all of that — it's in the element data. Use it.

**Think in actions, not gestures.** Don't think "I need to tap at (207, 443)." Think "I need to activate the Submit button." Don't think "I need to swipe right on row 3." Think "I need to call the 'Delete' custom action on the order-item element." The accessibility layer exposes named actions — `increment`, `decrement`, custom actions — that you can call directly. No coordinate math, no gesture simulation, no ambiguity about what you intended.

**Think in deltas, not re-observation.** After a coordinate tap, you have no idea what happened — you have to screenshot again and compare visually. After an `activate`, the response tells you exactly what changed: which elements appeared, which disappeared, which properties updated and from what to what. The app reports its own state changes. You don't have to infer them from pixels.

**Think in semantics, not workarounds.** Coordinate tools need workarounds for everything: wait 2 seconds for animations, add a retry loop for slow loads, adjust tap offsets for different devices, handle the keyboard covering elements. With the accessibility interface, `wait_for` polls on real UI settle events. `scroll_to_visible` finds elements by identity, not visual search. `activate` works on controls that have custom hit-test regions that would defeat a coordinate tap.

### The accessibility feedback loop

There's a second benefit: every interaction you make is an accessibility audit. If you can't find a control, neither can VoiceOver. If a button has no label, it's broken for you *and* for blind users. Coordinate-based tools never surface this — they'll happily tap unlabeled pixels that VoiceOver users can't reach. Button Heist won't, and that's a feature.

## The Core Loop

Every agent session follows the same rhythm:

1. **See** the screen → `get_interface`
2. **Act** on an element → `activate`, `type_text`, `scroll`, `swipe`
3. **Check** what changed → read the delta in the action response
4. Repeat

That's it. The entire API exists to make this loop fast and reliable.

## Connecting

Connect to the running app by named target or direct address:

```json
{"tool": "connect", "arguments": {"target": "sim"}}
{"tool": "connect", "arguments": {"device": "127.0.0.1:1455", "token": "my-task-slug"}}
```

Named targets come from a `.buttonheist.json` config file (in the working directory or `~/.config/buttonheist/config.json`):

```json
{
  "targets": {
    "sim": { "device": "127.0.0.1:1455", "token": "my-workspace-token" }
  },
  "default": "sim"
}
```

If a default target is set, the first command that needs a connection will auto-connect — no explicit `connect` call required.

## Reading the Screen

### Default: what's visible

```json
{"tool": "get_interface"}
```

Returns every element currently on screen. The response looks like:

```
14 elements
login-title "Welcome Back" [header]
email-field "Email" [textField] {tap}
password-field "Password" [textField] {tap}
login-button "Sign In" [button] {tap}
forgot-link "Forgot password?" [link] {tap}
```

Each line is one element. The first token is the **heistId** — a stable identifier for that element on the current screen. It won't change between refreshes or actions as long as the screen stays the same. After it: the label in quotes, the value (if any) after `=`, traits in `[]`, and available actions in `{}`.

### The visibility problem: scroll views hide elements

`get_interface` returns what's visible *right now*. But iOS apps are full of scroll views — lists, forms, collection views, nested scroll containers — and elements below the fold don't exist in the accessibility tree until they're scrolled into view. If you're looking at a long settings screen, you might see 12 elements, but there are 40 more waiting below the visible area.

This means an element you need to interact with might not show up in `get_interface` at all. It's not missing — it's just off-screen, and the system hasn't rendered it yet. You have three strategies for dealing with this:

**Strategy 1: Scroll to find it.** If you know what the element looks like (label, identifier, traits), `scroll_to_visible` will search for it automatically. It scrolls through every scrollable container on screen, checking after each scroll, and stops when the element appears:

```json
{"tool": "scroll_to_visible", "arguments": {"label": "Delete Account", "traits": ["button"]}}
```

This is the right choice when you know what you're looking for but don't know where it is. The response tells you how many scrolls it took and returns the element's heistId once found.

**Strategy 2: Full census.** If you need a complete inventory of everything on the screen — not just what's visible — use `get_interface` with `full: true`:

```json
{"tool": "get_interface", "arguments": {"full": true}}
```

This explores every scrollable container on screen: scrolling page by page to discover all off-screen content, then restoring the original scroll positions. You get back every element the screen contains, including ones that were never visible. The response includes stats on what the exploration found:

```json
{
  "explore": {
    "elementCount": 147,
    "scrollCount": 12,
    "containersExplored": 2,
    "explorationTime": 3.4
  }
}
```

Use `full: true` when you need to understand the entire screen before acting — surveying a long form, counting items in a list, or planning a multi-step interaction across elements that aren't all visible at once.

**Strategy 3: Scroll manually.** When you want more control, scroll explicitly and check the delta:

```json
{"tool": "scroll", "arguments": {"heistId": "settings-list", "direction": "down"}}
```

The delta shows you which elements appeared (`+`) and disappeared (`-`) as content scrolled in and out of view. You can scroll and inspect incrementally.

**When to use which:**
- You know the element's label → `scroll_to_visible`
- You need the full picture → `get_interface` with `full: true`
- You're exploring or want step-by-step control → `scroll` + read deltas
- The element is already visible → just use its heistId directly

### Filtering

You don't always need the full tree. Filter by heistId list, or by matcher predicates:

```json
{"tool": "get_interface", "arguments": {"label": "Sign In"}}
{"tool": "get_interface", "arguments": {"traits": ["button"]}}
{"tool": "get_interface", "arguments": {"elements": ["login-button", "email-field"]}}
```

### Detail levels

By default, geometry (frames, activation points) is omitted to save tokens. Request it when you need coordinates:

```json
{"tool": "get_interface", "arguments": {"detail": "full"}}
```

## Targeting Elements

Every interaction command accepts the same targeting options. There are two strategies, and understanding when to use each is critical.

### HeistIds: use what you were handed

A heistId is valid **only because you saw it in a response**. When `get_interface` or an action delta hands you `login-button`, you can use it to target that element — on that screen, right now:

```json
{"tool": "activate", "arguments": {"heistId": "login-button"}}
```

HeistIds are stable for the duration of the current screen. You can use them across multiple actions, refreshes, and `get_interface` calls without them changing — they're deterministic and consistent while the screen is alive. But when the screen changes — a navigation push, a modal, a tab switch — every heistId from the previous screen is invalid. Never cache them across screen transitions. Never predict what a heistId will be. Never construct one yourself. If you haven't seen it in a response from the current screen, it doesn't exist.

This means: after a `screen_changed` delta, your heistId inventory is whatever was in that delta's `newInterface`. Everything you knew from before is gone.

### Matchers: describe what you're looking for

When you don't have a heistId — because you haven't seen the screen yet, because you're looking for an element across a screen transition, or because you want to find something by its properties — use a matcher:

```json
{"tool": "activate", "arguments": {"label": "Sign In", "traits": ["button"]}}
```

Matcher fields: `label`, `identifier`, `value`, `traits`, `excludeTraits`. Strings must equal the matcher value, compared case-insensitively after typography folding (smart quotes/dashes/ellipsis fold to ASCII; emoji, accents, and CJK pass through). Traits match exactly (all listed traits must be present). Matching is **exact or miss** — partial labels miss. If the matcher hits zero elements you get a structured near-miss with suggestions ("did you mean 'Save Draft', 'Save All', 'Save As'?"), so you can refine the matcher with the actual label.

Matchers are the right tool when:
- You're targeting an element you haven't seen yet (`wait_for` with a label)
- You just navigated and need to find something on the new screen
- You're writing a batch that will cross screen boundaries
- You know what the element looks like (label, traits) but not its heistId

### Which to use

On the current screen, with elements you've already seen: **heistId**. Zero ambiguity, no matching logic, no risk of hitting the wrong "Submit" button if there are two.

Across screen transitions, for elements you haven't observed, or in `wait_for`/`scroll_to_visible` where the element may not exist yet: **matcher**.

## Acting on Elements

### Activate (the primary interaction)

```json
{"tool": "activate", "arguments": {"heistId": "login-button"}}
```

`activate` uses the accessibility-first path: it calls `accessibilityActivate()` (the same code path VoiceOver uses), then falls back to a synthetic tap. This works reliably across SwiftUI, UIKit, and custom controls. Use it for buttons, links, switches, cells — anything a user would tap.

For elements with named actions (steppers, sliders):
```json
{"tool": "activate", "arguments": {"heistId": "quantity-stepper", "action": "increment"}}
```

### Type text

```json
{"tool": "type_text", "arguments": {"heistId": "email-field", "text": "user@example.com"}}
```

Optionally clear the field first:
```json
{"tool": "type_text", "arguments": {"heistId": "email-field", "text": "new text", "clearFirst": true}}
```

### Scroll

Three flavors:

```json
// Scroll down one page in the element's nearest scrollable ancestor
{"tool": "scroll", "arguments": {"heistId": "some-element", "direction": "down"}}

// Keep scrolling until a specific element becomes visible
{"tool": "scroll_to_visible", "arguments": {"label": "Submit Order"}}

// Jump to an edge
{"tool": "scroll_to_edge", "arguments": {"heistId": "list-container", "edge": "bottom"}}
```

### Wait for state

```json
// Wait for an element to appear
{"tool": "wait_for", "arguments": {"label": "Success", "timeout": 10}}

// Wait for an element to disappear
{"tool": "wait_for", "arguments": {"heistId": "loading-spinner", "absent": true}}

// Wait for animations to settle
{"tool": "wait_for_idle", "arguments": {"timeout": 5}}
```

## Understanding Deltas

Every action response includes a **delta** — what changed in the UI as a result of your action. This is the key to working efficiently. You don't need to call `get_interface` after every action to see what happened.

A delta response looks like:

```
activate: elementsChanged (14 elements)
+ success-banner "Payment complete" [staticText]
~ total-label: value "$0.00" → "$47.99"
- loading-spinner
```

Three things can happen:
- `+` elements were **added**
- `-` elements were **removed** (by heistId)
- `~` elements were **updated** (property changed, with old → new values)

If the action caused a full screen change (navigation push, modal presentation), the delta kind is `screenChanged` and includes the complete new interface — no separate `get_interface` needed.

If nothing changed: `no change`.

**Use deltas to drive your next decision.** If you tapped a button and the delta shows a new screen, read the new elements from the delta. If the delta shows a value changed, you know the action worked. If the delta shows no change, something went wrong — investigate.

## Expectations: Say What You Care About

Expectations are lightweight, inline outcome checks. Attach one to any action to declare what you think should happen. The system checks the delta against your expectation and tells you if it matched. They're like on-the-fly unit tests — but dynamic and flexible, written at the moment you need them, not ahead of time.

### The validation model

The philosophy is **say what you care about, leave out what you don't**. Every field in an expectation is optional. You specify only the properties that matter for your assertion, and everything else is a wildcard. This is the opposite of rigid test assertions that break when unrelated things change.

Three levels of specificity:

**"Something should change"**
```json
{"tool": "activate", "arguments": {"heistId": "save-button", "expect": "elements_changed"}}
```
Met if any elements were added, removed, or updated. You're saying: "this action should do *something* visible."

**"We should navigate"**
```json
{"tool": "activate", "arguments": {"heistId": "next-button", "expect": "screen_changed"}}
```
Met only if the view controller identity changed (a push, modal, or tab switch). More specific than `elements_changed`.

**"A specific thing should change"**
```json
{
  "tool": "activate",
  "arguments": {
    "heistId": "quantity-stepper",
    "action": "increment",
    "expect": {
      "type": "element_updated",
      "heistId": "quantity-label",
      "property": "value",
      "oldValue": "1",
      "newValue": "2"
    }
  }
}
```

Every field on an `element_updated` expectation other than `type` is optional. You can mix and match:

- Just check that *something* changed on a specific element:
  ```json
  {"expect": {"type": "element_updated", "heistId": "quantity-label"}}
  ```
- Check that a property changed without caring about specific values:
  ```json
  {"expect": {"type": "element_updated", "property": "value"}}
  ```
- Check the new value without knowing the old:
  ```json
  {"expect": {"type": "element_updated", "heistId": "total", "property": "value", "newValue": "$47.99"}}
  ```

This is the "say what you care about" model. If you know the heistId but not the property, say so. If you know the expected new value but not the old one, say so. If you only know that *something* on *some element* should update, `"elements_changed"` covers it.

### What happens when expectations fail

The action still executes — expectations never prevent or roll back an action. On failure, the response includes a diagnostic:

```
activate: elementsChanged (14 elements)
~ other-label: value "x" → "y"
[expectation FAILED: got value: "x" → "y"]
```

The `actual` field tells you what *did* happen, so you can adapt. An unmet expectation is information, not an error — you decide what to do with it.

### When to use expectations

Use them whenever you have a hypothesis about what an action should do:

- **Navigating**: `"expect": "screen_changed"` after tapping a navigation link
- **Form filling**: `"expect": {"type": "element_updated", "heistId": "field-id", "property": "value"}` after typing
- **Toggling**: `"expect": {"type": "element_updated", "heistId": "switch-id", "property": "value", "newValue": "1"}` after flipping a switch
- **Deleting**: `"expect": "elements_changed"` after swiping to delete a row

Don't use them when you genuinely don't know what will happen (exploratory interaction). They're assertions, not discovery tools.

### Expectations vs. reading deltas

Deltas tell you *what* changed. Expectations tell you *whether what changed matches what you expected*. Use both:

1. Set an expectation for the thing you care about
2. Read the delta for the full picture
3. If the expectation fails, the delta tells you what actually happened

## Batching: Multiple Actions in One Call

`run_batch` sends a sequence of commands as a single request. Each step runs serially, and you get back per-step results plus a merged net delta across all steps.

```json
{
  "tool": "run_batch",
  "arguments": {
    "steps": [
      {"command": "activate", "heistId": "email-field"},
      {"command": "type_text", "text": "user@example.com", "expect": {"type": "element_updated", "property": "value"}},
      {"command": "activate", "heistId": "password-field"},
      {"command": "type_text", "text": "hunter2", "expect": {"type": "element_updated", "property": "value"}},
      {"command": "activate", "heistId": "login-button", "expect": "screen_changed"}
    ],
    "policy": "stop_on_error"
  }
}
```

### Why batch?

- **Fewer round trips.** Five actions in one call instead of five separate calls.
- **Atomic sequences.** With `stop_on_error` (default), the batch halts on the first failure — you don't blindly continue a login flow if the email field didn't accept input.
- **Net deltas.** The batch response merges all per-step deltas into a single net delta. An element added then removed within the batch nets to nothing. A property updated three times keeps the first `old` and last `new`. This gives you the *effective* change without intermediate noise.
- **Expectation summary.** The batch header shows `[expectations: 3/3]` — how many were checked and how many passed.

### Batch response

```
Login | batch: 5 steps in 847ms [expectations: 3/3]
  [0] activate → elementsChanged
  [1] type_text → elementsChanged ✓
  [2] activate → elementsChanged
  [3] type_text → elementsChanged ✓
  [4] activate → screenChanged ✓
net: screen changed
Dashboard | 8 elements
  ...
```

Each step shows its command, delta kind, and expectation result (`✓`/`✗`). The net delta at the bottom shows the cumulative effect.

### Batch policies

- `stop_on_error` (default): Halts on the first step that fails or has an unmet expectation. Remaining steps are skipped.
- `continue_on_error`: Runs all steps regardless. Use this when steps are independent and you want to see all results.

### What can go in a batch?

Any interaction command: `activate`, `type_text`, `scroll`, `scroll_to_visible`, `scroll_to_edge`, `swipe`, gesture commands, `edit_action`, `set_pasteboard`, `get_pasteboard`, `dismiss_keyboard`. You can also include `get_interface` and `get_screen` as steps.

## Efficient Agent Patterns

### Don't over-fetch

After an action, **read the delta first**. If the delta tells you everything you need (element appeared, value changed, screen navigated), skip the `get_interface` call. Only call `get_interface` when you need to discover elements you don't already know about.

### HeistIds on this screen, matchers across screens

Once you've seen an element in a `get_interface` response or action delta, use its heistId for interactions on that screen — it's unambiguous and fast. But remember: heistIds die on screen transitions. After a navigation push or modal, switch to matchers or read the new heistIds from the delta's `newInterface`. Never carry a heistId from one screen to the next.

### Batch predictable sequences

If you know the sequence of actions ahead of time (fill a form, navigate a flow), batch them. The round-trip savings compound, and the net delta gives you a cleaner signal than five individual deltas.

### Use expectations as guard rails

Attach expectations to actions where you have a clear hypothesis. They cost nothing when they pass and surface problems immediately when they don't. A batch with expectations is a self-verifying script — you'll know exactly which step diverged from your plan.

### Progressive disclosure

Start with `get_interface` (visible only). If you need more, filter by traits or labels. If the element isn't visible, try `scroll_to_visible`. If you need everything, use `full: true`. Each level costs more time — escalate only when the cheaper option isn't enough.

## Quick Reference

| Task | Tool | Key Parameters |
|------|------|----------------|
| Read visible UI | `get_interface` | `detail`, `label`, `traits` |
| Read all UI (scroll-discovered) | `get_interface` | `full: true` |
| Find off-screen element | `scroll_to_visible` | `label`/`identifier` |
| Tap/activate a control | `activate` | `heistId`, `action` |
| Type text | `type_text` | `heistId`, `text`, `clearFirst` |
| Scroll | `scroll` | `heistId`, `direction` |
| Wait for element | `wait_for` | `label`/`heistId`, `absent`, `timeout` |
| Run multiple actions | `run_batch` | `steps`, `policy` |
| Check what changed | *(read the delta in any action response)* | |
| Verify an outcome | *(add `expect` to any action)* | |
