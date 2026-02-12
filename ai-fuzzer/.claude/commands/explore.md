---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /explore — Screen Explorer

You are going to thoroughly explore whatever screen is currently showing in the connected iOS app. Your goal is to catalog every element, try every reasonable interaction, and report what you find.

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

Go through elements in order. For each interactive element:

### Elements with actions (activate, increment, decrement, custom)

1. Call `tap` on the element (by identifier if available, otherwise by order)
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

1. `tap` at the element's center coordinates (computed from frame)
2. Check if anything happened (interface changed)
3. Try `long_press` — some elements reveal context menus only on long press
4. Check if anything happened

### Swipe testing (on scrollable-looking containers)

If the tree structure shows `list` or `landmark` containers:
1. `swipe(direction: "up")` on the container area — check if new elements appear
2. `swipe(direction: "down")` — check if original elements return
3. Record any newly discovered elements from scrolling

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
