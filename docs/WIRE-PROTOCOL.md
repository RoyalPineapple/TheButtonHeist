# Accra Wire Protocol Specification

**Version**: 1.0

This document specifies the communication protocol between AccraHost (iOS) and AccraClient (macOS).

## Transport

- **Layer**: WebSocket over TCP
- **Discovery**: Bonjour/mDNS
- **Service Type**: `_a11ybridge._tcp`
- **Port**: Dynamic (assigned by OS, advertised via Bonjour)
- **Encoding**: JSON (UTF-8)

## Discovery

AccraHost advertises itself using Bonjour with:
- **Domain**: `local.`
- **Type**: `_a11ybridge._tcp`
- **Name**: `{AppName}-{DeviceName}`

Example: `MyApp-iPhone 15 Pro`

## Connection Lifecycle

```
Client                                    Server
   │                                         │
   │──────── WebSocket Connect ─────────────►│
   │                                         │
   │◄─────── ServerMessage.info ────────────│
   │                                         │
   │──────── ClientMessage.subscribe ───────►│
   │                                         │
   │◄─────── ServerMessage.hierarchy ────────│
   │              (repeated)                 │
   │                                         │
   │──────── ClientMessage.ping ────────────►│
   │◄─────── ServerMessage.pong ─────────────│
   │                                         │
   │──────── WebSocket Close ───────────────►│
   │                                         │
```

## Message Types

### Client → Server

#### requestHierarchy

Request a single hierarchy snapshot.

```json
{
  "type": "requestHierarchy"
}
```

#### subscribe

Subscribe to automatic hierarchy updates. Server will send `hierarchy` messages when changes are detected.

```json
{
  "type": "subscribe"
}
```

#### unsubscribe

Stop receiving automatic updates.

```json
{
  "type": "unsubscribe"
}
```

#### ping

Keepalive ping. Server responds with `pong`.

```json
{
  "type": "ping"
}
```

### Server → Client

#### info

Sent immediately after connection. Contains device and app metadata.

```json
{
  "type": "info",
  "payload": {
    "protocolVersion": "1.0",
    "appName": "MyApp",
    "bundleIdentifier": "com.example.myapp",
    "deviceName": "iPhone 15 Pro",
    "systemVersion": "17.0",
    "screenWidth": 393.0,
    "screenHeight": 852.0
  }
}
```

#### hierarchy

Accessibility hierarchy snapshot.

```json
{
  "type": "hierarchy",
  "payload": {
    "timestamp": "2026-02-01T10:30:45.123Z",
    "elements": [
      {
        "traversalIndex": 0,
        "description": "Welcome",
        "label": "Welcome",
        "value": null,
        "traits": ["staticText"],
        "identifier": "welcomeLabel",
        "hint": null,
        "frameX": 16.0,
        "frameY": 100.0,
        "frameWidth": 361.0,
        "frameHeight": 24.0,
        "activationPointX": 196.5,
        "activationPointY": 112.0,
        "customActions": []
      },
      {
        "traversalIndex": 1,
        "description": "Sign In",
        "label": "Sign In",
        "value": null,
        "traits": ["button"],
        "identifier": "signInButton",
        "hint": "Double tap to sign in",
        "frameX": 16.0,
        "frameY": 140.0,
        "frameWidth": 361.0,
        "frameHeight": 44.0,
        "activationPointX": 196.5,
        "activationPointY": 162.0,
        "customActions": []
      }
    ]
  }
}
```

#### pong

Response to `ping`.

```json
{
  "type": "pong"
}
```

#### error

Error message.

```json
{
  "type": "error",
  "message": "Root view not available"
}
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

## JSON Schemas

### ClientMessage Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["type"],
  "properties": {
    "type": {
      "type": "string",
      "enum": ["requestHierarchy", "subscribe", "unsubscribe", "ping"]
    }
  }
}
```

### ServerMessage Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "oneOf": [
    {
      "type": "object",
      "required": ["type", "payload"],
      "properties": {
        "type": { "const": "info" },
        "payload": { "$ref": "#/definitions/ServerInfo" }
      }
    },
    {
      "type": "object",
      "required": ["type", "payload"],
      "properties": {
        "type": { "const": "hierarchy" },
        "payload": { "$ref": "#/definitions/HierarchyPayload" }
      }
    },
    {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": { "const": "pong" }
      }
    },
    {
      "type": "object",
      "required": ["type", "message"],
      "properties": {
        "type": { "const": "error" },
        "message": { "type": "string" }
      }
    }
  ],
  "definitions": {
    "ServerInfo": {
      "type": "object",
      "required": ["protocolVersion", "appName", "deviceName", "systemVersion", "screenWidth", "screenHeight"],
      "properties": {
        "protocolVersion": { "type": "string" },
        "appName": { "type": "string" },
        "bundleIdentifier": { "type": ["string", "null"] },
        "deviceName": { "type": "string" },
        "systemVersion": { "type": "string" },
        "screenWidth": { "type": "number" },
        "screenHeight": { "type": "number" }
      }
    },
    "HierarchyPayload": {
      "type": "object",
      "required": ["timestamp", "elements"],
      "properties": {
        "timestamp": { "type": "string", "format": "date-time" },
        "elements": {
          "type": "array",
          "items": { "$ref": "#/definitions/AccessibilityElementData" }
        }
      }
    },
    "AccessibilityElementData": {
      "type": "object",
      "required": ["traversalIndex", "description", "traits", "frameX", "frameY", "frameWidth", "frameHeight", "activationPointX", "activationPointY", "customActions"],
      "properties": {
        "traversalIndex": { "type": "integer" },
        "description": { "type": "string" },
        "label": { "type": ["string", "null"] },
        "value": { "type": ["string", "null"] },
        "traits": { "type": "array", "items": { "type": "string" } },
        "identifier": { "type": ["string", "null"] },
        "hint": { "type": ["string", "null"] },
        "frameX": { "type": "number" },
        "frameY": { "type": "number" },
        "frameWidth": { "type": "number" },
        "frameHeight": { "type": "number" },
        "activationPointX": { "type": "number" },
        "activationPointY": { "type": "number" },
        "customActions": { "type": "array", "items": { "type": "string" } }
      }
    }
  }
}
```

## Implementation Notes

### Keepalive

Clients should send `ping` messages periodically (recommended: every 30 seconds) to detect connection loss.

### Polling Interval

AccraHost polls for changes at a configurable interval (default: 1.0 second). Changes are only broadcast when the hierarchy hash differs from the previous snapshot.

### Error Recovery

If the WebSocket connection is lost, clients should:
1. Update connection state to `.disconnected`
2. Optionally attempt reconnection
3. Re-subscribe after reconnecting

### Large Hierarchies

For apps with many accessibility elements, the JSON payload can be large. Consider:
- Filtering elements client-side
- Using `--once` mode in CLI for one-time snapshots
- Increasing polling interval to reduce bandwidth
