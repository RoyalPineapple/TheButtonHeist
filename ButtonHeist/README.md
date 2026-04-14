# ButtonHeist Frameworks

Three framework targets, one shared protocol. Each folder has its own README walking through the code.

```
ButtonHeist/
├── Sources/
│   ├── TheScore/           # Wire protocol (iOS + macOS)
│   ├── TheButtonHeist/     # Client framework (macOS)
│   │   ├── TheFence/       #   Command dispatch
│   │   ├── TheHandoff/     #   Device discovery + connection
│   │   ├── TheBookKeeper/  #   Session logs + heist recording
│   │   ├── Config/         #   Environment + target config
│   │   └── Support/        #   Utilities
│   └── TheInsideJob/       # Server framework (iOS)
│       ├── TheGetaway/     #   Message routing + comms
│       ├── TheBrains/      #   Action orchestration + delta cycle
│       ├── TheStash/       #   Element registry + resolution
│       ├── TheBurglar/     #   Accessibility tree parsing
│       ├── TheSafecracker/ #   Touch injection + gestures
│       ├── TheTripwire/    #   UI pulse + settle detection
│       ├── TheStakeout/    #   Screen recording
│       ├── Server/         #   TLS server + auth
│       └── Support/        #   Utilities
└── Tests/
    ├── TheScoreTests/
    ├── ButtonHeistTests/
    └── TheInsideJobTests/
```

## How they connect

```
┌─────────────────────┐         ┌─────────────────────┐
│   TheButtonHeist    │   TLS   │    TheInsideJob      │
│   (macOS client)    │◄───────►│    (iOS server)      │
└────────┬────────────┘         └────────┬────────────┘
         │ imports                        │ imports
         ▼                               ▼
    ┌─────────┐                     ┌─────────┐
    │TheScore │                     │TheScore │
    └─────────┘                     └─────────┘
```

TheScore is the shared contract. Client encodes `ClientMessage` (37 cases), server decodes it, processes it, encodes `ServerMessage` (18 cases), client decodes the response. Wire format: newline-delimited JSON over TLS 1.3.

## Where to start

- **[`Sources/`](Sources/)** — Module overview and reading guide
- **[`docs/dossiers/`](../docs/dossiers/)** — Architecture, design philosophy, and diagrams

## Auto-start

TheInsideJob starts automatically when the framework loads in DEBUG builds — no code changes needed. `ThePlant` (ObjC `+load`) dispatches to main queue, reads config from env vars or Info.plist, creates the server, and begins polling. See `AutoStart.swift` at the TheInsideJob root.

## Configuration

| Env var | Info.plist key | Default | Purpose |
|---------|---------------|---------|---------|
| `INSIDEJOB_TOKEN` | `InsideJobToken` | Auto-generated UUID | Auth token |
| `INSIDEJOB_ID` | `InsideJobInstanceId` | Short UUID prefix | Instance identifier |
| `INSIDEJOB_PORT` | `InsideJobPort` | 0 (OS-assigned) | Preferred listen port |
| `INSIDEJOB_POLLING_INTERVAL` | `InsideJobPollingInterval` | `2.0` | Hierarchy poll interval (min 0.5s) |
| `INSIDEJOB_SCOPE` | — | `simulator,usb` | Connection scope filter |
| `INSIDEJOB_SESSION_TIMEOUT` | — | `30.0` | Session lock timeout |
| `INSIDEJOB_DISABLE` | `InsideJobDisableAutoStart` | Not set | Set `true` to prevent auto-start |
| `INSIDEJOB_DISABLE_FINGERPRINTS` | `InsideJobDisableFingerprints` | `false` | Disable touch indicators |

## See also

- [Project README](../README.md) — Quick start, features, usage
- [Architecture](../docs/ARCHITECTURE.md) — System design and data flow
- [API Reference](../docs/API.md) — Public API documentation
- [Wire Protocol](../docs/WIRE-PROTOCOL.md) — Message format specification
