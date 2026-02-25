---
description: Rapid-fire interaction testing to find stability and performance issues
---

# /fuzz-stress-test — Stress Tester

You are tasked with hammering the connected iOS app with rapid, repeated interactions to find stability issues, memory leaks, and crash bugs.

## CRITICAL
- ALWAYS verify the app is still responsive after each sequence — call `get_interface`
- ALWAYS record which sequence and iteration caused a crash — this makes reproduction trivial
- DO NOT stop at the first crash — record it and continue with other elements if possible

**Arguments** (optional): `$ARGUMENTS`
- Element identifier or "all" (default: "all" — stress test every interactive element)

## Step 0: Verify Connection + Check for Existing Session

1. **Ensure CLI is on PATH**: Build the CLI and add to PATH if `buttonheist` is not already available:
   ```bash
   cd ButtonHeistCLI && swift build -c release && cd ..
   export PATH="$PWD/ButtonHeistCLI/.build/release:$PATH"
   ```
2. Run `buttonheist list --format json` (via Bash) — confirm at least one device is connected
3. If no devices found: stop and tell the user to launch the app and try again
4. Print the connected device name and app name for confirmation
5. **Check for existing session**: List `.fuzzer-data/sessions/fuzzsession-*.md` files. If the most recent one has `Status: in_progress`, read it to know which elements and sequences have already been stress-tested. Skip completed ones. If starting fresh, create a new notes file: `.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-stress-test-{target}.md`
5. **Load navigation knowledge**: Read `references/nav-graph.md` if it exists. If targeting an element on a different screen, use the nav graph to plan a route there.
6. **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.

During stress testing, update your session notes file continuously:
- After each sequence completes: update `## Coverage` with the result (PASS/FAIL)
- After each finding: add to `## Findings`
- Every 3 sequences: update `## Progress` and `## Next Actions`

## Step 1: Identify Targets

1. Run `buttonheist watch --once --format json --quiet` to get the current screen
2. If a specific element was requested, find it by identifier
3. If "all" (default), collect all interactive elements (those with actions or tappable)
4. Run `buttonheist screenshot --output /tmp/bh-screen.png` then Read the PNG for baseline visual state

## Step 2: Stress Test Sequences

For each target element, run these sequences. After each sequence, run `buttonheist watch --once --format json --quiet` to verify the app is still alive.

### Sequence 1: Rapid Taps (20x)

```
for i in 1..20:
    buttonheist touch tap --identifier ELEMENT --format json
```

Check: Is the app still responsive? Did any element disappear? Did the screen change unexpectedly?

### Sequence 2: Rapid Swipes (10x alternating)

```
for i in 1..5:
    buttonheist touch swipe --identifier ELEMENT --direction up --format json
    buttonheist touch swipe --identifier ELEMENT --direction down --format json
```

Check: Does the element still exist? Is the screen in a sane state?

### Sequence 3: Rapid Pinch Cycles (5x)

```
for i in 1..5:
    buttonheist touch pinch --identifier ELEMENT --scale 2.0 --format json
    buttonheist touch pinch --identifier ELEMENT --scale 0.5 --format json
```

Check: Did the view return to its original state after equal in/out cycles?

### Sequence 4: Rapid Rotate Cycles (5x)

```
for i in 1..5:
    buttonheist touch rotate --identifier ELEMENT --angle 1.57 --format json
    buttonheist touch rotate --identifier ELEMENT --angle -1.57 --format json
```

Check: Same as pinch — did it return to original?

### Sequence 5: Mixed Rapid Gestures

```
buttonheist touch tap --identifier ELEMENT --format json
buttonheist touch longpress --identifier ELEMENT --duration 0.1 --format json
buttonheist touch swipe --identifier ELEMENT --direction left --format json
buttonheist touch tap --identifier ELEMENT --format json
buttonheist touch pinch --identifier ELEMENT --scale 1.5 --format json
buttonheist touch tap --identifier ELEMENT --format json
buttonheist touch rotate --identifier ELEMENT --angle 0.5 --format json
buttonheist touch tap --identifier ELEMENT --format json
buttonheist touch two-finger-tap --identifier ELEMENT --format json
buttonheist touch tap --identifier ELEMENT --format json
```

Check: App still alive? Any unexpected state changes?

### Sequence 6: Increment/Decrement Hammering (if adjustable)

```
for i in 1..20:
    buttonheist action --identifier ELEMENT --type increment --format json
for i in 1..20:
    buttonheist action --identifier ELEMENT --type decrement --format json
```

Check: Did value go up 20 then back down 20? Any overflow?

## Step 3: Full-Screen Stress

After individual element testing, do a full-screen stress pass:

1. Tap 10 random coordinates across the screen
2. Swipe in all 4 directions from screen center
3. Pinch at screen center (scale 3.0 then 0.3)
4. Rotate at screen center (full rotation then reverse)

## Step 4: Health Check

After all sequences:

1. `buttonheist watch --once --format json --quiet` — verify element count hasn't changed dramatically
2. `buttonheist screenshot` — visual comparison with baseline
3. Report any degradation:
   - Elements that disappeared
   - Values that changed unexpectedly
   - Visual differences from baseline
   - Tool calls that started timing out (performance degradation)

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

[Any CRASH, ERROR, or ANOMALY findings]

### Health Check
- Elements before: [count], after: [count]
- Visual changes: [yes/no — describe if yes]
- Responsiveness: [normal / degraded]
```

## Crash Handling

Crashes during stress testing are **expected and valuable**. When detected:
1. Record exactly which sequence and iteration caused the crash
2. Record the element being stressed
3. This is reproducible: "[sequence name] on [element] at iteration [N]"
4. Save report and stop
