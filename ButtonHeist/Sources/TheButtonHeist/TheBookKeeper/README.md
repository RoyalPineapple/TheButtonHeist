# TheBookKeeper

Session logs, artifact storage, compression, and heist recording. All filesystem I/O lives here.

## Files

| File | Purpose |
|------|---------|
| `TheBookKeeper.swift` | State machine, session lifecycle, artifact writes, heist recording |
| `TheBookKeeper+Logging.swift` | JSONL log serialization, binary data exclusion |
| `TheBookKeeper+Compression.swift` | gzip logs, tar.gz archives |
| `SessionManifest.swift` | Manifest types, artifact entries, metadata structs |
| `PlaybackFailure.swift` | Diagnostic context for heist playback step failures |

## Boundaries

- Owned by TheFence. Accepts `String` command names at the API boundary — no dependency on `TheFence.Command` or `FenceResponse`.
- Session phase modeled as explicit state machine: `.idle` / `.active` / `.closing` / `.closed` / `.archived`.
- No network I/O — purely local filesystem.

> Full dossier: [`docs/dossiers/16-THEBOOKKEEPER.md`](../../../../docs/dossiers/16-THEBOOKKEEPER.md)
