# TheGetaway

The getaway driver — runs all comms between the wire and the crew.

## Files

**`TheGetaway.swift`** — `@MainActor final class`. Does not own any crew members — receives references to TheMuscle and TheBrains from TheInsideJob at init. Owns the central client-message dispatch switch and delegates encoding, transport, delivery, status, and recording details to focused extensions.

**`TheGetaway+Transport.swift`** — wires ServerTransport to TheMuscle, consumes ordered transport events, and maps terminal client delivery failures through the disconnect lifecycle.

**`TheGetaway+WireEncoding.swift`** — owns the ResponseEnvelope/RequestEnvelope encode/decode contract, typed delivery results, and the invariant that response encoding failures do not synthesize alternate wire shapes.

**`TheGetaway+Broadcast.swift`** — owns authenticated-client broadcast delivery, including typed delivery failures and the "no screenshots over broadcast" session contract.

**`TheGetaway+Status.swift`** — builds server identity, status, and cached pong payloads from runtime process/device state.

**`BackgroundChangeState.swift`** — tracks settled background parse progress and command/parser phase transitions.

### Transport wiring

`wireTransport(_:)` installs six closures on TheMuscle (sendToClient, markClientAuthenticated, markClientAwaitingApproval, disconnectClient, onClientAuthenticated, onSessionActiveChanged), installs a synchronous ping fast-path on the transport via `setSyncDataInterceptor(_:)`, and starts a single long-lived consumer task that awaits `transport.events` (an ordered `AsyncStream<TransportEvent>`) and dispatches each event via `handleTransportEvent(_:)`. This is the bridge between auth and networking — TheMuscle and ServerTransport never reference each other directly. Routing every event through one stream means `clientConnected` always lands before its first `dataReceived`, the race the prior per-event `Task { @MainActor in ... }` callback bridge could lose.

### Message dispatch

`handleClientMessage(_:data:respond:)` is the two-level switch:

1. **Protocol level** — clientHello/authenticate (pre-auth, owned by TheMuscle), requestInterface, ping, status.
2. **Observation level** — requestScreen, waitForIdle (`brains.executeWaitForIdle`), waitForChange (`brains.executeWaitForChange`)
3. **Action level** — recording start/stop, or `brains.executeCommand(message)` for all action commands

Before dispatching actions, checks `brains.computeBackgroundAccessibilityTrace()` so the response can include background accessibility context. Element-scoped commands still dispatch through TheBrains; semantic targeting owns viewport inflation and live geometry acquisition.

### Encode / decode / send

- `encodeEnvelope(_:requestId:accessibilityTrace:)` — wraps `ServerMessage` in `ResponseEnvelope`, JSON-encodes
- `decodeRequest(_:)` — JSON-decodes `RequestEnvelope`
- `sendMessage(_:requestId:accessibilityTrace:respond:)` — encode + respond with `DeliveryResult`; encoding failures do not synthesize alternate response shapes
- `broadcastToAll(_:)` — encode once, send lightweight recording notifications to all authenticated clients with the same `DeliveryResult` contract

### Recording

Owns `RecordingRouteState` (`.idle`, `.starting`, `.recording`, `.stopping`, `.invalidating`, `.completed`, `.invalidated`) plus a projected `RecordingPhase` for status. `handleStartRecording` creates a `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()`, and records the originator client. `handleStopRecording` parks a waiter while finalization runs; auto-finished recordings are delivered only to the originator when possible, with other clients receiving lightweight `recordingStopped` notifications.

### Settled change tracking

`noteSettledChangeIfNeeded()` updates recording inactivity state when a settled accessibility capture has changed. Runtime hierarchy subscriptions are no longer a public surface.

`sendInterface(query:requestId:respond:)` forwards the observation request to TheBrains, sends the returned accessibility state, and records the sent state. TheBrains owns refresh, exploration, selection, and stale-state decisions; TheGetaway only routes typed messages and responses.

### Identity

Receives a `ServerIdentity` struct from TheInsideJob at init (sessionId, effectiveInstanceId, tlsActive). Used to populate `ServerInfo` responses.

> Full dossier: [`docs/dossiers/09-THEGETAWAY.md`](../../../../docs/dossiers/09-THEGETAWAY.md)
