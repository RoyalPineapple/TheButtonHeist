# ButtonHeist Wire Protocol Specification

**Version**: 2.0

This document specifies the communication protocol between InsideMan (iOS) and clients (Wheelman, CLI, Python scripts).

## Transport

- **Layer**: TCP socket (BSD sockets)
- **Discovery**: Bonjour/mDNS (WiFi) or CoreDevice IPv6 tunnel (USB)
- **Service Type**: `_buttonheist._tcp`
- **Port**: 1455 (configurable via Info.plist `InsideManPort` key)
- **Encoding**: Newline-delimited JSON (UTF-8)
- **Socket**: IPv6 dual-stack (accepts both IPv4 and IPv6)

## Discovery Methods

### WiFi (Bonjour)
InsideMan advertises itself using Bonjour:
- **Domain**: `local.`
- **Type**: `_buttonheist._tcp`
- **Name**: `{AppName}-{DeviceName}`

### USB (CoreDevice IPv6 Tunnel)
When connected via USB, macOS creates an IPv6 tunnel:
- **Device address**: `fd{prefix}::1` (e.g., `fd9a:6190:eed7::1`)
- **Port**: 1455
- **Discovery**: `lsof -i -P -n | grep CoreDev`

## Connection Lifecycle

```
Client                                    Server
   │                                         │
   │──────── TCP Connect ────────────────────►│
   │                                         │
   │◄─────── info ───────────────────────────│  (automatic on connect)
   │                                         │
   │──────── subscribe ──────────────────────►│  (enable auto-updates)
   │──────── requestHierarchy ───────────────►│
   │──────── requestScreenshot ──────────────►│
   │◄─────── hierarchy ──────────────────────│
   │◄─────── screenshot ────────────────────│
   │                                         │
   │──────── activate/touchTap/touchDrag... ──►│
   │◄─────── actionResult ───────────────────│
   │                                         │
   │◄─────── hierarchy ──────────────────────│  (auto-pushed on change)
   │◄─────── screenshot ────────────────────│  (auto-pushed on change)
   │                                         │
   │──────── ping ───────────────────────────►│
   │◄─────── pong ───────────────────────────│
   │                                         │
   │──────── TCP Close ──────────────────────►│
   │                                         │
```

## Message Format

All messages are JSON objects terminated by a newline (`\n`). Swift enums with associated values encode with `_0` wrapper.

## Client → Server Messages

### requestHierarchy

Request current accessibility hierarchy.

```json
{"requestHierarchy":{}}
```

### subscribe

Subscribe to automatic hierarchy and screenshot updates.

```json
{"subscribe":{}}
```

### unsubscribe

Unsubscribe from automatic updates.

```json
{"unsubscribe":{}}
```

### activate

Activate an element (equivalent to VoiceOver double-tap). Uses the TouchInjector system with synthetic event fallback chain.

**By identifier:**
```json
{"activate":{"_0":{"identifier":"loginButton"}}}
```

**By traversal index:**
```json
{"activate":{"_0":{"traversalIndex":5}}}
```

### touchTap

Tap at coordinates or on an element using synthetic touch injection via SafeCracker.

**At coordinates:**
```json
{"touchTap":{"_0":{"pointX":196.5,"pointY":659.0}}}
```

**On element by identifier:**
```json
{"touchTap":{"_0":{"elementTarget":{"identifier":"submitButton"}}}}
```

### touchLongPress

Long press at coordinates or on an element.

```json
{"touchLongPress":{"_0":{"pointX":100,"pointY":200,"duration":1.0}}}
```

**On element (default 0.5s):**
```json
{"touchLongPress":{"_0":{"elementTarget":{"identifier":"myButton"},"duration":0.5}}}
```

### touchSwipe

Swipe between two points or in a direction from an element.

**With explicit coordinates:**
```json
{"touchSwipe":{"_0":{"startX":200,"startY":400,"endX":200,"endY":100,"duration":0.15}}}
```

**From element in direction:**
```json
{"touchSwipe":{"_0":{"elementTarget":{"identifier":"list"},"direction":"up","distance":300}}}
```

### touchDrag

Drag from one point to another (slower than swipe, for sliders/reordering).

**With explicit coordinates:**
```json
{"touchDrag":{"_0":{"startX":100,"startY":200,"endX":300,"endY":200,"duration":0.5}}}
```

**From element:**
```json
{"touchDrag":{"_0":{"elementTarget":{"identifier":"slider"},"endX":300,"endY":200}}}
```

### touchPinch

Pinch/zoom gesture centered at a point. Scale >1.0 zooms in, <1.0 zooms out.

```json
{"touchPinch":{"_0":{"centerX":200,"centerY":300,"scale":2.0,"spread":100,"duration":0.5}}}
```

**On element:**
```json
{"touchPinch":{"_0":{"elementTarget":{"identifier":"mapView"},"scale":0.5}}}
```

### touchRotate

Rotation gesture centered at a point. Angle in radians.

```json
{"touchRotate":{"_0":{"centerX":200,"centerY":300,"angle":1.57,"radius":100,"duration":0.5}}}
```

### touchTwoFingerTap

Two-finger tap at a point or element.

```json
{"touchTwoFingerTap":{"_0":{"centerX":200,"centerY":300,"spread":40}}}
```

### increment

Increment an adjustable element (e.g., slider, stepper). Calls `accessibilityIncrement()` on the element's view.

**By identifier:**
```json
{"increment":{"_0":{"identifier":"volumeSlider"}}}
```

**By traversal index:**
```json
{"increment":{"_0":{"traversalIndex":8}}}
```

### decrement

Decrement an adjustable element. Calls `accessibilityDecrement()` on the element's view.

**By identifier:**
```json
{"decrement":{"_0":{"identifier":"volumeSlider"}}}
```

### performCustomAction

Invoke a named custom action on an element. The action name must match one of the element's `customActions`.

```json
{"performCustomAction":{"_0":{"elementTarget":{"identifier":"myCell"},"actionName":"Delete"}}}
```

### requestScreenshot

Request a PNG screenshot of the current screen.

```json
{"requestScreenshot":{}}
```

### ping

Keepalive ping.

```json
{"ping":{}}
```

## Server → Client Messages

### info

Sent immediately after connection. Contains device and app metadata.

```json
{"info":{"_0":{
  "protocolVersion":"2.0",
  "appName":"MyApp",
  "bundleIdentifier":"com.example.myapp",
  "deviceName":"iPhone 15 Pro",
  "systemVersion":"17.0",
  "screenWidth":393.0,
  "screenHeight":852.0
}}}
```

### hierarchy

Accessibility hierarchy snapshot. Contains a flat element list and an optional tree structure.

```json
{"hierarchy":{"_0":{
  "timestamp":"2026-02-03T10:30:45.123Z",
  "elements":[
    {
      "traversalIndex":0,
      "description":"Welcome",
      "label":"Welcome",
      "value":null,
      "traits":["staticText"],
      "identifier":"welcomeLabel",
      "hint":null,
      "frameX":16.0,
      "frameY":100.0,
      "frameWidth":361.0,
      "frameHeight":24.0,
      "activationPointX":196.5,
      "activationPointY":112.0,
      "customActions":[]
    },
    {
      "traversalIndex":1,
      "description":"Sign In",
      "label":"Sign In",
      "value":null,
      "traits":["button"],
      "identifier":"signInButton",
      "hint":"Double tap to sign in",
      "frameX":16.0,
      "frameY":140.0,
      "frameWidth":361.0,
      "frameHeight":44.0,
      "activationPointX":196.5,
      "activationPointY":162.0,
      "customActions":[]
    }
  ],
  "tree":[
    {"element":{"_0":0}},
    {"container":{"_0":[
      {"containerType":"semanticGroup","label":"Form","value":null,"identifier":null,
       "frameX":0.0,"frameY":88.0,"frameWidth":393.0,"frameHeight":600.0,"traits":[]},
      [{"element":{"_0":1}}]
    ]}}
  ]
}}}
```

The `tree` field is optional for backwards compatibility. When present, it provides the hierarchical container structure that the flat `elements` list does not capture.

### actionResult

Response to `activate`, `tap`, `increment`, `decrement`, or `performCustomAction` commands.

```json
{"actionResult":{"_0":{
  "success":true,
  "method":"syntheticTap",
  "message":null
}}}
```

Possible methods:
- `syntheticTap` - Tap synthesized via SafeCracker
- `syntheticLongPress` - Long press synthesized via SafeCracker
- `syntheticSwipe` - Swipe synthesized via SafeCracker
- `syntheticDrag` - Drag synthesized via SafeCracker
- `syntheticPinch` - Pinch gesture synthesized via SafeCracker
- `syntheticRotate` - Rotation gesture synthesized via SafeCracker
- `syntheticTwoFingerTap` - Two-finger tap synthesized via SafeCracker
- `accessibilityActivate` - Element's `accessibilityActivate()` was used
- `accessibilityIncrement` - Element's `accessibilityIncrement()` was called
- `accessibilityDecrement` - Element's `accessibilityDecrement()` was called
- `customAction` - Named custom action was invoked
- `elementNotFound` - Target element could not be found
- `elementDeallocated` - Element's underlying view was deallocated

The optional `message` field provides additional context, especially for failures:
```json
{"actionResult":{"_0":{
  "success":false,
  "method":"elementNotFound",
  "message":"Element is disabled (has 'notEnabled' trait)"
}}}
```

### screenshot

PNG screenshot of the current screen.

```json
{"screenshot":{"_0":{
  "pngData":"iVBORw0KGgo...",
  "width":393.0,
  "height":852.0,
  "timestamp":"2026-02-03T10:30:45.123Z"
}}}
```

The `pngData` field is base64-encoded PNG image data.

### pong

Response to `ping`.

```json
{"pong":{}}
```

### error

Error message.

```json
{"error":{"_0":"Root view not available"}}
```

## Data Types

### ServerInfo

| Field | Type | Description |
|-------|------|-------------|
| `protocolVersion` | `String` | Protocol version (e.g., "2.0") |
| `appName` | `String` | App display name |
| `bundleIdentifier` | `String` | App bundle identifier |
| `deviceName` | `String` | Device name (e.g., "iPhone 15 Pro") |
| `systemVersion` | `String` | iOS version (e.g., "17.0") |
| `screenWidth` | `Double` | Screen width in points |
| `screenHeight` | `Double` | Screen height in points |

### HierarchyPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | `ISO8601 Date` | When hierarchy was captured |
| `elements` | `[AccessibilityElementData]` | Flat list of all accessibility elements |
| `tree` | `[AccessibilityHierarchyNode]?` | Optional tree structure with containers |

### AccessibilityElementData

| Field | Type | Description |
|-------|------|-------------|
| `traversalIndex` | `Int` | VoiceOver reading order (0-based) |
| `description` | `String` | What VoiceOver reads |
| `label` | `String?` | Accessibility label |
| `value` | `String?` | Current value (for controls) |
| `traits` | `[String]` | Trait names (see Traits section) |
| `identifier` | `String?` | Accessibility identifier |
| `hint` | `String?` | Accessibility hint |
| `frameX` | `Double` | Frame origin X in points |
| `frameY` | `Double` | Frame origin Y in points |
| `frameWidth` | `Double` | Frame width in points |
| `frameHeight` | `Double` | Frame height in points |
| `activationPointX` | `Double` | Touch target X in points |
| `activationPointY` | `Double` | Touch target Y in points |
| `customActions` | `[String]` | Custom action names |

### AccessibilityHierarchyNode

Recursive enum representing the tree structure:

- `element(traversalIndex: Int)` - Leaf node referencing an element by its index in the flat `elements` array
- `container(AccessibilityContainerData, children: [AccessibilityHierarchyNode])` - Container node with metadata and children

### AccessibilityContainerData

| Field | Type | Description |
|-------|------|-------------|
| `containerType` | `String` | Container type (see below) |
| `label` | `String?` | Container's accessibility label |
| `value` | `String?` | Container's accessibility value |
| `identifier` | `String?` | Container's accessibility identifier |
| `frameX` | `Double` | Frame origin X in points |
| `frameY` | `Double` | Frame origin Y in points |
| `frameWidth` | `Double` | Frame width in points |
| `frameHeight` | `Double` | Frame height in points |
| `traits` | `[String]` | Trait names (e.g., `["tabBar"]`) |

Container types:
- `"semanticGroup"` - Semantic grouping (with optional label/value/identifier)
- `"list"` - List container (affects rotor navigation)
- `"landmark"` - Landmark container (affects rotor navigation)
- `"dataTable"` - Data table container

### ActionTarget

| Field | Type | Description |
|-------|------|-------------|
| `identifier` | `String?` | Element's accessibility identifier |
| `traversalIndex` | `Int?` | Element's traversal index |

At least one field should be provided. When both are provided, identifier is tried first.

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
| `distance` | `Double?` | Swipe distance in points (with direction) |
| `duration` | `Double?` | Duration in seconds (default: 0.15) |

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

### CustomActionTarget

| Field | Type | Description |
|-------|------|-------------|
| `elementTarget` | `ActionTarget` | Target element |
| `actionName` | `String` | Name of the custom action |

### ActionResult

| Field | Type | Description |
|-------|------|-------------|
| `success` | `Bool` | Whether action succeeded |
| `method` | `String` | How action was performed (see method values above) |
| `message` | `String?` | Additional context or error description |

### ScreenshotPayload

| Field | Type | Description |
|-------|------|-------------|
| `pngData` | `String` | Base64-encoded PNG image data |
| `width` | `Double` | Screen width in points |
| `height` | `Double` | Screen height in points |
| `timestamp` | `ISO8601 Date` | When screenshot was captured |

### Traits

Traits are human-readable strings converted from `UIAccessibilityTraits`:

| Trait String | UIAccessibilityTraits |
|--------------|----------------------|
| `"button"` | `.button` |
| `"link"` | `.link` |
| `"image"` | `.image` |
| `"staticText"` | `.staticText` |
| `"header"` | `.header` |
| `"adjustable"` | `.adjustable` |
| `"selected"` | `.selected` |
| `"tabBar"` | `.tabBar` |
| `"searchField"` | `.searchField` |
| `"playsSound"` | `.playsSound` |
| `"keyboardKey"` | `.keyboardKey` |
| `"summaryElement"` | `.summaryElement` |
| `"notEnabled"` | `.notEnabled` |
| `"updatesFrequently"` | `.updatesFrequently` |
| `"startsMediaSession"` | `.startsMediaSession` |
| `"allowsDirectInteraction"` | `.allowsDirectInteraction` |
| `"causesPageTurn"` | `.causesPageTurn` |

## Example Session

```
# Client connects to fd9a:6190:eed7::1:1455

# Server sends info
{"info":{"_0":{"protocolVersion":"2.0","appName":"TestApp","bundleIdentifier":"com.buttonheist.testapp","deviceName":"iPhone","systemVersion":"26.2.1","screenWidth":393.0,"screenHeight":852.0}}}

# Client subscribes to updates
{"subscribe":{}}

# Client requests hierarchy
{"requestHierarchy":{}}

# Server responds with hierarchy (flat + tree)
{"hierarchy":{"_0":{"timestamp":"2026-02-03T14:08:14.123Z","elements":[...],"tree":[...]}}}

# Client requests screenshot
{"requestScreenshot":{}}

# Server responds with screenshot
{"screenshot":{"_0":{"pngData":"iVBORw0KGgo...","width":393.0,"height":852.0,"timestamp":"2026-02-03T14:08:14.200Z"}}}

# Client activates a button
{"activate":{"_0":{"identifier":"loginButton"}}}

# Server confirms action
{"actionResult":{"_0":{"success":true,"method":"syntheticTap","message":null}}}

# Client increments a slider
{"increment":{"_0":{"identifier":"volumeSlider"}}}

# Server confirms
{"actionResult":{"_0":{"success":true,"method":"accessibilityIncrement","message":null}}}

# Client performs custom action
{"performCustomAction":{"_0":{"elementTarget":{"identifier":"messageCell"},"actionName":"Delete"}}}

# Server confirms
{"actionResult":{"_0":{"success":true,"method":"customAction","message":null}}}

# Client sends keepalive
{"ping":{}}

# Server responds
{"pong":{}}

# Server auto-pushes hierarchy change
{"hierarchy":{"_0":{"timestamp":"2026-02-03T14:08:15.500Z","elements":[...],"tree":[...]}}}
{"screenshot":{"_0":{"pngData":"...","width":393.0,"height":852.0,"timestamp":"2026-02-03T14:08:15.550Z"}}}
```

## Implementation Notes

### Port Configuration

The port is configured via Info.plist:

```xml
<key>InsideManPort</key>
<integer>1455</integer>
```

Or via environment variable `INSIDEMAN_PORT`.

### IPv6 Dual-Stack

The server binds to `::` (IPv6 any) with `IPV6_V6ONLY=0`, accepting:
- IPv4 connections (mapped to `::ffff:x.x.x.x`)
- IPv6 connections (USB tunnel, WiFi)

### Keepalive

Clients should send `ping` messages periodically (recommended: every 30 seconds) to detect connection loss.

### Error Recovery

If the TCP connection is lost, clients should:
1. Close the socket
2. Optionally attempt reconnection
3. Re-request hierarchy after reconnecting

### Hierarchy Change Detection

InsideMan uses hash-based change detection during polling:
1. Parse hierarchy at configurable interval (default: 1.0s)
2. Compute hash of the flat elements array
3. Only broadcast if hash differs from last broadcast
4. Screenshots are automatically captured and broadcast alongside hierarchy changes
