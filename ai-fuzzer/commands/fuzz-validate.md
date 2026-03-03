---
description: Validate a specific feature by name — targeted testing with regression checks
---

# /fuzz-validate — Feature Validator

You are tasked with validating a specific feature in the connected iOS app. Unlike `/fuzz` (broad exploration) or `/fuzz-explore` (current-screen deep-dive), this command is **feature-focused** — navigate directly to the feature's screen(s), run targeted validation, check for regressions, and report whether the feature works correctly.

**Arguments**: `$ARGUMENTS`
- **Feature name** (required): Name of the feature, screen, or area to validate. Matched against screen names and intents from `references/nav-graph.md` and `references/app-knowledge.md`.
- **Additional context** (optional): Free-text instructions following the feature name. Tells you what to focus on (e.g., "focus on persistence", "test the new filter dropdown", "make sure toggles work after the identifier fix").

Examples:
- `/fuzz-validate todo list` — validate the Todo List feature
- `/fuzz-validate settings focus on cross-screen effects` — validate Settings with extra attention to how changes affect other screens
- `/fuzz-validate disclosure test if toggles respond now` — validate the Disclosure & Grouping screen, specifically checking whether inner toggles work

## CRITICAL
- ALWAYS resolve the feature name to specific screen(s) before doing anything — never start testing without a clear target
- ALWAYS check `references/app-knowledge.md` for known findings on the target screen(s) — regression checking is the highest-value activity
- ALWAYS use `references/nav-graph.md` to plan direct routes — don't wander to the feature's screen
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- Every action tool returns an interface delta JSON (`noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`) — use it instead of calling `buttonheist watch --once` after actions
- On `screenChanged`, the delta includes the full new interface — no separate `buttonheist watch --once` needed
- ALWAYS plan actions in explicit sub-phase batches — do not reason individually per element
- ALWAYS batch your file writes — update notes and trace at sub-phase boundaries, not every action
- DO NOT call `buttonheist screenshot` on every action — only for findings, new screens, and the initial observation
- DO NOT test screens unrelated to the feature — stay scoped

## Step 0: Setup

Follow **## Session Setup** from SKILL.md (build CLI, verify connection, bootstrap auth token, check for existing session, load cross-session knowledge).

Additionally load: `references/navigation-planning.md`, `references/examples.md`, `references/action-patterns.md`.

## Step 1: Resolve Feature

Parse `$ARGUMENTS` to extract the feature name and any additional context.

### Feature Resolution

Match the feature name against known screens and intents. Search in this order:

1. **Screen names** (from `references/nav-graph.md` Screens table): Fuzzy match against the `Name` column. Examples:
   - "todo" → "Todo List"
   - "settings" → "Settings"
   - "disclosure" → "Disclosure & Grouping"
   - "alerts" → "Alerts & Sheets"
   - "canvas" → "Touch Canvas"
   - "text input" or "text fields" → "Text Input"
   - "adjustable" or "sliders" → "Adjustable Controls"
   - "buttons" → "Buttons & Actions"
   - "toggles" or "pickers" → "Toggles & Pickers"
   - "display" → "Display"

2. **Screen intents** (from `references/app-knowledge.md` Coverage Summary, Intent column): Match against intent categories:
   - "form" or "data entry" → screens with "Form" intent (e.g., Text Input)
   - "list" or "crud" → screens with "Item List" intent (e.g., Todo List)
   - "navigation" or "hub" → screens with "Nav Hub" intent (e.g., Main Menu, Controls Demo Submenu)

3. **Element identifiers** (from `references/nav-graph.md` Fingerprint column): If the feature name matches a specific element identifier prefix:
   - "color picker" → Toggles & Pickers screen (colorPicker element)
   - "date picker" → Date Picker calendar screen
   - "stepper" → Adjustable Controls screen

### Handle Resolution Results

- **Single match**: Proceed with that screen as the primary target
- **Multiple matches**: List all matches and ask the user to pick one:
  ```
  Multiple screens match "picker":
  1. Toggles & Pickers (contains menuPicker, colorPicker)
  2. Date Picker calendar (date selection)
  Which one? (or "both" to validate both)
  ```
- **No match**: Report what was searched and ask the user to clarify:
  ```
  No screen matches "checkout". Known screens:
  Main Menu, Controls Demo Submenu, Text Input, Toggles & Pickers,
  Buttons & Actions, Adjustable Controls, Disclosure & Grouping,
  Alerts & Sheets, Display, Touch Canvas, Todo List, Settings,
  Date Picker calendar, Alert overlay, Confirmation sheet, Sheet overlay

  Which screen should I validate?
  ```

### Identify Validation Scope

After resolving to a primary screen, also identify:

1. **Related screens** with cross-screen effects: Check `references/app-knowledge.md` Behavioral Models for `Cross-screen effects` entries that mention the target screen. For example:
   - Target "Todo List" → related "Settings" (showCompleted affects filter behavior)
   - Target "Settings" → related "Todo List" (showCompleted), all screens (colorScheme, accentColor, textSize)

2. **Known findings**: Filter `references/app-knowledge.md` Findings Tracker for findings on the target screen(s). These are your regression check targets.

3. **Known testing gaps**: Filter `references/app-knowledge.md` Testing Gaps for unchecked items mentioning the target screen(s).

4. **User context**: Parse any additional text after the feature name as focus instructions.

### Print Validation Plan

```
[Validation Plan]
Target: [screen name] ([intent])
Related screens: [list of related screens and why]
Known findings to check: [list findings with IDs and summaries]
Testing gaps to fill: [list gaps]
User context: [additional instructions, or "none"]
Route: [planned route from current position to target screen]

Proceeding with validation.
```

## Step 2: Initialize Session Notes

Create a new session notes file:

**Filename**: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-validate-{feature-name}.md`
(e.g., `.fuzzer-data/sessions/fuzzsession-2026-02-25-1430-validate-todo-list.md`)

1. Write the `## Config` section: command: `validate`, target feature, related screens, user context, status: `in_progress`, trace file name, next finding ID: `F-1`
2. Write the `## Progress` section: actions: 0, current screen, phase: `navigating`
3. Write empty sections: `## Screens Discovered`, `## Coverage`, `## Behavioral Models`, `## Transitions`, `## Navigation Stack`, `## Findings`, `## Regression Check`, `## Action Log`, `## Next Actions`
4. **Create the companion trace file** (see `references/session-files.md` for format)

## Step 3: Navigate to Feature

1. Run `buttonheist watch --once --format json --quiet` to fingerprint the current screen
2. If already on the target screen: skip navigation, proceed to Step 4
3. Plan a route using `references/nav-graph.md`:
   - Find the target screen in the Transitions table
   - BFS from the current screen to the target (see `references/navigation-planning.md`)
   - If no route found: navigate to the app root (Main Menu) first, then route from there
4. Execute the route step by step:
   - For each step: execute the action, read the delta, verify the destination fingerprint
   - Push each forward navigation onto `## Navigation Stack`
   - Write `navigate` trace entries for each step (purpose: `setup`)
5. If navigation fails at any step: report the failure and ask the user for help

Update `## Progress`: phase: `observing`

## Step 4: Observe + Build Model

1. Run `buttonheist screenshot --output /tmp/bh-validate-screen.png` (via Bash), then Read the PNG — see the feature's current state
2. Run `buttonheist watch --once --format json --quiet` (via Bash) — read the full element hierarchy
3. Print what you see: screen description, element count, interactive elements
4. Record as first screen in `## Screens Discovered`

### Load or Build Behavioral Model

1. Check `references/app-knowledge.md` Behavioral Models for an existing model of this screen
2. If a model exists:
   - Load it as your starting hypothesis
   - Print: "Loading existing behavioral model for [screen]. Will verify it's still accurate."
   - Verify key aspects: element count matches? State variables present? Coupling still holds?
   - Update the model in session notes with any differences
3. If no model exists:
   - Identify the screen's intent using `references/screen-intent.md`
   - Build a new behavioral model from observation (see SKILL.md `## Behavioral Modeling`)
   - Record in session notes `## Behavioral Models`

4. If the user provided additional context, note how it maps to specific elements, state variables, or test approaches. For example:
   - "focus on persistence" → prioritize Persistence invariant (Pass 4 from invariant-testing strategy)
   - "test the filter" → focus on filter-related elements and cross-screen effects
   - "make sure toggles work" → test activate on all toggle elements

Update `## Progress`: phase: `validating`

## Step 5: Validation Loop (Delegated to Haiku)

Run validation in this priority order, delegating each sub-phase to a Haiku executor. Track actions taken — budget ~50 actions total for a single feature (adjustable based on feature complexity).

Use the **Execution Plan Template** from SKILL.md for delegation. For each sub-phase, Opus designs actions, builds an execution plan, dispatches to Haiku, reads the result, and adjusts the next sub-phase.

### 5a. Regression Check (known findings)

**This is the highest-value activity.** For each known finding on this screen (from `references/app-knowledge.md` Findings Tracker), Opus builds an execution plan:

**What Opus writes into the plan:**
- For each finding: the exact triggering action (CLI command), precondition setup actions, expected behavior from the finding's description
- Prediction for each action: what the original finding observed
- Purpose: `regression`
- Budget: up to 3 actions per known finding

**What Haiku does:**
- Execute the actions mechanically
- Note whether each finding's behavior matches the original description
- Record in session notes `## Regression Check` and trace

**What Opus does after Haiku returns:**
- Classify each finding from Haiku's notes:
  - **Still present**: Finding reproduces — same behavior as originally reported
  - **Appears fixed**: Finding does NOT reproduce — behavior now matches expectations
  - **Changed**: Different behavior than both — may need investigation

Print: `[Regression] Checked N known findings: X still present, Y appear fixed`

### 5b. Workflow Validation (intent-driven)

Opus designs the workflow test sequence based on the screen's intent (from `references/screen-intent.md`):

**What Opus writes into the plan:**
- **Happy path** actions: the primary workflow for the screen's intent:
  - **Item List**: Add item → verify in list → edit → delete → verify removed
  - **Form**: Fill fields → submit → verify success
  - **Settings**: Change setting → navigate away → return → verify persisted
  - **Navigation Hub**: Visit each destination → return → verify hub unchanged
- **Violation test** actions: the intent's violation tests:
  - **Item List**: Delete when empty, add duplicate, rapid add/delete
  - **Form**: Submit empty, partial fill, fill-then-abandon
  - **Settings**: Toggle rapidly, dependency chain, boundary values
- Predictions from the behavioral model for each action
- Purpose: `fuzzing`
- Budget: ~20-30 actions total (one batch for happy path + violations)

**What Haiku does:**
- Execute workflow steps, read deltas, record findings
- Note any prediction mismatches

**What Opus does after Haiku returns:**
- Review findings and notes
- Update behavioral model if predictions were wrong

Print: `[Workflow] Happy path: PASS/FAIL | Violations: N new findings`

### 5c. User-Specified Validation

If the user provided additional context, Opus maps it to specific test actions:

**What Opus writes into the plan:**
- "persistence" → change values, navigate away, return, verify values persist (include navigation commands)
- "cross-screen" or "effects" → change values, navigate to related screens, verify effects
- "boundary" or "edge cases" → test min/max values, empty states, overflow
- "stress" → rapid-fire interactions on key elements (10x taps, rapid toggles)
- Specific element mentions → focused testing on those elements
- Purpose: `fuzzing` or `investigation`
- Budget: ~10 actions

**What Haiku does:**
- Execute the targeted tests, record results

Print: `[User Focus] [context]: tested N elements, M findings`

### 5d. Gap Coverage

If `references/app-knowledge.md` Testing Gaps has unchecked items for this screen:

**What Opus writes into the plan:**
- Actions to fill each gap:
  - "adversarial values not tested" → type commands with values from `references/interesting-values.md`
  - "increment/decrement boundary not tested" → increment/decrement to min/max
  - "drawing gestures untested" → `buttonheist touch draw-path` / `buttonheist touch draw-bezier` commands
- Purpose: `fuzzing`
- Budget: ~5-10 actions

**What Haiku does:**
- Execute gap-filling actions, record findings

Print: `[Gaps] Filled X/Y testing gaps for this screen`

### 5e. Cross-Screen Validation

If the behavioral model identifies cross-screen effects:

**What Opus writes into the plan** (one batch per cross-screen relationship):
- Action to make a change on the target screen (e.g., toggle showCompleted)
- Navigation commands to reach the affected screen (from nav-graph)
- Observation commands to verify the effect
- Navigation commands to return to the target screen
- Action to restore the original value
- Purpose: `fuzzing`
- Budget: ~5-10 actions per relationship

**What Haiku does:**
- Execute the change → navigate → verify → return → restore sequence
- Note whether the expected cross-screen effect was observed

**What Opus does after Haiku returns:**
- Record findings if effects don't propagate as expected

Print: `[Cross-Screen] source→target effect: verified/failed`

### Between Sub-Phases

After each Haiku return, Opus:
1. Reads the Execution Result (status, findings, notes, coverage)
2. Updates its running totals (actions taken, findings count)
3. Decides whether to continue to the next sub-phase or stop (budget exhausted, crash)
4. Adjusts the next batch based on what was learned (e.g., if a finding appears fixed, skip related tests)

## Step 6: Generate Scoped Report

When validation completes (all phases done or action budget exhausted):

1. **Update session notes**: Set `## Status` to `complete`
2. **Write the report** to `.fuzzer-data/reports/`:

**Filename**: `.fuzzer-data/reports/YYYY-MM-DD-HHMM-validate-{feature-name}.md`

```markdown
# Feature Validation Report

**Feature**: [feature name]
**Screen(s)**: [primary screen + related screens tested]
**Date**: [timestamp]
**App**: [app name]
**Device**: [device name]
**Actions taken**: [count]

## Summary

| Category | Result |
|----------|--------|
| Regression checks | X/Y findings checked (Z still present, W appear fixed) |
| Workflow (happy path) | [PASS/FAIL — brief description if FAIL] |
| Workflow (violations) | X violations tested, Y findings |
| User focus: [context] | [summary of targeted test results] |
| Gap coverage | X/Y gaps filled |
| Cross-screen effects | X/Y effects verified |
| **New findings** | **N total (by severity)** |

## Regression Check

| Finding ID | Original Summary | Status | Notes |
|------------|-----------------|--------|-------|
| A-HIGH-1 | Items not persisted | still present | Reproduced — items lost on back/return |
| A-LOW-1 | Grammar error | appears fixed | Now shows "No todos" correctly |

## New Findings

[Each finding in standard format from SKILL.md]

### F-1 [SEVERITY] Brief description
**Finding ID**: F-1
**Trace refs**: #X, #Y
**Screen**: [screen]
**Action**: [exact CLI command] [trace #Y]
**Expected**: [what you expected]
**Actual**: [what happened]
**Steps to Reproduce**:
1. [navigation to screen]
2. [triggering action]

## Workflow Test Results

### Happy Path
[Describe the workflow executed and whether each step produced expected behavior]

### Violation Tests
| Test | Result | Notes |
|------|--------|-------|
| [violation name] | PASS/FAIL | [brief description] |

## Coverage

### Elements Tested
[List of elements interacted with on the target screen, grouped by test phase]

### Testing Gaps Addressed
- [x] [gap that was filled]
- [ ] [gap that remains — explain why]

## Cross-Screen Effects
| Source | Effect | Target Screen | Verified |
|--------|--------|---------------|----------|
| [setting/action] | [what it affects] | [screen] | YES/NO |
```

3. **Update persistent knowledge**: Merge session discoveries into `references/app-knowledge.md`:
   - Update `## Coverage Summary` for all screens touched
   - Update `## Behavioral Models` if models were refined
   - Update `## Findings Tracker` — change status to `closed:fixed` for findings that appear fixed, add new findings
   - Check off completed items in `## Testing Gaps`
   - Add this session to `## Session History`
4. **Update nav graph**: Merge any new transitions into `references/nav-graph.md`

5. Print the report summary to the conversation and tell the user where the full report was saved.

## Crash Handling

If the app crashes (CLI command fails with connection error or non-zero exit code after previously working):

1. **Stop immediately** — the connection is dead
2. **Update trace**: Append the `interact` entry with `result.status: crash`
3. **Update session notes**: Add the CRASH finding, set `## Status` to `crashed`
4. Generate a partial report with what you have
5. Tell the user the app crashed and they need to relaunch it

## Error Recovery

- If a CLI command returns an error but the app is still connected: record the error, continue with the next validation step
- If navigation to the target screen fails: try an alternate route via the nav-graph, or ask the user for help
- If an element from the behavioral model is missing: note it as a finding (element removed or renamed), adapt and continue
- See **## Error Recovery** in SKILL.md for additional recovery procedures
