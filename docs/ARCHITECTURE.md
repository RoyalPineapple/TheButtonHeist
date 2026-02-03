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
│  │   Inspector  │  │     CLI      │  │ Python/Shell │              │
│  │     (GUI)    │  │              │  │   Scripts    │              │
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
│      │  Device   │  │  Device   │  │    TCP    │                   │
│      │ Discovery │  │Connection │  │  Client   │                   │
│      │(NWBrowser)│  │   Mgmt    │  │           │                   │
│      └───────────┘  └───────────┘  └─────┬─────┘                   │
└──────────────────────────────────────────┼──────────────────────────┘
                                           │
                    WiFi (Bonjour + TCP) or USB (IPv6 + TCP)
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
│           │  NetService │         │SimpleSocket │         │   A11y      │
│           │  (Bonjour)  │         │Server (TCP) │         │   Parser    │
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
├── SimpleSocketServer (TCP server, IPv6 dual-stack)
│   └── Client connections (file descriptors)
├── NetService (Bonjour advertisement)
├── AccessibilityHierarchyParser (from AccessibilitySnapshot)
├── TouchInjector (tap synthesis)
└── Polling Timer (hierarchy change detection)
```

**Auto-Start Mechanism**:

AccraHost uses ObjC `+load` for automatic initialization:

```
AccraHostLoader/
├── AccraHostAutoStart.h  (public header)
└── AccraHostAutoStart.m  (+load implementation)
```

When the framework loads:
1. `+load` is called automatically by the runtime
2. Reads port from `AccraHostPort` in Info.plist (or env var)
3. Configures and starts AccraHost singleton
4. Begins polling for hierarchy changes

**Threading Model**:
- Entire class marked `@MainActor`
- All UIKit operations on main thread
- Network callbacks dispatch to main actor
- Socket I/O on dedicated GCD queues

**TCP Server (SimpleSocketServer)**:
- IPv6 dual-stack socket (accepts both IPv4 and IPv6)
- Fixed port from configuration (default: 1455)
- Newline-delimited JSON protocol
- Multiple concurrent client support

### AccraClient

**Purpose**: macOS client for discovering and connecting to AccraHost instances.

**Architecture**:
```
AccraClient (ObservableObject)
├── DeviceDiscovery
│   └── NWBrowser (Bonjour browsing)
├── DeviceConnection
│   └── NWConnection (TCP client)
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
1. AccraHost loads (ObjC +load)
   └── SimpleSocketServer.start(port: 1455)
   └── NetService.publish("_a11ybridge._tcp")

2. AccraClient.startDiscovery()
   └── NWBrowser.start(for: "_a11ybridge._tcp")

3. NWBrowser finds service
   └── AccraClient.discoveredDevices.append(device)
```

### Connection Flow

```
1. AccraClient.connect(to: device)
   └── NWConnection(to: endpoint)

2. TCP connection established
   └── AccraHost sends ServerMessage.info

3. AccraClient receives info
   └── serverInfo = info
   └── connectionState = .connected

4. AccraClient sends requestHierarchy
   └── AccraHost responds with hierarchy
```

### Hierarchy Update Flow

```
1. Polling timer fires (1.0 second interval)

2. AccraHost.checkForChanges()
   └── parser.parseAccessibilityElements(in: rootView)
   └── Convert to AccessibilityElementData[]
   └── Compute hash

3. If hash changed:
   └── Create HierarchyPayload(timestamp, elements)
   └── Broadcast to all connected clients
```

### Action Flow (tap/activate)

```
1. Client sends activate/tap message

2. AccraHost receives message
   └── Find target element (by identifier or index)
   └── Try accessibilityActivate() first
   └── Fall back to tap gesture if needed

3. AccraHost sends actionResult
   └── success: true/false
   └── method: "accessibilityActivate" or "tapGesture"
```

## Network Protocol

See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for complete protocol specification.

**Summary**:
- Transport: TCP socket (not WebSocket)
- Discovery: Bonjour/mDNS (`_a11ybridge._tcp`) or USB IPv6 tunnel
- Encoding: Newline-delimited JSON
- Port: 1455 (configurable via Info.plist)

## Connection Methods

### WiFi (Bonjour)
- Service advertised via mDNS
- Client discovers via NWBrowser
- TCP connection to advertised endpoint

### USB (CoreDevice IPv6 Tunnel)
- macOS creates IPv6 tunnel for USB-connected devices
- Device address: `fd{prefix}::1` (e.g., `fd9a:6190:eed7::1`)
- Direct TCP connection to port 1455
- Bypasses WiFi/VPN issues

## Threading Considerations

### AccraHost (iOS)
- `@MainActor` for UIKit compatibility
- Parser must run on main thread
- Socket accept/read on GCD queues
- Message handling dispatched to main

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

## Configuration

### Port Configuration Priority
1. `ACCRA_HOST_PORT` environment variable
2. `AccraHostPort` key in Info.plist
3. Default: 1455

### Required Info.plist Keys
```xml
<key>AccraHostPort</key>
<integer>1455</integer>
<key>NSLocalNetworkUsageDescription</key>
<string>Accessibility inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_a11ybridge._tcp</string>
</array>
```

## Future Considerations

1. **Multiple Device Connections**: AccraClient currently supports one connection
2. **Connection Recovery**: No automatic reconnection on network change
3. **Binary Protocol**: JSON adds overhead for large hierarchies
4. **Screenshot Capture**: Add screenshot-with-overlay capability
