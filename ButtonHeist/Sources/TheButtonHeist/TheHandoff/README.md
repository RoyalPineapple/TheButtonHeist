# TheHandoff

Client-side device lifecycle — discovery, TLS connection, keepalive, and auto-reconnect.

## Files

| File | Role |
|------|------|
| `TheHandoff.swift` | Lifecycle orchestrator: discovery, connection, reconnect policy |
| `DeviceDiscovery.swift` | Bonjour `NWBrowser` wrapper |
| `USBDeviceDiscovery.swift` | CoreDevice IPv6 tunnel polling (macOS only) |
| `DeviceConnection.swift` | TLS/TCP `NWConnection` client with fingerprint pinning |
| `DeviceResolver.swift` | Stabilize-then-probe device resolution |
| `DeviceProtocols.swift` | `DeviceConnecting`, `DeviceDiscovering` — the mock boundary for tests |
| `DiscoveredDevice.swift` | Bonjour service record + reachability probing |

## Boundaries

- Owned by TheFence. TheFence never reaches into `DeviceConnection` or `DeviceDiscovery` directly.
- `DeviceConnecting` / `DeviceDiscovering` protocols are injectable for testing.
- Connection phase modeled as explicit state machine: `.disconnected` / `.connecting` / `.connected` / `.failed`.

> Full dossier: [`docs/dossiers/02-THEHANDOFF.md`](../../../../docs/dossiers/02-THEHANDOFF.md)
