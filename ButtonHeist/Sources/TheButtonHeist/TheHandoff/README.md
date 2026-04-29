# TheHandoff

Device lifecycle manager. Finds devices via Bonjour/USB, connects over TLS, maintains keepalive, and auto-reconnects on disconnect.

## Reading order

1. **`DeviceProtocols.swift`** — Start here. Two protocols define the mock boundary:
   - `DeviceDiscovering` — `discoveredDevices`, `onEvent`, `start()`/`stop()`. Events: `.found`, `.lost`, `.stateChanged(isReady:)`.
   - `DeviceConnecting` — `isConnected`, `observeMode`, `onEvent`, `connect()`/`disconnect()`, `send(_:requestId:)`. Events: `.transportReady`, `.connected`, `.message(ServerMessage, requestId:, backgroundDelta:)`, `.disconnected(DisconnectReason)`.

2. **`DiscoveredDevice.swift`** — Value type for a discovered device. Key fields: `id` (service name), `endpoint` (NWEndpoint), `simulatorUDID`, `certFingerprint` (SHA-256 for TLS pinning), `sessionActive`. `matches(filter:)` does case-insensitive substring check on name/appName/deviceName and prefix check on shortId/installationId/instanceId/simulatorUDID. `isReachable(timeout:)` creates a throwaway connection and sends `.status` to probe.

3. **`TheHandoff.swift`** — The `@ButtonHeistActor final class`. Three state machines:
   - `ConnectionPhase`: `.disconnected` / `.connecting(device:)` / `.connected(device:, keepaliveTask:)` / `.failed(ConnectionFailure)` — keepalive task lives inside `.connected` so it's automatically scoped.
   - `ReconnectPolicy`: `.disabled` / `.enabled(filter:, reconnectTask:)`.
   - `RecordingPhase`: `.idle` / `.recording`.

   **`connectWithDiscovery(filter:timeout:)`** is the main entry: starts discovery if needed → `DeviceResolver.resolve()` → `connect(to: device)` → polls `connectionPhase` every 100ms until `.connected` or timeout.

   **`connect(to:)`** creates a connection via the `makeConnection` closure, installs the `onEvent` handler (which drives phase transitions), and calls `connection.connect()`.

   **Keepalive**: `.ping` every 5 seconds. After 6 missed pongs (roughly 30s silence), forces disconnect.

   **Auto-reconnect** (`runAutoReconnect`): up to 60 attempts, exponential backoff (1s base, capped at 30s, ±20% jitter). Checks `discoveredDevices.first(matching: filter)` each iteration — no re-resolve, just reads the live list.

4. **`DeviceConnection.swift`** — `DeviceConnecting` implementation. `ConnectionState`: `.disconnected` / `.connecting(NWConnection)` / `.connected(ActiveConnection)`. TLS fingerprint verification in `sec_protocol_options_set_verify_block`: extracts leaf cert → SHA256 → compares to `device.certFingerprint`. Loopback endpoints skip pinning. Wire format: newline-delimited JSON, 10 MB buffer cap. The `handleMessage` method drives the auth handshake: `.serverHello` → send `.clientHello` → `.authRequired` → send `.authenticate` → `.info` → fire `.connected` event.

5. **`DeviceDiscovery.swift`** — Bonjour `NWBrowser` wrapper. Uses a `DiscoveryRegistry` for deduplication: devices are keyed by `discoveryIdentity` (installationId-based), not service name. Registry handles same-app re-advertisement (old service lost + new found as a single swap). Background reachability validation every 3s evicts stale devices.

6. **`DeviceResolver.swift`** — Stabilize-then-probe algorithm in a `struct` (no instance state). Fast path: if filter is a loopback `host:port`, returns immediately. Otherwise: polls `getDiscoveredDevices()` every 100ms, waits for the list to stabilize (same device IDs for 500ms), then probes reachability. Multiple reachable devices with no filter → error (ambiguous).

7. **`USBDeviceDiscovery.swift`** — macOS only. Polls `xcrun devicectl list devices` + `lsof -i -P -n` every 3s to find CoreDevice IPv6 tunnels. No TXT records, no fingerprints — USB devices use loopback TLS (accept any cert). Constructs `DiscoveredDevice` with `id: "usb-\(deviceName)"`.

> Full dossier: [`docs/dossiers/04-THEHANDOFF.md`](../../../../docs/dossiers/04-THEHANDOFF.md)
