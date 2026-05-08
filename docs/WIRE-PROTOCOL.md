# Button Heist Wire Protocol Specification

**Version**: 9.0

This document specifies the communication protocol between TheInsideJob (iOS) and clients (ButtonHeist framework, CLI, Python scripts).

## Transport

- **Layer**: TLS over TCP (Network.framework `NWProtocolTLS`)
- **Discovery**: Bonjour/mDNS (WiFi) or CoreDevice IPv6 tunnel (USB)
- **Service Type**: `_buttonheist._tcp`
- **Port**: OS-assigned (advertised via Bonjour)
- **Encoding**: Newline-delimited JSON (UTF-8)
- **Socket**: IPv6 dual-stack (accepts both IPv4 and IPv6)
- **Encryption**: TLS 1.2+ with self-signed ECDSA (P-256) certificates, verified via SHA-256 fingerprint pinning

## Discovery Methods

### WiFi (Bonjour)
TheInsideJob advertises itself using Bonjour:
- **Domain**: `local.`
- **Type**: `_buttonheist._tcp`
- **Name**: `{AppName}#{instanceId}` (instanceId from `INSIDEJOB_ID` env var, or first 8 chars of a per-launch UUID)
- **TXT Record**:
  - `simudid` — Simulator UDID (only present when running in iOS Simulator, from `SIMULATOR_UDID` env var)
  - `installationid` — Stable per-installation identifier for device discovery and filtering
  - `instanceid` — Human-readable instance identifier
  - `devicename` — Human-readable device name
  - `sessionactive` — `"1"` when an active session exists, `"0"` otherwise. Used by clients to show session state pre-connection.
  - `certfp` — TLS certificate SHA-256 fingerprint, format: `sha256:<64 hex chars>`
  - `transport` — `"tls"`

The TXT record enables pre-connection device identification. Clients can match devices by simulator UDID, instance ID, or session state without establishing a TCP connection first. The `certfp` field enables trust-on-first-discovery (TOFU): clients verify the server's TLS certificate against this fingerprint during the TLS handshake. TLS is required — clients must refuse connections to servers that do not advertise a `certfp`.

> **Security note**: The `certfp` value is delivered via mDNS, which provides no integrity protection. An attacker on the same network segment could spoof Bonjour responses with a different fingerprint. This is acceptable for a local development tool but does not provide the same guarantees as a PKI-based certificate chain. The fingerprint prevents passive eavesdropping and verifies the server identity hasn't changed between discovery and connection.

### USB (CoreDevice IPv6 Tunnel)
When connected via USB, macOS creates an IPv6 tunnel:
- **Device address**: `fd{prefix}::1` (e.g., `fd9a:6190:eed7::1`)
- **Port**: OS-assigned (same port as WiFi, advertised via Bonjour)
- **Discovery**: `lsof -i -P -n | grep CoreDev`

## Connection Lifecycle

```mermaid
sequenceDiagram
    participant Client
    participant Server

    Client->>Server: TLS Handshake (verify certfp from Bonjour TXT)
    Note over Client,Server: All subsequent messages encrypted
    Server-->>Client: serverHello

    alt Protocol mismatch
        Client-->>Server: clientHello
        Server-->>Client: protocolMismatch
        Server--xClient: TCP Close
    else Reachability probe
        Client->>Server: clientHello
        Server-->>Client: authRequired
        Client->>Server: status
        Server-->>Client: status(StatusPayload)
        Client->>Server: TCP Close
    else Driver connection
        Client->>Server: clientHello
        Server-->>Client: authRequired
        Client->>Server: authenticate(token)

        alt Success + session acquired
            Server-->>Client: info
        else Bad token
            Server-->>Client: authFailed → disconnect
        else Session held by another driver
            Server-->>Client: sessionLocked → disconnect
        end

        Client->>Server: subscribe (enable auto-updates)
        Client->>Server: requestInterface
        opt explicit screen capture
            Client->>Server: requestScreen
            Server-->>Client: screen
        end
        Server-->>Client: interface

        Client->>Server: activate / touchTap / touchDrag ...
        Server-->>Client: actionResult
    else Watch (observer) connection
        Client->>Server: clientHello
        Server-->>Client: authRequired
        Client->>Server: watch(token:"")
        Note over Server: Token-checked (default)<br>or auto-approved if INSIDEJOB_RESTRICT_WATCHERS=0
        Server-->>Client: info
        Note over Client: Auto-subscribed to broadcasts
    end

    Server-->>Client: interface (auto-pushed on change)
    Server-->>Client: interaction (broadcast after driver actions)

    Client->>Server: ping
    Server-->>Client: pong

    Client->>Server: TCP Close
```

## Message Format

All messages are JSON objects terminated by a newline (`\n`). Envelopes use an explicit `type` discriminator and optional `payload`, rather than relying on Swift enum synthesis. The `Interface` payload follows the same rule — its `tree` uses a discriminator-keyed shape (`{"element": {...}}` / `{"container": {...}}`) with explicit field names, never the synthesized `_0` form.

### Request/Response Envelopes

All messages are wrapped in envelope types for request-response correlation. Examples below omit `requestId` unless the correlation behavior is relevant.

**Client → Server** (`RequestEnvelope`):
```json
{"protocolVersion":"9.0","requestId":"abc-123","type":"activate","payload":{"identifier":"loginButton"}}
```

**Server → Client** (`ResponseEnvelope`):
```json
{"protocolVersion":"9.0","requestId":"abc-123","type":"actionResult","payload":{"success":true,"method":"syntheticTap"}}
```

When `requestId` is present, the server echoes it in the corresponding response so the client can match request-response pairs. Push broadcasts such as interface updates and interaction events have `requestId: null`. Screenshots are never broadcast; `screen` is only returned for explicit `requestScreen` requests.

| Field | Type | Description |
|-------|------|-------------|
| `protocolVersion` | `String` | Exact wire protocol version. Client and server must match exactly. |
| `requestId` | `String?` | Optional correlation ID; echoed in the response |
| `type` | `String` | Explicit message discriminator |
| `payload` | `Object / String / null` | Optional message payload |
| `backgroundDelta` | `InterfaceDelta?` | (Response only) Changes that occurred while the agent was thinking between requests. Present when the accessibility tree changed since the last response was sent. Nil when nothing changed. |

## Client → Server Messages

### clientHello

Version handshake sent immediately after `serverHello`.

```json
{"protocolVersion":"9.0","type":"clientHello"}
```

### authenticate

Authenticate with the server. Must be sent after a successful `clientHello` / `authRequired` handshake. Sending any other command before the handshake completes will result in immediate disconnection.

```json
{"protocolVersion":"9.0","type":"authenticate","payload":{"token":"your-secret-token"}}
```

**With driver identity:**
```json
{"protocolVersion":"9.0","type":"authenticate","payload":{"token":"your-secret-token","driverId":"agent-1"}}
```

The optional `driverId` field provides a unique driver identity for session locking — when set, it takes precedence over the token for distinguishing drivers. See [Session Locking](#session-locking) for details.

### requestInterface

Request current UI element interface. Returns only elements currently visible on screen.

```json
{"protocolVersion":"9.0","type":"requestInterface"}
```

### subscribe

Subscribe to automatic interface and interaction updates. Screenshots are never broadcast; request them explicitly with `requestScreen`.

```json
{"protocolVersion":"9.0","type":"subscribe"}
```

### unsubscribe

Unsubscribe from automatic updates.

```json
{"protocolVersion":"9.0","type":"unsubscribe"}
```

### activate

Activate an element (equivalent to VoiceOver double-tap). Uses the TouchInjector system with synthetic event fallback chain.

**By identifier:**
```json
{"protocolVersion":"9.0","type":"activate","payload":{"identifier":"loginButton"}}
```

**By matcher ordinal:**
```json
{"protocolVersion":"9.0","type":"activate","payload":{"label":"Save","traits":["button"],"ordinal":1}}
```

### touchTap

Tap at coordinates or on an element using synthetic touch injection via TheSafecracker.

**At coordinates:**
```json
{"protocolVersion":"9.0","type":"touchTap","payload":{"pointX":196.5,"pointY":659.0}}
```

**On element by identifier:**
```json
{"protocolVersion":"9.0","type":"touchTap","payload":{"elementTarget":{"identifier":"submitButton"}}}
```

### touchLongPress

Long press at coordinates or on an element.

```json
{"protocolVersion":"9.0","type":"touchLongPress","payload":{"pointX":100,"pointY":200,"duration":1.0}}
```

**On element (default 0.5s):**
```json
{"protocolVersion":"9.0","type":"touchLongPress","payload":{"elementTarget":{"identifier":"myButton"},"duration":0.5}}
```

### touchSwipe

Swipe between two points or in a direction from an element.

**With explicit coordinates:**
```json
{"protocolVersion":"9.0","type":"touchSwipe","payload":{"startX":200,"startY":400,"endX":200,"endY":100,"duration":0.15}}
```

**From element in direction:**
```json
{"protocolVersion":"9.0","type":"touchSwipe","payload":{"elementTarget":{"identifier":"list"},"direction":"up","distance":300}}
```

### touchDrag

Drag from one point to another (slower than swipe, for sliders/reordering).

**With explicit coordinates:**
```json
{"protocolVersion":"9.0","type":"touchDrag","payload":{"startX":100,"startY":200,"endX":300,"endY":200,"duration":0.5}}
```

**From element:**
```json
{"protocolVersion":"9.0","type":"touchDrag","payload":{"elementTarget":{"identifier":"slider"},"endX":300,"endY":200}}
```

### touchPinch

Pinch/zoom gesture centered at a point. Scale >1.0 zooms in, <1.0 zooms out.

```json
{"protocolVersion":"9.0","type":"touchPinch","payload":{"centerX":200,"centerY":300,"scale":2.0,"spread":100,"duration":0.5}}
```

**On element:**
```json
{"protocolVersion":"9.0","type":"touchPinch","payload":{"elementTarget":{"identifier":"mapView"},"scale":0.5}}
```

### touchRotate

Rotation gesture centered at a point. Angle in radians.

```json
{"protocolVersion":"9.0","type":"touchRotate","payload":{"centerX":200,"centerY":300,"angle":1.57,"radius":100,"duration":0.5}}
```

### touchTwoFingerTap

Two-finger tap at a point or element.

```json
{"protocolVersion":"9.0","type":"touchTwoFingerTap","payload":{"centerX":200,"centerY":300,"spread":40}}
```

### touchDrawPath

Draw along a path by tracing through a sequence of waypoints. Supports duration (seconds) or velocity (points/second) for timing.

```json
{"protocolVersion":"9.0","type":"touchDrawPath","payload":{"points":[{"x":100,"y":400},{"x":200,"y":300},{"x":300,"y":400}],"duration":1.0}}
```

**With velocity:**
```json
{"protocolVersion":"9.0","type":"touchDrawPath","payload":{"points":[{"x":100,"y":400},{"x":200,"y":300},{"x":300,"y":400}],"velocity":500}}
```

### touchDrawBezier

Draw along cubic bezier curves. The server samples the curves to a polyline, then traces using the drawPath engine.

```json
{"protocolVersion":"9.0","type":"touchDrawBezier","payload":{"startX":100,"startY":400,"segments":[{"cp1X":100,"cp1Y":200,"cp2X":300,"cp2Y":200,"endX":300,"endY":400}],"duration":1.0}}
```

**With samples and velocity:**
```json
{"protocolVersion":"9.0","type":"touchDrawBezier","payload":{"startX":100,"startY":400,"segments":[{"cp1X":100,"cp1Y":200,"cp2X":300,"cp2Y":200,"endX":300,"endY":400}],"samplesPerSegment":40,"velocity":300}}
```

### increment

Increment an adjustable element (e.g., slider, stepper). Calls `increment()` on the element's view.

**By identifier:**
```json
{"protocolVersion":"9.0","type":"increment","payload":{"identifier":"volumeSlider"}}
```

**By matcher ordinal:**
```json
{"protocolVersion":"9.0","type":"increment","payload":{"label":"Volume","traits":["adjustable"],"ordinal":0}}
```

### decrement

Decrement an adjustable element. Calls `decrement()` on the element's view.

**By identifier:**
```json
{"protocolVersion":"9.0","type":"decrement","payload":{"identifier":"volumeSlider"}}
```

### performCustomAction

Invoke a named custom action on an element. The action name must match one of the element's `actions`.

```json
{"protocolVersion":"9.0","type":"performCustomAction","payload":{"elementTarget":{"identifier":"myCell"},"actionName":"Delete"}}
```

### typeText

Type text character-by-character by injecting into the keyboard input system (via UIKeyboardImpl.sharedInstance), and/or delete characters. Returns the current text field value in the `actionResult`. Works in both software and hardware keyboard modes.

**Type text into a field (taps element to focus first):**
```json
{"protocolVersion":"9.0","type":"typeText","payload":{"text":"Hello","elementTarget":{"identifier":"nameField"}}}
```

**Delete 3 characters:**
```json
{"protocolVersion":"9.0","type":"typeText","payload":{"deleteCount":3,"elementTarget":{"identifier":"nameField"}}}
```

**Delete then retype (correction):**
```json
{"protocolVersion":"9.0","type":"typeText","payload":{"deleteCount":4,"text":"orld","elementTarget":{"identifier":"nameField"}}}
```

**Clear existing text then type new text:**
```json
{"protocolVersion":"9.0","type":"typeText","payload":{"clearFirst":true,"text":"replacement","elementTarget":{"identifier":"nameField"}}}
```

| Field | Type | Description |
|-------|------|-------------|
| `text` | `String?` | Text to type character-by-character |
| `deleteCount` | `Int?` | Number of delete key taps before typing |
| `clearFirst` | `Bool?` | Clear all existing text before typing (select-all + delete) |
| `elementTarget` | `ActionTarget?` | Element to tap for focus (also reads value back) |

### requestScreen

Request a PNG capture of the current screen.

```json
{"protocolVersion":"9.0","type":"requestScreen"}
```

### startRecording

Start recording the screen as H.264/MP4 video. Frames are captured at the configured FPS using `drawHierarchy` compositing (includes fingerprint overlays for taps and continuous gestures). Recording auto-stops when no screen changes and no real interactions (actions, touches, typing) are received for the inactivity timeout. Pings and keepalive messages do not reset the inactivity timer.

```json
{"protocolVersion":"9.0","type":"startRecording","payload":{"fps":8,"scale":0.5,"inactivityTimeout":5.0,"maxDuration":60.0}}
```

All fields are optional — defaults are applied server-side.

| Field | Type | Description |
|-------|------|-------------|
| `fps` | `Int?` | Frames per second (1-15, default: 8) |
| `scale` | `Double?` | Resolution scale of native pixels (0.25-1.0, default: 1x point size) |
| `inactivityTimeout` | `Double?` | Seconds of no activity before auto-stop (default: 5.0) |
| `maxDuration` | `Double?` | Maximum recording duration in seconds (default: 60.0) |

### stopRecording

Stop an active recording. The server finalizes the video and sends a `recording` message.

```json
{"protocolVersion":"9.0","type":"stopRecording"}
```

### scroll

Scroll the nearest scroll view ancestor of a target element by approximately one page in the given direction. Uses direct `setContentOffset` manipulation for UIScrollView, synthetic swipe for other scrollable containers.

**By identifier:**
```json
{"protocolVersion":"9.0","type":"scroll","payload":{"elementTarget":{"identifier":"buttonheist.longList.item-5"},"direction":"up"}}
```

**By matcher ordinal:**
```json
{"protocolVersion":"9.0","type":"scroll","payload":{"elementTarget":{"label":"Messages","ordinal":1},"direction":"down"}}
```

Directions: `"up"`, `"down"`, `"left"`, `"right"`, `"next"`, `"previous"`.

### scrollToVisible

Scroll a known registry element into view. This is a one-shot recorded-position jump for elements already discovered by `get_interface --full` or prior scrolling. For iterative discovery of an element that may not be in the registry yet, use `element_search`.

**Target fields:** `heistId`, or flat matcher fields `label`, `identifier`, `value`, `traits`, `excludeTraits`. Matcher fields are decoded at the payload root; there is no nested `match` object.

**By heistId:**
```json
{"protocolVersion":"9.0","type":"scrollToVisible","payload":{"heistId":"buttonheist.longList.colorPicker"}}
```

**By label:**
```json
{"protocolVersion":"9.0","type":"scrollToVisible","payload":{"label":"Color Picker"}}
```

**Compound matcher:**
```json
{"protocolVersion":"9.0","type":"scrollToVisible","payload":{"label":"Settings","traits":["header"]}}
```

**Response** is an `actionResult` with `method: "scrollToVisible"`:
```json
{"type":"actionResult","payload":{"success":true,"method":"scrollToVisible"}}
```

### elementSearch

Search for an element by scrolling through scroll views. Uses an `ElementTarget` predicate — all specified matcher fields must match (AND semantics). Returns a `ScrollSearchResult` with diagnostics. Walks the accessibility hierarchy tree (outermost first), scrolling each container until the target appears or all containers are exhausted.

**Target fields:** `heistId`, or flat matcher fields `label`, `identifier`, `value`, `traits`, `excludeTraits`.

**Search options:** `direction` (`"down"`, `"up"`, `"left"`, `"right"`, default: `"down"`).

**By label:**
```json
{"protocolVersion":"9.0","type":"elementSearch","payload":{"label":"Color Picker"}}
```

**Compound matcher with direction:**
```json
{"protocolVersion":"9.0","type":"elementSearch","payload":{"label":"Settings","traits":["header"],"direction":"up"}}
```

**Response** includes `scrollSearchResult` on the `actionResult`:
```json
{"type":"actionResult","payload":{"success":true,"method":"elementSearch","scrollSearchResult":{"scrollCount":3,"uniqueElementsSeen":25,"totalItems":80,"exhaustive":false,"foundElement":{...}}}}
```

### scrollToEdge

Scroll the nearest scroll view ancestor to an edge (top, bottom, left, right).

**By identifier:**
```json
{"protocolVersion":"9.0","type":"scrollToEdge","payload":{"elementTarget":{"identifier":"buttonheist.longList.item-0"},"edge":"bottom"}}
```

Edges: `"top"`, `"bottom"`, `"left"`, `"right"`.

### explore

Full screen element census. Scrolls every scrollable container to its limits and back, discovering all elements including off-screen content. Scroll positions are saved and restored — no visual change occurs.

No payload required.

```json
{"protocolVersion":"9.0","type":"explore"}
```

Returns an `actionResult` with `method: "explore"` and an `exploreResult` containing the complete element list, scroll count, containers explored, and exploration time.

> **Note**: `explore` is not exposed as a standalone CLI/MCP command. It is dispatched internally by `get_interface` when the `full` parameter is true. See [Element Discovery](#element-discovery) for usage guidance.

### editAction

Perform a standard edit action via the responder chain.

```json
{"protocolVersion":"9.0","type":"editAction","payload":{"action":"copy"}}
```

Valid actions: `"copy"`, `"paste"`, `"cut"`, `"select"`, `"selectAll"`.

### setPasteboard

Write text to the general pasteboard from within the app. Content written by the app itself does not trigger the iOS "Allow Paste" dialog when subsequently read.

```json
{"protocolVersion":"9.0","type":"setPasteboard","payload":{"text":"clipboard content"}}
```

| Field | Type | Description |
|-------|------|-------------|
| `text` | `String` | Text to write to the pasteboard (required) |

### getPasteboard

Read text from the general pasteboard.

```json
{"protocolVersion":"9.0","type":"getPasteboard"}
```

No payload. Returns an `actionResult` with `method: "getPasteboard"` and the pasteboard text in `value`.

### resignFirstResponder

Dismiss the keyboard by resigning first responder.

```json
{"protocolVersion":"9.0","type":"resignFirstResponder"}
```

### waitForChange

Wait for the UI to change in a way that matches an expectation. With no expectation, returns on any tree change. With `expect`, rides through intermediate states (e.g. spinners) until the expectation is met.

```json
{"protocolVersion":"9.0","type":"waitForChange","payload":{"expect":"screen_changed","timeout":10}}
```

| Field | Type | Description |
|-------|------|-------------|
| `expect` | `ActionExpectation?` | The change to wait for — `"screen_changed"`, `"elements_changed"`, or a JSON expectation object. When nil, any tree change satisfies. |
| `timeout` | `Double?` | Max wait time in seconds (default: 10, max: 30) |

Returns an `actionResult` with `method: "waitForChange"` and an `interfaceDelta` describing what changed. On timeout, returns `success: false` with `errorKind: "timeout"`.

**Fast path**: if the tree already changed since the last response (while the agent was thinking), returns immediately with the accumulated delta.

**Example flow**: `activate pay_now_button expect="screen_changed"` → delta shows spinner, expectation not met → `waitForChange expect="screen_changed" timeout=10` → receipt screen arrives, expectation met.

### waitFor

Wait for an element matching a predicate to appear (or disappear). Uses settle-event polling, not busy-waiting.

```json
{"protocolVersion":"9.0","type":"waitFor","payload":{"label":"Loading","absent":true,"timeout":5.0}}
```

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | Stable element identifier assigned by `get_interface` |
| `label` / `identifier` / `value` / `traits` / `excludeTraits` | matcher fields | Predicate describing the element to wait for, decoded flat at the payload root |
| `absent` | `Bool?` | When `true`, wait for element to NOT exist (default: `false`) |
| `timeout` | `Double?` | Max wait time in seconds (default: 10, max: 30) |

Returns an `actionResult` with `method: "waitFor"` and an `interfaceDelta` containing the settled interface.

### ping

Keepalive ping.

```json
{"protocolVersion":"9.0","type":"ping"}
```

### status

Lightweight status probe. Unlike normal driver commands, this message may be sent before authentication and does not claim a session. It is intended for reachability checks and identity discovery.

```json
{"protocolVersion":"9.0","type":"status"}
```

### watch

Connect as a read-only observer. Sent instead of `authenticate` after receiving `authRequired`. Observers receive interface and interaction broadcasts but cannot send commands or claim a session.

```json
{"protocolVersion":"9.0","type":"watch","payload":{"token":""}}
```

By default, watch connections require a valid token (same as drivers). Set `INSIDEJOB_RESTRICT_WATCHERS=0` to allow unauthenticated observers.

| Field | Type | Description |
|-------|------|-------------|
| `token` | `String` | Auth token (required by default; empty string allowed when `INSIDEJOB_RESTRICT_WATCHERS=0`) |

## Server → Client Messages

### serverHello

Sent immediately on connection. The client must verify `protocolVersion` and respond with `clientHello`.

```json
{"protocolVersion":"9.0","requestId":null,"type":"serverHello"}
```

### protocolMismatch

Sent when the peer's `protocolVersion` does not exactly match the server's current wire version. The server closes the connection immediately after sending this message.

```json
{"protocolVersion":"9.0","requestId":null,"type":"protocolMismatch","payload":{"expectedProtocolVersion":"9.0","receivedProtocolVersion":"8.0"}}
```

### authRequired

Sent after a successful hello/version handshake. Indicates the client must authenticate before any other interaction.

```json
{"protocolVersion":"9.0","requestId":null,"type":"authRequired"}
```

### authFailed

Sent when the client provides an invalid token or when a UI approval request is denied. The server disconnects shortly after.

```json
{"protocolVersion":"9.0","type":"authFailed","payload":"Invalid token"}
```

### authApproved

Sent when a connection is approved via the on-device UI (see [UI Approval Flow](#ui-approval-flow)). Contains the auth token for future reconnections.

```json
{"protocolVersion":"9.0","type":"authApproved","payload":{"token":"auto-generated-uuid-token"}}
```

After receiving `authApproved`, the client should store the token and use it for future `authenticate` messages to skip the approval flow.

### sessionLocked

Sent when the server's session is held by a different driver. The server disconnects the client shortly after sending this message. See [Session Locking](#session-locking).

```json
{"protocolVersion":"9.0","type":"sessionLocked","payload":{"message":"Session is locked by another driver","activeConnections":1}}
```

| Field | Type | Description |
|-------|------|-------------|
| `message` | `String` | Human-readable description of why the session is locked |
| `activeConnections` | `Int` | Number of active connections in the current session |

### info

Sent after successful authentication. Contains device and app metadata.

```json
{"protocolVersion":"9.0","type":"info","payload":{
  "appName":"MyApp",
  "bundleIdentifier":"com.example.myapp",
  "deviceName":"iPhone 15 Pro",
  "systemVersion":"17.0",
  "screenWidth":393.0,
  "screenHeight":852.0,
  "instanceId":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "instanceIdentifier":"my-instance",
  "listeningPort":52341,
  "simulatorUDID":"DEADBEEF-1234-5678-9ABC-DEF012345678",
  "vendorIdentifier":null,
  "tlsActive":true
}}
```

### status

Sent in response to a `status` probe. This response is valid before authentication and returns app identity plus session availability without claiming the session.

```json
{"protocolVersion":"9.0","type":"status","payload":{
  "identity":{
    "appName":"MyApp",
    "bundleIdentifier":"com.example.myapp",
    "appBuild":"42",
    "deviceName":"iPhone 15 Pro",
    "systemVersion":"18.0",
    "buttonHeistVersion":"0.0.1"
  },
  "session":{
    "active":false,
    "watchersAllowed":false,
    "activeConnections":0
  }
}}
```

### interface

UI element interface. Public JSON output uses a tree structure. Summary detail includes the semantic accessibility surface; full detail adds geometry.

```json
{"protocolVersion":"9.0","type":"interface","payload":{
  "screenDescription":"Welcome — 1 button",
  "timestamp":"2026-02-03T10:30:45.123Z",
  "tree":[
    {"element":{
      "heistId":"staticText_welcome",
      "label":"Welcome",
      "traits":["staticText"],
      "frameX":16.0,
      "frameY":100.0,
      "frameWidth":361.0,
      "frameHeight":24.0,
      "activationPointX":196.5,
      "activationPointY":112.0
    }},
    {"container":{
      "type":"semanticGroup",
      "label":"Form",
      "frameX":0.0,
      "frameY":88.0,
      "frameWidth":393.0,
      "frameHeight":600.0,
      "children":[{"element":{
        "heistId":"button_sign_in",
        "label":"Sign In",
        "identifier":"signInButton",
        "traits":["button"],
        "frameX":16.0,
        "frameY":140.0,
        "frameWidth":361.0,
        "frameHeight":44.0,
        "activationPointX":196.5,
        "activationPointY":162.0
      }}]
    }}
  ]
}}
```

The `tree` is the canonical wire shape — every element appears exactly once at its tree position; there is no parallel flat array. Leaves carry the full `HeistElement` payload directly under the `element` key (no `order` field, no `_0` wrapper).

### actionResult

Response to `activate`, `one_finger_tap`, `increment`, `decrement`, `typeText`, `performCustomAction`, `handleAlert`, `setPasteboard`, `getPasteboard`, `scroll`, `scrollToVisible`, `elementSearch`, or `scrollToEdge` commands. Also returned internally by `explore` (dispatched via `get_interface` with `full: true`).

```json
{"protocolVersion":"9.0","type":"actionResult","payload":{
  "success":true,
  "method":"syntheticTap",
  "message":null
}}
```

For `typeText`, the response includes the current text field value:
```json
{"protocolVersion":"9.0","type":"actionResult","payload":{
  "success":true,
  "method":"typeText",
  "value":"Hello World"
}}
```

Possible methods:
- `syntheticTap` - Tap synthesized via TheSafecracker
- `syntheticLongPress` - Long press synthesized via TheSafecracker
- `syntheticSwipe` - Swipe synthesized via TheSafecracker
- `syntheticDrag` - Drag synthesized via TheSafecracker
- `syntheticPinch` - Pinch gesture synthesized via TheSafecracker
- `syntheticRotate` - Rotation gesture synthesized via TheSafecracker
- `syntheticTwoFingerTap` - Two-finger tap synthesized via TheSafecracker
- `syntheticDrawPath` - Path drawing synthesized via TheSafecracker
- `activate` - Element's `activate()` was used
- `increment` - Element's `increment()` was called
- `decrement` - Element's `decrement()` was called
- `typeText` - Text injected via UIKeyboardImpl
- `customAction` - Named custom action was invoked
- `editAction` - Edit action performed via responder chain
- `handleAlert` - System alert handled via IOHIDEventSystemClient
- `setPasteboard` - Text written to general pasteboard
- `getPasteboard` - Text read from general pasteboard
- `resignFirstResponder` - First responder resigned (keyboard dismissed)
- `waitForIdle` - Wait-for-idle completed
- `waitForChange` - Wait-for-change completed (expectation met or timeout)
- `waitFor` - Wait-for element completed
- `scroll` - Scroll view scrolled by one page
- `scrollToVisible` - Known registry element was scrolled into view
- `elementSearch` - Iterative scroll search found (or failed to find) element matching predicate
- `scrollToEdge` - Scroll view scrolled to an edge
- `explore` - Full element census completed (all scrollable content discovered, scroll positions restored)
- `elementNotFound` - Target element could not be found
- `elementDeallocated` - Element's underlying view was deallocated

The optional `message` field provides additional context, especially for failures:
```json
{"protocolVersion":"9.0","type":"actionResult","payload":{
  "success":false,
  "method":"elementNotFound",
  "message":"Element is disabled (has 'notEnabled' trait)"
}}
```

### screen

PNG capture of the current screen.

```json
{"protocolVersion":"9.0","type":"screen","payload":{
  "pngData":"iVBORw0KGgo...",
  "width":393.0,
  "height":852.0,
  "timestamp":"2026-02-03T10:30:45.123Z"
}}
```

The `pngData` field is base64-encoded PNG image data.

### pong

Response to `ping`.

```json
{"protocolVersion":"9.0","type":"pong"}
```

### recordingStarted

Acknowledgement that recording has begun.

```json
{"protocolVersion":"9.0","type":"recordingStarted"}
```

### recordingStopped

Lightweight notification that recording stopped without including the video payload. This is sent for automatic stops such as inactivity, max duration, or file size limit. The completed video is cached server-side and returned by the next `stopRecording` request.

```json
{"protocolVersion":"9.0","type":"recordingStopped"}
```

### recording

Completed screen recording. Contains the H.264/MP4 video as base64-encoded data. Sent as the response to `stopRecording`, not as an unsolicited broadcast.

```json
{"protocolVersion":"9.0","type":"recording","payload":{
  "videoData":"AAAAIGZ0eXBpc29t...",
  "width":390,
  "height":844,
  "duration":5.2,
  "frameCount":42,
  "fps":8,
  "startTime":"2026-02-24T10:30:00.000Z",
  "endTime":"2026-02-24T10:30:05.200Z",
  "stopReason":"inactivity",
  "interactionLog":[
    {
      "timestamp":1.2,
      "command":{"type":"activate","payload":{"identifier":"loginButton"}},
      "result":{"success":true,"method":"syntheticTap","interfaceDelta":{"kind":"elementsChanged","elementCount":12,"updated":[{"heistId":"button·loginButton","changes":[{"property":"value","old":null,"new":"Loading..."}]}]}}
    }
  ]
}}
```

The `videoData` field is base64-encoded MP4 video data. The raw file size is capped at 7MB to stay within the 10MB wire protocol buffer limit after base64 encoding. The optional `interactionLog` field contains an ordered array of `InteractionEvent` objects capturing each command, result, and interface delta during the recording. It is `null` or absent when no interactions occurred.

Stop reasons: `"manual"`, `"inactivity"`, `"maxDuration"`, `"fileSizeLimit"`.

### recordingError

Recording failed with an error.

```json
{"protocolVersion":"9.0","type":"recordingError","payload":"AVAssetWriter failed to start"}
```

### interaction

Broadcast to all subscribed clients (including observers) after a driver performs an action. Contains the command, result, and interface delta.

```json
{"protocolVersion":"9.0","type":"interaction","payload":{"timestamp":1709472045.123,"command":{"type":"activate","payload":{"identifier":"loginButton"}},"result":{"success":true,"method":"syntheticTap","interfaceDelta":{"kind":"elementsChanged","elementCount":12,"updated":[{"heistId":"button·loginButton","changes":[{"property":"value","old":null,"new":"Loading..."}]}]}}}}
```

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | `Double` | Unix timestamp of the interaction |
| `command` | `ClientMessage` | The command that triggered the interaction |
| `result` | `ActionResult` | The result of the action (includes `interfaceDelta` when the UI hierarchy changed) |

### error

Error message.

```json
{"protocolVersion":"9.0","type":"error","payload":"Root view not available"}
```

## Element Discovery

```mermaid
sequenceDiagram
    participant Agent
    participant TheFence
    participant TheInsideJob
    participant TheBrains

    Note over Agent,TheBrains: get_interface (visible only)
    Agent->>TheFence: get_interface
    TheFence->>TheInsideJob: requestInterface
    TheInsideJob->>TheBrains: snapshotElements()
    TheBrains-->>Agent: interface (visible elements)

    Note over Agent,TheBrains: get_interface --full (explore)
    Agent->>TheFence: get_interface(full: true)
    TheFence->>TheInsideJob: explore
    TheInsideJob->>TheBrains: exploreScreen()

    loop each scrollable container
        TheBrains->>TheBrains: save scroll position
        loop scroll forward until stagnation
            TheBrains->>TheBrains: scrollByPage
            TheBrains->>TheBrains: refreshAccessibilityData
            TheBrains->>TheBrains: record new elements
        end
        TheBrains->>TheBrains: restore scroll position
    end

    TheBrains-->>Agent: interface (all elements + explore metadata)
```

Three ways to find elements, each suited to a different situation:

| Command | What it returns | When to use |
|---------|----------------|-------------|
| `get_interface` | Visible elements only | Fast reads. You know the element is on screen, or you want the current viewport. |
| `get_interface` with `full: true` | Every element on screen, including off-screen content | You need to know what exists in scroll views without navigating. Returns the same `interface` response with all elements populated. |
| `scroll_to_visible` | Jumps to a known registry element, leaves viewport on it | You have already discovered the element and want to **navigate to it** for interaction. Changes the scroll position. |
| `element_search` | Scrolls until the target element is found, leaves viewport on it | You have not discovered the element yet and need to search scrollable content. |

### Choosing between full, element_search, and scroll_to_visible

- **`get_interface --full`** is a read operation. It explores, then restores scroll positions. The user sees no change. Use it when you need a census — "what elements are on this screen?" — without committing to navigate anywhere.

- **`scroll_to_visible`** is a recorded-position navigation action. It scrolls to a known target and leaves the viewport there so you can interact with the element. Use it after `get_interface --full`, previous scrolling, or a prior delta has discovered the element.

- **`element_search`** is an iterative navigation action. It pages through scrollable containers and stops when the target is found. Use it when the element has not been seen yet.

```mermaid
flowchart TD
    A[Need to find an element?] --> B{Is it likely visible?}
    B -->|Yes| C[get_interface]
    B -->|No / unsure| D{Need to interact with it?}
    D -->|Yes, already discovered| E[scroll_to_visible<br>Jumps to known element,<br>leaves viewport there]
    D -->|Yes, not yet discovered| I[element_search<br>Pages until found,<br>leaves viewport there]
    D -->|No, just check existence| F[get_interface --full<br>Census then restore<br>scroll positions]
    C --> G{Found it?}
    G -->|Yes| H[activate / scroll / interact]
    G -->|No| D
```

### When you don't need either

Most agent workflows don't need full exploration. The typical pattern is:

1. `get_interface` — see what's visible
2. `activate` / `scroll` / `swipe` — interact with visible elements
3. `element_search` — find a specific unseen off-screen element when needed
4. `scroll_to_visible` — return to a known off-screen element by recorded position

Use `get_interface --full` when the screen has deep scrollable content and you need to make decisions based on elements that aren't currently visible (e.g., checking if a specific item exists in a long list before deciding what to do).

## Data Types

### ServerInfo

The wire-level protocol version is carried by `ResponseEnvelope.protocolVersion`
and is not duplicated on `ServerInfo`.

| Field | Type | Description |
|-------|------|-------------|
| `appName` | `String` | App display name |
| `bundleIdentifier` | `String` | App bundle identifier |
| `deviceName` | `String` | Device name (e.g., "iPhone 15 Pro") |
| `systemVersion` | `String` | iOS version (e.g., "17.0") |
| `screenWidth` | `Double` | Screen width in points |
| `screenHeight` | `Double` | Screen height in points |
| `instanceId` | `String?` | Per-launch session UUID |
| `instanceIdentifier` | `String?` | Human-readable instance identifier from `INSIDEJOB_ID` env var (falls back to shortId) |
| `listeningPort` | `UInt16?` | Port the server is listening on |
| `simulatorUDID` | `String?` | Simulator UDID when running in iOS Simulator (nil on physical devices) |
| `vendorIdentifier` | `String?` | `UIDevice.identifierForVendor` UUID string (nil in simulator) |
| `tlsActive` | `Bool?` | Whether TLS transport encryption is active |

### Interface

| Field | Type | Description |
|-------|------|-------------|
| `screenDescription` | `String` | Deterministic one-line screen summary (e.g. `"Sign In — 1 text field, 1 password field, 3 buttons"`) |
| `timestamp` | `ISO8601 Date` | When interface was captured |
| `tree` | `[InterfaceNode]` | Canonical tree of leaf elements and grouping containers. Every element appears exactly once at its tree position; there is no parallel flat array on the wire. |

### HeistElement

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String` | Stable deterministic identifier (derived from developer identifier or synthesized from traits+label; value excluded for stability). Preferred for element targeting. |
| `label` | `String?` | Label |
| `value` | `String?` | Current value (for controls) |
| `identifier` | `String?` | Identifier |
| `hint` | `String?` | Accessibility hint |
| `traits` | `[String]` | Trait names (e.g., `"button"`, `"adjustable"`, `"staticText"`, `"backButton"`) |
| `frameX` | `Double` | Frame origin X in points (full detail only) |
| `frameY` | `Double` | Frame origin Y in points (full detail only) |
| `frameWidth` | `Double` | Frame width in points (full detail only) |
| `frameHeight` | `Double` | Frame height in points (full detail only) |
| `activationPointX` | `Double` | Activation point X (full detail only) |
| `activationPointY` | `Double` | Activation point Y (full detail only) |
| `customContent` | `[HeistCustomContent]?` | Custom accessibility content |
| `actions` | `[ElementAction]?` | Non-obvious actions only. Omitted when all actions are implied by traits (`activate` for buttons, `increment`/`decrement` for adjustable). Custom actions always included. |

### InterfaceNode

Recursive node in the canonical interface tree. Each node is a singleton object whose key discriminates the case:

- `{"element":{...HeistElement}}` — Leaf node carrying a full `HeistElement` payload (no `order`, no parallel flat array — the leaf's tree position is its order).
- `{"container":{type, …ContainerInfo, "children":[InterfaceNode]}}` — Container node carrying `ContainerInfo` fields (type discriminator + payload + frame) inline alongside `children`.

### ContainerInfo

The container payload is a flat object keyed by the discriminator `type`. Type-specific fields live at the same level alongside the frame:

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `type` | `String` | Yes | Discriminator; one of the container types listed below |
| `frameX` | `Double` | Yes | Frame origin X in points |
| `frameY` | `Double` | Yes | Frame origin Y in points |
| `frameWidth` | `Double` | Yes | Frame width in points |
| `frameHeight` | `Double` | Yes | Frame height in points |
| `children` | `[InterfaceNode]` | Yes (inside `InterfaceNode.container`) | Child nodes |
| `label` | `String?` | `semanticGroup` only | Container label |
| `value` | `String?` | `semanticGroup` only | Container value |
| `identifier` | `String?` | `semanticGroup` only | Container identifier |
| `contentWidth` | `Double` | `scrollable` only | Scroll content size width |
| `contentHeight` | `Double` | `scrollable` only | Scroll content size height |
| `rowCount` | `Int` | `dataTable` only | Number of rows |
| `columnCount` | `Int` | `dataTable` only | Number of columns |

Container types:
- `"semanticGroup"` — Semantic grouping (with optional `label`/`value`/`identifier`)
- `"list"` — List container (affects rotor navigation)
- `"landmark"` — Landmark container (affects rotor navigation)
- `"dataTable"` — Data table container; carries `rowCount` and `columnCount`
- `"tabBar"` — Tab bar container
- `"scrollable"` — Scrollable region; carries `contentWidth` and `contentHeight`

### ElementTarget

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | Stable element identifier assigned by `get_interface` |
| `label` / `identifier` / `value` / `traits` / `excludeTraits` | matcher fields | Predicate matcher fields for accessibility-based resolution, decoded flat at the target root |
| `ordinal` | `Int?` | 0-based index to select among multiple matcher results. Without ordinal, multiple matches return an ambiguity error. |

Two resolution strategies. Resolution priority: `heistId` > matcher fields. At least one identity field should be provided.

### TouchTapTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Target element (taps at activation point) |
| `pointX` | `Double?` | Explicit X coordinate |
| `pointY` | `Double?` | Explicit Y coordinate |

### LongPressTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Target element |
| `pointX` | `Double?` | Explicit X coordinate |
| `pointY` | `Double?` | Explicit Y coordinate |
| `duration` | `Double` | Press duration in seconds (default: 0.5) |

### SwipeTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Start from element's activation point |
| `startX` | `Double?` | Start X coordinate |
| `startY` | `Double?` | Start Y coordinate |
| `endX` | `Double?` | End X coordinate |
| `endY` | `Double?` | End Y coordinate |
| `direction` | `String?` | Swipe direction: "up", "down", "left", "right" |
| `duration` | `Double?` | Duration in seconds (default: 0.15) |
| `start` | `UnitPoint?` | Unit-point start relative to element frame (0–1) |
| `end` | `UnitPoint?` | Unit-point end relative to element frame (0–1) |

### DragTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Start from element's activation point |
| `startX` | `Double?` | Start X coordinate |
| `startY` | `Double?` | Start Y coordinate |
| `endX` | `Double` | End X coordinate |
| `endY` | `Double` | End Y coordinate |
| `duration` | `Double?` | Duration in seconds (default: 0.5) |

### PinchTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Center on element's activation point |
| `centerX` | `Double?` | Center X coordinate |
| `centerY` | `Double?` | Center Y coordinate |
| `scale` | `Double` | Scale factor (>1.0 zoom in, <1.0 zoom out) |
| `spread` | `Double?` | Initial finger spread from center (default: 100pt) |
| `duration` | `Double?` | Duration in seconds (default: 0.5) |

### RotateTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Center on element's activation point |
| `centerX` | `Double?` | Center X coordinate |
| `centerY` | `Double?` | Center Y coordinate |
| `angle` | `Double` | Rotation angle in radians |
| `radius` | `Double?` | Distance from center to each finger (default: 100pt) |
| `duration` | `Double?` | Duration in seconds (default: 0.5) |

### TwoFingerTapTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Center on element's activation point |
| `centerX` | `Double?` | Center X coordinate |
| `centerY` | `Double?` | Center Y coordinate |
| `spread` | `Double?` | Distance between fingers (default: 40pt) |

### DrawPathTarget

| Field | Type | Description |
|-------|------|-------------|
| `points` | `[PathPoint]` | Array of waypoints to trace through (minimum 2) |
| `duration` | `Double?` | Total duration in seconds (mutually exclusive with velocity) |
| `velocity` | `Double?` | Speed in points per second (mutually exclusive with duration) |

### PathPoint

| Field | Type | Description |
|-------|------|-------------|
| `x` | `Double` | X coordinate in screen points |
| `y` | `Double` | Y coordinate in screen points |

### DrawBezierTarget

| Field | Type | Description |
|-------|------|-------------|
| `startX` | `Double` | Starting X coordinate |
| `startY` | `Double` | Starting Y coordinate |
| `segments` | `[BezierSegment]` | Array of cubic bezier segments |
| `samplesPerSegment` | `Int?` | Points to sample per segment (default: 20) |
| `duration` | `Double?` | Total duration in seconds (mutually exclusive with velocity) |
| `velocity` | `Double?` | Speed in points per second (mutually exclusive with duration) |

### BezierSegment

| Field | Type | Description |
|-------|------|-------------|
| `cp1X` | `Double` | First control point X |
| `cp1Y` | `Double` | First control point Y |
| `cp2X` | `Double` | Second control point X |
| `cp2Y` | `Double` | Second control point Y |
| `endX` | `Double` | Endpoint X |
| `endY` | `Double` | Endpoint Y |

### TypeTextTarget

| Field | Type | Description |
|-------|------|-------------|
| `text` | `String?` | Text to type character-by-character |
| `deleteCount` | `Int?` | Number of delete key taps before typing |
| `elementTarget` | `ActionTarget?` | Element to tap for focus and value readback |

At least `text` or `deleteCount` must be provided. If `elementTarget` is provided, it is tapped first to bring up the keyboard, and its value is read back after the operation.

### CustomActionTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget` | Target element |
| `actionName` | `String` | Name of the custom action |

### EditActionTarget

| Field | Type | Description |
|-------|------|-------------|
| `action` | `String` | Edit action: `"copy"`, `"paste"`, `"cut"`, `"select"`, `"selectAll"` |

### ScrollDirection

Enum values: `"up"`, `"down"`, `"left"`, `"right"`, `"next"`, `"previous"`.

- `up` — Scroll up to reveal content above the current viewport
- `down` — Scroll down to reveal content below the current viewport
- `left` — Scroll left to reveal content to the left
- `right` — Scroll right to reveal content to the right
- `next` — Scroll to next page (equivalent to down for vertical content)
- `previous` — Scroll to previous page (equivalent to up for vertical content)

### ScrollTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Element to scroll from (bubbles up to nearest scroll view ancestor) |
| `direction` | `ScrollDirection` | Scroll direction |

### ScrollEdge

Enum values: `"top"`, `"bottom"`, `"left"`, `"right"`.

### ScrollToEdgeTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget?` | Element whose nearest scroll view ancestor to scroll |
| `edge` | `ScrollEdge` | Which edge to scroll to |

### ElementMatcher

Predicate for matching elements in the accessibility tree. All specified fields must match (AND semantics). Used by `scrollToVisible`, `waitFor`, `get_interface` filtering, and action commands through flat `ElementTarget` matcher fields.

| Field | Type | Description |
|-------|------|-------------|
| `label` | `String?` | Exact match on accessibility label |
| `identifier` | `String?` | Exact match on accessibility identifier |
| `value` | `String?` | Exact match on accessibility value |
| `traits` | `[String]?` | All listed traits must be present on the element |
| `excludeTraits` | `[String]?` | None of the listed traits may be present |

### ScrollToVisibleTarget

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | Known stable heistId to scroll into view |
| `label` / `identifier` / `value` / `traits` / `excludeTraits` | matcher fields | Flat matcher fields for the known element to scroll into view |

### ScrollSearchDirection

| Value | Description |
|-------|-------------|
| `"down"` | Scroll down (default) |
| `"up"` | Scroll up |
| `"left"` | Scroll left |
| `"right"` | Scroll right |

### ScrollSearchResult

Diagnostic output from `elementSearch`, included on every `actionResult` for that command.

| Field | Type | Description |
|-------|------|-------------|
| `scrollCount` | `Int` | Number of scroll steps performed |
| `uniqueElementsSeen` | `Int` | Number of distinct elements seen across all scroll positions (tracked via `StableKey`) |
| `totalItems` | `Int?` | Total item count from UITableView/UICollectionView data source (nil if not a collection) |
| `exhaustive` | `Bool` | `true` if `uniqueElementsSeen >= totalItems` — all items in the collection were visited |
| `foundElement` | `HeistElement?` | The matched element (nil on failure) |

### WaitForIdleTarget

| Field | Type | Description |
|-------|------|-------------|
| `timeout` | `Double?` | Maximum wait time in seconds (default: 5.0, max: 60.0) |

### WaitForTarget

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String?` | Assigned element id from the current screen, decoded flat at the payload root |
| `label` / `identifier` / `value` / `traits` / `excludeTraits` | matcher fields | Predicate fields for accessibility-based resolution, decoded flat at the payload root |
| `ordinal` | `Int?` | 0-based index to select among multiple matcher results |
| `absent` | `Bool?` | When `true`, wait for element to NOT exist (default: `false`) |
| `timeout` | `Double?` | Max wait time in seconds (default: 10, max: 30) |

### UnitPoint

A point in unit coordinates (0–1) relative to an element's accessibility frame. `(0, 0)` is top-left, `(1, 1)` is bottom-right.

| Field | Type | Description |
|-------|------|-------------|
| `x` | `Double` | Horizontal position (0 = left, 1 = right) |
| `y` | `Double` | Vertical position (0 = top, 1 = bottom) |

### ActionResult

| Field | Type | Description |
|-------|------|-------------|
| `success` | `Bool` | Whether action succeeded |
| `method` | `String` | How action was performed (see method values above) |
| `message` | `String?` | Additional context or error description |
| `errorKind` | `String?` | Typed error classification: `"elementNotFound"`, `"timeout"`, `"unsupported"`, `"inputError"`, `"validationError"`, `"actionFailed"`. Nil on success. |
| `value` | `String?` | Current text field value (populated by `typeText`) |
| `interfaceDelta` | `InterfaceDelta?` | Compact delta describing what changed after the action |
| `animating` | `Bool?` | `true` if UI was still animating when result was produced; `nil` means idle |
| `screenName` | `String?` | Label of the first header element in the post-action snapshot (screen name hint) |
| `screenId` | `String?` | Slugified screen name for machine use (e.g. `"controls_demo"`) |
| `scrollSearchResult` | `ScrollSearchResult?` | Diagnostics from `elementSearch` — scroll count, unique elements seen, total items, exhaustive flag, matched element |

### ActionExpectation (Fence-level)

Outcome signal classifiers attached to Fence requests via the `expect` field. `ActionExpectation` is a wire-protocol value with a stable, documented JSON shape as of protocol `7.0`.

Every action implicitly checks delivery (`success == true`). If delivery fails, the response includes an `expectation` object with `met: false` and `status: "expectation_failed"` — no `expect` field needed.

The `expect` field classifies what kind of outcome the caller was going for. Expectations follow a **"say what you know"** design: provide only the fields you care about, omit what you don't. Omitted fields are wildcards. The framework scans the result for any match.

#### Short forms

Two shorthand string values are accepted inline at the `expect` field for the two most common tiers:

| Value | Equivalent object | Description |
|-------|-------------------|-------------|
| `"screen_changed"` | `{"type": "screen_changed"}` | Expected `interfaceDelta.kind == "screenChanged"` |
| `"elements_changed"` | `{"type": "elements_changed"}` | Expected `interfaceDelta.kind == "elementsChanged"` or `"screenChanged"` (superset rule) |

#### Full object form

Every `ActionExpectation` serializes to a JSON object with a `type` discriminator. All forms below are accepted at the `expect` field; the server parses the string short forms above into the equivalent object.

| `type` | Payload | Description |
|--------|---------|-------------|
| `"screen_changed"` | *(no fields)* | VC identity changed |
| `"elements_changed"` | *(no fields)* | Element-level add/remove/update (superset-met by screen_changed) |
| `"element_updated"` | `heistId?`, `property?`, `oldValue?`, `newValue?` | A matching entry appears in `interfaceDelta.updated` |
| `"element_appeared"` | `matcher` (ElementMatcher) | An element matching the matcher appears in `interfaceDelta.added` |
| `"element_disappeared"` | `matcher` (ElementMatcher) | An element matching the matcher was removed |
| `"compound"` | `expectations` (`[ActionExpectation]`) | Every sub-expectation must be met |

Examples:
```json
{"expect": {"type": "element_updated", "newValue": "5"}}
{"expect": {"type": "element_updated", "heistId": "counter", "property": "value", "newValue": "5"}}
{"expect": {"type": "element_appeared", "matcher": {"label": "Success"}}}
{"expect": {"type": "element_disappeared", "matcher": {"identifier": "loading-spinner"}}}
{"expect": {"type": "compound", "expectations": [
  {"type": "screen_changed"},
  {"type": "element_appeared", "matcher": {"label": "Welcome"}}
]}}
```

For `element_updated`, all four payload fields (`heistId`, `property`, `oldValue`, `newValue`) are optional — provide more to tighten the check, fewer to loosen it. When both `oldValue` and `newValue` are provided they must match the same `PropertyChange` entry.

The `property` field accepts these values: `"label"`, `"value"`, `"traits"`, `"hint"`, `"actions"`, `"frame"`, `"activationPoint"`.

For `compound`, nesting is allowed — a `compound` may contain other `compound` entries.

**Breaking change in protocol 7.0**: prior versions used Swift's compiler-synthesized Codable shape for `ActionExpectation`, which wrapped `elementUpdated` / `elementAppeared` / `elementDisappeared` / `compound` in legacy container keys rather than using the `type` discriminator. Callers sending typed expectations must update to the new shape. The short string forms (`"screen_changed"`, `"elements_changed"`) are unchanged.

When an expectation is checked, the Fence response includes an `expectation` object:

| Field | Type | Description |
|-------|------|-------------|
| `met` | `Bool` | Whether the expectation was satisfied |
| `expected` | `ActionExpectation?` | The expectation that was checked (JSON-encoded). `null` for implicit delivery check. |
| `actual` | `String?` | What was actually observed (for diagnostics when `met` is false) |

If `met` is false, the response `status` is set to `"expectation_failed"`.

### Batch Expectations Summary

When a `run_batch` response includes steps with expectations, the response includes an `expectations` summary:

| Field | Type | Description |
|-------|------|-------------|
| `checked` | `Int` | Number of steps that had expectations checked |
| `met` | `Int` | Number of expectations that were satisfied |
| `allMet` | `Bool` | `true` if all checked expectations were met |

Under `stop_on_error` policy, a failed expectation (`status: "expectation_failed"`) stops the batch.

### InterfaceDelta

`InterfaceDelta` is a discriminated union — the `kind` field selects which other fields are valid. Empty edit collections are omitted on the wire; missing keys decode as empty arrays.

Common fields (every case):

| Field | Type | Description |
|-------|------|-------------|
| `kind` | `String` | `"noChange"`, `"elementsChanged"`, or `"screenChanged"` |
| `elementCount` | `Int` | Total element count after the action |
| `transient` | `[HeistElement]?` | Elements that appeared and disappeared during settle while baseline and final were otherwise identical. Omitted when empty. |

Case-specific fields:

| `kind` | Additional fields | Notes |
|--------|-------------------|-------|
| `noChange` | (none) | The hierarchy did not change. May still carry `transient`. |
| `elementsChanged` | `added`, `removed`, `updated`, `treeInserted`, `treeRemoved`, `treeMoved` | Element-level edits within the same screen. Each collection is omitted when empty. |
| `screenChanged` | `newInterface`, `postEdits?` | View controller identity changed. `postEdits` is an `ElementEdits` sub-object describing edits folded in by `NetDeltaAccumulator.mergeAfterScreenChange` — present only on batch-merged deltas, omitted otherwise. `newInterface.tree` reflects element-level swaps from `postEdits.added`/`removed`/`updated` (best-effort) but does **not** apply the structural `treeInserted`/`treeRemoved`/`treeMoved` entries — those are descriptive diff metadata. When tree structure matters, treat `postEdits` as authoritative over `newInterface.tree`. |

`postEdits` shape (when present):

| Field | Type | Description |
|-------|------|-------------|
| `added` | `[HeistElement]?` | Elements added after the screen change |
| `removed` | `[String]?` | HeistIds of elements removed after the screen change |
| `updated` | `[ElementUpdate]?` | Element property changes after the screen change |
| `treeInserted` | `[TreeInsertion]?` | Tree insertions after the screen change |
| `treeRemoved` | `[TreeRemoval]?` | Tree removals after the screen change |
| `treeMoved` | `[TreeMove]?` | Tree moves after the screen change |

### ElementUpdate

| Field | Type | Description |
|-------|------|-------------|
| `heistId` | `String` | Element heistId |
| `changes` | `[PropertyChange]` | Properties that changed on this element |

### PropertyChange

| Field | Type | Description |
|-------|------|-------------|
| `property` | `String` | Which property changed: `"label"`, `"value"`, `"traits"`, `"hint"`, `"actions"`, `"frame"`, `"activationPoint"` |
| `old` | `String?` | Previous value |
| `new` | `String?` | New value |

### HeistCustomContent

| Field | Type | Description |
|-------|------|-------------|
| `label` | `String` | Content label |
| `value` | `String` | Content value |
| `isImportant` | `Bool` | Whether this content is marked important |

### ScreenPayload

| Field | Type | Description |
|-------|------|-------------|
| `pngData` | `String` | Base64-encoded PNG image data |
| `width` | `Double` | Screen width in points |
| `height` | `Double` | Screen height in points |
| `timestamp` | `ISO8601 Date` | When screen was captured |

### RecordingConfig

| Field | Type | Description |
|-------|------|-------------|
| `fps` | `Int?` | Frames per second (1-15, default: 8) |
| `scale` | `Double?` | Resolution scale of native pixels (0.25-1.0, default: 1x point size) |
| `inactivityTimeout` | `Double?` | Seconds of inactivity before auto-stop (default: 5.0) |
| `maxDuration` | `Double?` | Maximum recording duration in seconds (default: 60.0) |

### RecordingPayload

| Field | Type | Description |
|-------|------|-------------|
| `videoData` | `String` | Base64-encoded H.264/MP4 video data |
| `width` | `Int` | Video width in pixels |
| `height` | `Int` | Video height in pixels |
| `duration` | `Double` | Recording duration in seconds |
| `frameCount` | `Int` | Number of frames captured |
| `fps` | `Int` | Frames per second used during recording |
| `startTime` | `ISO8601 Date` | When recording started |
| `endTime` | `ISO8601 Date` | When recording ended |
| `stopReason` | `String` | `"manual"`, `"inactivity"`, `"maxDuration"`, or `"fileSizeLimit"` |
| `interactionLog` | `[InteractionEvent]?` | Ordered log of interactions recorded during the session (nil if no interactions occurred) |

### InteractionEvent

A single recorded interaction event captured during a Stakeout recording.

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | `Double` | Time offset from recording start in seconds |
| `command` | `ClientMessage` | The command that triggered this interaction |
| `result` | `ActionResult` | The result returned to the client (includes `interfaceDelta` when the UI hierarchy changed) |

## Example Session

```
# Client connects to fd9a:6190:eed7::1 on the Bonjour-advertised port

# Server sends hello immediately after connect
{"protocolVersion":"9.0","requestId":null,"type":"serverHello"}

# Client acknowledges exact protocol match
{"protocolVersion":"9.0","requestId":null,"type":"clientHello"}

# Server sends auth challenge
{"protocolVersion":"9.0","requestId":null,"type":"authRequired"}

# Client authenticates
{"protocolVersion":"9.0","requestId":null,"type":"authenticate","payload":{"token":"my-secret-token"}}

# Server sends info after successful auth
{"protocolVersion":"9.0","requestId":null,"type":"info","payload":{"appName":"TestApp","bundleIdentifier":"com.buttonheist.testapp","deviceName":"iPhone","systemVersion":"26.2.1","screenWidth":393.0,"screenHeight":852.0,"instanceId":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","instanceIdentifier":"my-instance","listeningPort":52341,"simulatorUDID":"DEADBEEF-1234-5678-9ABC-DEF012345678","vendorIdentifier":null,"tlsActive":true}}

# Client subscribes to updates
{"protocolVersion":"9.0","type":"subscribe"}

# Client requests interface
{"protocolVersion":"9.0","type":"requestInterface"}

# Server responds with interface tree
{"protocolVersion":"9.0","type":"interface","payload":{"timestamp":"2026-02-03T14:08:14.123Z","tree":[...]}}

# Client requests screen capture
{"protocolVersion":"9.0","type":"requestScreen"}

# Server responds with screen capture
{"protocolVersion":"9.0","type":"screen","payload":{"pngData":"iVBORw0KGgo...","width":393.0,"height":852.0,"timestamp":"2026-02-03T14:08:14.200Z"}}

# Client activates a button
{"protocolVersion":"9.0","type":"activate","payload":{"identifier":"loginButton"}}

# Server confirms action
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"syntheticTap","message":null}}

# Client increments a slider
{"protocolVersion":"9.0","type":"increment","payload":{"identifier":"volumeSlider"}}

# Server confirms
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"increment","message":null}}

# Client performs custom action
{"protocolVersion":"9.0","type":"performCustomAction","payload":{"elementTarget":{"identifier":"messageCell"},"actionName":"Delete"}}

# Server confirms
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"customAction","message":null}}

# Client types text into a field
{"protocolVersion":"9.0","type":"typeText","payload":{"text":"Hello World","elementTarget":{"identifier":"nameField"}}}

# Server confirms with current field value
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"typeText","value":"Hello World"}}

# Client corrects a typo (delete 5 chars, retype)
{"protocolVersion":"9.0","type":"typeText","payload":{"deleteCount":5,"text":"World","elementTarget":{"identifier":"nameField"}}}

# Server confirms correction
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"typeText","value":"Hello World"}}

# Client starts recording
{"protocolVersion":"9.0","type":"startRecording","payload":{"fps":8}}

# Server acknowledges
{"protocolVersion":"9.0","type":"recordingStarted"}

# Client interacts while recording...
{"protocolVersion":"9.0","type":"activate","payload":{"identifier":"loginButton"}}
{"protocolVersion":"9.0","type":"actionResult","payload":{"success":true,"method":"syntheticTap"}}

# Client stops recording
{"protocolVersion":"9.0","type":"stopRecording"}

# Server acknowledges stop command
{"protocolVersion":"9.0","type":"recordingStopped"}

# Server responds with completed recording
{"protocolVersion":"9.0","type":"recording","payload":{"videoData":"AAAAIGZ0eXBpc29t...","width":390,"height":844,"duration":5.2,"frameCount":42,"fps":8,"startTime":"2026-02-24T10:30:00.000Z","endTime":"2026-02-24T10:30:05.200Z","stopReason":"manual"}}

# Client sends keepalive
{"protocolVersion":"9.0","type":"ping"}

# Server responds
{"protocolVersion":"9.0","type":"pong"}

# Server auto-pushes interface change
{"protocolVersion":"9.0","type":"interface","payload":{"timestamp":"2026-02-03T14:08:15.500Z","tree":[...]}}
{"protocolVersion":"9.0","type":"screen","payload":{"pngData":"...","width":393.0,"height":852.0,"timestamp":"2026-02-03T14:08:15.550Z"}}
```

### AuthenticatePayload

| Field | Type | Description |
|-------|------|-------------|
| `token` | `String` | Auth token for driver identification |
| `driverId` | `String?` | Unique driver identity for session locking. When set, used instead of token for session identity. Set via `BUTTONHEIST_DRIVER_ID` env var. |

### SessionLockedPayload

| Field | Type | Description |
|-------|------|-------------|
| `message` | `String` | Human-readable description |
| `activeConnections` | `Int` | Number of active connections in the current session |

### StatusPayload

| Field | Type | Description |
|-------|------|-------------|
| `identity` | `StatusIdentity` | App/device identity for the reachable Inside Job instance |
| `session` | `StatusSession` | Current session availability and connection counts |

### StatusIdentity

| Field | Type | Description |
|-------|------|-------------|
| `appName` | `String` | App name from the target bundle |
| `bundleIdentifier` | `String` | Bundle identifier of the running app |
| `appBuild` | `String` | Build number from `CFBundleVersion` |
| `deviceName` | `String` | Device name reported by UIKit |
| `systemVersion` | `String` | iOS version string |
| `buttonHeistVersion` | `String` | Protocol version exposed by Inside Job |

### StatusSession

| Field | Type | Description |
|-------|------|-------------|
| `active` | `Bool` | Whether a driver session is active |
| `watchersAllowed` | `Bool` | Whether observer connections are allowed for the active session |
| `activeConnections` | `Int` | Number of connections in the current session |

### WatchPayload

| Field | Type | Description |
|-------|------|-------------|
| `token` | `String` | Auth token required by default. Empty string is accepted only when `INSIDEJOB_RESTRICT_WATCHERS=0` is set on the server. |

## Implementation Notes

### Authentication

Token-based authentication is required for driver connections:

1. Server sends `serverHello` immediately on TCP connect
2. Client must respond with `clientHello` using the exact same `protocolVersion`
3. Server sends `authRequired`
4. Client must respond with `authenticate` (for drivers) or `watch` (for observers). The one exception is `status`, which is allowed after the hello handshake but before auth for reachability probes and returns `ServerMessage.status` without claiming a session.
5. For drivers: on success and session acquired, server sends `info` and the session proceeds normally
6. On auth failure, server sends `authFailed` and disconnects after a brief delay
7. On session conflict, server sends `sessionLocked` and disconnects
8. For observers: token required by default (same as drivers). Set `INSIDEJOB_RESTRICT_WATCHERS=0` to allow unauthenticated observers.

The token is configured via `INSIDEJOB_TOKEN` env var or `InsideJobToken` Info.plist key. If not set, a random UUID is auto-generated each launch (ephemeral — not persisted). The token is logged to the console at startup. Clients set the token via the `BUTTONHEIST_TOKEN` environment variable.

### Session Locking

Session locking prevents multiple drivers from interfering with each other. Only one driver can control a TheInsideJob host at a time.

**Why sessions?** A single "driver" isn't a single TCP connection. Each CLI command (`buttonheist activate`, `buttonheist get_screen`, etc.) creates a fresh connection, authenticates, executes, and disconnects. Only `session` maintains a persistent connection. The session concept spans multiple sequential connections from the same driver.

**Driver Identity**: The server identifies drivers using a two-tier approach:
1. `driverId` from the authenticate payload (when present) — set via `BUTTONHEIST_DRIVER_ID` env var
2. `token` as fallback (when `driverId` is absent) — all same-token connections are one "driver"

If `driverId` is absent, the auth token is used as the driver identity. Setting `BUTTONHEIST_DRIVER_ID` enables multiple drivers sharing the same auth token to be distinguished.

#### Session Lifecycle

1. **Claim** — The first authenticated client's driver identity becomes the active session
2. **Join** — Subsequent connections with the **same driver identity** are allowed (same driver, different commands)
3. **Reject** — Connections with a **different driver identity** receive `sessionLocked` and are disconnected. The busy signal includes the inactivity timeout so the client knows how long to wait.
4. **Inactivity timer** — When the last connection from the session holder disconnects, a single inactivity timer starts (default: 30 seconds)
5. **Release** — Timer fires → session clears → next driver can claim
6. **Cancel timer** — Same-driver reconnect within the timeout window cancels the timer

There is only one timer (inactivity). There is no separate "lease" timer. The token is **not** invalidated when the session expires — it remains valid for future connections.

```mermaid
sequenceDiagram
    participant A as Driver A (token: "abc")
    participant S as Server
    participant B as Driver B (token: "xyz")

    A->>S: authenticate(token:"abc")
    S-->>A: info (session claimed)

    B->>S: authenticate(token:"xyz")
    S-->>B: sessionLocked
    S-xB: disconnect

    A->>S: TCP Close
    Note over S: 30s inactivity timer starts
    Note over S: 30s timer fires → session released

    B->>S: authenticate(token:"xyz")
    S-->>B: info (session claimed)
```

#### Configuration

The session inactivity timeout (time after last connection disconnects before the session is released) is configurable:

- **Environment variable**: `INSIDEJOB_SESSION_TIMEOUT` (in seconds)
- **Default**: 30 seconds

### UI Approval Flow

When the token is auto-generated (not explicitly set), TheInsideJob supports an interactive approval flow that allows the iOS user to approve or deny connections from the device:

1. Server starts with auto-generated token
2. Client connects and sends `authenticate` with an empty token (`""`)
3. Server presents a `UIAlertController` with "Allow" and "Deny" buttons
4. **If approved**: Server sends `authApproved` with the token, then `info` — the session proceeds normally
5. **If denied**: Server sends `authFailed("Connection denied by user")` and disconnects

```mermaid
sequenceDiagram
    participant Client
    participant Server as Server (UI approval mode)

    Client->>Server: TCP Connect
    Server-->>Client: serverHello
    Client->>Server: clientHello
    Server-->>Client: authRequired
    Client->>Server: authenticate(token:"") (empty token)
    Note over Server: UIAlertController: "Allow / Deny"
    Note over Server: ... user taps Allow ...
    Server-->>Client: authApproved(token) (token for future use)
    Server-->>Client: info
```

The client stores the received token and uses it for subsequent connections, which will authenticate normally without requiring approval.

This flow is **only active** when the token is auto-generated. If `INSIDEJOB_TOKEN` or `InsideJobToken` is explicitly set, the standard token-based flow is used and no approval alert is shown.

### Security Limits

- **Max connections**: 5 concurrent TCP connections
- **Rate limiting**: 30 messages/second per client (token bucket). Applied to both authenticated and unauthenticated clients.
- **Buffer limit**: 10 MB per-client receive buffer. Clients exceeding this are disconnected.
- **Loopback binding**: The `bindToLoopback` parameter on `ServerTransport.start()` controls whether the server binds to `::1` (loopback only) or `::` (all interfaces). The caller (TheInsideJob) decides based on the runtime environment.

### Port Configuration

The server uses OS-assigned ports by default. The actual port is advertised via Bonjour and included in the `info` message (`listeningPort` field) after connection.

### IPv6 Dual-Stack

The server binds to `::` (IPv6 any) on physical devices or `::1` (loopback) on simulators, accepting:
- IPv4 connections (mapped to `::ffff:x.x.x.x`)
- IPv6 connections (USB tunnel, WiFi)

### Keepalive

Clients should send `ping` messages periodically (recommended: every 5 seconds) to detect connection loss. Treat several missed pongs as a failure rather than closing on the first delayed response; app main-thread stalls can delay pong handling.

### Error Recovery

If the TCP connection is lost, clients should:
1. Close the socket
2. Optionally attempt reconnection
3. Re-request interface after reconnecting

### Hierarchy Change Detection

TheInsideJob uses hash-based change detection during polling:
1. Parse hierarchy at configurable interval (default: 1.0s)
2. Compute hash of the flat elements array
3. Only broadcast if hash differs from last broadcast
4. Screen captures are automatically captured and broadcast alongside interface changes
