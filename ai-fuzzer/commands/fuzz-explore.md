---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /fuzz-explore — Screen Explorer

You are tasked with thoroughly exploring whatever screen is currently showing in the connected iOS app. You identify the screen's intent and design tests, then delegate execution to a Haiku agent.

## CRITICAL
- Every action tool returns an interface delta JSON (`noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`) — use it instead of calling `buttonheist watch --once` after actions
- On `screenChanged`, the delta includes the full new interface — no separate `buttonheist watch --once` needed
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- ALWAYS use `activate` before falling back to `tap` — accessibility API interaction is more reliable
- ALWAYS plan actions in batches — do not reason individually per element
- DO NOT call `buttonheist screenshot` on every action — only for findings and new screens

## Step 0: Verify Connection + Check for Existing Session

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm at least one device is connected
3. Bootstrap auth token once: run `buttonheist watch --once --format json --quiet`, capture `BUTTONHEIST_TOKEN=...` from output, and store as `AUTH_TOKEN` for the session
4. Reuse token on every later command: `buttonheist ... --token "$AUTH_TOKEN"` (or `BUTTONHEIST_TOKEN="$AUTH_TOKEN" buttonheist ...`)
5. If no devices found: stop and tell the user to launch the app and try again
6. Print the connected device name and app name for confirmation
7. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it (including `## Navigation Stack`) to understand what's already been explored. Skip elements already covered. If starting fresh:
   - Create a new notes file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.md` (include `Trace file` and `Next finding ID: F-1` in `## Config`)
   - Create the companion trace file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.trace.md` with the header (see `references/trace-format.md`)
8. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. This gives you known transitions and back-routes from prior sessions.
9. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
10. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.
11. **Load response examples**: Read `references/examples.md` for annotated CLI response interpretation examples.
12. **Load action patterns**: Read `references/action-patterns.md` for composable interaction sequences.

## Step 1: Observe the Current Screen

1. Run `buttonheist screenshot --output /tmp/bh-screen.png` (via Bash), then Read the PNG to see what's on screen.
2. Run `buttonheist watch --once --format json --quiet` (via Bash) to get the full element hierarchy.
3. Print a summary:
   - How many elements are on screen
   - List each element: `[order] label/description (identifier) — frame — actions`
   - Note the tree structure (containers, groups)

## Step 2: Identify Screen Intent + Design Tests

1. **Identify the screen's intent** using `references/screen-intent.md`. Is this a form, list, settings page, detail view, nav hub, picker, modal, or canvas? Record the intent in session notes (`## Screen Intents`).
2. Record the current state as your baseline:
   - Element count
   - Element identifiers and values
   - Screen capture visual state
3. **Design workflow tests** based on the screen's intent (see `references/screen-intent.md`):
   - **Form**: Fill all fields → submit → verify. Violations: submit empty, partial fill, fill-then-abandon.
   - **Item list**: Add → verify → edit → delete → verify empty state. Violations: delete-when-empty, add-duplicate, rapid-add-delete.
   - **Settings**: Change → navigate away → return → verify persisted. Violations: toggle-rapidly, dependency-chain.
   - **Other intents**: Follow the workflow and violation tests from screen-intent.md.
4. **Order elements** for exploration: randomize within priority tiers. Score by novelty (+3 if untested), action gap (+2 per untried action), navigation potential (+2), adjustable (+1).
5. **Plan text field values**: For each text field, read its label and generate context-appropriate values using `references/interesting-values.md`. Generate at least 1 novel value per field.

## Step 3: Dispatch Execution to Haiku

Read `references/execution-protocol.md` for the full execution plan format, delta handling rules, and return protocol.

### Batch 1: Workflow Tests

Build an execution plan containing the workflow test sequence designed in Step 2:

**Context block**: Include CLI path, auth token, session notes path, trace file path, next trace seq, next finding ID, current screen + fingerprint, nav stack.

**Action list**: Happy path actions first, then violation tests. Include:
- Exact CLI commands for each workflow step
- Expected deltas based on the screen intent's typical behavior
- Predictions from the behavioral model
- Navigation commands (with back-routes from nav-graph) for any workflow steps that leave the current screen
- Purpose: `fuzzing`

**Stop conditions**: Max actions ~15. Stop on crash. Stop on 3+ consecutive unexpected.

Dispatch to Haiku:
```
Task(
  description: "[the execution plan]",
  model: "haiku",
  subagent_type: "Bash"
)
```

Read Haiku's return. Print: `[Workflow] Happy path: PASS/FAIL | Violations: N findings`

### Batch 2+: Element-by-Element Exploration

For remaining elements not covered by workflow tests, build execution plans in chunks of 15-20 actions:

**For elements with actions** (activate, increment, decrement, custom):
- `buttonheist action --identifier ID --format json`
- If element has increment/decrement: include both actions
- Expected delta: varies by element type (buttons → noChange or screenChanged, toggles → valuesChanged)

**For elements without actions**:
- `buttonheist touch tap --x X --y Y --format json` at center coordinates
- `buttonheist touch longpress --x X --y Y --duration 1.0 --format json`
- Expected delta: `noChange` for most

**For text fields** (generate the CLI commands with values from Step 2):
- `buttonheist type --identifier ID --text "VALUE" --format json`
- `buttonheist type --identifier ID --delete N --text "ADVERSARIAL" --format json`
- Include values from at least 3 categories per field

**For scrollable containers** (list/landmark elements):
- `buttonheist touch swipe --direction up --format json` on the container area
- `buttonheist touch swipe --direction down --format json`

**Stop conditions**: Max actions per batch. Stop on crash. Stop on 3+ consecutive unexpected.

Dispatch each batch to Haiku. Between batches:
1. Read Haiku's return (findings, coverage, notes)
2. If Haiku discovered new elements via scrolling, add them to the next batch
3. If Haiku's notes report unexpected screenChanged with recovery, account for it
4. Plan the next batch with remaining untested elements

Print after each batch: `[Explore] Batch N: M actions | K findings | L elements remaining`

## Step 4: Report Findings

After all batches complete, Opus generates the report directly (not delegated):

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

### Haiku Execution Notes
[Collate noteworthy events from all Haiku returns — element-not-found, prediction mismatches, recovered screen changes, etc.]

### Element Catalog
| Order | Label | Identifier | Value | Actions | Tested |
|-------|-------|-----------|-------|---------|--------|
| 0 | ... | ... | ... | ... | tap, activate |
```

After reporting:
- **Update persistent nav graph**: Merge any new transitions and back-routes into `references/nav-graph.md`
- **Update app knowledge**: Merge coverage and findings into `references/app-knowledge.md`

## Error Handling

- If Haiku reports a crash (status: `stopped`, reason: `crash`): Record the CRASH finding. The app is dead — generate the report with what you have and tell the user to relaunch.
- If Haiku reports stuck on wrong screen: Read the current state from session notes, attempt to navigate back using nav-graph, then re-plan the remaining exploration.
- If Haiku skipped elements (not found): Note these in the report and try them manually if the list is short.
