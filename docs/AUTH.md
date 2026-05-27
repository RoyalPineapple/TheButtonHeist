# Button Heist Authentication

Every TCP connection must authenticate before it can send commands. This document describes how authentication works end-to-end.

## Overview

Authentication is mandatory for driver connections. When a client connects, the server first sends `serverHello`. The client must respond with `clientHello` using the exact same `buttonHeistVersion`, then wait for `authRequired`. After that, it responds with `authenticate`. Any other message before the handshake completes causes immediate disconnection.

There are two connection modes:

1. **Token auth** — The client sends a known token via `authenticate`. If it matches, the client is authenticated as a driver.
2. **UI approval** — The client sends an empty token via `authenticate`. If the server is in UI approval mode, an on-device prompt asks the user to Allow or Deny the connection. On Allow, the server sends the token back so the client can reuse it.

Auth outcomes are intentionally distinct:
- Wrong non-empty token: `error(kind: "authFailure")`, then disconnect. With an explicit server token, retry with that configured token. With an auto-generated token, retry without a token only if you want to request UI approval.
- Approval pending: `authApprovalPending`, non-terminal. The client should wait for the user to respond on the device.
- Approval denied: `error(kind: "authFailure", message: "Connection denied by user")`, then disconnect.
- Approval timeout: `error(kind: "authApprovalPending")`, then disconnect.

## Agent Isolation

When multiple agents run in parallel, each agent must use its own simulator, port, and token to prevent cross-talk. The token doubles as a human-readable label scoped to the agent's work item.

**Convention:** simulator name = token = instance ID = `{workspace}-{task-slug}`. See `.context/bh-infra/docs/MULTI_AGENT_SIMULATORS.md` (if available — clone via `/setup-context bh-infra`) for the full convention, pool architecture, and troubleshooting.

```bash
TASK_SLUG="accra-scroll-detection"
SIM_UDID=$(xcrun simctl create "$TASK_SLUG" "iPhone 16 Pro")
xcrun simctl boot "$SIM_UDID"

SIMCTL_CHILD_INSIDEJOB_PORT="$((RANDOM % 10000 + 20000))" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

**Why human-readable tokens?** When an agent gets an auth mismatch, the error
does not disclose the expected token. A human-readable explicit token such as
`accra-scroll-detection` still helps operators and logs identify which
simulator/work item owns the session without treating a random UUID as a
durable secret.

**Why per-task simulators?** Shared simulators lead to port collisions, stale app state, and agents killing each other's sessions. A dedicated simulator per task is cheap (`simctl create` takes milliseconds) and eliminates the entire class of interference bugs.

## Token Resolution

The server resolves its auth token at startup using this priority:

```mermaid
flowchart TD
    Start["Server starts"] --> Check1{"Explicit token set?"}
    Check1 -->|"INSIDEJOB_TOKEN env var<br/>or InsideJobToken plist key"| Explicit["Use explicit token"]
    Check1 -->|No| Generate["Generate fresh UUID<br/>(ephemeral, not persisted)"]
```

When no explicit token is set, a fresh UUID is generated each launch. Previously approved clients must re-authenticate after an app restart.

## Configuration

### Server-side (iOS app)

| Method | Key | Example |
|--------|-----|---------|
| Environment variable | `INSIDEJOB_TOKEN` | `INSIDEJOB_TOKEN=my-secret-token` |
| Info.plist | `InsideJobToken` | `<string>my-secret-token</string>` |
| Auto-generated | (none) | Ephemeral token redacted in startup logs; request UI approval to receive a reusable token |

When no explicit token is configured, startup logs show that the token exists
but redact its value:
```
[TheInsideJob] token=<redacted>
```

### Client-side (macOS / CLI)

| Method | Key | Example |
|--------|-----|---------|
| CLI flag | `--token` | `buttonheist session` (or pass token via `BUTTONHEIST_TOKEN` / `--token` where supported) |
| Environment variable | `BUTTONHEIST_TOKEN` | `export BUTTONHEIST_TOKEN=my-secret-token` |
| UI approval | (omit token) | Client sends empty token; user approves on device |

Priority: `--token` flag > `BUTTONHEIST_TOKEN` env var > empty string (UI approval).

When a client is approved via UI, the server sends the token in the `authApproved` message. The CLI prints it:
```
BUTTONHEIST_TOKEN=<token>
```

## Connection Flows

### Standard Token Auth

Client has the correct token (explicit or previously received via UI approval).

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: serverHello
    Client->>TheInsideJob: clientHello
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token)
    Note right of TheInsideJob: TheMuscle.handleUnauthenticatedMessage<br/>token matches → authenticated state
    TheInsideJob->>Client: info
    Note right of TheInsideJob: handleClientConnected → sendServerInfo
    Client->>TheInsideJob: requestInterface
    Note over Client,TheInsideJob: Client is now fully connected
```

### UI Approval — Allowed

Client has no token. Server is in UI approval mode (auto-generated token).

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: serverHello
    Client->>TheInsideJob: clientHello
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"")
    Note right of TheInsideJob: token is empty<br/>→ store in pendingApprovalClients<br/>→ show UIAlertController
    TheInsideJob->>Client: authApprovalPending

    rect rgb(240, 240, 240)
        Note right of TheInsideJob: Connection Request<br/>Connection #N is requesting access.<br/>[Deny] [Allow]
    end

    Note right of TheInsideJob: User taps Allow
    TheInsideJob->>Client: authApproved(token)
    Note left of Client: Client stores token for reuse
    Note right of TheInsideJob: TheMuscle.approveClient<br/>→ authenticated state
    TheInsideJob->>Client: info
    Note right of TheInsideJob: handleClientConnected → sendServerInfo
    Client->>TheInsideJob: requestInterface
```

The `authApproved` message includes the server's token. The client stores it and sends it on future connections, skipping the UI prompt.

### UI Approval — Denied

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: serverHello
    Client->>TheInsideJob: clientHello
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"")
    Note right of TheInsideJob: → show UIAlertController
    TheInsideJob->>Client: authApprovalPending
    Note right of TheInsideJob: User taps Deny
    TheInsideJob->>Client: error(authFailure)
    Note left of Client: "Connection denied by user"
    Note right of TheInsideJob: → disconnect after 100ms
    TheInsideJob--xClient: TCP closed
```

### UI Approval — Timeout

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: serverHello
    Client->>TheInsideJob: clientHello
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"")
    TheInsideJob->>Client: authApprovalPending
    Note right of TheInsideJob: User does not respond before auth deadline
    TheInsideJob->>Client: error(authApprovalPending)
    Note left of Client: "Approval timed out — user did not respond..."
    TheInsideJob--xClient: TCP closed
```

### Invalid Token

Client sends a wrong token (typo, rotated token, etc.).

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: serverHello
    Client->>TheInsideJob: clientHello
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"wrong")
    Note right of TheInsideJob: token doesn't match
    TheInsideJob->>Client: error(authFailure)
    Note left of Client: explicit token: retry with configured token<br/>auto-generated token: retry without token for UI approval
    Note right of TheInsideJob: → disconnect after 100ms
    TheInsideJob--xClient: TCP closed
```

## Wire Format

Auth messages use the standard newline-delimited JSON format wrapped in envelopes. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for full details.

### Server → Client (ResponseEnvelope)

```json
{"buttonHeistVersion":"<semver>","requestId":null,"type":"serverHello"}
{"buttonHeistVersion":"<semver>","requestId":null,"type":"authRequired"}
{"buttonHeistVersion":"<semver>","requestId":null,"type":"authApprovalPending","payload":{"message":"Waiting for approval on the device.","hint":"Tap Allow on the iOS device to continue."}}
{"buttonHeistVersion":"<semver>","requestId":null,"type":"authApproved","payload":{"token":"A1B2C3D4-E5F6-..."}}
{"buttonHeistVersion":"<semver>","requestId":null,"type":"error","payload":{"kind":"authFailure","message":"Invalid token. Retry with the configured token."}}
{"buttonHeistVersion":"<semver>","requestId":null,"type":"error","payload":{"kind":"authApprovalPending","message":"Approval timed out — user did not respond to the approval prompt on the device."}}
```

### Client → Server (RequestEnvelope)

```json
{"buttonHeistVersion":"<semver>","requestId":null,"type":"clientHello"}
{"buttonHeistVersion":"<semver>","requestId":"req-1","type":"authenticate","payload":{"token":"my-secret-token"}}
{"buttonHeistVersion":"<semver>","requestId":"req-2","type":"authenticate","payload":{"token":""}}
```

An empty token string in `authenticate` requests UI approval when the server token was auto-generated. A non-empty token attempts direct authentication.

## Security Limits

These limits are enforced by `SimpleSocketServer` and apply to both authenticated and unauthenticated connections:

| Limit | Value | Notes |
|-------|-------|-------|
| Max connections | 5 | Additional connections are rejected |
| Rate limit | 30 msg/sec | Per-client, sliding 1-second window |
| Receive buffer | 10 MB | Per-client; exceeded → disconnect |
| Auth failure delay | 100 ms | Allows the terminal auth error to arrive before TCP close |
| TLS listener | Required | Production listener startup fails closed if TLS identity/parameters are unavailable |
| Bind address (simulator-only scope) | `::1` (loopback) | Automatic when `allowedScopes == [.simulator]` |
| Bind address (USB or network scope) | `::` (all interfaces) | Required for CoreDevice USB; scope filtering rejects disallowed sources before auth |
| Bonjour advertisement | Network scope only | Default `simulator,usb` scope is not LAN-visible via Bonjour |

## Threat Model

Button Heist is a debug-only development tool. By default it accepts simulator loopback and CoreDevice USB traffic, does not advertise Bonjour on the LAN, and rejects WiFi/LAN connections before authentication. Enabling `INSIDEJOB_SCOPE=network` is an explicit trust decision that makes the listener discoverable and reachable from the local network.

### Bonjour Fingerprint Exposure

When network scope is enabled, the TLS certificate SHA-256 fingerprint is published in a plaintext Bonjour TXT record (`TXTRecordKey.certFingerprint` in `Messages.swift`, published via `ServerTransport.swift`). Any device on the LAN can read it. This is by design — clients need the fingerprint for trust-on-first-discovery pinning.

**Risk**: A LAN-local attacker can read the fingerprint. However, SHA-256 is collision-resistant, so knowledge of the fingerprint does not enable certificate forgery. The fingerprint is a verifier, not a secret.

**Mitigation**: Keep the default `simulator,usb` scope when LAN visibility is a concern. Use loopback or USB/direct targets instead of enabling network scope.

### Loopback TLS Bypass

When connecting to loopback (simulator-to-same-Mac path) without a fingerprint, TLS certificate verification is skipped (`DeviceConnection.swift` `makeLoopbackTLSParameters`). The connection still uses TLS encryption, but any certificate is accepted.

**Risk**: Any process on the same host can MITM the loopback connection.

**Mitigation**: This path is simulator-only. The simulator and client run on the same machine where process isolation is the trust boundary. The bypass is logged at `.warning` level. Non-loopback USB/WiFi connections require an explicit fingerprint and fail closed without one.

### Token as Coordination, Not Security

The session token prevents agent collisions, not unauthorized access. It is logged with `.public` privacy so that agents can self-diagnose auth mismatches by reading logs. The token appears in:

- Console logs at server startup
- `authApproved` wire messages (sent to the connecting client)
- Environment variables (`INSIDEJOB_TOKEN`, `BUTTONHEIST_TOKEN`)

The stronger access controls are TLS trust plus the `ConnectionScope` filter that restricts which network interfaces can connect (simulator, USB, or network). By default, only simulator and USB connections are accepted, and Bonjour is not published.

## Component Responsibilities

| Component | Role |
|-----------|------|
| **TheMuscle** | Token resolution, validation, UI approval, and session locking. Presents `UIAlertController` for Allow/Deny approval. Owns `authToken`, `pendingApprovalClients`, and authenticated client/session state. |
| **SimpleSocketServer** | Owns TCP/TLS framing, rate limiting, send buffers, and connection lifecycle. It emits raw framed data and does not own auth state. |
| **TheInsideJob** | Wires TheMuscle delivery callbacks to the socket server. Owns the server lifecycle. |
| **DeviceConnection** | Client-side handshake and auth handling. Verifies `buttonHeistVersion`, sends `clientHello` after `serverHello`, sends token on `authRequired`, stores token from `authApproved`, and emits the connected event only after receiving `info` (post-auth). |
| **TheHandoff** | Passes `token` to DeviceConnection. Stores approved tokens via `onAuthApproved` callback. Tracks `connectionPhase` including auth failures, approval-pending failures, and session-lock failures via `ConnectionError`. |

## TLS Certificate Lifecycle

```mermaid
sequenceDiagram
    participant TLS as TLSIdentity
    participant ST as ServerTransport
    participant NS as NetService (Bonjour)
    participant DD as DeviceDiscovery
    participant DC as DeviceConnection

    Note over TLS: getOrCreate() at startup
    TLS->>TLS: generateCertificate()<br>ECDSA P-256 key pair + self-signed cert
    TLS->>TLS: computeFingerprint(derBytes)<br>SHA-256 hash → "sha256:..."

    TLS->>ST: init(tlsIdentity:)
    ST->>ST: tlsIdentity.makeTLSParameters()<br>→ NWParameters with NWProtocolTLS

    ST->>NS: advertise(serviceName:)
    Note over NS: TXT record includes<br>certfp = "sha256:..."<br>transport = "tls"

    DD->>NS: NWBrowser discovers service
    NS-->>DD: TXT record with certfp
    DD->>DD: Extract certFingerprint<br>→ DiscoveredDevice

    DC->>DC: init(device:) stores<br>expectedFingerprint from device.certFingerprint
    DC->>DC: makeTLSParameters(expectedFingerprint:)<br>→ sec_protocol_options_set_verify_block

    DC->>ST: TLS handshake
    Note over DC,ST: verify_block: SHA-256(leaf cert)<br>== expectedFingerprint?
    ST-->>DC: Handshake complete (match)
```

## Related Documentation

- [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) — Full message specification
- [API.md](API.md) — Configuration keys and public API
- [ARCHITECTURE.md](ARCHITECTURE.md) — Component overview and TheMuscle details
