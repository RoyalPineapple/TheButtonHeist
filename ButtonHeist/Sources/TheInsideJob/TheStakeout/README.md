# TheStakeout

Screen recording engine. Captures frames at configurable FPS, encodes H.264/MP4 via `AVAssetWriter`, and delivers the video as base64 in a `RecordingPayload`.

## The one file

**`TheStakeout.swift`** — `@MainActor final class`.

### State machine

`StakeoutPhase`: `.idle` / `.recording(RecordingSession)` / `.finalizing(FinalizingSession)`. Each case carries exactly the data valid for that phase — `RecordingSession` holds the writer, input, adaptor, capture timer task, inactivity check task, frame count, interaction log; `FinalizingSession` drops the tasks and mutable bookkeeping.

### Recording lifecycle

**`startRecording(config:)`** — clamps fps (1-15, default 8), scale (0.25-1.0, default `1/screen.scale`), rounds dimensions to even (H.264 macroblock requirement). Creates `AVAssetWriter` with H.264 at `width * height * 2` bitrate, keyframe interval `fps * 2`. Starts the capture timer and inactivity monitor.

**Frame capture** — a `Task` that loops: `captureAndAppendFrame()` then sleep `1/fps` seconds. Each frame:
1. Guards `videoInput.isReadyForMoreMediaData` and `captureFrame?()` returns a `UIImage`
2. Checks file size (>7 MB → stop, `.fileSizeLimit`), max duration (configurable → stop)
3. Allocates `CVPixelBuffer` from the adaptor's pool, draws the image into a `CGContext`, appends with `CMTime(value: frameCount, timescale: fps)`

**Inactivity monitor** — wakes every 1s, checks `Date().timeIntervalSince(lastActivityTime)` against `inactivityTimeout`. Activity is bumped by `noteActivity()` (incoming commands) and `noteScreenChange()` (settled accessibility capture changes). When omitted, `inactivityTimeout` follows `maxDuration`; explicit values remain early-stop hints.

**`stopRecording(reason:)`** — cancels both tasks, transitions to `.finalizing`, calls `finalizeRecording`.

**Finalization** — `videoInput.markAsFinished()` → `writer.finishWriting` → read output file → build `RecordingPayload` (base64 video, dimensions, duration, fps, frameCount, start/end times, stop reason, interaction log) → call `onRecordingComplete?(.success(payload))` → delete temp file → transition to `.idle`.

### Interaction log

`recordInteraction(event:)` appends `InteractionEvent` (timestamp offset + command + result) up to 500 entries. Bundled into `RecordingPayload.interactionLog` at finalization.

### External wiring

TheInsideJob creates the stakeout on demand and wires two closures:
- `captureFrame = { brains.captureScreenForRecording() }` — captures all windows including TheFingerprints overlay
- `onRecordingComplete = { ... }` — stores the result for `stop_recording` and cleans up `recordingPhase`

TheStash holds `weak var stakeout` for `captureActionFrame()` — a bonus frame after each action to capture the visual effect.

> Full dossier: [`docs/dossiers/16-THESTAKEOUT.md`](../../../../docs/dossiers/16-THESTAKEOUT.md)
