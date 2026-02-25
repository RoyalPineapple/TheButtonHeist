---
description: Autonomous fuzzing loop — explores the app and discovers bugs
---

# /fuzz — Autonomous Fuzzer

You are tasked with autonomously fuzzing the connected iOS app. Explore screens, try interactions, navigate the app, and report any crashes, errors, or anomalies you find.

**Arguments** (optional): `$ARGUMENTS`
- First argument: strategy name (default: `systematic-traversal`). Options: `systematic-traversal`, `boundary-testing`, `gesture-fuzzing`, `state-exploration`, `swarm-testing`, `invariant-testing`
- Second argument: max iterations (default: 100)

## CRITICAL
- Every action tool returns an interface delta JSON (`noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`) — use it instead of calling `buttonheist watch --once` after actions
- On `screenChanged`, the delta includes the full new interface — no separate `buttonheist watch --once` needed
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- ALWAYS plan actions in explicit batches (typically 10-15 actions) — do not reason individually per element
- ALWAYS batch your file writes at batch boundaries — do not write notes and trace after every action
- DO NOT call `buttonheist screenshot` on every action — only for findings and new screens
- DO NOT re-read session notes between actions — keep state in memory, notes are for compaction survival
- DO NOT skip the refinement pass — unverified findings are unreliable

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
7. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. Find the most recent one and read it.
   - If one exists with `Status: in_progress`: **resume the session** — read all sections (including `## Navigation Stack`), skip to the appropriate step, and continue from `## Next Actions`
   - Otherwise: start a fresh session (previous notes files stay for reference)
8. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. This gives you all known transitions, back-routes, and screen fingerprints from prior sessions.
9. **Load app knowledge**: Read `references/app-knowledge.md` if it exists. This gives you accumulated coverage, behavioral models, finding investigation status, and known testing gaps from prior sessions.
10. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
11. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.
12. **Load response examples**: Read `references/examples.md` for annotated CLI response examples — these show how to interpret deltas and recognize screen intents in practice.
13. **Load action patterns**: Read `references/action-patterns.md` for composable interaction sequences to use when planning action batches.
14. **Gap analysis**: Before choosing a strategy, identify the highest-priority work from `references/app-knowledge.md`:
    - **Uninvestigated findings**: Check `## Findings Tracker` for `open:uninvestigated` entries — these need 5-10 actions of investigation each
    - **Untested areas**: Check `## Testing Gaps` for unchecked items — these are explicitly known blind spots
    - **Low-coverage screens**: Check `## Coverage Summary` for screens with < 80% element coverage or missing action types
    - **Stale screens**: Screens not tested in the last 2+ sessions may have regressed
    Print the gap analysis:
    ```
    [Gap Analysis]
    Uninvestigated findings: [list findings needing investigation]
    Untested areas: [list unchecked gaps]
    Low coverage: [list screens below 80%]
    Session plan: [prioritized plan for this session]
    ```

## Step 1: Load Strategy

Parse `$ARGUMENTS` for the strategy name and iteration limit. If a strategy was explicitly specified, read the corresponding strategy file from `references/strategies/[name].md`.

If no strategy was specified, defer selection until after Step 2 (Initial Observation) — see **Strategy Auto-Selection** below.

The strategy tells you how to select elements, which actions to try, when to move on, and what to look for.

### Strategy Auto-Selection

If no strategy was specified in `$ARGUMENTS`, choose based on gaps and context:

1. **Check for uninvestigated findings**: If `references/app-knowledge.md` has `open:uninvestigated` findings at CRITICAL or HIGH severity, use `state-exploration` focused on those findings' screens — investigation is highest priority.
2. **Check for untested strategies**: If `## Session History` shows that `invariant-testing` or `boundary-testing` have never been run, prefer those — they find different bug classes than traversal/exploration.
3. **Check for prior sessions**: If 3+ completed sessions exist with similar strategies, use `swarm-testing` — maximize diversity.
4. **Otherwise, use the initial observation** (after Step 2):
   - Count the interactive elements on the first screen
   - **> 3 navigation elements** (tabs, list cells, buttons with navigation labels): use `state-exploration` — map the app structure first
   - **> 5 adjustable elements** (sliders, steppers, pickers) or **> 2 text fields**: use `boundary-testing` — test value extremes. Consider `invariant-testing` if the screen also has toggles or navigation.
   - **< 5 total interactive elements**: use `gesture-fuzzing` — go deep on each element with every gesture type
   - **Otherwise** (default): use `systematic-traversal` — breadth-first coverage
5. Print the auto-selected strategy, reasoning, and how it connects to the gap analysis
6. Read the corresponding strategy file from `references/strategies/`

## Step 2: Initial Observation

1. Run `buttonheist screenshot --output /tmp/bh-screen.png` (via Bash), then Read the PNG — see the app's current state
2. Run `buttonheist watch --once --format json --quiet` (via Bash) — read the full element hierarchy
3. Print what you see:
   - App info (if visible from elements)
   - Screen description
   - Element count
   - Interactive elements count

Record this as Screen #1 with a fingerprint (set of identifiers + labels).

## Step 3: Initialize Session Notes

Create a new session notes file (see SKILL.md for naming convention):

**Filename**: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-fuzz-{strategy}.md`
(e.g. `.fuzzer-data/sessions/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md`)

1. Write the `## Config` section (strategy, max iterations, app/device info, status: `in_progress`, trace file name, next finding ID: `F-1`)
2. Write the `## Progress` section (actions: 0, current screen, phase: `fuzzing_loop`)
3. Write the `## Screens Discovered` table with Screen #1
4. Write the `## Coverage` section listing all elements on Screen #1 as untried
5. Write empty `## Transitions`, `## Navigation Stack` (with Screen #1 at depth 0), `## Findings`, `## Action Log` sections
6. Write `## Next Actions` describing what to try first on Screen #1
7. **Create the companion trace file**: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-fuzz-{strategy}.trace.md`
   - Write the trace header (Session, App, Device, Started, Format version: 1) — see `references/trace-format.md`
   - Append the first `observe` entry for the initial `buttonheist watch --once --format json --quiet` from Step 2

Both files are your lifeline — the session notes for compaction survival, the trace for reproducibility.

## Step 4: Fuzzing Loop (Opus Plans, Haiku Executes)

Read `references/execution-protocol.md` for the full execution plan format, delta handling rules, and return protocol.

Repeat until max iterations reached or a CRASH is detected:

### 4-pre. Investigation Queue (if uninvestigated findings exist)

Before starting the main exploration loop, process uninvestigated findings from `references/app-knowledge.md`. Opus plans the investigation, Haiku executes:

1. For each `open:uninvestigated` finding (highest severity first, max 3 per session):
   a. Plan a navigation route to the finding's screen using `references/nav-graph.md`
   b. Build an execution plan with up to 5 investigation actions: reproduce, vary, scope, reduce, boundary (see SKILL.md `### When Predictions Fail: Investigate`)
   c. Dispatch to Haiku via `Task(model: "haiku", subagent_type: "Bash")`
   d. Read Haiku's return. Update the finding's status based on results:
      - Reproduced consistently → `open:confirmed`
      - Fully understood (scope + minimal trigger) → `open:investigated`
      - Cannot reproduce → note the failure, keep as `open:uninvestigated`
2. After processing the investigation queue, continue to the main loop
3. Budget: max 15 actions total for investigation queue (3 findings x 5 actions)

### 4a. Opus: Observe + Identify Intent + Plan Batch

1. If this is the first batch or you don't have current state: run `buttonheist watch --once --format json --quiet`. Otherwise, use the state from Haiku's last return (current screen, fingerprint, nav stack).
2. **On a new screen, identify its intent first** using `references/screen-intent.md` (form, list, settings, nav hub, etc.). Record the intent in `## Screen Intents`. Plan workflow tests (happy path + violations) before element-by-element fuzzing. See "Screen Intent Recognition" in SKILL.md.
3. **Plan 10-15 actions** informed by the screen's intent:
   - For a **form**: fill fields with intent-appropriate values → submit → test violations (submit empty, partial fill, abandon)
   - For an **item list**: add → verify → edit → delete → test empty state
   - For **settings**: change → persist check → dependency chain testing
   - For **unknown** screens: fall back to element scoring (novelty +3, action gap +2, navigation +2, etc.)
   - If the element is a text field, generate values from `references/interesting-values.md` — use the context-aware generation section, not just the static lists
   - If everything on this screen has been tried, **plan a route** to the highest-priority unexplored screen using known transitions from `## Transitions` and `references/nav-graph.md` (see "Navigation Planning" in SKILL.md). Don't wander — navigate directly.
   - When choosing the next screen, **consult `references/app-knowledge.md`**: prefer screens listed in `## Testing Gaps` with unchecked items, screens with lowest coverage in `## Coverage Summary`, and screens not tested by the current session's strategy.
4. Generate the exact CLI commands for each planned action with expected deltas and predictions

### 4b. Opus: Build Execution Plan + Dispatch to Haiku

Build an execution plan containing the 10-15 planned actions:

**Context block**: CLI path, auth token, session notes path, trace file path, next trace seq, next finding ID, current screen + fingerprint, nav stack.

**Action list**: Each action with:
- Exact CLI command
- Expected delta kind
- Expected screen (if screenChanged)
- Prediction (free text from behavioral model)
- Purpose: `fuzzing` or `navigation`

**Stop conditions**: Max actions (the batch size). Stop on crash. Stop on 3+ consecutive unexpected.

Dispatch:
```
Task(
  description: "[the execution plan]",
  model: "haiku",
  subagent_type: "Bash"
)
```

### 4c. Opus: Process Results + Yield Check

Read Haiku's Execution Result:

1. **Parse status**:
   - `complete` → all actions executed, proceed to yield check
   - `stopped` with `crash` → proceed to crash handling
   - `stopped` with other reason → handle the issue (navigate back, replan)

2. **Incorporate results**:
   - Add Haiku's findings to the running findings list
   - Update mental model of coverage from Haiku's coverage report
   - Note any noteworthy events from Haiku's notes (element fallbacks, prediction mismatches, recovered screen changes)
   - Update current screen and nav stack from Haiku's current state

3. **Print progress** (every ~10 actions based on cumulative count):
   ```
   [Progress] Actions: 42/100 | Screens: 5 | Findings: 2 (0 crash, 1 error, 1 anomaly)
   ```

4. **Yield check** (every ~15 actions based on cumulative count): Count findings and new coverage from recent Haiku returns.
   - If yield is low (0 findings, < 3 new coverage items in ~15 actions): pivot to the highest-priority untested area from `references/app-knowledge.md`. Print:
     ```
     [Yield] Low yield on [screen] — 0 findings in 15 actions. Pivoting to [next target].
     ```
   - If yield is high (2+ findings in ~15 actions): stay and go deeper. Print:
     ```
     [Yield] Productive vein on [screen] — N findings in 15 actions. Continuing.
     ```
   - If same screen for 20+ actions with 0 findings: leave immediately and mark as saturated for current strategy.

5. **Loop back to 4a** — replan the next batch based on Haiku's results and the yield assessment.

## Step 5: Refinement Pass

If any ERROR or ANOMALY findings were discovered during the main loop:

### Pre-refinement: Prepare Recording

Before verifying findings, set up recording to capture video evidence:

1. Read `references/recording-guide.md` for the recording workflow (if not already loaded)
2. Create the recordings directory: `mkdir -p .fuzzer-data/recordings`

### For each finding:

**Start recording** before attempting reproduction:
1. Estimate duration for this finding's verification: `15 × 10 + 15 = 165` seconds (covers 3 reproduction attempts + variations)
2. Start background recording:
   ```bash
   buttonheist record \
     --output .fuzzer-data/recordings/F-N-refinement.mp4 \
     --max-duration <estimated> --inactivity-timeout 60 --fps 8 --scale 0.5 --quiet &
   RECORD_PID=$!
   sleep 2
   ```

**Verify the finding:**
1. **Navigate to finding's screen**: Use the navigation graph (`## Transitions` + `references/nav-graph.md`) to plan a route to each finding's screen
2. **Confirm**: Attempt to reproduce the exact same action 3 times
3. **Vary**: Try variations of the triggering action:
   - Same element, different action type (tap vs activate vs long_press)
   - Adjacent elements (order +/- 1)
   - Same action after arriving via a different navigation path
4. **Classify**: Update each finding's confidence:
   - **Reproducible**: Triggered on 2+ of 3 attempts
   - **Intermittent**: Triggered on 1 of 3 attempts
   - **Not reproduced**: Could not trigger again (may have been transient)

**Collect recording** after verification:
1. Wait for background recording: `wait $RECORD_PID`
2. Add recording to finding: `**Recording**: .fuzzer-data/recordings/F-N-refinement.mp4`
3. Update `## Recordings` in session notes

5. Remove findings that were "Not reproduced" from the main findings (mention them in a "Transient observations" section instead)

If no ERROR or ANOMALY findings, skip this step.

**Update session notes**: Update `## Status` to `refinement`, update finding confidence levels, update `## Recordings`, update `## Next Actions`.

## Step 6: Generate Report

When the loop ends (iterations exhausted, crash detected, or all screens explored):

1. Print a summary to the conversation
2. Write a full report to `.fuzzer-data/reports/` using the format from SKILL.md
3. **Update session notes**: Set `## Status` to `complete`
4. **Update persistent nav graph**: Merge all new transitions and back-routes into `references/nav-graph.md`
5. **Update app knowledge base**: Merge session discoveries into `references/app-knowledge.md`:
   - Update `## Coverage Summary` for all screens touched this session
   - Update or add `## Behavioral Models` for screens where models were built/refined
   - Update `## Findings Tracker` — add new findings, update investigation status for probed findings
   - Check off completed items in `## Testing Gaps`, add any newly identified gaps
   - Add this session to `## Session History`

```
## Fuzzing Report

**Strategy**: [name]
**Duration**: [actions_taken] actions across [screens_visited count] screens
**App**: [app name from server info if available]

### Summary
| Severity | Count |
|----------|-------|
| CRASH    | X     |
| ERROR    | X     |
| ANOMALY  | X     |
| INFO     | X     |

### Findings

[Each finding in the format from SKILL.md — include **Recording** field if video was captured]

### Recordings
| Finding | File | Duration | Notes |
|---------|------|----------|-------|
| F-1 | .fuzzer-data/recordings/F-1-refinement.mp4 | 12.3s | Reproduction confirmed |

### Screen Map
[List of screens visited and transitions between them]

### Coverage
[Elements tested / total elements across all screens]
```

## Crash Handling

If the app crashes (CLI command fails with a connection error or non-zero exit code):

1. **Stop immediately** — the connection is dead
2. **Update trace**: Append the `interact` entry with `result.status: crash` and `result.finding: F-N`
3. **Update session notes** immediately: Add the CRASH finding with finding ID, trace refs, the exact action, last 5-10 actions from `## Action Log`, and screen state. Set `## Status` to `crashed`.
4. Generate the report with what you have
5. Tell the user the app crashed and they need to relaunch it. Note that `/fuzz-reproduce F-N` can be used to replay the crash sequence.
