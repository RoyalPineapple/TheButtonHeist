---
description: Rapid-fire interaction testing to find stability and performance issues
---

# /fuzz-stress-test — Stress Tester

You are tasked with hammering the connected iOS app with rapid, repeated interactions to find stability issues, memory leaks, and crash bugs. You plan the stress tests, then delegate execution to a Haiku agent.

## CRITICAL
- ALWAYS verify the app is still responsive after each sequence — include health checks in the execution plan
- ALWAYS record which sequence and iteration caused a crash — this makes reproduction trivial
- ALWAYS reuse `BUTTONHEIST_TOKEN` after first auth approval — repeated auth prompts mean the token was not carried forward
- DO NOT stop at the first crash — record it and continue with other elements if possible

**Arguments** (optional): `$ARGUMENTS`
- Element identifier or "all" (default: "all" — stress test every interactive element)

## Step 0: Setup

Follow **## Session Setup** from SKILL.md (build CLI, verify connection, bootstrap auth token, check for existing session, load cross-session knowledge).

If starting fresh, create: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-stress-test-{target}.md`

## Step 1: Identify Targets

1. Run `buttonheist watch --once --format json --quiet` to get the current screen
2. If a specific element was requested, find it by identifier
3. If "all" (default), collect all interactive elements (those with actions or tappable)
4. Run `buttonheist screenshot --output /tmp/bh-screen.png` then Read the PNG for baseline visual state
5. Record the screen fingerprint (sorted set of identifiers) and element list

## Step 2: Build Execution Plans + Dispatch to Haiku

For each target element, build an execution plan and dispatch it to a Haiku executor via the Task tool (`model: "haiku"`).

### Building the Execution Plan

Use the **Execution Plan Template** from SKILL.md. For each target element, generate an execution plan containing:

**Context block**: CLI path, auth token, session notes path, trace file path, next trace seq, next finding ID, current screen name + fingerprint, nav stack.

**Action list**: All 6 stress test sequences for this element, with health checks between sequences. Generate the exact CLI commands by substituting the element's identifier into the templates below.

#### Sequence Templates

For each target element (`ELEMENT` = the identifier), the action list contains:

**Sequence 1 — Rapid Taps (20 actions)**:
- 20x `buttonheist touch tap --identifier ELEMENT --format json`
- Expected delta: `noChange` for most (some may produce `valuesChanged`)
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Sequence 2 — Rapid Swipes (10 actions, alternating up/down)**:
- 5x alternating: `buttonheist touch swipe --identifier ELEMENT --direction up --format json` then `--direction down`
- Expected delta: `noChange` or `valuesChanged`
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Sequence 3 — Rapid Pinch Cycles (10 actions)**:
- 5x alternating: `buttonheist touch pinch --identifier ELEMENT --scale 2.0 --format json` then `--scale 0.5`
- Expected delta: `noChange`
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Sequence 4 — Rapid Rotate Cycles (10 actions)**:
- 5x alternating: `buttonheist touch rotate --identifier ELEMENT --angle 1.57 --format json` then `--angle -1.57`
- Expected delta: `noChange`
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Sequence 5 — Mixed Rapid Gestures (10 actions)**:
- tap, longpress (0.1s), swipe left, tap, pinch (1.5), tap, rotate (0.5), tap, two-finger-tap, tap
- Expected delta: `noChange` for most
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Sequence 6 — Increment/Decrement Hammering (40 actions, only if element is adjustable)**:
- 20x `buttonheist action --identifier ELEMENT --type increment --format json`
- 20x `buttonheist action --identifier ELEMENT --type decrement --format json`
- Expected delta: `valuesChanged`
- Purpose: `stress`

**Health check**: `buttonheist watch --once --format json --quiet`

**Stop conditions**: Stop on crash. Stop on 3+ consecutive unexpected results.

**Total actions per element**: ~80-106 (depending on whether Sequence 6 applies).

### Dispatching

For each target element:

1. Generate the full execution plan from the templates above, substituting the element identifier
2. Dispatch to Haiku:
   ```
   Task(
     description: "[the execution plan as markdown]",
     model: "haiku",
     subagent_type: "Bash"
   )
   ```
3. Wait for Haiku to return
4. Read the Execution Result from Haiku's return
5. If status is `stopped` with reason `crash`:
   - Record the crash finding with exact sequence and iteration
   - If other target elements remain and crash was element-specific, continue to next element
   - If crash killed the app connection, stop and proceed to report
6. If status is `complete`: record results, proceed to next element
7. Update session notes between elements: `## Coverage` with per-sequence results, `## Findings` with any new findings, `## Progress` with action count

### Progress Tracking

After each element's batch completes, print:
```
[Stress] Element: IDENTIFIER — [complete/stopped] | Actions: N | Findings: M
```

## Step 3: Full-Screen Stress

After individual element testing, build a second execution plan for full-screen stress:

1. 10 taps at random coordinates across the screen
2. Swipes in all 4 directions from screen center
3. Pinch at screen center (scale 3.0 then 0.3)
4. Rotate at screen center (full rotation then reverse)

Dispatch this as a single Haiku batch (~20 actions). Read the return and record results.

## Step 4: Health Check

After all sequences (Opus does this directly — not delegated):

1. `buttonheist watch --once --format json --quiet` — verify element count hasn't changed dramatically
2. `buttonheist screenshot` — visual comparison with baseline
3. Report any degradation:
   - Elements that disappeared
   - Values that changed unexpectedly
   - Visual differences from baseline
   - Haiku-reported notes about unexpected state changes

## Step 5: Report

Print a stress test report:

```
## Stress Test Report

**Target**: [element identifier or "all elements"]
**Screen**: [screen description]
**Sequences Run**: [count]
**Total Interactions**: [count]

### Results

| Sequence | Target | Status | Notes |
|----------|--------|--------|-------|
| Rapid Taps (20x) | loginButton | PASS | No issues |
| Rapid Swipes (10x) | listView | ANOMALY | Element count changed |
| ...

### Findings

[Any CRASH, ERROR, or ANOMALY findings — include those reported by Haiku]

### Haiku Execution Notes

[Collate all Notes sections from Haiku returns — element-not-found, prediction mismatches, etc.]

### Health Check
- Elements before: [count], after: [count]
- Visual changes: [yes/no — describe if yes]
- Responsiveness: [normal / degraded]
```

## Crash Handling

Crashes during stress testing are **expected and valuable**. When Haiku reports a crash (status: `stopped`, reason: `crash`):
1. Record the exact sequence, element, and iteration from Haiku's Stop Details
2. This is directly reproducible: "[sequence name] on [element] at iteration [N]"
3. If the app is dead (connection lost), generate the report with what you have
4. Tell the user the app crashed and they need to relaunch it
