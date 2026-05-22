# TheStakeout

Screen recording engine. Captures frames at configurable FPS, encodes H.264/MP4 via `AVAssetWriter`, and returns a `RecordingPayload` to TheGetaway for routing.

## The one file

**`TheStakeout.swift`** — `actor`.

### State machine

`StakeoutPhase`: `.idle` / `.recording(ActiveRecording)` / `.finalizing(FinalizingRecording)`. Each case carries only the data valid for that lifecycle phase. `ActiveRecording` groups writer resources, output shape, timing, evidence, capture loop, activity tracking, and interaction log state; `FinalizingRecording` drops active-only tasks and the pixel-buffer adaptor before building the payload.

### Recording lifecycle

**`startRecording(config:)`** — clamps fps (1-15, default 8), scale (0.25-1.0, default `1/screen.scale`), rounds dimensions to even (H.264 macroblock requirement). Creates `AVAssetWriter` with H.264 at `width * height * 2` bitrate, keyframe interval `fps * 2`. Starts the capture timer and, when explicitly configured, the inactivity monitor.

**Frame capture** — a `Task` that loops: `captureAndAppendFrame()` then sleep `1/fps` seconds. Each frame:
1. Guards `videoInput.isReadyForMoreMediaData` and `captureFrame?()` returns a `UIImage`
2. Checks file size (>7 MB → stop, `.fileSizeLimit`), max duration (configurable → stop)
3. Allocates `CVPixelBuffer` from the adaptor's pool, draws the image into a `CGContext`, appends with `CMTime(value: frameCount, timescale: fps)`

**Inactivity monitor** — represented as `ActivityLifecycle`: `.notTracked` when `inactivityTimeout` is omitted, `.tracking` when it is explicit. The monitor wakes every 1s, checks elapsed time since the last tracked activity, and is bumped by `noteActivity()` (incoming commands) and `noteScreenChange()` (settled hierarchy changes reported by TheGetaway). Omitted values record until `maxDuration`, manual stop, or another hard cap.

**`stopRecording(reason:)`** — cancels the capture task and any active inactivity monitor, transitions to `.finalizing`, calls `finalizeRecording`.

**Finalization** — `videoInput.markAsFinished()` → `writer.finishWriting` → read output file → build `RecordingPayload` (base64 video, dimensions, duration, fps, frameCount, start/end times, stop reason, interaction log) → call `onRecordingComplete?(.success(payload))` → delete temp file → transition to `.idle`.

### Interaction log

`recordInteraction(event:)` appends `InteractionEvent` (timestamp offset + command + result) up to 500 entries. Bundled into `RecordingPayload.interactionLog` at finalization.

### External wiring

TheGetaway creates the stakeout on demand and wires two closures:
- `captureFrame = { brains.captureScreenForRecording() }` — captures all windows including TheFingerprints overlay
- `onRecordingComplete = { ... }` — routes the result through `RecordingRouteState` for `stop_recording`, originator delivery, or invalidation cleanup

TheStash holds `weak var stakeout` for `captureActionFrame()` — a bonus frame after each action to capture the visual effect.

> Full dossier: [`docs/dossiers/16-THESTAKEOUT.md`](../../../../docs/dossiers/16-THESTAKEOUT.md)
