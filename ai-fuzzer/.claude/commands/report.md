---
description: Generate a structured findings report from the current session
---

# /report — Report Generator

Generate a comprehensive report of all findings from this fuzzing session and save it to the `reports/` directory.

## Step 0: Verify Connection

1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app and try again
3. Print the connected device name and app name for confirmation

## Step 1: Gather Context

1. **Read the session notes file** — list `session/fuzzsession-*.md` files, find the most recent one. This is the primary source of truth for the session, especially after compaction. It contains screens, findings, transitions, coverage, and action log.
2. Call `get_interface` to get the current screen state (confirms the app is still connected)
3. Review the session notes plus any additional findings, observations, and notes from this conversation session
4. Collect:
   - Screens visited and their descriptions (from `## Screens Discovered`)
   - Actions taken (from `## Progress`)
   - All findings with severity levels (from `## Findings`)
   - Screen transitions discovered (from `## Transitions`)
   - Any crashes encountered

## Step 2: Build the Report

Write a report file to `reports/` with today's date and time:

**Filename**: `reports/YYYY-MM-DD-HHMM-fuzz-report.md`

**Structure**:

```markdown
# Fuzzing Report

**Date**: [timestamp]
**Strategy**: [strategy used, or "manual" if ad-hoc exploration]
**App**: [app name and bundle ID if known from server info]
**Device**: [device name and iOS version if known]

## Summary

| Metric | Value |
|--------|-------|
| Screens visited | X |
| Total actions | X |
| Findings | X |
| CRASH | X |
| ERROR | X |
| ANOMALY | X |
| INFO | X |

## Findings

### CRASH

[If any crashes found, list each with full details:]

#### [CRASH] [Brief description]
**Screen**: [where it happened]
**Action**: [exact tool call]
**Steps to Reproduce**:
1. [step-by-step from app launch]
2. [...]
3. [the triggering action]
**Notes**: [additional context]

---

### ERROR

[Same format for errors]

---

### ANOMALY

[Same format for anomalies]

---

### INFO

[Same format for informational findings]

## Screen Map

[If /map-screens was run, include the graph. Otherwise, list screens visited:]

| # | Screen | Elements | How Reached |
|---|--------|----------|-------------|
| 1 | [name] | [count]  | [starting screen / tap X from Y] |

## Coverage

### Elements Tested
[List of elements that were interacted with, grouped by screen]

### Elements Not Tested
[List of elements that were seen but not interacted with, and why]

### Gestures Used
| Gesture | Count |
|---------|-------|
| tap | X |
| swipe | X |
| long_press | X |
| pinch | X |
| rotate | X |
| [etc.] | X |
```

## Step 3: Save and Confirm

1. Write the report to `reports/YYYY-MM-DD-HHMM-fuzz-report.md`
2. Print the report summary to the conversation
3. Tell the user where the report was saved

## When There Are No Findings

If no bugs were found, that's still a valid result:

```markdown
## Summary

No crashes, errors, or anomalies detected during this fuzzing session.

| Metric | Value |
|--------|-------|
| Screens visited | X |
| Total actions | X |
| Findings | 0 |

This is a positive signal — the tested surfaces appear stable under the [strategy] strategy.
Untested areas: [list anything that wasn't covered and why]
```
