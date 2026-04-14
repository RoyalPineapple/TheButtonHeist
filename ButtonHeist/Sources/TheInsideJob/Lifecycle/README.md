# Lifecycle

ObjC auto-start bridge for TheInsideJob. Called from ThePlant's `+load` to configure and start the server without requiring manual setup.

## Files

**`AutoStart.swift`** — `@_cdecl("TheInsideJob_autoStartFromLoad")` entry point.

Called from ThePlant's `+load`. Reads config from env vars / Info.plist (`INSIDEJOB_DISABLE`, `INSIDEJOB_TOKEN`, `INSIDEJOB_ID`, `INSIDEJOB_PORT`, `INSIDEJOB_POLLING_INTERVAL`). Dispatches `Task { @MainActor }` to configure, start, and begin polling.

> Hierarchy broadcasting, wait handlers, screen capture, and recording are handled by [TheGetaway](../TheGetaway/).
