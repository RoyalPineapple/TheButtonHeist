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
- This is a PRESENTATION tool, not a verification tool
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
7. **Load session file format**: Read `references/session-files.md` for format conventions

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
- Plan: 1 action (verify screen)

### Act 2: Happy Path (optional)
Show what SHOULD happen to set a baseline expectation.
- If the finding involves an element that should change (toggle, slider, button navigation), demonstrate it working correctly on a DIFFERENT but similar element first
- This gives the viewer a "before" to compare against the bug
- **Skip this act** if: crash findings, launch failures, no meaningful comparison exists, or you cannot identify a working similar element
- Plan: 2-5 actions

### Act 3: The Bug
Navigate to the finding's screen and trigger the bug.
- Use the nav graph to plan the shortest route from the current screen to the finding's screen
- Fall back to trace entries if nav graph doesn't cover the route
- Execute the triggering action
- Plan: navigation actions + trigger action

### Duration Estimate

Calculate the total:
- Per-action time: **7 seconds** (MCP tool call ~50ms + agent think time ~5-7s)
- Buffer: **20 seconds** (final hold)
- Formula: `(total_actions × 7) + 20`

Present the demo script and **wait for user confirmation**:
```
[Demo Script]
Act 1 — Context:
  1. Home screen — verify starting state

Act 2 — Happy Path:
  2. activate(identifier: "wifiToggle") — show a working toggle
  3. activate(identifier: "wifiToggle") — toggle it back

Act 3 — The Bug:
  4. activate(identifier: "settings") — navigate to Settings
  5. activate(identifier: "darkModeToggle") — trigger the bug

Total: 5 actions, estimated duration: 55s
Output: .fuzzer-data/recordings/F-3-demo.mp4

Proceed? (waiting for confirmation)
```

## Step 3: Verify Connection

Follow **## Session Setup** from SKILL.md (verify connection).

Then: fingerprint the current screen. If not on the app's main/launch screen, navigate there using the nav graph or Back actions.

## Step 4: Execute the Demo with Recording

### Start Recording

1. Create the recordings directory: `mkdir -p .fuzzer-data/recordings` (via Bash)
2. Call `start_recording(fps: 8, scale: 0.5, maxDuration: <estimated_duration>, inactivityTimeout: 60)`

### Execute Each Action

For each action in the demo script:

1. **Execute** the MCP tool call (`activate`, `gesture`, `swipe`, `type_text`, etc.)
2. **Read the delta** from the action response
   - If `screenChanged`, use the new interface for context — no need to call `get_interface`
   - If on a new screen, note it for navigation awareness
4. **At key moments**, call `get_screen` to confirm what's on screen:
   - Start of Act 1 (home screen)
   - Start of Act 3 (the finding's screen, before triggering)
   - After the triggering action (the bug state)

### Stop and Collect Recording

After executing the last action, stop the recording:

Call `stop_recording(output: ".fuzzer-data/recordings/{FINDING_ID}-demo.mp4")` — returns metadata (duration, frame count, file size).

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
