---
description: Replay a finding's action trace to verify reproducibility and investigate root cause
---

# /fuzz-reproduce — Finding Reproducer

You are tasked with replaying the action sequence that triggered a specific finding to verify it is reproducible. You plan the reproduction, then delegate execution to a Haiku agent for each attempt.

**Arguments**: `$ARGUMENTS`
- Finding ID (e.g., `F-3`) or description keyword (e.g., `toggle`, `crash`)
- Optional: session file name to target a specific session

## CRITICAL
- ALWAYS use exact tool names and arguments from the trace — do not improvise actions
- ALWAYS compare fingerprints before and after each action against the trace's recorded state
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- ALWAYS present the reproduction plan and wait for user confirmation before executing
- DO NOT modify app state beyond what the trace specifies
- DO NOT continue past major divergence (< 50% similarity) without reporting

## Step 0: Find the Trace

1. List `.fuzzer-data/sessions/fuzzsession-*.trace.md` files
2. If a session was specified in `$ARGUMENTS`, find the matching trace file
3. Otherwise, use the most recent trace file
4. Read the trace file header to find the companion session notes file
5. Read the session notes file
6. **Load session notes format**: Read `references/session-notes-format.md` for notes file format conventions.
7. **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.

If no trace files exist, stop and tell the user: "No trace files found. Run `/fuzz` or `/fuzz-explore` first — they generate trace files automatically."

## Step 1: Find the Finding

1. In the session notes, search `## Findings` for the specified finding
2. Match by:
   - Exact finding ID: `F-3`
   - Severity keyword: `CRASH`, `ERROR`, `ANOMALY`
   - Description substring: `toggle`, `slider`, `navigate`
3. If multiple findings match, list them and ask the user to pick one
4. Extract the finding's `**Trace refs**` — these are the key sequence numbers
5. If no trace refs found, extract the finding's `**Action**` field and search the trace for matching entries

Print the finding:
```
Finding: F-3 [ANOMALY] Toggle doesn't respond to activate
Trace refs: #42, #43
Screen: Settings
```

## Step 2: Build the Reproduction Sequence

1. Find the earliest trace ref for the finding (e.g., `#42`)
2. **Plan navigation using nav graph** (preferred): Read `references/nav-graph.md` and find the shortest route from the app's root screen to the finding's screen. This uses accumulated knowledge from prior sessions and is often shorter than the original trace path.
3. **Fall back to trace-walking** if nav graph doesn't cover the finding's screen: Walk backward through the trace to build the navigation path — find all `type: interact` and `type: navigate` entries where `result.screen_changed: true`, chain them from initial screen to the finding's screen.
4. The reproduction sequence is: `[navigation path] + [finding's trace entries]`
5. Present the plan:

```
Reproduction plan (5 actions):
  1. [trace #2]  activate(order: 3)         — navigate Controls Demo → Adjustable Controls
  2. [trace #10] activate(order: 8)         — navigate Adjustable Controls → Controls Demo
  3. [trace #12] activate(identifier: "settings") — navigate Controls Demo → Settings
  4. [trace #42] activate(identifier: "darkModeToggle") — the triggering action
  5. [trace #43] buttonheist watch --once --format json --quiet — verify the anomaly

Proceed? (waiting for confirmation)
```

6. Wait for user confirmation before executing

## Step 3: Verify Connection

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm device is connected
3. Bootstrap auth token once: run `buttonheist watch --once --format json --quiet`, capture `BUTTONHEIST_TOKEN=...` from output, and store as `AUTH_TOKEN` for this reproduction run
4. Reuse token on every later command: `buttonheist ... --token "$AUTH_TOKEN"` (or `BUTTONHEIST_TOKEN="$AUTH_TOKEN" buttonheist ...`)
5. **Load nav graph**: Read `references/nav-graph.md` for route planning
6. Run `buttonheist watch --once --format json --quiet` — fingerprint the current screen
7. If already on the finding's screen, skip navigation steps
8. If not on the expected starting screen, **plan a route** from current screen to the finding's screen using the nav graph and `## Transitions`

## Step 4: Dispatch Execution to Haiku

For each reproduction attempt, build an execution plan and dispatch to Haiku.

### Building the Execution Plan

Read `references/execution-protocol.md` for the full plan format. The reproduction execution plan contains:

**Context block**: CLI path, auth token, session notes path, trace file path, next trace seq, next finding ID, current screen + fingerprint, nav stack.

**Action list**: The reproduction sequence from Step 2, where each action has:
- `command`: Exact CLI command from the trace entry
- `expected_delta`: Based on trace — `screenChanged` for navigation steps, the original delta kind for the triggering action
- `expected_screen`: Destination screen name for navigation steps
- `prediction`: From the trace's recorded result
- `purpose`: `navigation` for route steps, `investigation` for the triggering action and verification

**Additional instructions for Haiku** (included in the plan):

Before each action:
1. Run `buttonheist watch --once --format json --quiet` to get the current fingerprint
2. Compare with the trace's expected `screen_fingerprint_before` using overlap similarity:
   - **100%**: Exact match — continue
   - **≥ 80%**: Minor drift — note and continue
   - **≥ 50%**: Significant drift — note "uncertain reproduction", continue
   - **< 50%**: Major divergence — **stop and report back** (app is on a wrong screen)

After the finding's triggering action, verify whether the finding reproduces:
- **CRASH**: Did the connection die?
- **ERROR**: Did the same error occur?
- **ANOMALY**: Does the post-action state show the same anomalous behavior?

Include this verification result in the return's Notes.

**Recording setup** (include in the plan as first and last actions):
- First: `mkdir -p .fuzzer-data/recordings && buttonheist record --output .fuzzer-data/recordings/F-N-reproduce.mp4 --max-duration <estimated> --inactivity-timeout 60 --fps 8 --scale 0.5 --quiet >/tmp/fuzz-reproduce-record.log 2>&1 &` then `sleep 2`
- Last: `ls -la .fuzzer-data/recordings/F-N-reproduce.mp4` (recording auto-stops on inactivity)

**Stop conditions**: Stop on crash. Stop on < 50% fingerprint similarity (major divergence). Stop on 3+ consecutive unexpected results.

### Dispatching

```
Task(
  description: "[the execution plan as markdown]",
  model: "haiku",
  subagent_type: "Bash"
)
```

### Reading Haiku's Return

Parse the Execution Result:
- Check `Status` — complete or stopped
- Check `Notes` for divergence reports and finding reproduction result
- Check `Findings` for any CRASH findings
- Record the divergence summary for the report

## Step 5: Multiple Attempts

Try the reproduction up to 3 times. Opus manages the attempt loop, dispatching Haiku for each attempt:

1. **Attempt 1**: Straight replay — dispatch the exact reproduction plan
2. **Attempt 2** (if attempt 1 failed due to timing): Modify the plan to include brief pauses between actions (add `sleep 1` commands between action entries)
3. **Attempt 3** (if element identifiers changed): Modify the plan to use `--index N` instead of `--identifier ID` for elements Haiku reported as not found

Between attempts for CRASH findings, tell the user to relaunch the app and wait for `buttonheist list` to show the device again.

After each attempt, print:
```
[Reproduce] Attempt N: [reproduced/not reproduced/diverged] | Divergences: M
```

## Step 6: Report

Opus generates the report directly (not delegated):

```
## Reproduction Result

**Finding**: F-3 [ANOMALY] Toggle doesn't respond to activate
**Original session**: fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md
**Recording**: .fuzzer-data/recordings/F-3-reproduce.mp4
**Actions replayed**: 5

### Result: REPRODUCED

**Attempts**: 2/3 matched original behavior
**Details**:
- Attempt 1: REPRODUCED — toggle value remained "0" after activate (matches original)
- Attempt 2: REPRODUCED — same behavior
- Attempt 3: skipped (already confirmed)

### Divergences
| Step | Trace Expected | Actual | Severity |
|------|---------------|--------|----------|
| 3 | Settings: 12 elements | Settings: 13 elements | minor drift |

### Haiku Execution Notes
[Collate noteworthy events from all Haiku returns — element fallbacks, prediction mismatches, etc.]

### Conclusion
Finding F-3 is a **reproducible** anomaly. The dark mode toggle does not respond to
activate on the Settings screen. This occurs regardless of navigation path.
```

### Classification

| Result | Criteria |
|--------|----------|
| **REPRODUCED** | 2+ of 3 attempts showed the same behavior |
| **INTERMITTENT** | 1 of 3 attempts showed the behavior |
| **NOT REPRODUCED** | 0 of 3 attempts showed the behavior |
| **INCONCLUSIVE** | Could not reach the finding's screen due to divergence |

## Error Handling

- If the trace file is malformed or entries can't be parsed: report which entries failed and attempt to continue with parseable entries
- If the app is not running: tell the user to launch it and try again
- If the finding references trace entries that don't exist in the trace: report the gap and attempt to reproduce from the finding's `Steps to Reproduce` instead
