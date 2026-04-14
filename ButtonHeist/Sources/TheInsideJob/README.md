# TheInsideJob

iOS server framework. Embeds in apps to expose the accessibility hierarchy over TLS/TCP.

## Reading order

Start with **`TheInsideJob.swift`** — the `@MainActor public final class` singleton. Three coexisting state machines:

- `ServerPhase`: `.stopped` / `.running(transport:)` / `.suspended` / `.resuming(task:)`
- `PollingPhase`: `.disabled` / `.active(task:, interval:)` / `.paused(interval:)` — interval preserved across suspend/resume
- `RecordingPhase`: `.idle` / `.recording(stakeout:)`

**`start()`** creates a `TLSIdentity` (Keychain-persisted ECDSA cert, falls back to ephemeral), creates `ServerTransport`, calls `wireTransport(_:)` to install callbacks, starts listening, advertises via Bonjour, starts the pulse and keyboard observation.

**`wireTransport(_:)`** connects TheMuscle (auth) to ServerTransport (networking) via five closures. Transport callbacks route to `handleClientMessage` (authenticated) or `muscle.handleUnauthenticatedMessage` (pre-auth).

**`handleClientMessage`** is the two-level dispatch:
- Outer switch: protocol messages (ping, subscribe, status) and observation (requestInterface, requestScreen, waitForIdle/Change)
- Inner switch (non-observers only): recording start/stop, or `brains.executeCommand(message)` for all action commands
- Before dispatching actions: `computeBackgroundDelta()` checks if the tree changed while the agent was thinking — if the screen changed and the action targets a heistId, returns a synthetic "screen changed" result instead

**`suspend()`** / **`resume()`** handle app backgrounding — tears down transport/pulse/cache, recreates everything on foreground with a fresh TLS identity.

## Layout

| Folder | Start reading | What it does |
|--------|--------------|--------------|
| `TheBrains/` | `TheBrains+Dispatch.swift` | Command execution, scroll orchestration, exploration, delta cycle |
| `TheStash/` | `TheStash.swift` | Element registry, target resolution, wire conversion |
| `TheBurglar/` | `TheBurglar.swift` | Accessibility tree parsing (private to TheStash) |
| `TheSafecracker/` | `SyntheticTouch.swift` | Touch injection, text input, gesture synthesis |
| `TheTripwire/` | `TheTripwire.swift` | 10 Hz UI pulse, settle detection, VC tracking |
| `TheStakeout/` | `TheStakeout.swift` | H.264/MP4 screen recording |
| `Server/` | `SimpleSocketServer.swift` | TLS listener, auth, connection scope |
| `Lifecycle/` | `Pulse.swift` | Hierarchy broadcast, wait handlers, auto-start |
| `Support/` | `CancellableSleep.swift` | Shared utility |

Root files: `AccessibilityHierarchy+TreeOperations.swift` (catamorphism `folded()`, context-propagating `compactMap`, fingerprinting) and `AccessibilityHierarchy+Reconciliation.swift` (scroll-aware page stitching, content-space fingerprints). These are extensions on the parser library's types, used across TheBurglar, TheStash, and TheBrains.

## Ownership tree

```
TheInsideJob
├── TheTripwire (owned, injected into TheBrains/TheStash/TheBurglar)
├── TheMuscle (owned, closure-wired to ServerTransport)
├── RecordingPhase → TheStakeout (on-demand, weak back-ref in TheStash)
└── TheBrains (owned — TheInsideJob's only path to the element world)
    ├── TheSafecracker (owned)
    │   └── TheFingerprints (lazy)
    └── TheStash (owned)
        └── TheBurglar (private)
```

TheInsideJob talks to TheBrains — never directly to TheStash, TheBurglar, or TheSafecracker.

> Full dossiers: [`docs/dossiers/`](../../../docs/dossiers/) — start with `07-THEINSIDEJOB.md`
