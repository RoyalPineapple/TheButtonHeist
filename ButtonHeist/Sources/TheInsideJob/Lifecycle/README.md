# Lifecycle

TheInsideJob extensions for server lifecycle — pulse-driven hierarchy updates, wait handlers, screen capture, and the ObjC auto-start bridge.

## Files

| File | Purpose |
|------|---------|
| `Pulse.swift` | `scheduleHierarchyUpdate`, `broadcastIfChanged`, `sendInterface`, polling loop |
| `Animation.swift` | `handleWaitForIdle`, `handleWaitForChange` with settle detection and expectation polling |
| `Screen.swift` | Screen capture broadcast, recording start/stop handlers |
| `AutoStart.swift` | `@_cdecl` bridge for ObjC `+load` auto-start (called by ThePlant) |

All files are extensions on `TheInsideJob`.
