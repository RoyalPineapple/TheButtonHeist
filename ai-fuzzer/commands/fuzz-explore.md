---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /fuzz-explore — Screen Explorer

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

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm at least one device is connected
3. If no devices found: stop and tell the user to launch the app and try again
4. Print the connected device name and app name for confirmation
5. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it (including `## Navigation Stack`) to understand what's already been explored. Skip elements already covered. If starting fresh:
   - Create a new notes file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.md` (include `Trace file` and `Next finding ID: F-1` in `## Config`)
   - Create the companion trace file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.trace.md` with the header (see `references/trace-format.md`)
5. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. This gives you known transitions and back-routes from prior sessions.
6. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
7. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.
8. **Load response examples**: Read `references/examples.md` for annotated CLI response interpretation examples.
9. **Load action patterns**: Read `references/action-patterns.md` for composable interaction sequences.

## Step 1: Observe the Current Screen

1. Run `buttonheist screenshot --output /tmp/bh-screen.png` (via Bash), then Read the PNG to see what's on screen.
2. Run `buttonheist watch --once --format json --quiet` (via Bash) to get the full element hierarchy.
3. Print a summary:
   - How many elements are on screen
   - List each element: `[order] label/description (identifier) — frame — actions`
   - Note the tree structure (containers, groups)

## Step 2: Identify Screen Intent + Baseline State

1. **Identify the screen's intent** using `references/screen-intent.md`. Is this a form, list, settings page, detail view, nav hub, picker, modal, or canvas? Record the intent in session notes (`## Screen Intents`).
2. Record the current state as your baseline:
   - Element count
   - Element identifiers and values
   - Screen capture visual state

## Step 3: Workflow Tests, Then Element Interaction

**Before starting**: Read your session notes file — check `## Coverage` for this screen to know which elements have already been tested. Skip those and pick up where you left off.

### Intent-Driven Workflow Testing

If you identified a screen intent, **run the workflow tests first** (see `references/screen-intent.md` for the specific tests per category):
- **Form**: Fill all fields with intent-appropriate values → submit → verify. Then: submit empty, partial fill, fill-then-abandon.
- **Item list**: Add → verify → edit → delete → verify empty state. Then: delete-when-empty, add-duplicate, rapid-add-delete.
- **Settings**: Change → navigate away → return → verify persisted. Then: toggle-rapidly, dependency-chain.
- **Other intents**: Follow the workflow and violation tests from screen-intent.md.

Record workflow test results in session notes and trace. Then proceed to element-by-element exploration for anything the workflows didn't cover.

### Element-by-Element Exploration

Process elements in **randomized order** (not always top-to-bottom). For each interactive element:

### Elements with actions (activate, increment, decrement, custom)

Process elements in batches of 3-5. For each element:
1. Run `buttonheist action --identifier ID --format json` (by identifier if available, otherwise by order)
2. Read the delta from the response:
   - **`noChange`**: Element is inert — continue batch
   - **`valuesChanged`**: Note the value changes as expected behavior, continue batch
   - **`elementsChanged`**: Check `added`/`removedOrders` — if elements disappeared, flag as ANOMALY, continue batch
   - **`screenChanged`**: Stop batch, **push** onto `## Navigation Stack`, use the `newInterface` from delta to record the new screen and transition. Navigate back using **known back-route** from `## Transitions` or `references/nav-graph.md` if available, otherwise use heuristic back-nav. **Pop** navigation stack on return. Re-plan.
3. If the element has `increment`/`decrement`: run both via `buttonheist action --type increment/decrement`, read deltas to verify value changes
4. If the element has custom actions: try each via `perform_custom_action`

After the batch: append all trace entries at once, update session notes once.

### Elements without actions

1. `buttonheist touch tap --x X --y Y --format json` at the element's center coordinates (computed from frame) — use tap as a fallback since these elements lack accessibility actions
2. Read the delta — check if anything changed (`noChange` means truly inert)
3. Try `buttonheist touch longpress` — some elements reveal context menus only on long press
4. Read the delta — check if anything changed

### Text fields

If the element looks like a text input (text field, secure field, text editor):
1. **Read the field's label/identifier** to understand what it expects (name, email, phone, password, description, etc.)
2. **Generate context-appropriate values** using the "Context-Aware Value Generation" section of `references/interesting-values.md`. For a "Name" field, try real names that break assumptions (`O'Brien-Smith Jr.`, `Null`, `信田`). For an "Email" field, try technically-valid-but-weird addresses (`a@b.c`, `user+tag@example.com`). Don't default to `"test input"` and `<script>alert(1)</script>` for every field.
3. `buttonheist type --identifier ID --text "..." --format json` — type a value that matches the field's purpose
4. Check the returned value matches what you typed
5. `buttonheist type --identifier ID --delete N --text "..." --format json` — clear and try an adversarial version of valid input
6. Try values from at least 3 categories in `references/interesting-values.md`, starting from a **random** category (not always boundary numbers first). Use `deleteCount` to clear before each new value.
7. **Generate at least 1 novel value** not from any list — derive it from the field's label, mutate a listed value, or combine categories.

### Swipe testing (on scrollable-looking containers)

If the tree structure shows `list` or `landmark` containers:
1. `buttonheist touch swipe --direction up --format json` on the container area — check if new elements appear
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

- If a CLI command **fails with a connection error or non-zero exit**: the app crashed. This is a CRASH finding. Record the last action and stop.
- If a CLI command exits with non-zero status: record the error method and message. Continue testing other elements.
- If you can't navigate back after a transition: record as INFO ("no back navigation from [screen]") and continue exploring from the new screen.
