---
description: Autonomous fuzzing loop — explores the app and discovers bugs
---

# /fuzz — Autonomous Fuzzer

You are going to autonomously fuzz the connected iOS app. You will explore screens, try interactions, navigate the app, and report any crashes, errors, or anomalies you find.

**Arguments** (optional): `$ARGUMENTS`
- First argument: strategy name (default: `systematic-traversal`). Options: `systematic-traversal`, `boundary-testing`, `gesture-fuzzing`, `state-exploration`
- Second argument: max iterations (default: 100)

## Step 0: Load Strategy

Parse `$ARGUMENTS` for the strategy name and iteration limit. Read the corresponding strategy file from `strategies/[name].md`. If no strategy specified, read `strategies/systematic-traversal.md`.

The strategy tells you how to select elements, which actions to try, when to move on, and what to look for.

## Step 1: Initial Observation

1. Call `get_screen` — see the app's current state
2. Call `get_interface` — read the full element hierarchy
3. Print what you see:
   - App info (if visible from elements)
   - Screen description
   - Element count
   - Interactive elements count

Record this as Screen #1 with a fingerprint (set of identifiers + labels).

## Step 2: Initialize Tracking

Start tracking:
- `screens_visited`: set of screen fingerprints
- `screen_transitions`: list of (from_screen, action, to_screen) tuples
- `actions_taken`: count
- `findings`: list of (severity, description, details)
- `current_screen_actions`: set of (element, action_type) pairs already tried on current screen

## Step 3: Fuzzing Loop

Repeat until max iterations reached or a CRASH is detected:

### 3a. Observe
- `get_interface` — current hierarchy
- Fingerprint the screen

### 3b. Select Action (per strategy)
Follow the loaded strategy's element selection and action selection rules:
- Pick an untried element+action combination
- If everything on this screen has been tried, navigate to a new screen

### 3c. Execute
- Call the selected MCP tool
- Increment `actions_taken`
- Add to `current_screen_actions`

### 3d. Verify
- `get_interface` — new hierarchy
- `get_screen` — visual state (take screenshots periodically, not after every single action — use judgment)
- Compare with pre-action state:
  - **Same screen, no change**: Normal, continue
  - **Same screen, value changed**: Expected for adjustable elements, anomaly otherwise
  - **New screen**: Record transition, add to `screens_visited` if new
  - **Element disappeared**: Potential ANOMALY
  - **Connection error**: CRASH detected — stop loop

### 3e. Record Findings
If anything unexpected happened, add to findings with severity level.

### 3f. Navigate
If the action navigated to a new screen:
- If the new screen hasn't been visited: switch to exploring it
- If already visited: navigate back to continue current screen

Print a brief progress update every 10 actions:
```
[Progress] Actions: 42/100 | Screens: 5 | Findings: 2 (0 crash, 1 error, 1 anomaly)
```

## Step 4: Generate Report

When the loop ends (iterations exhausted, crash detected, or all screens explored):

1. Print a summary to the conversation
2. Write a full report to `reports/` using the format from CLAUDE.md

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

[Each finding in the format from CLAUDE.md]

### Screen Map
[List of screens visited and transitions between them]

### Coverage
[Elements tested / total elements across all screens]
```

## Crash Handling

If the app crashes (MCP tool call fails with connection error):

1. **Stop immediately** — the connection is dead
2. Record the CRASH finding with:
   - The exact action that caused it
   - The last 5-10 actions leading up to it
   - The screen state before the crash
3. Generate the report with what you have
4. Tell the user the app crashed and they need to relaunch it
