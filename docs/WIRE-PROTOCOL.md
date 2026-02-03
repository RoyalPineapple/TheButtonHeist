# Accra Wire Protocol Specification

**Version**: 1.1

This document specifies the communication protocol between AccraHost (iOS) and clients (AccraClient, CLI, Python scripts).

## Transport

- **Layer**: TCP socket
- **Discovery**: Bonjour/mDNS (WiFi) or CoreDevice IPv6 tunnel (USB)
- **Service Type**: `_a11ybridge._tcp`
- **Port**: 1455 (configurable via Info.plist `AccraHostPort` key)
- **Encoding**: Newline-delimited JSON (UTF-8)
- **Socket**: IPv6 dual-stack (accepts both IPv4 and IPv6)

## Discovery Methods

### WiFi (Bonjour)
AccraHost advertises itself using Bonjour:
- **Domain**: `local.`
- **Type**: `_a11ybridge._tcp`
- **Name**: `{AppName}`

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
   │◄─────── info ───────────────────────────│
   │                                         │
   │──────── requestHierarchy ───────────────►│
   │◄─────── hierarchy ──────────────────────│
   │                                         │
   │──────── activate/tap ───────────────────►│
   │◄─────── actionResult ───────────────────│
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

### activate

Activate an element (equivalent to VoiceOver double-tap).

**By identifier:**
```json
{"activate":{"_0":{"identifier":"loginButton"}}}
```

**By traversal index:**
```json
{"activate":{"_0":{"traversalIndex":5}}}
```

### tap

Tap at coordinates or on an element.

**At coordinates:**
```json
{"tap":{"_0":{"pointX":196.5,"pointY":659.0}}}
```

**On element by identifier:**
```json
{"tap":{"_0":{"elementTarget":{"identifier":"submitButton"}}}}
```

**On element by index:**
```json
{"tap":{"_0":{"elementTarget":{"traversalIndex":3}}}}
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
  "protocolVersion":"1.0",
  "appName":"MyApp",
  "bundleIdentifier":"com.example.myapp",
  "deviceName":"iPhone 15 Pro",
  "systemVersion":"17.0",
  "screenWidth":393.0,
  "screenHeight":852.0
}}}
```

### hierarchy

Accessibility hierarchy snapshot.

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
  ]
}}}
```

### actionResult

Response to `activate` or `tap` commands.

```json
{"actionResult":{"_0":{
  "success":true,
  "method":"accessibilityActivate"
}}}
```

Possible methods:
- `accessibilityActivate` - Element's `accessibilityActivate()` returned true
- `tapGesture` - Tap gesture synthesized at activation point
- `coordinateTap` - Tap at specified coordinates

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
| `protocolVersion` | `String` | Protocol version (e.g., "1.0") |
| `appName` | `String` | App display name |
| `bundleIdentifier` | `String?` | App bundle identifier |
| `deviceName` | `String` | Device name (e.g., "iPhone 15 Pro") |
| `systemVersion` | `String` | iOS version (e.g., "17.0") |
| `screenWidth` | `Double` | Screen width in points |
| `screenHeight` | `Double` | Screen height in points |

### HierarchyPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | `ISO8601 Date` | When hierarchy was captured |
| `elements` | `[AccessibilityElementData]` | All accessibility elements |

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

### ActionResult

| Field | Type | Description |
|-------|------|-------------|
| `success` | `Bool` | Whether action succeeded |
| `method` | `String` | How action was performed |

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
{"info":{"_0":{"protocolVersion":"1.0","appName":"TestApp","bundleIdentifier":"com.accra.testapp","deviceName":"iPhone","systemVersion":"26.2.1","screenWidth":393.0,"screenHeight":852.0}}}

# Client requests hierarchy
{"requestHierarchy":{}}

# Server responds with hierarchy
{"hierarchy":{"_0":{"timestamp":"2026-02-03T14:08:14.123Z","elements":[...]}}}

# Client taps a button
{"activate":{"_0":{"identifier":"loginButton"}}}

# Server confirms action
{"actionResult":{"_0":{"success":true,"method":"accessibilityActivate"}}}

# Client sends keepalive
{"ping":{}}

# Server responds
{"pong":{}}
```

## Implementation Notes

### Port Configuration

The port is configured via Info.plist:

```xml
<key>AccraHostPort</key>
<integer>1455</integer>
```

Or via environment variable `ACCRA_HOST_PORT`.

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
