# TheButtonHeist (ButtonHeist framework)

macOS client framework. CLI and MCP both enter through `TheFence.execute(request:)` — everything else is internal.

## Layout

| Folder | What to read first | What it does |
|--------|--------------------|--------------|
| `TheFence/` | `TheFence.swift` → `TheFence+CommandCatalog.swift` | Command dispatch hub. 42-case `Command` enum, request-response correlation via `PendingRequestTracker`, response formatting. |
| `TheHandoff/` | `DeviceProtocols.swift` → `TheHandoff.swift` | Device lifecycle. Bonjour/USB discovery, TLS connection, 5s keepalive with 6 missed pongs before disconnect, auto-reconnect (up to 60 attempts with exponential backoff). |
| `TheBookKeeper/` | `TheBookKeeper.swift` | Session I/O. Append-only JSONL logs, sequence-numbered artifacts, gzip compression, heist recording with minimal-matcher synthesis. |
| `Config/` | `EnvironmentConfig.swift` | Reads `BUTTONHEIST_*` env vars and `.buttonheist.json` target files. |
| `Support/` | Any file | `CancellableSleep`, `IdleMonitor`, `PendingRequestTracker`, `Error+Message`, `String+PathValidation`. |

Root files: `ButtonHeistActor.swift` (global actor declaration), `Exports.swift` (public re-exports of TheScore).

## How a command flows

```
CLI/MCP call
  → TheFence.execute(request:)           // parse command, auto-connect, log
    → dispatch(command:args:)            // switch on Command enum
      → handler (e.g. handleOneFingerTap)
        → sendAction(.touchTap(...))     // build ClientMessage
          → handoff.send(message, requestId:)  // wire transmission
            → actionTracker.wait(requestId:)   // suspend until response
              ← handoff.onActionResult resolves the tracker
    ← FenceResponse                      // formatted for human/JSON/compact output
```

All three types (`TheFence`, `TheHandoff`, `TheBookKeeper`) are `@ButtonHeistActor`-isolated, so cross-object calls are synchronous hops on the same actor — no `await` needed between them.

> Full dossiers: [`docs/dossiers/`](../../../docs/dossiers/) — see `03-THEFENCE.md`, `04-THEHANDOFF.md`, `05-THEBOOKKEEPER.md`
