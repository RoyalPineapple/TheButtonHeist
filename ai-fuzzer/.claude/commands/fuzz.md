---
description: Autonomous fuzzing loop — explores the app and discovers bugs
---

# /fuzz — Autonomous Fuzzer

You are going to autonomously fuzz the connected iOS app. You will explore screens, try interactions, navigate the app, and report any crashes, errors, or anomalies you find.

**Arguments** (optional): `$ARGUMENTS`
- First argument: strategy name (default: `systematic-traversal`). Options: `systematic-traversal`, `boundary-testing`, `gesture-fuzzing`, `state-exploration`, `swarm-testing`, `invariant-testing`
- Second argument: max iterations (default: 100)

## Step 0: Verify Connection + Check for Existing Session

1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app and try again
3. Print the connected device name and app name for confirmation
4. **Check for existing session**: List `session/fuzzsession-*.md` files. Find the most recent one and read it.
   - If one exists with `Status: in_progress`: **resume the session** — read all sections, skip to the appropriate step, and continue from `## Next Actions`
   - Otherwise: start a fresh session (previous notes files stay for reference)

## Step 1: Load Strategy

Parse `$ARGUMENTS` for the strategy name and iteration limit. If a strategy was explicitly specified, read the corresponding strategy file from `references/strategies/[name].md`.

If no strategy was specified, defer selection until after Step 2 (Initial Observation) — see **Strategy Auto-Selection** below.

The strategy tells you how to select elements, which actions to try, when to move on, and what to look for.

### Strategy Auto-Selection

If no strategy was specified in `$ARGUMENTS`, choose based on context:

1. **Check for prior sessions**: List `session/fuzzsession-*.md` files for this app. If 2+ completed sessions exist, use `swarm-testing` — previous sessions already covered the basics, now maximize diversity.
2. **Otherwise, use the initial observation** (after Step 2):
   - Count the interactive elements on the first screen
   - **> 3 navigation elements** (tabs, list cells, buttons with navigation labels): use `state-exploration` — map the app structure first
   - **> 5 adjustable elements** (sliders, steppers, pickers) or **> 2 text fields**: use `boundary-testing` — test value extremes. Consider `invariant-testing` if the screen also has toggles or navigation.
   - **< 5 total interactive elements**: use `gesture-fuzzing` — go deep on each element with every gesture type
   - **Otherwise** (default): use `systematic-traversal` — breadth-first coverage
3. Print the auto-selected strategy and reasoning
4. Read the corresponding strategy file from `references/strategies/`

## Step 2: Initial Observation

1. Call `get_screen` — see the app's current state
2. Call `get_interface` — read the full element hierarchy
3. Print what you see:
   - App info (if visible from elements)
   - Screen description
   - Element count
   - Interactive elements count

Record this as Screen #1 with a fingerprint (set of identifiers + labels).

## Step 3: Initialize Session Notes

Create a new session notes file (see SKILL.md for naming convention):

**Filename**: `session/fuzzsession-YYYY-MM-DD-HHMM-fuzz-{strategy}.md`
(e.g. `session/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md`)

1. Write the `## Config` section (strategy, max iterations, app/device info, status: `in_progress`)
2. Write the `## Progress` section (actions: 0, current screen, phase: `fuzzing_loop`)
3. Write the `## Screens Discovered` table with Screen #1
4. Write the `## Coverage` section listing all elements on Screen #1 as untried
5. Write empty `## Transitions`, `## Findings`, `## Action Log` sections
6. Write `## Next Actions` describing what to try first on Screen #1

This file is your lifeline — keep it updated throughout the session.

## Step 4: Fuzzing Loop

Repeat until max iterations reached or a CRASH is detected:

### 4a. Observe
- `get_interface` — current hierarchy
- Fingerprint the screen

### 4b. Select Action (per strategy)
**Consult your notes first.** Read your session notes file — specifically `## Coverage` (which elements+actions have been tried on this screen) and `## Next Actions` (what you planned to do next). Use this to avoid repeating work and to follow through on your own plan.

Then follow the loaded strategy's element selection and action selection rules:
- Score elements using the Element Scoring system from SKILL.md (novelty +3, action gap +2, navigation +2, etc.) and pick the highest-scoring untried element+action combination
- If the element is a text field, read `references/interesting-values.md` for curated test inputs — try values from at least 3 categories
- If everything on this screen has been tried, use Screen Prioritization from SKILL.md to choose the next screen (highest exploration gap, fewest visits, directly reachable)
- If your planned Next Actions are still relevant, follow them

### 4c. Execute
- Call the selected MCP tool
- Increment `actions_taken`
- Add to `current_screen_actions`

### 4d. Verify
- `get_interface` — new hierarchy
- `get_screen` — visual state (take screenshots periodically, not after every single action — use judgment)
- Compare with pre-action state:
  - **Same screen, no change**: Normal, continue
  - **Same screen, value changed**: Expected for adjustable elements, anomaly otherwise
  - **New screen**: Record transition, add to `screens_visited` if new
  - **Element disappeared**: Potential ANOMALY
  - **Connection error**: CRASH detected — stop loop

### 4e. Record Findings
If anything unexpected happened, add to findings with severity level.
**Update session notes**: Add the finding to `## Findings`.

### 4f. Navigate
If the action navigated to a new screen:
- If the new screen hasn't been visited: switch to exploring it
- If already visited: navigate back to continue current screen

**Update session notes**: If a new screen was discovered, add it to `## Screens Discovered` and `## Coverage`. Add the transition to `## Transitions`.

### 4g. Checkpoint
Every 5 actions (or after any significant event):
- Update `## Progress` (action count, current screen, phase)
- Update `## Coverage` (mark tested elements)
- Update `## Action Log` (keep last 10 actions)
- Update `## Next Actions` (what you plan to do next)

Print a brief progress update every 10 actions:
```
[Progress] Actions: 42/100 | Screens: 5 | Findings: 2 (0 crash, 1 error, 1 anomaly)
```

## Step 5: Refinement Pass

If any ERROR or ANOMALY findings were discovered during the main loop:

1. **Reproduce**: For each finding, navigate back to the screen where it occurred
2. **Confirm**: Attempt to reproduce the exact same action 3 times
3. **Vary**: Try variations of the triggering action:
   - Same element, different action type (tap vs activate vs long_press)
   - Adjacent elements (order +/- 1)
   - Same action after arriving via a different navigation path
4. **Classify**: Update each finding's confidence:
   - **Reproducible**: Triggered on 2+ of 3 attempts
   - **Intermittent**: Triggered on 1 of 3 attempts
   - **Not reproduced**: Could not trigger again (may have been transient)
5. Remove findings that were "Not reproduced" from the main findings (mention them in a "Transient observations" section instead)

If no ERROR or ANOMALY findings, skip this step.

**Update session notes**: Update `## Status` to `refinement`, update finding confidence levels, update `## Next Actions`.

## Step 6: Generate Report

When the loop ends (iterations exhausted, crash detected, or all screens explored):

1. Print a summary to the conversation
2. Write a full report to `reports/` using the format from SKILL.md
3. **Update session notes**: Set `## Status` to `complete`

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

[Each finding in the format from SKILL.md]

### Screen Map
[List of screens visited and transitions between them]

### Coverage
[Elements tested / total elements across all screens]
```

## Crash Handling

If the app crashes (MCP tool call fails with connection error):

1. **Stop immediately** — the connection is dead
2. **Update session notes** immediately: Add the CRASH finding with the exact action, last 5-10 actions from `## Action Log`, and screen state. Set `## Status` to `crashed`.
3. Generate the report with what you have
4. Tell the user the app crashed and they need to relaunch it
