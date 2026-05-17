# TheInsideJob

iOS server framework. Embeds in apps to expose the accessibility hierarchy over TLS/TCP.

## Reading order

Start with **`TheInsideJob.swift`** — the `@MainActor public final class` singleton. This is the job itself: it assembles the crew, manages the server lifecycle, and provides the public API (`start()`, `stop()`, `notifyChange()`, `startPolling()`). It does not handle messages, encode responses, or touch the accessibility tree — those are delegated to the crew.

Two state machines:
- `ServerPhase`: `.stopped` / `.running(transport:)` / `.suspended` / `.resuming(task:)`
- `PollingPhase`: `.disabled` / `.active(task:, interval:)` / `.paused(interval:)` — interval preserved across suspend/resume

**`start()`** creates a TLS identity, creates ServerTransport, tells TheGetaway to wire the transport, starts listening, advertises via Bonjour, starts the pulse and keyboard observation.

**`suspend()`** / **`resume()`** handle app backgrounding — tears down everything, recreates on foreground.

**`AutoStart.swift`** is the `@_cdecl` bridge called by ThePlant's ObjC `+load`. Reads config from env vars / Info.plist, dispatches `TheInsideJob.configure()` + `start()` + `startPolling()`.

## Layout

| Folder | Crew member | Role |
|--------|-------------|------|
| `TheGetaway/` | TheGetaway | Message dispatch, encode/decode, transport wiring, response state, recording |
| `TheBrains/` | TheBrains | Action execution, scroll orchestration, exploration, delta cycle, wait handlers |
| `TheStash/` | TheStash | Current element state, target resolution, wire conversion |
| `TheBurglar/` | TheBurglar | Accessibility tree parsing (private to TheStash) |
| `TheSafecracker/` | TheSafecracker | Touch injection, text input, gesture synthesis (includes TheFingerprints) |
| `TheTripwire/` | TheTripwire | 10 Hz UI pulse, settle detection, VC tracking |
| `TheStakeout/` | TheStakeout | H.264/MP4 screen recording |
| `Server/` | TheMuscle + transport | TLS server, auth, connection scope |
| `Support/` | — | CancellableSleep |

Root files: `TheInsideJob.swift` (singleton), `AutoStart.swift` (ObjC bridge), `AccessibilityHierarchy+*.swift` (shared parser extensions used by TheBurglar, TheStash, and TheBrains).

## Ownership

```
TheInsideJob (the job — singleton, lifecycle, crew assembly)
├── TheGetaway (comms — dispatch, encode, transport wiring, response state)
├── TheTripwire (pulse — settle detection, injected into others)
├── TheMuscle (auth — session locking, closure-wired to transport via TheGetaway)
└── TheBrains (actions — execution, scroll, explore, delta, wait handlers)
    ├── TheSafecracker (gestures — touch injection, text input)
    │   └── TheFingerprints (visual overlay)
    └── TheStash (registry — elements, resolution, wire conversion)
        └── TheBurglar (parsing — accessibility tree read, private to TheStash)
```

TheInsideJob assembles and manages. TheGetaway drives comms. TheBrains drives accessibility. TheInsideJob never touches TheStash, TheBurglar, or TheSafecracker directly.

> Full dossiers: [`docs/dossiers/`](../../../docs/dossiers/)
