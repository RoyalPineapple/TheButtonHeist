# Recording Guide

How to use `buttonheist record` to capture video evidence of bugs during fuzzing sessions.

## When to Record

Record during **targeted, pre-planned action sequences** — not during routine exploration.

| Situation | Record? | Why |
|-----------|---------|-----|
| Reproducing a finding (`/fuzz-reproduce`) | **Yes** | Pre-planned sequence with known action count |
| Refinement pass (Step 5 of `/fuzz`) | **Yes** | Verifying specific findings, short sequences |
| Investigating a deviation (5-action budget) | **Optional** | Short, focused probe — worth recording if CRASH/ERROR |
| Creating a demo (`/fuzz-demo`) | **Yes** | Polished single-take with deliberate pacing for sharing |
| Routine exploration loop | **No** | Too long, too much dead time between actions, file size limit |

## How Inactivity Timeout Works

The recording engine (`Stakeout`) has an inactivity timer that auto-stops recording when no real activity occurs. Only **real interactions** reset this timer — actions, taps, swipes, typing, etc. **Pings and keepalive messages do NOT reset the timer.**

This means:
- `buttonheist record` running in the background will **not** stay alive indefinitely — pings don't count
- The recording stops after `inactivityTimeout` seconds (default 5) of no real interactions
- Between your CLI commands, the agent takes time to think (5-30+ seconds) — this **will** trigger inactivity auto-stop at the default timeout

### The Solution: Set a Long Inactivity Timeout

Use `--inactivity-timeout` to accommodate your think time between actions:

```bash
buttonheist record --inactivity-timeout 60 ...
```

Set the inactivity timeout **longer than your longest expected gap between actions**. A conservative value is **60 seconds** — this gives you plenty of time to think between CLI commands without the recording stopping.

The recording will still stop naturally via:
- **`maxDuration`**: the hard cap you set (your estimated sequence duration)
- **Inactivity**: if you truly stop interacting for 60+ seconds, the recording auto-stops and saves
- **File size limit** (7MB): safety guard for the wire protocol

## Duration Estimation

Estimate how long your planned actions will take:

```
estimated_duration = (number_of_actions × 10) + 15
```

- **10 seconds per action**: accounts for CLI execution (~1s) + your think time between actions (~5-9s)
- **15 second buffer**: headroom for slow actions, navigation, and screenshots

Examples:
| Scenario | Actions | Estimated Duration |
|----------|---------|-------------------|
| Reproduce a 5-step finding | 5 | 65s |
| Refinement: 3 attempts × 3 actions | 9 | 105s |
| Quick investigation | 5 | 65s |
| Refinement with variations | 15 | 165s |

## Recommended Settings

For fuzzer recordings, optimize for small file size and tolerance of agent think time:

```bash
buttonheist record \
  --output .fuzzer-data/recordings/F-N-reproduce.mp4 \
  --max-duration 65 \
  --inactivity-timeout 60 \
  --fps 8 \
  --scale 0.5 \
  --quiet
```

| Setting | Value | Why |
|---------|-------|-----|
| `--fps 8` | 8 frames/sec | Smooth enough to see interactions clearly; matches the default |
| `--scale 0.5` | Half native | Readable for debugging, ~4x smaller than full resolution |
| `--inactivity-timeout 60` | 60 seconds | Accommodates agent think time between actions (default 5s is too short) |
| `--quiet` | Suppress status | Cleaner output when running in background |
| `--max-duration` | Estimated | Set from duration estimation formula above |

At these settings, a 60-second recording is typically 200-500KB.

## The Background Recording Pattern

Always start recording **before** executing actions, and wait for it **after**.

### Step 1: Create the recordings directory

```bash
mkdir -p .fuzzer-data/recordings
```

### Step 2: Start recording in background

```bash
buttonheist record \
  --output .fuzzer-data/recordings/F-1-reproduce.mp4 \
  --max-duration 65 --inactivity-timeout 60 --fps 8 --scale 0.5 --quiet &
RECORD_PID=$!
```

### Step 3: Wait for recording to connect

```bash
sleep 2
```

The recording needs ~1-2 seconds to discover the device, connect, and start capturing. Always pause before executing your first action.

### Step 4: Execute your planned actions

Run your pre-planned CLI commands normally. Each command creates its own connection, acts, and disconnects. Each interaction resets the inactivity timer, keeping the recording alive.

**Important**: Execute actions within 60 seconds of each other (the inactivity timeout). If you need to think longer, the recording will auto-stop — which is fine, since extended gaps mean the interesting part is over.

### Step 5: Wait for recording to finish

```bash
wait $RECORD_PID
```

The recording stops when either `maxDuration` is reached or the inactivity timeout fires (whichever comes first). The `wait` command blocks until the background process exits and the MP4 file is written.

### Step 6: Verify the recording exists

```bash
ls -la .fuzzer-data/recordings/F-1-reproduce.mp4
```

## File Naming Convention

```
.fuzzer-data/recordings/{FINDING_ID}-{context}.mp4
```

Examples:
- `F-1-reproduce.mp4` — reproduction attempt for finding F-1
- `F-3-refinement.mp4` — refinement pass verification for finding F-3
- `F-5-investigation.mp4` — deviation investigation for finding F-5

## Pre-Planning Checklist

Before starting a recording, verify:

1. **Actions are pre-planned**: You know exactly what commands you'll run (from trace, reproduction plan, or investigation plan)
2. **Duration is estimated**: Apply the formula: `(actions × 10) + 15`
3. **Output path is set**: Use the naming convention above
4. **Device is connected**: `buttonheist list` shows the target device
5. **Recordings directory exists**: `mkdir -p .fuzzer-data/recordings`

## Troubleshooting

### Recording stopped before all actions completed
- **Inactivity timeout fired**: Your think time between actions exceeded `--inactivity-timeout`. Increase the value (try `90` or `120`).
- **File size limit (7MB)**: Use lower `--fps` or `--scale`.
- **App crashed**: Recording stops when InsideMan goes down.

### Recording file is empty or missing
- The device may have disconnected. Check `buttonheist list` first.
- The recording may not have had time to connect before the first action. Ensure `sleep 2` after starting.

### Recording is much larger than expected
- Long `maxDuration` with many static frames still accumulates data. Tighten your duration estimate.
- Try `--fps 2` for even smaller files if 4 fps is too much.
