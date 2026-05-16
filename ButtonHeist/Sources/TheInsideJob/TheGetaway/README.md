# TheGetaway

The getaway driver — runs all comms between the wire and the crew.

## The one file

**`TheGetaway.swift`** — `@MainActor final class`. Does not own any crew members — receives references to TheMuscle, TheBrains, and TheTripwire from TheInsideJob at init.

### Transport wiring

`wireTransport(_:)` installs five closures on TheMuscle (sendToClient, markClientAuthenticated, disconnectClient, onClientAuthenticated, onSessionActiveChanged), installs a synchronous ping fast-path on the transport via `setSyncDataInterceptor(_:)`, and starts a single long-lived consumer task that awaits `transport.events` (an ordered `AsyncStream<TransportEvent>`) and dispatches each event via `handleTransportEvent(_:)`. This is the bridge between auth and networking — TheMuscle and ServerTransport never reference each other directly. Routing every event through one stream means `clientConnected` always lands before its first `dataReceived`, the race the prior per-event `Task { @MainActor in ... }` callback bridge could lose.

### Message dispatch

`handleClientMessage(_:data:respond:)` is the two-level switch:

1. **Protocol level** — clientHello/authenticate/watch (pre-auth, handled via onUnauthenticatedData), requestInterface, subscribe/unsubscribe, ping, status
2. **Observation level** — requestScreen, waitForIdle (`brains.executeWaitForIdle`), waitForChange (`brains.executeWaitForChange`)
3. **Action level** (blocked for observers) — recording start/stop, or `brains.executeCommand(message)` for all action commands

Before dispatching actions, checks `brains.computeBackgroundDelta()` — if the screen changed while the agent was thinking and the command targets a specific element, fails before execution and returns the current delta.

### Encode / decode / send

- `encodeEnvelope(_:requestId:backgroundDelta:)` — wraps `ServerMessage` in `ResponseEnvelope`, JSON-encodes
- `decodeRequest(_:)` — JSON-decodes `RequestEnvelope`
- `sendMessage(_:requestId:backgroundDelta:respond:)` — encode + respond, with error fallback
- `broadcastToSubscribed(_:)` / `broadcastToAll(_:)` — encode once, send to many

### Recording

Owns `RecordingPhase` state machine (`.idle` / `.recording(stakeout:)`). `handleStartRecording` creates a `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()`, and stores completed recordings until `stop_recording` retrieves them. `handleStopRecording` calls `stakeout.stopRecording(reason: .manual)` and returns the final payload to that caller.

### Hierarchy broadcast

`broadcastIfChanged()` calls `brains.broadcastInterfaceIfChanged()` — if the tree changed, broadcasts the `Interface` to subscribers. Called by TheInsideJob's pulse handler and polling task.

`sendInterface(requestId:respond:)` settles, refreshes, builds the visible `Interface` payload via `brains.currentInterface()`, sends it, and records the sent state. Full-screen exploration is handled by the explicit `.explore` command.

### Identity

Receives a `ServerIdentity` struct from TheInsideJob at init (sessionId, effectiveInstanceId, tlsActive). Used to populate `ServerInfo` responses.

> Full dossier: [`docs/dossiers/09-THEGETAWAY.md`](../../../../docs/dossiers/09-THEGETAWAY.md)
