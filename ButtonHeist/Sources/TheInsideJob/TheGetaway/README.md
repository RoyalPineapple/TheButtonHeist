# TheGetaway

The getaway driver — runs all comms between the wire and the crew.

## The one file

**`TheGetaway.swift`** — `@MainActor final class`. Does not own any crew members — receives references to TheMuscle, TheBrains, and TheTripwire from TheInsideJob at init.

### Transport wiring

`wireTransport(_:)` installs five closures on TheMuscle (sendToClient, markClientAuthenticated, disconnectClient, onClientAuthenticated, onSessionActiveChanged) and four on ServerTransport (onClientConnected, onClientDisconnected, onDataReceived, onUnauthenticatedData). This is the bridge between auth and networking — TheMuscle and ServerTransport never reference each other directly.

### Message dispatch

`handleClientMessage(_:data:respond:)` is the two-level switch:

1. **Protocol level** — clientHello/authenticate/watch (pre-auth, handled via onUnauthenticatedData), requestInterface, subscribe/unsubscribe, ping, status
2. **Observation level** — requestScreen, waitForIdle (`brains.executeWaitForIdle`), waitForChange (`brains.executeWaitForChange`)
3. **Action level** (blocked for observers) — recording start/stop, or `brains.executeCommand(message)` for all action commands

Before dispatching actions, checks `brains.computeBackgroundDelta()` — if the screen changed while the agent was thinking and the action targets a heistId, returns a synthetic "screen changed" result instead of executing the stale action.

### Encode / decode / send

- `encodeEnvelope(_:requestId:backgroundDelta:)` — wraps `ServerMessage` in `ResponseEnvelope`, JSON-encodes
- `decodeRequest(_:)` — JSON-decodes `RequestEnvelope`
- `sendMessage(_:requestId:backgroundDelta:respond:)` — encode + respond, with error fallback
- `broadcastToSubscribed(_:)` / `broadcastToAll(_:)` — encode once, send to many

### Recording

Owns `RecordingPhase` state machine (`.idle` / `.recording(stakeout:)`). `handleStartRecording` creates a `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()` and `onRecordingComplete` to broadcast the result. `handleStopRecording` calls `stakeout.stopRecording(reason: .manual)`.

### Hierarchy broadcast

`broadcastIfChanged()` calls `brains.broadcastInterfaceIfChanged()` — if the tree changed, broadcasts the `Interface` to subscribers and captures a screen for recording. Called by TheInsideJob's pulse handler and polling task.

`sendInterface(requestId:respond:)` settles, refreshes, explores, builds the full `Interface` payload via `brains.currentInterface()`, sends it, and records the sent state.

### Identity

Receives a `ServerIdentity` struct from TheInsideJob at init (sessionId, effectiveInstanceId, tlsActive). Used to populate `ServerInfo` responses.

> Full dossier: [`docs/dossiers/09-THEGETAWAY.md`](../../../../docs/dossiers/09-THEGETAWAY.md)
