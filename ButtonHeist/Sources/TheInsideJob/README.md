# TheInsideJob

iOS server framework — embeds in apps to expose the accessibility hierarchy over TLS/TCP.

## Layout

| Folder | Crew member | Role |
|--------|-------------|------|
| `TheBrains/` | TheBrains | Action dispatch, scroll orchestration, exploration, delta cycle |
| `TheStash/` | TheStash | Element registry, target resolution, wire conversion |
| `TheBurglar/` | TheBurglar | Accessibility tree parsing (private to TheStash) |
| `TheSafecracker/` | TheSafecracker | Touch injection, text input, gesture synthesis (includes TheFingerprints) |
| `TheTripwire/` | TheTripwire | 10 Hz UI pulse, settle detection, keyboard/VC tracking |
| `TheStakeout/` | TheStakeout | Screen recording (H.264/MP4) |
| `Server/` | TheMuscle + transport | TLS server, auth, connection scope |
| `Lifecycle/` | — | Pulse hooks, wait handlers, auto-start bridge |
| `Support/` | — | Shared utilities |

Root files: `TheInsideJob.swift` (singleton entry point), `AccessibilityHierarchy+*.swift` (shared parser extensions).

## Ownership

```
TheInsideJob (singleton)
├── TheTripwire (owned, injected into others)
├── TheMuscle (owned, closure-wired to transport)
├── RecordingPhase → TheStakeout (on-demand)
└── TheBrains (owned)
    ├── TheSafecracker (owned)
    │   └── TheFingerprints (lazy)
    └── TheStash (owned)
        └── TheBurglar (private)
```

TheInsideJob talks to TheBrains, never directly to TheStash or below.

> Full dossiers: [`docs/dossiers/`](../../../docs/dossiers/)
