---
description: Generate a structured findings report from the current session
---

# /fuzz-report — Report Generator

You are tasked with generating a comprehensive report of all findings from the current fuzzing session and saving it to the `.fuzzer-data/reports/` directory.

## CRITICAL
- ALWAYS read the session notes file as primary source of truth — it survives compaction, your memory doesn't
- ALWAYS include trace refs for every finding — findings without trace refs are not reproducible
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- DO NOT invent or embellish findings — report only what was observed and recorded

## Step 0: Setup

Follow **## Session Setup** from SKILL.md (build CLI, verify connection, bootstrap auth token).

## Step 1: Gather Context

1. **Read the session notes file** — list `.fuzzer-data/sessions/fuzzsession-*.md` files, find the most recent one. This is the primary source of truth for the session, especially after compaction. It contains screens, findings, transitions, coverage, and action log.
2. Run `buttonheist watch --once --format json --quiet` to get the current screen state (confirms the app is still connected)
3. Review the session notes plus any additional findings, observations, and notes from this conversation session
4. Collect:
   - Screens visited and their descriptions (from `## Screens Discovered`)
   - Actions taken (from `## Progress`)
   - All findings with severity levels (from `## Findings`)
   - Screen transitions discovered (from `## Transitions`)
   - Any crashes encountered

## Step 2: Build the Report

Write a report file to `.fuzzer-data/reports/` with today's date and time:

**Filename**: `.fuzzer-data/reports/YYYY-MM-DD-HHMM-fuzz-report.md`

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

[If /fuzz-map-screens was run, include the graph. Otherwise, list screens visited:]

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

1. Write the report to `.fuzzer-data/reports/YYYY-MM-DD-HHMM-fuzz-report.md`
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
