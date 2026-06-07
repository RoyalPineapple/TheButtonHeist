# Button Heist Wire Protocol

This document describes the raw TheScore transport between Button Heist clients
and the iOS host. It is not the CLI, MCP, or heist command catalog.

Use generated references for product command surfaces:

- [Command Reference](reference/commands.md)
- [MCP Tool Reference](reference/mcp-tools.md)

## Versioning

There is no separate wire-protocol version. Both sides carry
`buttonHeistVersion` in envelopes and compare it for exact equality during the
hello handshake. Any mismatch returns `protocolMismatch` and closes the
connection. Wire-format changes ship with a product version bump.

## Command Layers

Button Heist has one product command contract: `TheFence.Command`. CLI,
session JSON, MCP tools, and heist execution adapt to command names
such as `get_interface`, `activate`, and `scroll_to_visible`.

The wire protocol is lower-level transport. Its `type` values are TheScore
message discriminators such as `requestInterface`, `activate`, `requestScreen`,
and `scrollToVisible`. Use Fence command names at public adapter boundaries and
wire discriminators only when speaking raw TCP.

## Transport

- TLS over TCP using Network.framework
- Newline-delimited UTF-8 JSON
- Service type `_buttonheist._tcp`
- OS-assigned port by default
- IPv6 dual-stack listener
- TLS with token-derived pre-shared key material

Default connection scope is `simulator,usb`. Bonjour/LAN discovery is opt-in
with `network` scope.

Clients must provide the same token as the server before connecting. The token
derives the TLS pre-shared key and is also sent in the JSON `authenticate`
payload after the hello handshake.

## Discovery

### Bonjour

Bonjour is published only when `INSIDEJOB_SCOPE` includes `network`.

TXT metadata includes app/device identity and transport mode:

```text
simudid=<simulator UDID when available>
installationid=<stable app installation identifier>
instanceid=<human-readable instance id>
devicename=<device name>
transport=tls-psk
```

The token is not advertised over Bonjour. mDNS itself does not provide
integrity protection.

### USB

USB uses the CoreDevice IPv6 tunnel. It is classified as `usb` scope and uses
the same TLS wire protocol as other non-loopback transports.

## Handshake

```mermaid
sequenceDiagram
    participant Client
    participant Server

    Client->>Server: TLS handshake
    Server-->>Client: serverHello
    Client->>Server: clientHello

    alt Version mismatch
        Server-->>Client: protocolMismatch
        Server--xClient: close
    else Reachability probe
        Server-->>Client: authRequired
        Client->>Server: status
        Server-->>Client: status
        Client->>Server: close
    else Driver connection
        Server-->>Client: authRequired
        Client->>Server: authenticate
        alt Success
            Server-->>Client: info
        else Failure
            Server-->>Client: error / sessionLocked
            Server--xClient: close
        end
    end
```

`status` is the only post-hello message allowed before authentication. It
reports identity and session availability without claiming a driver session.

## Envelopes

Every message is a JSON object terminated by `\n`.

Client request:

```json
{"buttonHeistVersion":"<semver>","requestId":"abc-123","type":"requestInterface","payload":{}}
```

Server response:

```json
{"buttonHeistVersion":"<semver>","requestId":"abc-123","type":"interface","payload":{"timestamp":"2026-02-03T10:30:45.123Z","tree":[],"annotations":{"elements":[],"containers":[]}}}
```

| Field | Description |
|-------|-------------|
| `buttonHeistVersion` | Product SemVer. Must match exactly across client and server. |
| `requestId` | Optional correlation id. Echoed by the matching response. |
| `type` | Explicit TheScore message discriminator. |
| `payload` | Optional payload object. |

## Public Wire Examples

These examples show edge contracts that raw clients may need. Command and
parameter inventories belong in the generated references.

### Hello

```json
{"buttonHeistVersion":"<semver>","type":"serverHello"}
{"buttonHeistVersion":"<semver>","type":"clientHello"}
{"buttonHeistVersion":"<semver>","type":"authRequired"}
```

### Authentication

```json
{"buttonHeistVersion":"<semver>","type":"authenticate","payload":{"token":"your-secret-token","driverId":"agent-1"}}
```

`driverId` is optional. When present, it is the session-locking identity. When
absent, the token is used as the driver identity.

### Unsupported Legacy Auth Messages

`authApprovalPending` and `authApproved` are not valid current server messages.
Current clients reject either tag as an unsupported auth response and instruct the
user to rebuild or reinstall the app, then retry with the configured token.
Clients without a token fail before starting the TLS connection.

### Protocol Mismatch

```json
{"buttonHeistVersion":"<server-semver>","type":"protocolMismatch","payload":{"serverButtonHeistVersion":"<server-semver>","clientButtonHeistVersion":"<client-semver>"}}
```

### Session Locked

```json
{"buttonHeistVersion":"<semver>","type":"sessionLocked","payload":{"message":"Session is locked by another driver","activeConnections":1}}
```

### Status Probe

```json
{"buttonHeistVersion":"<semver>","type":"status"}
```

```json
{"buttonHeistVersion":"<semver>","type":"status","payload":{"identity":{"appName":"MyApp","bundleIdentifier":"com.example.myapp","appBuild":"42","deviceName":"iPhone 15 Pro","systemVersion":"18.0","buttonHeistVersion":"<semver>"},"session":{"active":false,"watchersAllowed":false,"activeConnections":0}}}
```

### Interface

```json
{"buttonHeistVersion":"<semver>","type":"requestInterface","payload":{}}
```

The interface payload carries the canonical hierarchy tree plus Button Heist
annotations. There is no parallel wire `elements` array in the public wire
contract.

```json
{
  "buttonHeistVersion": "<semver>",
  "type": "interface",
  "payload": {
    "screenDescription": "Sign In - 1 text field, 1 button",
    "timestamp": "2026-02-03T10:30:45.123Z",
    "tree": [
      {
        "element": {
          "heistId": "button_sign_in",
          "label": "Sign In",
          "identifier": "signInButton",
          "traits": ["button"],
          "frameX": 16,
          "frameY": 140,
          "frameWidth": 361,
          "frameHeight": 44,
          "activationPointX": 196.5,
          "activationPointY": 162
        }
      }
    ],
    "annotations": {
      "elements": [],
      "containers": []
    }
  }
}
```

`heistId` is a current-capture annotation for correlation and diagnostics.
Public action messages identify elements with `ElementTarget` predicate fields
such as `label`, `identifier`, `value`, `traits`, `excludeTraits`, and optional
`ordinal`. Durable replay uses the same semantic target shape.

### Semantic Action

```json
{"buttonHeistVersion":"<semver>","requestId":"act-1","type":"activate","payload":{"label":"Sign In","traits":["button"]}}
```

Semantic action messages identify elements semantically. The host resolves the
target against current state, moves the viewport if needed, refreshes, acquires
fresh live geometry, and then dispatches. Cached coordinates from a prior
capture are not the authority.

Explicit viewport messages such as `scroll`, `scrollToEdge`, and
`scrollToVisible` expose viewport state because moving the viewport is the
requested behavior. They are direct viewport/debug commands, not durable heist
primitives.

### Screen Capture

```json
{"buttonHeistVersion":"<semver>","type":"requestScreen"}
```

The raw wire response carries base64 PNG data plus a fresh visible interface.
Public CLI/MCP adapters return artifact paths by default and include inline
media only through explicit, size-bounded opt-ins.

### Wait

```json
{"buttonHeistVersion":"<semver>","type":"wait","payload":{"predicate":{"type":"screen_changed"},"timeout":30}}
```

The host evaluates the predicate against the current settled accessibility
state first, then waits for later settled accessibility state until the
predicate is true or the timeout expires. Absence predicates are satisfied by
current absence.

## Action Results

Action responses use `actionResult`:

```json
{"buttonHeistVersion":"<semver>","type":"actionResult","payload":{"success":true,"method":"activate"}}
```

`ActionResult.payload` is a tagged union when command-specific data is needed,
for example:

```json
{"kind":"value","data":"Hello"}
```

Returned elements may include capture-local annotations. Compose follow-up
commands from their semantic fields, not from `heistId`.

Errors use typed `errorKind` on action results when the error belongs to the
action. Server-level failures use the `error` message with `kind` and
`message`.

## Traces and Deltas

The trace stores captures. Segments and deltas are derived projections used for
formatting, expectations, and diagnostics; they are not the authoritative
storage truth.

`AccessibilityTrace.Delta` is discriminated by `kind`:

| `kind` | Meaning |
|--------|---------|
| `noChange` | The settled hierarchy did not change. |
| `elementsChanged` | Same screen, element-level additions/removals/updates. |
| `screenChanged` | Screen identity changed; the post-change interface is included. |

Empty edit collections are omitted on the wire.

## Authentication and Sessions

Driver connections require authentication. A session is held by one driver
identity at a time:

1. First authenticated driver claims the session.
2. Same driver identity can reconnect or issue separate direct CLI commands.
3. Different driver identities receive `sessionLocked`.
4. When the last connection closes, the inactivity timer starts.
5. After timeout, the session is released.

The token is not invalidated when the session expires.

## Security Limits

- TLS is required for production listener startup.
- Default scope is `simulator,usb`; LAN exposure requires explicit `network`
  scope.
- Bonjour is published only in `network` scope.
- Non-loopback targets require explicit or persisted TLS trust.
- The server applies connection, rate, and receive-buffer limits.

## Keepalive and Recovery

Clients should send `ping` periodically and tolerate a few delayed responses
before declaring failure. App main-thread stalls can delay pong handling.

After reconnecting, clients should request fresh interface state before acting.

## Current Shape

The current wire shape is whatever the matching `buttonHeistVersion` ships.
Older clients are not supported. Clients should update in lockstep with the
server.
