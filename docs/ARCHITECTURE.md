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
