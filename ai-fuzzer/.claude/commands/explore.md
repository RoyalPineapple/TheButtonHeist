---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /explore — Screen Explorer

You are tasked with thoroughly exploring whatever screen is currently showing in the connected iOS app. Catalog every element, try every reasonable interaction, and report what you find.

## CRITICAL
- Every action tool returns an interface delta JSON (`noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`) — use it instead of calling `get_interface` after actions
- On `screenChanged`, the delta includes the full new interface — no separate `get_interface` needed
- ALWAYS use `activate` before falling back to `tap` — accessibility API interaction is more reliable
- ALWAYS process elements in batches of 3-5 — plan multiple actions, execute them, then write files once
- DO NOT write trace/notes after every single action — batch your file I/O every 3-5 actions
- DO NOT call `get_screen` on every action — only for findings and new screens
- DO NOT skip elements without actions — tap and long-press may still reveal behavior

## Step 0: Verify Connection + Check for Existing Session

1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app and try again
3. Print the connected device name and app name for confirmation
4. **Check for existing session**: List `session/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it (including `## Navigation Stack`) to understand what's already been explored. Skip elements already covered. If starting fresh:
   - Create a new notes file: `session/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.md` (include `Trace file` and `Next finding ID: F-1` in `## Config`)
   - Create the companion trace file: `session/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.trace.md` with the header (see `references/trace-format.md`)
5. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. This gives you known transitions and back-routes from prior sessions.

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

Process elements in batches of 3-5. For each element:
1. Call `activate` (by identifier if available, otherwise by order)
2. Read the delta from the response:
   - **`noChange`**: Element is inert — continue batch
   - **`valuesChanged`**: Note the value changes as expected behavior, continue batch
   - **`elementsChanged`**: Check `added`/`removedOrders` — if elements disappeared, flag as ANOMALY, continue batch
   - **`screenChanged`**: Stop batch, **push** onto `## Navigation Stack`, use the `newInterface` from delta to record the new screen and transition. Navigate back using **known back-route** from `## Transitions` or `references/nav-graph.md` if available, otherwise use heuristic back-nav. **Pop** navigation stack on return. Re-plan.
3. If the element has `increment`/`decrement`: call both, read deltas to verify value changes
4. If the element has custom actions: try each via `perform_custom_action`

After the batch: append all trace entries at once, update session notes once.

### Elements without actions

1. `tap` at the element's center coordinates (computed from frame) — use `tap` as a fallback since these elements lack accessibility actions
2. Read the delta — check if anything changed (`noChange` means truly inert)
3. Try `long_press` — some elements reveal context menus only on long press
4. Read the delta — check if anything changed

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

Your notes exist for compaction survival, not per-action bookkeeping. Keep state in memory during active exploration.

**Read notes**: Only at session start and after compaction. Don't re-read between actions on the same screen.

**Write notes** in batches after every 3-5 elements:
- Update `## Coverage` — mark all tested elements from the batch
- Add any findings with finding IDs and trace refs
- Add any transitions and update `## Navigation Stack`
- Update `## Progress` and `## Next Actions`

**Write trace entries** in batches — accumulate entries, then append them all at once.

**Write immediately**: Only for CRASH findings or new screen discoveries.

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
#### F-N [SEVERITY] Description
- Trace refs: #X, #Y
- Action: [what you did] [trace #Y]
- Expected: [what you expected]
- Actual: [what happened]

### Element Catalog
| Order | Label | Identifier | Value | Actions | Tested |
|-------|-------|-----------|-------|---------|--------|
| 0 | ... | ... | ... | ... | tap, activate |
```

After reporting, **update persistent nav graph**: Merge any new transitions and back-routes into `references/nav-graph.md`.

## Error Handling

- If a tool call **fails with a connection error**: the app crashed. This is a CRASH finding. Record the last action and stop.
- If an action returns `success: false`: record the error method and message. Continue testing other elements.
- If you can't navigate back after a transition: record as INFO ("no back navigation from [screen]") and continue exploring from the new screen.
