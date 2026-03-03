# Recording Guide

How to use the MCP recording tools to capture video evidence of bugs during fuzzing sessions.

## Starting a Recording

Call the `start_recording` tool:
- `start_recording(fps: 8, scale: 0.5, maxDuration: 65, inactivityTimeout: 60)`

The recording starts immediately on the device. No background process management needed.

## Stopping a Recording

Call the `stop_recording` tool with an output path:
- `stop_recording(output: ".fuzzer-data/recordings/F-1-reproduce.mp4")`

Returns metadata (duration, frame count, file size). The file is saved at the specified path.

## Duration Estimation

```
estimated_duration = (number_of_actions × 7) + 15
```

7 seconds per action (MCP tool call ~50ms + agent think time ~5-7s) + 15 second buffer.

| Scenario | Actions | Duration |
|----------|---------|----------|
| Reproduce a 5-step finding | 5 | 50s |
| Refinement: 3 attempts × 3 actions | 9 | 78s |
| Quick investigation | 5 | 50s |
| Refinement with variations | 15 | 120s |

## Recommended Settings

| Setting | Value | Why |
|---------|-------|-----|
| `fps: 8` | 8 frames/sec | Smooth enough; matches default |
| `scale: 0.5` | Half native | Readable, ~4x smaller than full res |
| `inactivityTimeout: 60` | 60 seconds | Accommodates agent think time (default 5s is too short) |
| `maxDuration` | From formula | Hard cap |

At these settings, 60 seconds of recording is typically 200-500KB.

**Inactivity timeout**: Only real interactions (actions, taps, swipes, typing) reset the timer — pings do not. Set it longer than your longest expected gap between actions.

## Recording Pattern

### Start recording

```
mkdir -p .fuzzer-data/recordings  (via Bash — needed for directory creation)
start_recording(fps: 8, scale: 0.5, maxDuration: 65, inactivityTimeout: 60)
```

### Execute actions

Call MCP tools normally. Each interaction resets the inactivity timer.

### Stop recording

```
stop_recording(output: ".fuzzer-data/recordings/F-1-reproduce.mp4")
```

Returns metadata — no need for separate file verification.

## File Naming

```
.fuzzer-data/recordings/{FINDING_ID}-{context}.mp4
```

Examples: `F-1-reproduce.mp4`, `F-3-refinement.mp4`, `F-5-demo.mp4`
