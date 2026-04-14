# TheStakeout

Screen recording engine — captures, encodes, and delivers H.264/MP4 video with interaction logs.

## Files

| File | Purpose |
|------|---------|
| `TheStakeout.swift` | State machine, frame capture, AVAssetWriter encoding, interaction logging |

## Boundaries

- Owned by TheInsideJob (created on-demand via `RecordingPhase`).
- TheStash holds a `weak var stakeout` for recording frame capture.
- Communicates outward via injected closures (`captureFrame`, `onRecordingComplete`).
- State machine: `.idle` / `.recording(RecordingSession)` / `.finalizing(FinalizingSession)`.

> Full dossier: [`docs/dossiers/05-THESTAKEOUT.md`](../../../../docs/dossiers/05-THESTAKEOUT.md)
