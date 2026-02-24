# ButtonHeist Authentication

Every TCP connection must authenticate before it can send commands. This document describes how authentication works end-to-end.

## Overview

Authentication is mandatory. When a client connects, the server sends an `authRequired` challenge. The client must respond with an `authenticate` message containing a valid token. Any other message before authenticating causes immediate disconnection.

There are two authentication modes:

1. **Token auth** — The client sends a known token. If it matches, the client is authenticated.
2. **UI approval** — The client sends an empty token. If the server is in UI approval mode, an on-device prompt asks the user to Allow or Deny the connection. On Allow, the server sends the token back so the client can reuse it.

## Token Resolution

The server resolves its auth token at startup using this priority:

```
1. Explicit token
   └─ INSIDEMAN_TOKEN env var, or InsideManToken Info.plist key
   └─ requiresUIApproval = false

2. Persisted token (UserDefaults)
   └─ Key: "InsideManAuthToken"
   └─ Survives app relaunches — same token until invalidated
   └─ requiresUIApproval = true

3. Generated token (first launch)
   └─ UUID().uuidString → stored in UserDefaults for step 2 on next launch
   └─ requiresUIApproval = true
```

When an explicit token is set, it is used directly and UserDefaults is not touched. When no explicit token is set, the auto-generated token persists across app relaunches so previously approved clients retain access.

### Token Invalidation

Call `invalidateToken()` on TheMuscle to rotate the token. This generates a new UUID, stores it in UserDefaults, and invalidates all previously approved clients. They must re-authenticate on their next connection.

## Configuration

### Server-side (iOS app)

| Method | Key | Example |
|--------|-----|---------|
| Environment variable | `INSIDEMAN_TOKEN` | `INSIDEMAN_TOKEN=my-secret-token` |
| Info.plist | `InsideManToken` | `<string>my-secret-token</string>` |
| Auto-generated | (none) | Token logged to console at startup |

When no explicit token is configured, the token is logged to the console:
```
[InsideMan] Auth token: A1B2C3D4-E5F6-...
```

### Client-side (macOS / CLI)

| Method | Key | Example |
|--------|-----|---------|
| CLI flag | `--token` | `buttonheist watch --once --token my-secret-token` |
| Environment variable | `BUTTONHEIST_TOKEN` | `export BUTTONHEIST_TOKEN=my-secret-token` |
| UI approval | (omit token) | Client sends empty token; user approves on device |

Priority: `--token` flag > `BUTTONHEIST_TOKEN` env var > empty string (UI approval).

When a client is approved via UI, the server sends the token in the `authApproved` message. The CLI prints it:
```
Set BUTTONHEIST_TOKEN=<token> for future connections
```

## Connection Flows

### Standard Token Auth

Client has the correct token (explicit or previously received via UI approval).

```
Client                                    InsideMan (iOS)
   │                                         │
   │──────── TCP Connect ────────────────────►│
   │                                         │
   │◄─────── authRequired ──────────────────│  TheMuscle.sendAuthRequired
   │                                         │
   │──────── authenticate(token) ───────────►│  TheMuscle.handleUnauthenticatedMessage
   │                                         │    token matches → markAuthenticated
   │                                         │
   │◄─────── info ──────────────────────────│  handleClientConnected → sendServerInfo
   │                                         │
   │──────── subscribe / requestInterface ──►│  (client is now fully connected)
   │                                         │
```

### UI Approval — Allowed

Client has no token. Server is in UI approval mode (auto-generated token).

```
Client                                    InsideMan (iOS)
   │                                         │
   │──────── TCP Connect ────────────────────►│
   │                                         │
   │◄─────── authRequired ──────────────────│
   │                                         │
   │──────── authenticate(token:"") ────────►│  token is empty + requiresUIApproval
   │                                         │    → store in pendingApprovalClients
   │                                         │    → show UIAlertController
   │                                         │
   │                              ┌──────────┤
   │                              │ "Connection Request"
   │                              │ Connection #N is
   │                              │ requesting access.
   │                              │ [Deny]  [Allow]
   │                              └──────────┤
   │                                         │
   │                              [User taps Allow]
   │                                         │
   │◄─────── authApproved(token) ───────────│  TheMuscle.approveClient
   │   (client stores token for reuse)       │    → markAuthenticated
   │                                         │
   │◄─────── info ──────────────────────────│  handleClientConnected → sendServerInfo
   │                                         │
   │──────── subscribe / requestInterface ──►│
   │                                         │
```

The `authApproved` message includes the server's token. The client stores it and sends it on future connections, skipping the UI prompt.

### UI Approval — Denied

```
Client                                    InsideMan (iOS)
   │                                         │
   │──────── TCP Connect ────────────────────►│
   │◄─────── authRequired ──────────────────│
   │──────── authenticate(token:"") ────────►│  → show UIAlertController
   │                                         │
   │                              [User taps Deny]
   │                                         │
   │◄─────── authFailed ───────────────────│  "Connection denied by user"
   │                                         │    → disconnect after 100ms
   │◄─────── [TCP closed] ─────────────────│
   │                                         │
```

### Invalid Token

Client sends a wrong token (typo, rotated token, etc.).

```
Client                                    InsideMan (iOS)
   │                                         │
   │──────── TCP Connect ────────────────────►│
   │◄─────── authRequired ──────────────────│
   │──────── authenticate(token:"wrong") ───►│  token doesn't match
   │                                         │
   │◄─────── authFailed ───────────────────│  "Invalid token"
   │                                         │    → disconnect after 100ms
   │◄─────── [TCP closed] ─────────────────│
   │                                         │
```

## Wire Format

Auth messages use the standard newline-delimited JSON format. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for full details.

### Server → Client

```json
{"authRequired":{}}
{"authApproved":{"_0":{"token":"A1B2C3D4-E5F6-..."}}}
{"authFailed":{"_0":"Invalid token"}}
```

### Client → Server

```json
{"authenticate":{"_0":{"token":"my-secret-token"}}}
{"authenticate":{"_0":{"token":""}}}
```

An empty token string requests UI approval. A non-empty token attempts direct authentication.

## Bonjour Token Hash

The server publishes a SHA256 hash prefix of its token in the Bonjour TXT record:

```
tokenhash = SHA256(token).prefix(8 bytes).hexEncoded   // 16 hex chars
```

Clients can use this to identify the correct server instance before connecting — useful when multiple apps are running. The hash prevents exposing the actual token over mDNS.

## Security Limits

These limits are enforced by `SimpleSocketServer` and apply to both authenticated and unauthenticated connections:

| Limit | Value | Notes |
|-------|-------|-------|
| Max connections | 5 | Additional connections are rejected |
| Rate limit | 30 msg/sec | Per-client, sliding 1-second window |
| Receive buffer | 10 MB | Per-client; exceeded → disconnect |
| Auth failure delay | 100 ms | Allows `authFailed` to arrive before TCP close |
| Bind address (simulator) | `::1` (loopback) | Override with `INSIDEMAN_BIND_ALL=true` |
| Bind address (device) | `::` (all interfaces) | Accepts WiFi and USB connections |

## Component Responsibilities

| Component | Role |
|-----------|------|
| **TheMuscle** | Token resolution, persistence (UserDefaults), validation, UI approval state, `invalidateToken()`. Presents `UIAlertController` for Allow/Deny approval. Owns `authToken`, `requiresUIApproval`, `pendingApprovalClients`, `authenticatedClientIDs`. |
| **SimpleSocketServer** | Tracks `authenticatedClients` set. Routes messages to `onDataReceived` (authenticated) or `onUnauthenticatedData` (not yet authenticated). |
| **InsideMan** | Wires TheMuscle callbacks to the socket server. Owns the server lifecycle. |
| **DeviceConnection** | Client-side auth handling. Sends token on `authRequired`, stores token from `authApproved`, fires `onConnected` only after receiving `info` (post-auth). |
| **HeistClient** | Passes `token` to DeviceConnection. Stores approved tokens via `onTokenReceived` callback. |

## Related Documentation

- [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) — Full message specification
- [API.md](API.md) — Configuration keys and public API
- [ARCHITECTURE.md](ARCHITECTURE.md) — Component overview and TheMuscle details
