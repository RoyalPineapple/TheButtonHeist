# Accra Documentation Suite Implementation Plan

## Overview

Create a comprehensive documentation suite for the Accra accessibility inspection toolkit, including contributor guidelines, detailed API documentation, architecture deep-dive, wire protocol specification, changelog, and design system documentation.

## Current State Analysis

The project has a solid README.md that covers:
- Project overview and features
- Architecture diagram
- Quick start guides
- CLI usage
- Basic API examples
- Development setup
- Troubleshooting

### What's Missing:
- No CONTRIBUTING.md for contributors
- No detailed API reference beyond examples
- No deep architecture documentation
- Wire protocol lacks JSON schemas
- No CHANGELOG.md
- No design system documentation for Inspector

## Desired End State

After implementation:
```
accra/
├── README.md                    # (enhanced) Main entry point
├── CONTRIBUTING.md              # Contributor guidelines
├── CHANGELOG.md                 # Version history
├── LICENSE                      # (exists) MIT license
└── docs/
    ├── API.md                   # Detailed API reference
    ├── ARCHITECTURE.md          # System design deep-dive
    ├── WIRE-PROTOCOL.md         # Complete protocol spec
    └── DESIGN-SYSTEM.md         # Inspector UI documentation
```

### Verification:
- All documentation files exist and are properly linked
- README.md includes navigation to docs/
- All code examples compile (verified by reading source)
- Cross-references between documents work

## What We're NOT Doing

- Not adding automated documentation generation (DocC, etc.)
- Not creating a documentation website
- Not writing tutorials or guides beyond what exists
- Not adding inline code documentation/comments
- Not creating video content or screenshots

## Implementation Approach

Create documentation in dependency order: foundational docs first (CONTRIBUTING, CHANGELOG), then technical docs (ARCHITECTURE, WIRE-PROTOCOL, API), and finally specialized docs (DESIGN-SYSTEM). Update README last to link everything together.

---

## Phase 1: Foundation Documents

### Overview
Create contributor guidelines and changelog to establish project governance and history.

### Changes Required:

#### 1. CONTRIBUTING.md
**File**: `CONTRIBUTING.md`

```markdown
# Contributing to Accra

Thank you for your interest in contributing to Accra!

## Development Setup

### Prerequisites

- Xcode 15+
- [Tuist](https://tuist.io) for project generation
- iOS 17+ device or simulator
- macOS 14+

### Getting Started

1. Clone the repository
2. Install Tuist: `curl -Ls https://install.tuist.io | bash`
3. Generate the Xcode project: `tuist generate`
4. Open `Accra.xcworkspace`

## Project Structure

| Directory | Description |
|-----------|-------------|
| `AccraCore/Sources/AccraCore/` | Shared types and protocol messages |
| `AccraCore/Sources/AccraHost/` | iOS server framework |
| `AccraCore/Sources/AccraClient/` | macOS client library |
| `AccraInspector/Sources/` | macOS GUI application |
| `AccraCLI/` | Command-line tool (SPM package) |
| `TestApp/` | Sample iOS applications |

## Code Style

### Swift

- Use Swift's standard naming conventions
- Prefer `@MainActor` for UI-related code
- Use explicit access control (`public`, `internal`, `private`)
- Keep files focused on a single responsibility

### Formatting

- 4-space indentation
- Opening braces on same line
- No trailing whitespace

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes

### Commit Messages

Write clear, concise commit messages:
- Use present tense ("Add feature" not "Added feature")
- Keep the first line under 72 characters
- Reference issues when applicable

### Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Test on both iOS device/simulator and macOS
4. Submit a pull request with:
   - Clear description of changes
   - Any relevant issue references
   - Screenshots for UI changes

## Testing

### Building All Targets

```bash
# Generate project
tuist generate

# Build frameworks
xcodebuild -workspace Accra.xcworkspace -scheme AccraCore build
xcodebuild -workspace Accra.xcworkspace -scheme AccraHost \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcodebuild -workspace Accra.xcworkspace -scheme AccraClient build

# Build apps
xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector build
xcodebuild -workspace Accra.xcworkspace -scheme TestApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# CLI
cd AccraCLI && swift build
```

### Manual Testing

1. Run TestApp on iOS simulator
2. Run AccraInspector on macOS
3. Verify device discovery works
4. Verify hierarchy updates in real-time

## Module Guidelines

### AccraCore

- Keep types `Codable` and cross-platform compatible
- Avoid UIKit/AppKit imports
- Document all public types

### AccraHost

- iOS-only, UIKit is allowed
- Run all operations on `@MainActor`
- Use Network framework for WebSocket

### AccraClient

- macOS-only
- Provide both `@Published` properties and callbacks
- Handle connection lifecycle gracefully

### AccraInspector

- Follow the design system in `docs/DESIGN-SYSTEM.md`
- Use semantic colors and typography tokens
- Keep views small and composable

## Questions?

Open an issue for questions or discussion.
```

#### 2. CHANGELOG.md
**File**: `CHANGELOG.md`

```markdown
# Changelog

All notable changes to Accra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial public release
- AccraCore: Cross-platform shared types and wire protocol
- AccraHost: iOS server framework with Bonjour discovery
- AccraClient: macOS client library with SwiftUI support
- AccraInspector: macOS GUI application for visual inspection
- AccraCLI: Unix-standard command-line tool
- TestApp: Sample SwiftUI and UIKit applications
- Documentation suite

### Technical Details
- Wire protocol version: 1.0
- Bonjour service type: `_a11ybridge._tcp`
- Minimum iOS: 17.0
- Minimum macOS: 14.0
```

### Success Criteria:

#### Automated Verification:
- [x] Files exist: `ls CONTRIBUTING.md CHANGELOG.md`
- [x] Markdown is valid (no syntax errors)

#### Manual Verification:
- [ ] CONTRIBUTING.md covers all necessary topics for new contributors
- [ ] CHANGELOG.md format follows Keep a Changelog standard

---

## Phase 2: Architecture Documentation

### Overview
Create detailed architecture documentation explaining system design, component interactions, and data flow.

### Changes Required:

#### 1. docs/ARCHITECTURE.md
**File**: `docs/ARCHITECTURE.md`

```markdown
# Accra Architecture

This document describes the internal architecture of Accra and how its components interact.

## System Overview

Accra is a distributed system with two main components:

1. **AccraHost** - An iOS framework embedded in the app being inspected
2. **AccraClient** - A macOS library that connects to and receives data from AccraHost

```
┌─────────────────────────────────────────────────────────────────────┐
│                              macOS                                   │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Inspector  │  │     CLI      │  │  Your Tool   │              │
│  │     (GUI)    │  │              │  │              │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                       │
│         └─────────────────┼─────────────────┘                       │
│                           │                                          │
│                  ┌────────┴────────┐                                │
│                  │   AccraClient   │                                │
│                  │   (Framework)   │                                │
│                  └────────┬────────┘                                │
│                           │                                          │
│            ┌──────────────┼──────────────┐                          │
│            │              │              │                          │
│      ┌─────┴─────┐  ┌─────┴─────┐  ┌─────┴─────┐                   │
│      │  Device   │  │  Device   │  │ WebSocket │                   │
│      │ Discovery │  │Connection │  │  Client   │                   │
│      │(NWBrowser)│  │   Mgmt    │  │           │                   │
│      └───────────┘  └───────────┘  └─────┬─────┘                   │
└──────────────────────────────────────────┼──────────────────────────┘
                                           │
                              Local Network (Bonjour + TCP)
                                           │
┌──────────────────────────────────────────┼──────────────────────────┐
│                           ┌──────────────┴──────────────┐           │
│                           │         AccraHost           │           │
│                           │        (Framework)          │           │
│                           └──────────────┬──────────────┘           │
│                                          │                          │
│                  ┌───────────────────────┼───────────────────────┐  │
│                  │                       │                       │  │
│           ┌──────┴──────┐         ┌──────┴──────┐         ┌──────┴──────┐
│           │  NetService │         │ NWListener  │         │   A11y      │
│           │  (Bonjour)  │         │ (WebSocket) │         │   Parser    │
│           └─────────────┘         └─────────────┘         └─────────────┘
│                                                                      │
│                              iOS Device                              │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Details

### AccraCore

**Purpose**: Shared types and protocol definitions for cross-platform communication.

**Key Types**:
- `ClientMessage` - Messages from client to server
- `ServerMessage` - Messages from server to client
- `AccessibilityElementData` - Accessibility element representation
- `HierarchyPayload` - Container for hierarchy snapshots
- `ServerInfo` - Device and app metadata

**Design Decisions**:
- All types are `Codable` for JSON serialization
- No platform-specific imports (UIKit/AppKit)
- Protocol version included for future compatibility

### AccraHost

**Purpose**: iOS server that captures and broadcasts accessibility hierarchy.

**Architecture**:
```
AccraHost (singleton)
├── NWListener (WebSocket server)
│   └── NWConnection[] (connected clients)
├── NetService (Bonjour advertisement)
├── AccessibilityHierarchyParser (from AccessibilitySnapshot)
└── Polling Timer (hierarchy change detection)
```

**Threading Model**:
- Entire class marked `@MainActor`
- All UIKit operations on main thread
- Network callbacks dispatch to main actor

**Lifecycle**:
1. `start()` - Create listener, begin advertising
2. `startPolling()` - Enable automatic updates
3. Client connects → send `ServerInfo`
4. Client subscribes → add to broadcast list
5. Poll timer fires → compare hierarchy hash → broadcast if changed
6. `stop()` - Cancel connections, stop advertising

### AccraClient

**Purpose**: macOS client for discovering and connecting to AccraHost instances.

**Architecture**:
```
AccraClient (ObservableObject)
├── DeviceDiscovery
│   └── NWBrowser (Bonjour browsing)
├── DeviceConnection
│   └── NWConnection (WebSocket client)
└── Published Properties
    ├── discoveredDevices: [DiscoveredDevice]
    ├── connectionState: ConnectionState
    ├── currentHierarchy: HierarchyPayload?
    └── serverInfo: ServerInfo?
```

**Dual API Design**:

1. **SwiftUI (Reactive)**: `@Published` properties trigger view updates
2. **Callbacks (Imperative)**: Closures for non-SwiftUI usage

**Connection State Machine**:
```
disconnected ──connect()──► connecting ──success──► connected
     ▲                          │                      │
     │                          │                      │
     └────────────disconnect()──┴──────────failure─────┘
```

## Data Flow

### Discovery Flow

```
1. AccraHost.start()
   └── NetService.publish("_a11ybridge._tcp")

2. AccraClient.startDiscovery()
   └── NWBrowser.start(for: "_a11ybridge._tcp")

3. NWBrowser finds service
   └── AccraClient.discoveredDevices.append(device)
```

### Connection Flow

```
1. AccraClient.connect(to: device)
   └── NWConnection(to: endpoint, using: websocket)

2. Connection established
   └── AccraHost sends ServerMessage.info(serverInfo)

3. AccraClient receives info
   └── serverInfo = info
   └── connectionState = .connected
   └── send(ClientMessage.subscribe)

4. AccraHost adds to subscribers
   └── subscribedConnections.insert(connection)
```

### Hierarchy Update Flow

```
1. Polling timer fires (or notifyChange() called)

2. AccraHost.checkForChanges()
   └── parser.parseAccessibilityElements(in: rootView)
   └── Convert to AccessibilityElementData[]
   └── Compute hash

3. If hash changed:
   └── Create HierarchyPayload(timestamp, elements)
   └── For each subscribed connection:
       └── send(ServerMessage.hierarchy(payload))

4. AccraClient receives hierarchy
   └── currentHierarchy = payload
   └── onHierarchyUpdate?(payload)
```

## Accessibility Parsing

AccraHost uses [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) to parse the UIKit accessibility tree.

**Process**:
1. Get root view from key window
2. Parser traverses view hierarchy
3. Each `AccessibilityMarker` converted to `AccessibilityElementData`
4. Traits converted from `UIAccessibilityTraits` to string array

**Trait Mapping**:
| UIAccessibilityTraits | String |
|----------------------|--------|
| `.button` | "button" |
| `.link` | "link" |
| `.image` | "image" |
| `.staticText` | "staticText" |
| `.header` | "header" |
| `.adjustable` | "adjustable" |
| `.selected` | "selected" |
| ... | ... |

## Network Protocol

See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for complete protocol specification.

**Summary**:
- Transport: WebSocket over TCP
- Discovery: Bonjour/mDNS (`_a11ybridge._tcp`)
- Encoding: JSON
- Port: Dynamic (advertised via Bonjour)

## Threading Considerations

### AccraHost (iOS)
- `@MainActor` for UIKit compatibility
- Parser must run on main thread
- Network callbacks dispatched to main

### AccraClient (macOS)
- `@MainActor` for SwiftUI `@Published` properties
- Discovery and connection on main thread
- Safe for use from SwiftUI views

## Error Handling

### Connection Errors
- Network unavailable → `.failed("Network error")`
- Host unreachable → `.failed("Connection refused")`
- Unexpected disconnect → `onDisconnected?(error)`

### Protocol Errors
- Invalid JSON → Logged, message dropped
- Unknown message type → Logged, message dropped
- Missing required field → Error response sent

## Future Considerations

1. **Multiple Device Connections**: AccraClient currently supports one connection
2. **Connection Recovery**: No automatic reconnection on network change
3. **Binary Protocol**: JSON adds overhead for large hierarchies
4. **Simulator Detection**: Different behavior for simulator vs device
```

### Success Criteria:

#### Automated Verification:
- [x] File exists: `ls docs/ARCHITECTURE.md`
- [x] Directory created: `ls -la docs/`

#### Manual Verification:
- [ ] Diagrams render correctly in markdown preview
- [ ] All component descriptions are accurate
- [ ] Data flow descriptions match implementation

---

## Phase 3: Wire Protocol Specification

### Overview
Create complete wire protocol documentation with JSON schemas and examples.

### Changes Required:

#### 1. docs/WIRE-PROTOCOL.md
**File**: `docs/WIRE-PROTOCOL.md`

```markdown
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
```

### Success Criteria:

#### Automated Verification:
- [x] File exists: `ls docs/WIRE-PROTOCOL.md`
- [x] JSON schemas are valid JSON

#### Manual Verification:
- [ ] All message types documented
- [ ] JSON examples match actual protocol
- [ ] Schemas match AccraCore/Sources/AccraCore/Messages.swift

---

## Phase 4: API Documentation

### Overview
Create detailed API reference for AccraHost and AccraClient public interfaces.

### Changes Required:

#### 1. docs/API.md
**File**: `docs/API.md`

```markdown
# Accra API Reference

Complete API documentation for AccraHost (iOS) and AccraClient (macOS).

## AccraHost

**Import**: `import AccraHost`
**Platform**: iOS 17.0+
**Location**: `AccraCore/Sources/AccraHost/AccraHost.swift`

### AccraHost

Main server class. Use the shared singleton instance.

```swift
@MainActor
public final class AccraHost
```

#### Properties

##### shared

```swift
public static let shared: AccraHost
```

Singleton instance. All operations should go through this instance.

##### isRunning

```swift
public private(set) var isRunning: Bool
```

Whether the server is currently running.

#### Methods

##### start()

```swift
public func start(port: UInt16 = 0) throws
```

Start the WebSocket server and begin Bonjour advertisement.

**Parameters**:
- `port`: Port to listen on. Use `0` for automatic port selection (recommended).

**Throws**: Network errors if the listener fails to start.

**Example**:
```swift
try AccraHost.shared.start()
```

##### stop()

```swift
public func stop()
```

Stop the server, disconnect all clients, and stop Bonjour advertisement.

**Example**:
```swift
AccraHost.shared.stop()
```

##### startPolling(interval:)

```swift
public func startPolling(interval: TimeInterval = 1.0)
```

Enable automatic polling for accessibility changes.

**Parameters**:
- `interval`: Polling interval in seconds. Minimum 0.5 seconds.

**Example**:
```swift
AccraHost.shared.startPolling(interval: 0.5)
```

##### stopPolling()

```swift
public func stopPolling()
```

Stop automatic polling.

##### notifyChange()

```swift
public func notifyChange()
```

Manually trigger a hierarchy broadcast to subscribed clients. Useful for notifying clients of changes outside the normal polling cycle.

**Example**:
```swift
// After a significant UI change
AccraHost.shared.notifyChange()
```

---

## AccraClient

**Import**: `import AccraClient`
**Platform**: macOS 14.0+
**Location**: `AccraCore/Sources/AccraClient/AccraClient.swift`

### AccraClient

Main client class. Conforms to `ObservableObject` for SwiftUI integration.

```swift
@MainActor
public final class AccraClient: ObservableObject
```

#### Published Properties

##### discoveredDevices

```swift
@Published public private(set) var discoveredDevices: [DiscoveredDevice]
```

Devices found via Bonjour discovery. Updated automatically when discovery is active.

##### connectionState

```swift
@Published public private(set) var connectionState: ConnectionState
```

Current connection state. See `ConnectionState` enum.

##### currentHierarchy

```swift
@Published public private(set) var currentHierarchy: HierarchyPayload?
```

Most recent accessibility hierarchy received from the connected device.

##### serverInfo

```swift
@Published public private(set) var serverInfo: ServerInfo?
```

Server information received after connecting.

#### Callback Properties

For non-SwiftUI usage, set these callbacks to receive events.

##### onDeviceDiscovered

```swift
public var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
```

Called when a new device is discovered.

##### onDeviceLost

```swift
public var onDeviceLost: ((DiscoveredDevice) -> Void)?
```

Called when a device is no longer available.

##### onConnected

```swift
public var onConnected: ((ServerInfo) -> Void)?
```

Called when connection is established and server info received.

##### onHierarchyUpdate

```swift
public var onHierarchyUpdate: ((HierarchyPayload) -> Void)?
```

Called when a new hierarchy is received.

##### onDisconnected

```swift
public var onDisconnected: ((Error?) -> Void)?
```

Called when disconnected. Error is nil for clean disconnections.

#### Methods

##### init()

```swift
public init()
```

Create a new client instance.

##### startDiscovery()

```swift
public func startDiscovery()
```

Begin discovering devices via Bonjour.

**Example**:
```swift
let client = AccraClient()
client.startDiscovery()
```

##### stopDiscovery()

```swift
public func stopDiscovery()
```

Stop device discovery.

##### connect(to:)

```swift
public func connect(to device: DiscoveredDevice)
```

Connect to a discovered device.

**Parameters**:
- `device`: Device to connect to (from `discoveredDevices`).

**Example**:
```swift
if let device = client.discoveredDevices.first {
    client.connect(to: device)
}
```

##### disconnect()

```swift
public func disconnect()
```

Disconnect from the current device.

##### requestHierarchy()

```swift
public func requestHierarchy()
```

Request a single hierarchy snapshot. Useful when not subscribed to automatic updates.

---

## AccraCore Types

**Import**: `import AccraCore`
**Platform**: iOS 17.0+ / macOS 14.0+
**Location**: `AccraCore/Sources/AccraCore/Messages.swift`

### ConnectionState

```swift
public enum ConnectionState: Equatable
```

Connection state enumeration.

#### Cases

- `disconnected` - No active connection
- `connecting` - Connection in progress
- `connected` - Connected to a device
- `failed(String)` - Connection failed with error message

### DiscoveredDevice

```swift
public struct DiscoveredDevice: Identifiable, Hashable
```

Represents a discovered AccraHost device.

#### Properties

- `id: String` - Unique identifier
- `name: String` - Device display name
- `endpoint: NWEndpoint` - Network endpoint for connection

### ServerInfo

```swift
public struct ServerInfo: Codable, Equatable
```

Device and app metadata received after connecting.

#### Properties

- `protocolVersion: String` - Protocol version
- `appName: String` - App display name
- `bundleIdentifier: String?` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points

### HierarchyPayload

```swift
public struct HierarchyPayload: Codable, Equatable
```

Container for accessibility hierarchy snapshot.

#### Properties

- `timestamp: Date` - When the hierarchy was captured
- `elements: [AccessibilityElementData]` - Accessibility elements

### AccessibilityElementData

```swift
public struct AccessibilityElementData: Codable, Equatable, Hashable, Identifiable
```

Represents a single accessibility element.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `Int` | Computed from `traversalIndex` |
| `traversalIndex` | `Int` | VoiceOver reading order |
| `description` | `String` | VoiceOver description |
| `label` | `String?` | Accessibility label |
| `value` | `String?` | Current value |
| `traits` | `[String]` | Trait names |
| `identifier` | `String?` | Accessibility identifier |
| `hint` | `String?` | Accessibility hint |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |
| `activationPointX` | `Double` | Touch target X |
| `activationPointY` | `Double` | Touch target Y |
| `customActions` | `[String]` | Custom action names |

#### Computed Properties

##### frame

```swift
public var frame: CGRect
```

Frame as CGRect.

##### activationPoint

```swift
public var activationPoint: CGPoint
```

Activation point as CGPoint.

---

## Usage Examples

### SwiftUI Integration

```swift
import SwiftUI
import AccraClient
import AccraCore

struct InspectorView: View {
    @StateObject private var client = AccraClient()

    var body: some View {
        NavigationSplitView {
            // Device list
            List(client.discoveredDevices, selection: $selectedDevice) { device in
                Text(device.name)
            }
        } detail: {
            // Hierarchy display
            if let hierarchy = client.currentHierarchy {
                List(hierarchy.elements) { element in
                    VStack(alignment: .leading) {
                        Text(element.description)
                        Text(element.traits.joined(separator: ", "))
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            client.startDiscovery()
        }
        .onChange(of: selectedDevice) { device in
            if let device {
                client.connect(to: device)
            }
        }
    }

    @State private var selectedDevice: DiscoveredDevice?
}
```

### Callback-Based Usage

```swift
import AccraClient
import AccraCore

class Inspector {
    let client = AccraClient()

    init() {
        client.onDeviceDiscovered = { [weak self] device in
            print("Found: \(device.name)")
            self?.client.connect(to: device)
        }

        client.onConnected = { info in
            print("Connected to \(info.appName) on \(info.deviceName)")
        }

        client.onHierarchyUpdate = { payload in
            print("Received \(payload.elements.count) elements")
            for element in payload.elements {
                print("  \(element.traversalIndex): \(element.description)")
            }
        }

        client.onDisconnected = { error in
            if let error {
                print("Disconnected with error: \(error)")
            } else {
                print("Disconnected")
            }
        }
    }

    func start() {
        client.startDiscovery()
    }
}
```

### iOS App Integration

```swift
import SwiftUI
import AccraHost

@main
struct MyApp: App {
    init() {
        #if DEBUG
        // Only enable in debug builds
        try? AccraHost.shared.start()
        AccraHost.shared.startPolling(interval: 1.0)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```
```

### Success Criteria:

#### Automated Verification:
- [x] File exists: `ls docs/API.md`

#### Manual Verification:
- [ ] All public APIs documented
- [ ] Examples compile (verified against source)
- [ ] Parameter descriptions are accurate

---

## Phase 5: Design System Documentation

### Overview
Document the AccraInspector design system including colors, typography, and spacing.

### Changes Required:

#### 1. docs/DESIGN-SYSTEM.md
**File**: `docs/DESIGN-SYSTEM.md`

```markdown
# Accra Inspector Design System

Design tokens and guidelines for the AccraInspector macOS application.

## Overview

AccraInspector uses a typography-driven design system with semantic tokens for colors, fonts, and spacing. All design values are defined in the `Design/` directory.

## File Structure

```
AccraInspector/Sources/Design/
├── Colors.swift      # Semantic color definitions
├── Typography.swift  # Font definitions
└── Spacing.swift     # Layout constants
```

## Colors

**Location**: `AccraInspector/Sources/Design/Colors.swift`

Colors are accessed via the `Color.Tree` namespace extension.

### Semantic Colors

| Token | Usage |
|-------|-------|
| `Color.Tree.textPrimary` | Primary text, element labels |
| `Color.Tree.textSecondary` | Secondary text, metadata |
| `Color.Tree.textTertiary` | Tertiary text, hints |
| `Color.Tree.background` | View backgrounds |
| `Color.Tree.rowHover` | Row hover state |
| `Color.Tree.rowSelected` | Row selection state |

### Usage

```swift
Text(element.description)
    .foregroundStyle(Color.Tree.textPrimary)

Text(element.traits.joined(separator: ", "))
    .foregroundStyle(Color.Tree.textSecondary)
```

### Color Values

Colors adapt to light/dark mode using semantic system colors or custom asset catalog colors.

## Typography

**Location**: `AccraInspector/Sources/Design/Typography.swift`

Fonts are accessed via the `Font.Tree` namespace extension.

### Font Tokens

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `Font.Tree.elementLabel` | 13pt | Regular | Element descriptions |
| `Font.Tree.elementTrait` | 11pt | Regular, Monospaced | Trait badges |
| `Font.Tree.searchInput` | 14pt | Regular | Search field |
| `Font.Tree.detailSectionTitle` | Caption | Regular | Detail panel headers |

### Usage

```swift
Text(element.description)
    .font(.Tree.elementLabel)

Text(trait)
    .font(.Tree.elementTrait)
```

## Spacing

**Location**: `AccraInspector/Sources/Design/Spacing.swift`

Spacing constants are defined in the `TreeSpacing` enum.

### Spacing Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `TreeSpacing.unit` | 8pt | Base unit for calculations |
| `TreeSpacing.rowHeight` | 28pt | List row height |
| `TreeSpacing.searchHeight` | 32pt | Search bar height |

### Usage

```swift
List {
    ForEach(elements) { element in
        ElementRow(element: element)
    }
}
.listRowInsets(EdgeInsets(
    top: TreeSpacing.unit / 2,
    leading: TreeSpacing.unit,
    bottom: TreeSpacing.unit / 2,
    trailing: TreeSpacing.unit
))
```

## Component Patterns

### Element Row

Standard row for displaying accessibility elements:

```swift
struct ElementRow: View {
    let element: AccessibilityElementData

    var body: some View {
        HStack(spacing: TreeSpacing.unit) {
            // Index badge
            Text(String(format: "%02d", element.traversalIndex))
                .font(.Tree.elementTrait)
                .foregroundStyle(Color.Tree.textTertiary)

            // Traits
            HStack(spacing: 4) {
                ForEach(element.traits, id: \.self) { trait in
                    Text(trait)
                        .font(.Tree.elementTrait)
                        .foregroundStyle(Color.Tree.textSecondary)
                }
            }

            // Label
            Text(element.description)
                .font(.Tree.elementLabel)
                .foregroundStyle(Color.Tree.textPrimary)
        }
        .frame(height: TreeSpacing.rowHeight)
    }
}
```

### Search Bar

Consistent search bar styling:

```swift
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.Tree.textTertiary)

            TextField("Search", text: $text)
                .font(.Tree.searchInput)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, TreeSpacing.unit)
        .frame(height: TreeSpacing.searchHeight)
        .background(Color.Tree.background)
    }
}
```

### Detail Panel

Section styling for detail views:

```swift
struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TreeSpacing.unit / 2) {
            Text(title)
                .font(.Tree.detailSectionTitle)
                .foregroundStyle(Color.Tree.textTertiary)

            content
        }
    }
}
```

## Guidelines

### Consistency

- Always use design tokens instead of hardcoded values
- Use semantic color names that describe purpose, not appearance
- Maintain consistent spacing using `TreeSpacing.unit` multiples

### Accessibility

- Ensure sufficient color contrast in both light and dark modes
- Use Dynamic Type-compatible font sizes
- Provide proper accessibility labels for all interactive elements

### Adding New Tokens

When adding new design tokens:

1. Add to the appropriate file (`Colors.swift`, `Typography.swift`, or `Spacing.swift`)
2. Use the existing namespace extension pattern
3. Document the token's intended usage
4. Update this documentation
```

### Success Criteria:

#### Automated Verification:
- [x] File exists: `ls docs/DESIGN-SYSTEM.md`

#### Manual Verification:
- [ ] Token names match source code
- [ ] Usage examples are accurate
- [ ] Guidelines are clear and actionable

---

## Phase 6: Update README

### Overview
Add documentation links to the main README.

### Changes Required:

#### 1. Update README.md
**File**: `README.md`

Add a Documentation section after the Troubleshooting section:

```markdown
## Documentation

- [Contributing Guide](CONTRIBUTING.md) — How to contribute to Accra
- [Changelog](CHANGELOG.md) — Version history
- [Architecture](docs/ARCHITECTURE.md) — System design and data flow
- [Wire Protocol](docs/WIRE-PROTOCOL.md) — Complete protocol specification
- [API Reference](docs/API.md) — Detailed API documentation
- [Design System](docs/DESIGN-SYSTEM.md) — Inspector UI guidelines
```

### Success Criteria:

#### Automated Verification:
- [x] All linked files exist
- [x] Links are relative and correct

#### Manual Verification:
- [ ] Documentation section appears in logical location
- [ ] Links work when clicked in GitHub

---

## Testing Strategy

### Automated Verification
After all phases complete, verify:

```bash
# All files exist
ls CONTRIBUTING.md CHANGELOG.md docs/ARCHITECTURE.md docs/WIRE-PROTOCOL.md docs/API.md docs/DESIGN-SYSTEM.md

# Check for broken internal links
grep -r "\](docs/" README.md CONTRIBUTING.md docs/*.md
```

### Manual Verification
1. Open each markdown file in a preview tool
2. Verify diagrams render correctly
3. Check that code examples are syntactically correct
4. Verify internal links work
5. Review for accuracy against source code

## References

- Research document: `thoughts/shared/research/2026-02-01-accra-codebase-documentation.md`
- Existing README: `README.md`
- Source: `AccraCore/Sources/`
