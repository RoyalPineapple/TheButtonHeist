# ButtonHeist Authentication

Every TCP connection must authenticate before it can send commands. This document describes how authentication works end-to-end.

## Overview

Authentication is mandatory for driver connections. When a client connects, the server sends an `authRequired` challenge. The client must respond with either `authenticate` (for drivers) or `watch` (for observers). Any other message before authenticating causes immediate disconnection.

There are three connection modes:

1. **Token auth** — The client sends a known token via `authenticate`. If it matches, the client is authenticated as a driver.
2. **UI approval** — The client sends an empty token via `authenticate`. If the server is in UI approval mode, an on-device prompt asks the user to Allow or Deny the connection. On Allow, the server sends the token back so the client can reuse it.
3. **Watch (observer)** — The client sends `watch` instead of `authenticate`. By default, observers are auto-approved without a token. Observers receive all broadcasts but cannot send commands or claim a session. See [Watch (Observer) Connections](#watch-observer-connections) below.

## Token Resolution

The server resolves its auth token at startup using this priority:

```mermaid
flowchart TD
    Start["Server starts"] --> Check1{"Explicit token set?"}
    Check1 -->|"INSIDEJOB_TOKEN env var<br/>or InsideJobToken plist key"| Explicit["Use explicit token"]
    Check1 -->|No| Generate["Generate fresh UUID<br/>(ephemeral, not persisted)"]
```

When no explicit token is set, a fresh UUID is generated each launch. Previously approved clients must re-authenticate after an app restart.

### Token Invalidation

Call `invalidateToken()` on TheMuscle to rotate the token. This generates a new UUID in memory. All previously approved clients lose access and must re-authenticate on their next connection.

## Configuration

### Server-side (iOS app)

| Method | Key | Example |
|--------|-----|---------|
| Environment variable | `INSIDEJOB_TOKEN` | `INSIDEJOB_TOKEN=my-secret-token` |
| Info.plist | `InsideJobToken` | `<string>my-secret-token</string>` |
| Auto-generated | (none) | Token logged to console at startup |

When no explicit token is configured, the token is logged to the console:
```
[TheInsideJob] Auth token: A1B2C3D4-E5F6-...
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
    TheInsideJob->>Client: authRequired
    Note right of TheInsideJob: TheMuscle.sendAuthRequired
    Client->>TheInsideJob: authenticate(token)
    Note right of TheInsideJob: TheMuscle.handleUnauthenticatedMessage<br/>token matches → markAuthenticated
    TheInsideJob->>Client: info
    Note right of TheInsideJob: handleClientConnected → sendServerInfo
    Client->>TheInsideJob: subscribe / requestInterface
    Note over Client,TheInsideJob: Client is now fully connected
```

### UI Approval — Allowed

Client has no token. Server is in UI approval mode (auto-generated token).

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"")
    Note right of TheInsideJob: token is empty<br/>→ store in pendingApprovalClients<br/>→ show UIAlertController

    rect rgb(240, 240, 240)
        Note right of TheInsideJob: Connection Request<br/>Connection #N is requesting access.<br/>[Deny] [Allow]
    end

    Note right of TheInsideJob: User taps Allow
    TheInsideJob->>Client: authApproved(token)
    Note left of Client: Client stores token for reuse
    Note right of TheInsideJob: TheMuscle.approveClient<br/>→ markAuthenticated
    TheInsideJob->>Client: info
    Note right of TheInsideJob: handleClientConnected → sendServerInfo
    Client->>TheInsideJob: subscribe / requestInterface
```

The `authApproved` message includes the server's token. The client stores it and sends it on future connections, skipping the UI prompt.

### UI Approval — Denied

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"")
    Note right of TheInsideJob: → show UIAlertController
    Note right of TheInsideJob: User taps Deny
    TheInsideJob->>Client: authFailed
    Note left of Client: "Connection denied by user"
    Note right of TheInsideJob: → disconnect after 100ms
    TheInsideJob--xClient: TCP closed
```

### Invalid Token

Client sends a wrong token (typo, rotated token, etc.).

```mermaid
sequenceDiagram
    participant Client
    participant TheInsideJob as TheInsideJob (iOS)

    Client->>TheInsideJob: TCP Connect
    TheInsideJob->>Client: authRequired
    Client->>TheInsideJob: authenticate(token:"wrong")
    Note right of TheInsideJob: token doesn't match
    TheInsideJob->>Client: authFailed
    Note left of Client: "Invalid token. Retry without<br/>a token to request a fresh session."
    Note right of TheInsideJob: → disconnect after 100ms
    TheInsideJob--xClient: TCP closed
```

## Wire Format

Auth messages use the standard newline-delimited JSON format wrapped in envelopes. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for full details.

### Server → Client (ResponseEnvelope)

```json
{"requestId":null,"message":{"authRequired":{}}}
{"requestId":null,"message":{"authApproved":{"_0":{"token":"A1B2C3D4-E5F6-..."}}}}
{"requestId":null,"message":{"authFailed":{"_0":"Invalid token. Retry without a token to request a fresh session."}}}
```

### Client → Server (RequestEnvelope)

```json
{"requestId":"req-1","message":{"authenticate":{"_0":{"token":"my-secret-token"}}}}
{"requestId":"req-2","message":{"authenticate":{"_0":{"token":""}}}}
{"requestId":null,"message":{"watch":{"_0":{"token":""}}}}
```

An empty token string in `authenticate` requests UI approval. A non-empty token attempts direct authentication. The `watch` message establishes a read-only observer connection.

## Watch (Observer) Connections

Watch connections use a separate auth flow from driver connections. Instead of `authenticate`, the client sends `watch` in response to `authRequired`.

### Default (Open Access)

By default, watch connections are auto-approved without requiring a token:

```mermaid
sequenceDiagram
    participant Observer
    participant TheInsideJob as TheInsideJob (iOS)

    Observer->>TheInsideJob: TCP Connect
    TheInsideJob->>Observer: authRequired
    Observer->>TheInsideJob: watch(token:"")
    Note right of TheInsideJob: TheMuscle auto-approves observer
    TheInsideJob->>Observer: info
    Note over Observer: Auto-subscribed to broadcasts
    TheInsideJob-->>Observer: interface, screen, interaction
```

### Restricted (Token Required)

Set `INSIDEJOB_RESTRICT_WATCHERS=1` (env) or `InsideJobRestrictWatchers=true` (Info.plist) on the server to require a valid token for watch connections:

```mermaid
sequenceDiagram
    participant Observer
    participant TheInsideJob as TheInsideJob (iOS)

    Observer->>TheInsideJob: TCP Connect
    TheInsideJob->>Observer: authRequired
    Observer->>TheInsideJob: watch(token:"valid-token")
    Note right of TheInsideJob: TheMuscle validates token
    TheInsideJob->>Observer: info
    Note over Observer: Auto-subscribed to broadcasts
```

### Key Differences from Driver Auth

| Aspect | Driver (`authenticate`) | Observer (`watch`) |
|--------|------------------------|-------------------|
| Session lock | Claims exclusive session | No session lock |
| Commands | Full command set | Read-only (no commands) |
| Default auth | Token required | Auto-approved |
| Restricted auth | N/A | `INSIDEJOB_RESTRICT_WATCHERS=1` / `InsideJobRestrictWatchers` plist |
| UI approval | Supported (empty token) | Not supported |
| Broadcasts | When subscribed | Always (auto-subscribed) |

### Configuration

| Method | Key | Example |
|--------|-----|---------|
| Environment variable (server) | `INSIDEJOB_RESTRICT_WATCHERS` | `INSIDEJOB_RESTRICT_WATCHERS=1` (require token) |
| Info.plist key (server) | `InsideJobRestrictWatchers` | `true` (require token) |
| CLI flag (client) | `--token` | `buttonheist watch --token my-secret-token` |

## Security Limits

These limits are enforced by `SimpleSocketServer` and apply to both authenticated and unauthenticated connections:

| Limit | Value | Notes |
|-------|-------|-------|
| Max connections | 5 | Additional connections are rejected |
| Rate limit | 30 msg/sec | Per-client, sliding 1-second window |
| Receive buffer | 10 MB | Per-client; exceeded → disconnect |
| Auth failure delay | 100 ms | Allows `authFailed` to arrive before TCP close |
| Bind address (simulator) | `::1` (loopback) | Controlled by `bindToLoopback` parameter |
| Bind address (device) | `::` (all interfaces) | Accepts WiFi and USB connections |

## Component Responsibilities

| Component | Role |
|-----------|------|
| **TheMuscle** | Token resolution, validation, UI approval, session locking, observer management, `invalidateToken()`. Presents `UIAlertController` for Allow/Deny approval. Owns `authToken`, `pendingApprovalClients`, `authenticatedClientIDs`, `observerClients`. Routes `watch` messages via `handleWatchRequest`. |
| **SimpleSocketServer** | Tracks `authenticatedClients` set. Routes messages to `onDataReceived` (authenticated) or `onUnauthenticatedData` (not yet authenticated). |
| **TheInsideJob** | Wires TheMuscle callbacks to the socket server. Owns the server lifecycle. |
| **DeviceConnection** | Client-side auth handling. Sends token on `authRequired`, stores token from `authApproved`, fires `onConnected` only after receiving `info` (post-auth). |
| **TheMastermind** | Passes `token` to DeviceConnection. Stores approved tokens via `onAuthApproved` callback. |

## Related Documentation

- [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) — Full message specification
- [API.md](API.md) — Configuration keys and public API
- [ARCHITECTURE.md](ARCHITECTURE.md) — Component overview and TheMuscle details
