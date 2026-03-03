# Recording Guide

How to use `buttonheist record` to capture video evidence of bugs during fuzzing sessions.

## Duration Estimation

```
estimated_duration = (number_of_actions × 10) + 15
```

10 seconds per action (CLI ~1s + think time ~5-9s) + 15 second buffer.

| Scenario | Actions | Duration |
|----------|---------|----------|
| Reproduce a 5-step finding | 5 | 65s |
| Refinement: 3 attempts × 3 actions | 9 | 105s |
| Quick investigation | 5 | 65s |
| Refinement with variations | 15 | 165s |

## Recommended Settings

```bash
buttonheist record \
  --output .fuzzer-data/recordings/F-N-reproduce.mp4 \
  --action-log .fuzzer-data/recordings/F-N-reproduce.actionlog.json \
  --max-duration 65 \
  --inactivity-timeout 60 \
  --fps 8 --scale 0.5 --quiet
```

| Setting | Value | Why |
|---------|-------|-----|
| `--fps 8` | 8 frames/sec | Smooth enough; matches default |
| `--scale 0.5` | Half native | Readable, ~4x smaller than full res |
| `--action-log` | JSON sidecar | Server-side authoritative record |
| `--inactivity-timeout 60` | 60 seconds | Accommodates agent think time (default 5s is too short) |
| `--max-duration` | From formula | Hard cap |

At these settings, 60 seconds of recording is typically 200-500KB.

**Inactivity timeout**: Only real interactions (actions, taps, swipes, typing) reset the timer — pings do not. Set it longer than your longest expected gap between actions.

## Background Recording Pattern

### Start recording

```bash
mkdir -p .fuzzer-data/recordings
buttonheist record \
  --output .fuzzer-data/recordings/F-1-reproduce.mp4 \
  --action-log .fuzzer-data/recordings/F-1-reproduce.actionlog.json \
  --max-duration 65 --inactivity-timeout 60 --fps 8 --scale 0.5 --quiet &
RECORD_PID=$!
sleep 2  # Wait for connection
```

### Execute actions

Run CLI commands normally. Each interaction resets the inactivity timer.

### Stop recording

```bash
# Option A: Explicit stop (preferred for demos)
buttonheist stop-recording --quiet
wait $RECORD_PID

# Option B: Let inactivity/maxDuration handle it
wait $RECORD_PID
```

### Verify

```bash
ls -la .fuzzer-data/recordings/F-1-reproduce.mp4
```

## File Naming

```
.fuzzer-data/recordings/{FINDING_ID}-{context}.mp4
.fuzzer-data/recordings/{FINDING_ID}-{context}.actionlog.json
```

Examples: `F-1-reproduce.mp4`, `F-3-refinement.mp4`, `F-5-demo.mp4`
