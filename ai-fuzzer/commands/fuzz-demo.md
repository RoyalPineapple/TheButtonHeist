---
description: Create a polished demo video showing a fuzzer finding's bug reproduction
---

# /fuzz-demo — Finding Demo Video

You are tasked with creating a polished, human-watchable demo video of a specific finding from a fuzzing session. The output is a single MP4 that clearly shows the bug — suitable for sharing in bug reports, Slack, or presentations.

Unlike `/fuzz-reproduce` (which verifies reproducibility with multiple attempts and divergence detection), this command focuses on **presentation**: deliberate pacing, narrative structure, and a single clean take.

**Arguments**: `$ARGUMENTS`
- Finding ID (e.g., `F-3`) — required
- Optional: session file name to target a specific session

## CRITICAL
- This is a PRESENTATION tool, not a verification tool — prioritize watchability over speed
- ALWAYS add deliberate pauses (`sleep 3-5`) between actions so a human viewer can follow
- ALWAYS start from the app's main/launch screen for context
- ALWAYS show the happy path first (what SHOULD happen), then the bug — unless there is no meaningful happy path (e.g., crash on launch)
- DO NOT attempt multiple reproduction tries — one clean take
- DO NOT use divergence detection — if the bug doesn't appear, report it and stop
- DO NOT modify the session notes findings — only add the demo recording path to `## Recordings`
- ALWAYS present the demo script and wait for user confirmation before executing

## Step 0: Find the Finding

1. List `.fuzzer-data/sessions/fuzzsession-*.md` files
2. If a session was specified in `$ARGUMENTS`, find that session
3. Otherwise, search all session files for the finding ID in `## Findings`
4. Read the session notes and extract:
   - Finding ID, severity, description
   - Screen where it occurs
   - Action that triggers it (from `**Action**` field)
   - Trace refs (from `**Trace refs**` field)
   - Steps to Reproduce (if present)
5. Read the companion `.trace.md` file and extract the relevant trace entries
6. If the finding has `**Steps to Reproduce**`, prefer those over raw trace entries
7. **Load session notes format**: Read `references/session-notes-format.md` for format conventions

Print:
```
[Demo Target]
Finding: F-3 [ANOMALY] Toggle doesn't respond to activate
Screen: Settings
Trigger: activate(identifier: "darkModeToggle")
Session: fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md
```

If the finding cannot be found, list available findings from recent sessions and ask the user to pick one.

## Step 1: Load References

1. Read `references/recording-guide.md` for recording settings and the background recording pattern
2. Read `references/navigation-planning.md` for route planning
3. Read `references/nav-graph.md` (if it exists) for known screen transitions

## Step 2: Build the Demo Script

Plan the entire demo sequence before executing. The demo has three acts:

### Act 1: Context
Show the app's starting state to orient the viewer.
- Ensure the app is on its main/launch screen
- Hold for 3 seconds so the viewer sees the home screen
- Plan: 1 action (verify screen) + 3s pause

### Act 2: Happy Path (optional)
Show what SHOULD happen to set a baseline expectation.
- If the finding involves an element that should change (toggle, slider, button navigation), demonstrate it working correctly on a DIFFERENT but similar element first
- This gives the viewer a "before" to compare against the bug
- **Skip this act** if: crash findings, launch failures, no meaningful comparison exists, or you cannot identify a working similar element
- Plan: 2-5 actions with 3s pauses between each

### Act 3: The Bug
Navigate to the finding's screen and trigger the bug.
- Use the nav graph to plan the shortest route from the current screen to the finding's screen
- Fall back to trace entries if nav graph doesn't cover the route
- Execute the triggering action
- Hold for 5 seconds so the viewer sees the result
- Plan: navigation actions + trigger action + 5s final hold

### Duration Estimate

Calculate the total:
- Per-action time: **15 seconds** (higher than reproduce to account for deliberate pauses)
- Buffer: **20 seconds** (connection setup + final hold)
- Formula: `(total_actions × 15) + 20`

Present the demo script and **wait for user confirmation**:
```
[Demo Script]
Act 1 — Context:
  1. [pause 3s] Home screen — verify starting state

Act 2 — Happy Path:
  2. [pause 3s] activate(identifier: "wifiToggle") — show a working toggle
  3. [pause 3s] activate(identifier: "wifiToggle") — toggle it back

Act 3 — The Bug:
  4. [pause 3s] activate(identifier: "settings") — navigate to Settings
  5. [pause 3s] activate(identifier: "darkModeToggle") — trigger the bug
  6. [pause 5s] Final hold — viewer sees the anomaly

Total: 6 actions, estimated duration: 110s
Output: .fuzzer-data/recordings/F-3-demo.mp4

Proceed? (waiting for confirmation)
```

## Step 3: Verify Connection

1. **Ensure CLI is on PATH**: Build the CLI if `buttonheist` is not available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` — confirm device is connected
3. **Set up fast connections**: If `BUTTONHEIST_HOST` is not already set:
   ```bash
   export BUTTONHEIST_HOST=127.0.0.1
   export BUTTONHEIST_PORT=1455
   ```
4. Run `buttonheist watch --once --format json --quiet` — fingerprint the current screen
5. If not on the app's main/launch screen, navigate there using the nav graph or Back actions

## Step 4: Execute the Demo with Recording

### Start Recording

```bash
mkdir -p .fuzzer-data/recordings
buttonheist record \
  --output .fuzzer-data/recordings/{FINDING_ID}-demo.mp4 \
  --max-duration <estimated_duration> \
  --inactivity-timeout 60 \
  --fps 8 --scale 0.5 --quiet &
RECORD_PID=$!
sleep 2
```

### Execute Each Action with Deliberate Pacing

For each action in the demo script:

1. **Pause** before the action:
   - Standard actions: `sleep 3`
   - Final hold (last action in Act 3): `sleep 5`
   - This gives viewers time to read the screen before the next interaction
2. **Execute** the CLI command (`buttonheist action`, `buttonheist touch`, etc.)
3. **Read the delta** from the action response
   - If `screenChanged`, use the new interface for context — no need to call `watch`
   - If on a new screen, note it for navigation awareness
4. **At key moments**, take a screenshot and read it to confirm what's on screen:
   - Start of Act 1 (home screen)
   - Start of Act 3 (the finding's screen, before triggering)
   - After the triggering action (the bug state)

### Stop and Collect Recording

After executing the last action and the final hold pause, explicitly stop the recording:

```bash
buttonheist stop-recording --quiet
wait $RECORD_PID
ls -la .fuzzer-data/recordings/{FINDING_ID}-demo.mp4
```

## Step 5: Verify and Report

1. Confirm the recording file exists and has non-zero size
2. Assess whether the bug appeared during Act 3:
   - **Yes**: Demo is complete and valid
   - **No**: Report that the bug did not reproduce; keep the recording (it documents the attempt) and suggest running `/fuzz-reproduce` to verify the finding's status

3. Update session notes:
   - Add the demo to `## Recordings` table:
     ```
     | {FINDING_ID} | .fuzzer-data/recordings/{FINDING_ID}-demo.mp4 | {duration}s | Demo video |
     ```
   - Add `**Demo**: .fuzzer-data/recordings/{FINDING_ID}-demo.mp4` to the finding entry

4. Print the result:

```
## Demo Result

**Finding**: F-3 [ANOMALY] Toggle doesn't respond to activate
**Recording**: .fuzzer-data/recordings/F-3-demo.mp4
**Duration**: ~45s
**Acts**: Context (home screen) → Happy path (wifi toggle works) → Bug (dark mode toggle fails)
**Bug reproduced**: Yes

The demo video is ready at .fuzzer-data/recordings/F-3-demo.mp4
```

## Error Handling

- **Finding not found**: List available findings from recent sessions and ask the user to pick one
- **App not running**: Tell the user to launch the app and try again
- **Cannot reach finding's screen**: Report the navigation failure and suggest the user manually navigate to the screen, then re-run
- **Bug does not reproduce**: Save the recording anyway, report it, suggest `/fuzz-reproduce` for formal verification
- **Recording fails to start**: Fall back to taking screenshots at each step and report the sequence with screenshots instead of video
- **Happy path element not found**: Skip Act 2 entirely — go straight from Context to the Bug
