# Fuzzer Screen Recording Integration Plan

## Overview

Integrate ButtonHeist's screen recording (`buttonheist record`) into the AI fuzzer so findings and reproduction attempts are documented with MP4 video evidence. The key challenge is that the fuzzer is an agent with variable think-time between actions (5-30+ seconds), which would trigger inactivity auto-stop if not handled correctly.

## Key Technical Insight

The recording engine's inactivity timer only resets on **real interactions** (actions, taps, swipes, typing) — not pings or keepalive messages. This means `buttonheist record` running in background will auto-stop after `inactivityTimeout` seconds of no real interactions. Since the fuzzer agent takes 5-30+ seconds to think between actions, the default 5-second inactivity timeout would kill recordings prematurely.

**Solution**: Use `--inactivity-timeout 60` to give the agent ample think time between actions. Each real CLI interaction (from separate connections) resets the timer. The fuzzer should:

1. Pre-plan the actions it will record
2. Estimate the total duration (actions × ~10s average including agent think time)
3. Start `buttonheist record` in background with `--inactivity-timeout 60` and appropriate `--max-duration`
4. Execute the planned actions via normal CLI commands — each interaction resets the inactivity timer
5. Wait for the background recording process to finish (stops at maxDuration or after 60s of no interactions)

## Current State Analysis

- `buttonheist record` CLI exists and works (Phase 5 of Stakeout plan)
- The fuzzer has no awareness of recording capabilities
- SKILL.md CLI reference doesn't include the `record` command
- Finding format has no field for video evidence
- `fuzz-reproduce.md` doesn't record reproduction attempts

## Desired End State

- Fuzzer SKILL.md documents `buttonheist record` in CLI reference
- New `references/recording-guide.md` explains the recording workflow for agents, including the keepalive-prevents-inactivity insight and duration estimation
- `fuzz-reproduce.md` Step 4 records the reproduction execution as video evidence
- `fuzz.md` Step 5 (Refinement Pass) records each finding's reproduction attempt
- Finding format includes optional `**Recording**` field for video file path
- Session notes format includes a `## Recordings` section

## What We're NOT Doing

- **Recording entire fuzzing sessions** — too long, too much dead time, files would be too big
- **Real-time streaming** — the fuzzer writes video to disk, references the file path
- **Adding a `stop-recording` CLI command** — recording stops naturally at maxDuration
- **Modifying the recording engine** — Stakeout and RecordCommand work as-is

## Implementation Approach

Recording is targeted at specific moments where video evidence adds value:
1. **Reproduction attempts** (`/fuzz-reproduce`) — record the entire reproduction sequence
2. **Refinement pass** (`/fuzz` Step 5) — record each finding's verification attempt
3. **Investigation** (during the fuzzing loop) — optionally record when investigating a deviation

The pattern is always the same:
```
Pre-plan actions → Estimate duration → Start record in background → Execute actions → Wait for completion
```

---

## Phase 1: Recording Guide Reference

### Overview
Create a reference file that teaches the agent how to use recording effectively, including the timing insight and duration estimation.

### Changes Required:

#### 1. New Recording Guide
**File**: `ai-fuzzer/references/recording-guide.md` (new file)

Content covers:
- The `buttonheist record` command and its options
- Why inactivity timeout doesn't fire (keepalive pings)
- Duration estimation formula: `numActions × 10 seconds + 15 second buffer`
- Recommended settings: `--fps 4 --scale 0.5` for fuzzer recordings (keeps file size small)
- The background recording pattern (Bash `&` + wait)
- File naming convention: `.fuzzer-data/recordings/FINDING-ID.mp4`
- When to record (reproduction, investigation) and when not to (routine exploration)

### Success Criteria:
- [x] File exists and is well-structured

---

## Phase 2: Update SKILL.md

### Overview
Add the `record` command to the CLI Quick Reference and add a reference entry for the recording guide.

### Changes Required:

#### 1. CLI Reference Table
**File**: `ai-fuzzer/SKILL.md`
**Changes**: Add `record` to the Commands table (after Screenshot row)

```
| Record screen | `buttonheist record --output /tmp/bh-recording.mp4 --max-duration 30 --fps 4 --scale 0.5` |
```

#### 2. Reference Files Table
**File**: `ai-fuzzer/SKILL.md`
**Changes**: Add recording guide entry to the Reference Files table

```
| `references/recording-guide.md` | When recording a finding reproduction | Recording workflow, duration estimation, background pattern |
```

#### 3. Finding Format
**File**: `ai-fuzzer/SKILL.md`
**Changes**: Add optional `**Recording**` field to the finding format template

```
**Recording**: [path to MP4 if recorded]
```

### Success Criteria:
- [x] `record` command appears in CLI reference
- [x] Recording guide appears in reference files table
- [x] Finding format includes recording field

---

## Phase 3: Update fuzz-reproduce.md

### Overview
Add recording to the reproduction workflow. The reproduction is a planned sequence with known action count — ideal for recording.

### Changes Required:

#### 1. Step 4: Execute with Recording
**File**: `ai-fuzzer/commands/fuzz-reproduce.md`
**Changes**: Before executing the reproduction sequence, start a background recording. After execution, wait for it to complete.

Before the execution loop:
```markdown
### Pre-execution: Start Recording

1. Read `references/recording-guide.md` for the recording workflow
2. Estimate duration: `(number of actions in plan) × 10 + 15` seconds
3. Set recording output path: `.fuzzer-data/recordings/F-N-reproduce.mp4`
4. Start recording in background:
   ```bash
   buttonheist record --output .fuzzer-data/recordings/F-N-reproduce.mp4 \
     --max-duration <estimated_duration> --fps 4 --scale 0.5 --quiet &
   RECORD_PID=$!
   ```
5. Wait 2 seconds for the recording to connect and start capturing
```

After the execution loop:
```markdown
### Post-execution: Collect Recording

1. Wait for background recording to finish: `wait $RECORD_PID`
2. If the recording file exists, reference it in the reproduction report
3. Add `**Recording**: .fuzzer-data/recordings/F-N-reproduce.mp4` to the report
```

#### 2. Step 6: Report
**File**: `ai-fuzzer/commands/fuzz-reproduce.md`
**Changes**: Add recording file reference to the report template

### Success Criteria:
- [x] Reproduction workflow includes recording steps
- [x] Report template references recording file

---

## Phase 4: Update fuzz.md

### Overview
Add recording to the refinement pass (Step 5) where findings are verified.

### Changes Required:

#### 1. Step 5: Refinement Pass Recording
**File**: `ai-fuzzer/commands/fuzz.md`
**Changes**: Add recording to each finding's reproduction attempt during refinement

Before the reproduction attempts:
```markdown
For each finding, before attempting reproduction:
1. Read `references/recording-guide.md` if not already loaded
2. Estimate recording duration: `15 × 10 + 15 = 165` seconds (generous for 3 reproduction attempts + variations)
3. Start background recording:
   ```bash
   buttonheist record --output .fuzzer-data/recordings/F-N-refinement.mp4 \
     --max-duration <estimated> --fps 4 --scale 0.5 --quiet &
   RECORD_PID=$!
   ```
4. Wait 2 seconds for recording to start
```

After the reproduction attempts:
```markdown
After reproducing/varying the finding:
1. Wait for background recording: `wait $RECORD_PID`
2. Reference recording in finding: `**Recording**: .fuzzer-data/recordings/F-N-refinement.mp4`
```

#### 2. Step 6: Report
**File**: `ai-fuzzer/commands/fuzz.md`
**Changes**: Include recording references in the report for findings that were recorded

### Success Criteria:
- [x] Refinement pass includes recording for each finding
- [x] Report includes recording references

---

## Phase 5: Update Session Notes Format

### Overview
Add a `## Recordings` section to the session notes format to track recorded videos.

### Changes Required:

#### 1. Session Notes Format
**File**: `ai-fuzzer/references/session-notes-format.md`
**Changes**: Add a `## Recordings` section template

```markdown
## Recordings
| Finding | File | Duration | Size | Notes |
|---------|------|----------|------|-------|
| F-1 | .fuzzer-data/recordings/F-1-refinement.mp4 | 12.3s | 245KB | Reproduction confirmed |
```

### Success Criteria:
- [x] Session notes format includes recordings section

---

## Testing Strategy

This is entirely documentation/skill changes — no code to compile or test. Verification is:
1. All modified markdown files are syntactically correct
2. The recording workflow is self-consistent (duration estimates make sense, file paths are consistent)
3. The recording guide accurately describes the keepalive/inactivity behavior

## References

- Stakeout implementation: `ButtonHeist/Sources/InsideMan/Stakeout.swift`
- `noteActivity()` called in `handleClientMessage`: `ButtonHeist/Sources/InsideMan/InsideMan.swift:260`
- RecordCommand: `ButtonHeistCLI/Sources/RecordCommand.swift`
- HeistClient keepalive (3s pings): `ButtonHeist/Sources/ButtonHeist/HeistClient.swift:315`
