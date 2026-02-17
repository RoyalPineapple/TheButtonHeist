---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /explore — Screen Explorer

You are going to thoroughly explore whatever screen is currently showing in the connected iOS app. Your goal is to catalog every element, try every reasonable interaction, and report what you find.

## Step 0: Verify Connection + Check for Existing Session

1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app and try again
3. Print the connected device name and app name for confirmation
4. **Check for existing session**: List `session/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it to understand what's already been explored on this screen. Skip elements already covered. If starting fresh, create a new notes file: `session/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.md`

## Step 1: Observe the Current Screen

1. Call `get_screen` to see what's on screen.
2. Call `get_interface` to get the full element hierarchy.
3. Print a summary:
   - How many elements are on screen
   - List each element: `[order] label/description (identifier) — frame — actions`
   - Note the tree structure (containers, groups)

## Step 2: Baseline State

Record the current state as your baseline:
- Element count
- Element identifiers and values
- Screen capture visual state

## Step 3: Interact with Each Element

**Before starting**: Read your session notes file — check `## Coverage` for this screen to know which elements have already been tested. Skip those and pick up where you left off.

Go through elements in order. For each interactive element:

### Elements with actions (activate, increment, decrement, custom)

1. Call `activate` on the element (by identifier if available, otherwise by order) — this uses the accessibility API with live object references for reliable interaction
2. Call `get_interface` — compare with baseline:
   - If the **screen changed** (different elements appeared): record the transition, then navigate back. Use back buttons, "Close"/"Cancel" elements, or swipe right from left edge.
   - If the **screen is the same** but **values changed**: record the change as expected behavior.
   - If the **element disappeared** unexpectedly: record as ANOMALY.
3. If the element has `increment`/`decrement` in its actions:
   - Call `increment` — check the value changed
   - Call `decrement` — check the value changed back
4. If the element has custom actions:
   - Try each custom action via `perform_custom_action`
   - Record the result

### Elements without actions

1. `tap` at the element's center coordinates (computed from frame) — use `tap` as a fallback since these elements lack accessibility actions
2. Check if anything happened (interface changed)
3. Try `long_press` — some elements reveal context menus only on long press
4. Check if anything happened

### Text fields

If the element looks like a text input (text field, secure field, text editor):
1. `type_text(identifier: element, text: "test input")` — type a basic string
2. Check the returned value matches what you typed
3. `type_text(identifier: element, deleteCount: 10, text: "replaced")` — test delete + retype
4. Check the returned value is correct
5. Read `references/interesting-values.md` for curated test inputs. Try values from at least 3 categories (boundary numbers, unicode edge cases, injection strings, long strings, etc.). Use `deleteCount` to clear before each new value.

### Swipe testing (on scrollable-looking containers)

If the tree structure shows `list` or `landmark` containers:
1. `swipe(direction: "up")` on the container area — check if new elements appear
2. `swipe(direction: "down")` — check if original elements return
3. Record any newly discovered elements from scrolling

## Keeping Notes

Your notes are your memory. Both read AND write your session notes file throughout:

**Read your notes** before each action decision — check `## Coverage` to avoid repeating work, check `## Next Actions` to follow your plan.

**Write your notes** after each result:
- After each element interaction: update `## Coverage` to mark it tested
- After each finding: add to `## Findings`
- After each transition: add to `## Transitions`
- Every 5 elements: update `## Progress` and `## Next Actions`

This ensures you can resume if the session hits compaction.

## Step 4: Report Findings

After going through all elements, print a structured report:

```
## Screen Exploration Report

**Screen**: [description based on prominent elements]
**Elements found**: [count]
**Interactions tested**: [count]

### Transitions Discovered
- [element] → [new screen description]

### Findings
#### [SEVERITY] Description
- Action: [what you did]
- Expected: [what you expected]
- Actual: [what happened]

### Element Catalog
| Order | Label | Identifier | Value | Actions | Tested |
|-------|-------|-----------|-------|---------|--------|
| 0 | ... | ... | ... | ... | tap, activate |
```

## Error Handling

- If a tool call **fails with a connection error**: the app crashed. This is a CRASH finding. Record the last action and stop.
- If an action returns `success: false`: record the error method and message. Continue testing other elements.
- If you can't navigate back after a transition: record as INFO ("no back navigation from [screen]") and continue exploring from the new screen.
