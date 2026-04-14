# Server

TLS/TCP server infrastructure — listener, transport, authentication, and connection scope classification.

## Reading order

1. **`SimpleSocketServer.swift`** — `public actor`. `ServerPhase`: `.stopped` / `.listening(listener:, port:)`. `ClientPhase`: `.unauthenticated(connection:, timestamps:)` / `.authenticated(connection:, timestamps:)`. Max 5 concurrent clients.

   `startAsync(port:tlsParameters:callbacks:)` creates an `NWListener`, uses `withCheckedThrowingContinuation` to bridge the state handler (resumes on `.ready` with the bound port). `newConnectionHandler` routes to `handleNewConnection`, which optionally checks `ConnectionScope.classify` against `allowedScopes`, starts receiving, and schedules a 10-second auth deadline.

   Receive loop: `receiveNextChunk` appends to a buffer (10 MB cap), scans for `0x0A` newline delimiters, routes each complete message to `callbacks.onDataReceived` (authenticated) or `callbacks.onUnauthenticatedData` (pre-auth). Rate limiting: 30 messages/second per client.

   `listeningPort` is `nonisolated` via an `OSAllocatedUnfairLock<UInt16>` — readable without actor hop.

2. **`TheMuscle.swift`** — `@MainActor final class`. Authentication and session locking.

   **`ClientPhase`**: `.connected` → `.helloValidated` → `.pendingApproval` or `.authenticated` or `.observer`.

   **`SessionPhase`**: `.idle` → `.active(driverId:, connections:)` → `.draining(driverId:, releaseTimer:)` → `.idle`.

   Auth flow: `handleUnauthenticatedMessage` decodes the envelope, checks protocol version, then dispatches:
   - `.clientHello` → transition to `.helloValidated`, send `.authRequired`
   - `.authenticate(payload)` → check lockout → empty token: show `UIAlertController` (`.pendingApproval`) → wrong token: `recordFailedAttempt`, locked after 5 failures for 30s → correct token: `acquireSession`
   - `.watch(payload)` → observer mode (read-only, no session claim)

   `acquireSession`: `.idle` → claim. Same driver → add connection. Different driver → `.sessionLocked`, disconnect after 100ms grace. Draining same driver → cancel release timer, re-activate.

   Session release: when all connections drop, starts a 30s drain timer (configurable via `INSIDEJOB_SESSION_TIMEOUT`). If no reconnect arrives, transitions to `.idle`.

   Communicates outward entirely through injected closures (`sendToClient`, `markClientAuthenticated`, `disconnectClient`, `onClientAuthenticated`, `onSessionActiveChanged`).

3. **`ServerTransport.swift`** — `@MainActor public final class NSObject`. Wraps `SimpleSocketServer` + `NetService`. Created by TheInsideJob, wired to TheMuscle by TheGetaway's `wireTransport(_:)`. `start(port:)` gets TLS parameters from `tlsIdentity`, starts the server. `advertise(serviceName:...)` creates a `NetService` with TXT record (cert fingerprint, simulator UDID, instance ID, etc.). `updateTXTRecord(_:)` merges entries and re-publishes.

4. **`TLSIdentity.swift`** — `public actor`. `getOrCreate()` checks Keychain for stored identity, regenerates if expiry ≤30 days. `generateCertificate(validityDays:)` creates a `P256.Signing.PrivateKey`, builds a self-signed `X509.Certificate` (CN=ButtonHeist, ECDSA-SHA256, 1-year), serializes to DER. `computeFingerprint` hashes DER bytes with SHA-256. `createEphemeral()` generates cert, briefly stores in Keychain to get a `SecIdentity`, then immediately deletes both Keychain items.

5. **`ConnectionScope+Classify.swift`** — Extends `ConnectionScope` (from TheScore) with `classify(host:interfaces:)`. IPv4/IPv6 loopback → `.simulator`. `anpi` interface name prefix → `.usb`. Everything else → `.network`.

> Full dossiers: [`docs/dossiers/06-THEMUSCLE.md`](../../../../docs/dossiers/06-THEMUSCLE.md)
