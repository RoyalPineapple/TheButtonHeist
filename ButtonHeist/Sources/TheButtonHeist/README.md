# TheButtonHeist (ButtonHeist framework)

macOS client framework — the host-side orchestration layer for CLI, MCP, and SDK consumers.

## Layout

| Folder | Crew member | Role |
|--------|-------------|------|
| `TheFence/` | TheFence | Command dispatch hub — routes 41 commands, manages request-response correlation |
| `TheHandoff/` | TheHandoff | Device lifecycle — Bonjour/USB discovery, TLS connection, keepalive, auto-reconnect |
| `TheBookKeeper/` | TheBookKeeper | Session logs, artifact storage, compression, heist recording |
| `Config/` | — | Environment and target configuration |
| `Support/` | — | Concurrency primitives and small utilities |

Root files: `ButtonHeistActor.swift` (global actor), `Exports.swift` (public re-exports).

## Ownership

```
TheFence
├── TheHandoff (owned)
│   ├── DeviceDiscovery (protocol-mediated)
│   ├── USBDeviceDiscovery
│   └── DeviceConnection (protocol-mediated)
└── TheBookKeeper (owned, no TheFence type dependencies)
```

CLI and MCP both enter through `TheFence.execute(request:)`. Nothing else is public.

> Full dossiers: [`docs/dossiers/`](../../../docs/dossiers/)
