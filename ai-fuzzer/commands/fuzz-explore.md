---
description: Deep-dive exploration of the current screen — catalogs every element and tries every action
---

# /fuzz-explore — Screen Explorer

You are tasked with thoroughly exploring whatever screen is currently showing in the connected iOS app. You identify the screen's intent and design tests, then delegate execution to a Haiku agent.

## CRITICAL
- Every action tool returns an interface delta JSON (`noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`) — use it instead of calling `get_interface` after actions
- On `screenChanged`, the delta includes the full new interface — no separate `get_interface` needed
- ALWAYS use `activate` before falling back to `tap` — accessibility API interaction is more reliable
- ALWAYS plan actions in batches — do not reason individually per element
- DO NOT call `get_screen` on every action — only for findings and new screens

## Step 0: Setup

Follow **## Session Setup** from SKILL.md (verify connection, check for existing session, load cross-session knowledge).

Additionally load: `references/navigation-planning.md`, `references/examples.md`, `references/action-patterns.md`.

If starting fresh, create session notes and companion trace file (see `references/session-files.md` for format): `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-explore-{screen-name}.md`

## Step 1: Observe the Current Screen

1. Call `get_screen` to see what's on screen.
2. Call `get_interface` to get the full element hierarchy.
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

Use the **Execution Plan Template** from SKILL.md for delegation.

### Batch 1: Workflow Tests

Build an execution plan containing the workflow test sequence designed in Step 2:

**Context block**: Session notes path, trace file path, next trace seq, next finding ID, current screen + fingerprint, nav stack.

**Action list**: Happy path actions first, then violation tests. Include:
- Exact MCP tool calls for each workflow step
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
  subagent_type: "general-purpose"
)
```

Read Haiku's return. Print: `[Workflow] Happy path: PASS/FAIL | Violations: N findings`

### Batch 2+: Element-by-Element Exploration

For remaining elements not covered by workflow tests, build execution plans in chunks of 15-20 actions:

**For elements with actions** (activate, increment, decrement, custom):
- `activate(identifier: ID)`
- If element has increment/decrement: include both `accessibility_action(type: increment, identifier: ID)` and `accessibility_action(type: decrement, identifier: ID)`
- Expected delta: varies by element type (buttons → noChange or screenChanged, toggles → valuesChanged)

**For elements without actions**:
- `gesture(type: one_finger_tap, x: X, y: Y)` at center coordinates
- `gesture(type: long_press, x: X, y: Y, duration: 1.0)`
- Expected delta: `noChange` for most

**For text fields** (generate the tool calls with values from Step 2):
- `type_text(text: "VALUE", identifier: ID)`
- `type_text(deleteCount: N, text: "ADVERSARIAL", identifier: ID)`
- Include values from at least 3 categories per field

**For scrollable containers** (list/landmark elements):
- `scroll(direction: up)` / `scroll(direction: down)` on the container
- `scroll_to_visible(identifier: ID)` to bring a known off-screen element into view
- `scroll_to_edge(edge: top)` / `scroll_to_edge(edge: bottom)` to jump to list boundaries

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
