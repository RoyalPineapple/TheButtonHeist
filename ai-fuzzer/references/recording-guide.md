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

The recording engine has an inactivity timer that auto-stops recording when no real activity occurs. Only **real interactions** reset this timer — actions, taps, swipes, typing, etc. **Pings and keepalive messages do NOT reset the timer.**

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
  --action-log .fuzzer-data/recordings/F-N-reproduce.actionlog.json \
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
| `--action-log` | JSON sidecar | Server-side interaction log — authoritative record of every command and result |
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
  --action-log .fuzzer-data/recordings/F-1-reproduce.actionlog.json \
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

### Step 5: Stop the recording

**Option A: Explicit stop (preferred for demos)**

```bash
buttonheist stop-recording --quiet
wait $RECORD_PID
```

Use `buttonheist stop-recording` to end the recording at exactly the right moment. The stop signal tells the server to finalize the video, which is then received by the background `record` process. The `wait` ensures the file is written before you continue.

**Option B: Let inactivity timeout handle it**

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
.fuzzer-data/recordings/{FINDING_ID}-{context}.actionlog.json
```

Examples:
- `F-1-reproduce.mp4` + `F-1-reproduce.actionlog.json` — reproduction attempt for finding F-1
- `F-3-refinement.mp4` + `F-3-refinement.actionlog.json` — refinement pass verification for finding F-3
- `F-5-investigation.mp4` + `F-5-investigation.actionlog.json` — deviation investigation for finding F-5

## Pre-Planning Checklist

Before starting a recording, verify:

1. **Actions are pre-planned**: You know exactly what commands you'll run (from trace, reproduction plan, or investigation plan)
2. **Duration is estimated**: Apply the formula: `(actions × 10) + 15`
3. **Output path is set**: Use the naming convention above
4. **Device is connected**: `buttonheist list` shows the target device
5. **Recordings directory exists**: `mkdir -p .fuzzer-data/recordings`

## Action Log

The `--action-log <path>` flag saves the stakeout's server-side interaction log as a JSON file alongside the MP4. This log is authoritative — it captures every command and result as seen by the server, with precise timestamps relative to recording start.

**Always use `--action-log`** when recording during refinement, reproduction, or demo flows.

### Format

The action log is a JSON array of `InteractionEvent` objects:

```json
[
  {
    "timestamp": 1.234,
    "command": {"activate": {"identifier": "loginButton", "order": null}},
    "result": {
      "success": true,
      "method": "activate",
      "message": null,
      "value": null,
      "interfaceDelta": {
        "kind": "valuesChanged",
        "elementCount": 12,
        "valueChanges": [{"order": 3, "identifier": "loginButton", "oldValue": null, "newValue": "Loading..."}]
      },
      "animating": null
    },
    "interfaceDelta": { ... }
  }
]
```

Each event contains:
- **`timestamp`**: Seconds since recording start (precise server-side timing)
- **`command`**: The `ClientMessage` that triggered this interaction (discriminated union — key is the case name, value is the payload)
- **`result`**: The `ActionResult` with success/failure, method used, value changes, and interface delta
- **`interfaceDelta`**: Copy of `result.interfaceDelta` for convenience

### What the Action Log Provides (vs Trace)

| Data | Action Log | Trace |
|------|-----------|-------|
| Precise timestamps | Yes (server-side) | Approximate (client-side) |
| Command + result | Yes (wire format) | Yes (human-readable) |
| Interface deltas | Yes | Yes |
| Screen fingerprints | No | Yes |
| Element target details (label, order, actions) | No | Yes |
| Predictions + validation | No | Yes |
| Pre/post screen names | No | Yes |

Use action logs for:
- **Cross-checking traces**: Compare Haiku's trace entries against the action log to detect execution discrepancies
- **Timestamped histories**: Exact timing between actions for performance analysis
- **Authoritative results**: Server-side ground truth for what happened
- **Reports**: Generate action log summary tables from the JSON

### Reading the Action Log

After the recording completes, read the JSON to get the interaction history:

```bash
# Check if action log was generated
ls -la .fuzzer-data/recordings/F-N-reproduce.actionlog.json
```

Then use `Read` to parse the JSON and generate an Action Log Summary:

| # | Timestamp | Command | Result | Delta |
|---|-----------|---------|--------|-------|
| 1 | 0.0s | activate(identifier: "settings") | success (activate) | screenChanged |
| 2 | 8.3s | activate(identifier: "darkModeToggle") | success (activate) | valuesChanged |

## Troubleshooting

### Recording stopped before all actions completed
- **Inactivity timeout fired**: Your think time between actions exceeded `--inactivity-timeout`. Increase the value (try `90` or `120`).
- **File size limit (7MB)**: Use lower `--fps` or `--scale`.
- **App crashed**: Recording stops when TheInsideJob goes down.

### Recording file is empty or missing
- The device may have disconnected. Check `buttonheist list` first.
- The recording may not have had time to connect before the first action. Ensure `sleep 2` after starting.

### Recording is much larger than expected
- Long `maxDuration` with many static frames still accumulates data. Tighten your duration estimate.
- Try `--fps 2` for even smaller files if 4 fps is too much.
