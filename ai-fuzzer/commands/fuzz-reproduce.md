---
description: Replay a finding's action trace to verify reproducibility and investigate root cause
---

# /fuzz-reproduce — Finding Reproducer

You are tasked with replaying the action sequence that triggered a specific finding to verify it is reproducible. Read the action trace from a previous fuzzing session and re-execute the minimal sequence needed to reach and trigger the finding.

**Arguments**: `$ARGUMENTS`
- Finding ID (e.g., `F-3`) or description keyword (e.g., `toggle`, `crash`)
- Optional: session file name to target a specific session

## CRITICAL
- ALWAYS use exact tool names and arguments from the trace — do not improvise actions
- ALWAYS compare fingerprints before and after each action against the trace's recorded state
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
4. Present the plan:

```
Reproduction plan (5 actions):
  1. [trace #2]  activate(order: 3)         — navigate Controls Demo → Adjustable Controls
  2. [trace #10] activate(order: 8)         — navigate Adjustable Controls → Controls Demo
  3. [trace #12] activate(identifier: "settings") — navigate Controls Demo → Settings
  4. [trace #42] activate(identifier: "darkModeToggle") — the triggering action
  5. [trace #43] get_interface              — verify the anomaly

Proceed? (waiting for confirmation)
```

5. Wait for user confirmation before executing

## Step 3: Verify Connection

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm device is connected
3. **Load nav graph**: Read `references/nav-graph.md` for route planning
3. Run `buttonheist watch --once --format json --quiet` — fingerprint the current screen
4. If already on the finding's screen, skip navigation steps
5. If not on the expected starting screen, **plan a route** from current screen to the finding's screen using the nav graph and `## Transitions`

## Step 4: Execute with Recording + Divergence Detection

### Pre-execution: Start Recording

Before executing the reproduction sequence, start a background recording to capture video evidence:

1. Read `references/recording-guide.md` for the full recording workflow
2. Estimate duration: `(number of actions in reproduction plan) × 10 + 15` seconds
3. Create the recordings directory and start recording:
   ```bash
   mkdir -p .fuzzer-data/recordings
   buttonheist record \
     --output .fuzzer-data/recordings/F-N-reproduce.mp4 \
     --max-duration <estimated_duration> --inactivity-timeout 60 --fps 8 --scale 0.5 --quiet &
   RECORD_PID=$!
   sleep 2
   ```
4. The recording runs independently in the background with a 60-second inactivity timeout — each of your CLI interactions resets the timer, keeping the recording alive between actions

### Execute Actions

For each action in the reproduction sequence:

### Before each action
1. Run `buttonheist watch --once --format json --quiet` to get the current fingerprint
2. Compare with the trace's expected `screen_fingerprint_before`:

```
expected = set(trace_entry.screen_fingerprint_before)
actual   = set(current_interface_identifiers)
overlap  = expected & actual
similarity = len(overlap) / max(len(expected), len(actual))
```

3. React based on similarity:
   - **100%**: Exact match — continue
   - **≥ 80%**: Minor drift — log and continue
   - **≥ 50%**: Significant drift — warn, continue but flag reproduction as uncertain
   - **< 50%**: Major divergence — app is on a different screen. Report and ask to continue or abort.

### Execute the action
1. Run the corresponding CLI command from the trace entry
2. If the target element's identifier is not found in the current interface:
   a. Search by label (trace's `target.label`)
   b. Search by frame position overlap
   c. If found by alternate method: use it, log the identifier mismatch
   d. If not found at all: skip this action, report "element not found"

### After each action
1. Read the delta from the action response — quick check: did `screenChanged` match the trace's expectation?
2. If the delta was `screenChanged`, use the included `newInterface` for fingerprinting. Otherwise, call `get_interface` for full state.
3. Compare the fingerprint with the trace's `screen_fingerprint_after`
4. **At the finding's triggering action**, check if the finding reproduces:
   - **CRASH**: Did the connection die?
   - **ERROR**: Did the same error occur?
   - **ANOMALY**: Does the post-action state show the same anomalous behavior described in the finding?

### Post-execution: Collect Recording

After completing all actions for this attempt:

1. Wait for background recording to finish: `wait $RECORD_PID`
2. Verify the recording file exists: `ls -la .fuzzer-data/recordings/F-N-reproduce.mp4`
3. Note the file path for the report

For subsequent attempts (Step 5), start a new recording with a numbered suffix (e.g., `F-N-reproduce-2.mp4`). Use the best recording (the one where the finding reproduced) in the final report.

## Step 5: Multiple Attempts

Try the reproduction up to 3 times:

1. **Attempt 1**: Straight replay — execute actions exactly as traced
2. **Attempt 2** (if attempt 1 failed due to timing): Add a brief pause between actions
3. **Attempt 3** (if element identifiers changed): Match elements by label and position instead of identifier

Between attempts for CRASH findings, tell the user to relaunch the app and wait for `list_devices` to show the device again.

## Step 6: Report

Print a structured result:

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
