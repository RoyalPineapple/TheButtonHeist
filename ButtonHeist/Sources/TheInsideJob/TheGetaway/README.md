# TheGetaway

The getaway driver — runs all comms between the wire and the crew.

## The one file

**`TheGetaway.swift`** — `@MainActor final class`. Does not own any crew members — receives references to TheMuscle, TheBrains, and TheTripwire from TheInsideJob at init.

### Transport wiring

`wireTransport(_:)` installs five closures on TheMuscle (sendToClient, markClientAuthenticated, disconnectClient, onClientAuthenticated, onSessionActiveChanged), installs a synchronous ping fast-path on the transport via `setSyncDataInterceptor(_:)`, and starts a single long-lived consumer task that awaits `transport.events` (an ordered `AsyncStream<TransportEvent>`) and dispatches each event via `handleTransportEvent(_:)`. This is the bridge between auth and networking — TheMuscle and ServerTransport never reference each other directly. Routing every event through one stream means `clientConnected` always lands before its first `dataReceived`, the race the prior per-event `Task { @MainActor in ... }` callback bridge could lose.

### Message dispatch

`handleClientMessage(_:data:respond:)` is the two-level switch:

1. **Protocol level** — clientHello/authenticate (pre-auth, owned by TheMuscle), requestInterface, ping, status. Legacy subscribe/unsubscribe/watch messages return `unsupported`.
2. **Observation level** — requestScreen, waitForIdle (`brains.executeWaitForIdle`), waitForChange (`brains.executeWaitForChange`)
3. **Action level** — recording start/stop, or `brains.executeCommand(message)` for all action commands

Before dispatching actions, checks `brains.computeBackgroundAccessibilityTrace()` — if the screen changed while the agent was thinking and the command targets a specific element, fails before execution and returns the current accessibility trace plus its derived delta.

### Encode / decode / send

- `encodeEnvelope(_:requestId:accessibilityTrace:)` — wraps `ServerMessage` in `ResponseEnvelope`, JSON-encodes
- `decodeRequest(_:)` — JSON-decodes `RequestEnvelope`
- `sendMessage(_:requestId:accessibilityTrace:respond:)` — encode + respond, with error fallback
- `broadcastToSubscribed(_:)` / `broadcastToAll(_:)` — encode once, send to many

### Recording

Owns `RecordingPhase` state machine (`.idle` / `.recording(stakeout:)`). `handleStartRecording` creates a `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()`, and stores completed recordings until `stop_recording` retrieves them. `handleStopRecording` calls `stakeout.stopRecording(reason: .manual)` and returns the final payload to that caller.

### Settled change tracking

`noteSettledChangeIfNeeded()` updates recording inactivity state when a settled accessibility capture has changed. Runtime hierarchy subscriptions are no longer a public surface.

`sendInterface(requestId:respond:)` settles, refreshes, builds the normal app accessibility-state payload via `brains.currentInterface()`, sends it, and records the sent state. Diagnostic on-screen reads and explicit exploration are command-level concerns outside this transport helper.

### Identity

Receives a `ServerIdentity` struct from TheInsideJob at init (sessionId, effectiveInstanceId, tlsActive). Used to populate `ServerInfo` responses.

> Full dossier: [`docs/dossiers/09-THEGETAWAY.md`](../../../../docs/dossiers/09-THEGETAWAY.md)
