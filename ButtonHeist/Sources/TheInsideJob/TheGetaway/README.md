# TheGetaway

The getaway driver — runs all comms between the wire and the crew.

## The one file

**`TheGetaway.swift`** — `@MainActor final class`. Does not own any crew members — receives references to TheMuscle, TheBrains, and TheTripwire from TheInsideJob at init.

### Transport wiring

`wireTransport(_:)` installs six closures on TheMuscle (sendToClient, markClientAuthenticated, markClientAwaitingApproval, disconnectClient, onClientAuthenticated, onSessionActiveChanged), installs a synchronous ping fast-path on the transport via `setSyncDataInterceptor(_:)`, and starts a single long-lived consumer task that awaits `transport.events` (an ordered `AsyncStream<TransportEvent>`) and dispatches each event via `handleTransportEvent(_:)`. This is the bridge between auth and networking — TheMuscle and ServerTransport never reference each other directly. Routing every event through one stream means `clientConnected` always lands before its first `dataReceived`, the race the prior per-event `Task { @MainActor in ... }` callback bridge could lose.

### Message dispatch

`handleClientMessage(_:data:respond:)` is the two-level switch:

1. **Protocol level** — clientHello/authenticate (pre-auth, owned by TheMuscle), requestInterface, ping, status.
2. **Observation level** — requestScreen, waitForIdle (`brains.executeWaitForIdle`), waitForChange (`brains.executeWaitForChange`)
3. **Action level** — recording start/stop, or `brains.executeCommand(message)` for all action commands

Before dispatching actions, checks `brains.computeBackgroundAccessibilityTrace()` — if the screen changed while the agent was thinking and the command targets a specific element, fails before execution and returns the current accessibility trace plus its derived delta.

### Encode / decode / send

- `encodeEnvelope(_:requestId:accessibilityTrace:)` — wraps `ServerMessage` in `ResponseEnvelope`, JSON-encodes
- `decodeRequest(_:)` — JSON-decodes `RequestEnvelope`
- `sendMessage(_:requestId:accessibilityTrace:respond:)` — encode + respond; encoding failures do not synthesize alternate response shapes
- `broadcastToAll(_:)` — encode once, send lightweight recording notifications to all authenticated clients

### Recording

Owns `RecordingRouteState` (`.idle`, `.starting`, `.recording`, `.stopping`, `.invalidating`, `.completed`, `.invalidated`) plus a projected `RecordingPhase` for status. `handleStartRecording` creates a `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()`, and records the originator client. `handleStopRecording` parks a waiter while finalization runs; auto-finished recordings are delivered only to the originator when possible, with other clients receiving lightweight `recordingStopped` notifications.

### Settled change tracking

`noteSettledChangeIfNeeded()` updates recording inactivity state when a settled accessibility capture has changed. Runtime hierarchy subscriptions are no longer a public surface.

`sendInterface(query:requestId:respond:)` forwards the observation request to TheBrains, sends the returned accessibility state, and records the sent state. TheBrains owns refresh, exploration, selection, and stale-state decisions; TheGetaway only routes typed messages and responses.

### Identity

Receives a `ServerIdentity` struct from TheInsideJob at init (sessionId, effectiveInstanceId, tlsActive). Used to populate `ServerInfo` responses.

> Full dossier: [`docs/dossiers/09-THEGETAWAY.md`](../../../../docs/dossiers/09-THEGETAWAY.md)
