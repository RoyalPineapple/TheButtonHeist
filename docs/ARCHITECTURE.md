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
│      │  Device   │  │  Device   │  │    BSD    │                   │
│      │ Discovery │  │Connection │  │  Socket   │                   │
│      │(NWBrowser)│  │   Mgmt    │  │  Client   │                   │
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
│           ┌──────────────┬───────────────┼───────────────┐          │
│           │              │               │               │          │
│     ┌─────┴─────┐  ┌────┴──────┐  ┌─────┴─────┐  ┌─────┴─────┐    │
│     │ NetService│  │SimpleSocket│  │   A11y    │  │  Touch    │    │
│     │ (Bonjour) │  │Server(TCP)│  │  Parser   │  │ Injector  │    │
│     └───────────┘  └───────────┘  └───────────┘  └───────────┘    │
│                                                                      │
│                              iOS Device                              │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Details

### AccraCore

**Purpose**: Shared types and protocol definitions for cross-platform communication.

**Key Types**:
- `ClientMessage` - Messages from client to server (11 cases)
- `ServerMessage` - Messages from server to client (6 cases)
- `AccessibilityElementData` - Flat accessibility element representation
- `AccessibilityHierarchyNode` - Recursive tree structure with containers
- `AccessibilityContainerData` - Container metadata (type, label, frame, traits)
- `HierarchyPayload` - Container for hierarchy snapshots (flat list + optional tree)
- `ServerInfo` - Device and app metadata
- `ActionResult` - Action outcome with method and optional message
- `ScreenshotPayload` - Base64-encoded PNG with dimensions

**Design Decisions**:
- All types are `Codable` and `Sendable` for JSON serialization and concurrency safety
- No platform-specific imports (UIKit/AppKit)
- Protocol version 2.0 included for compatibility

### AccraHost

**Purpose**: iOS server that captures and broadcasts accessibility hierarchy and handles remote interaction.

**Architecture**:
```
AccraHost (singleton, @MainActor)
├── SimpleSocketServer (BSD socket TCP server, IPv6 dual-stack)
│   └── Client connections (file descriptors)
├── NetService (Bonjour advertisement)
├── AccessibilityHierarchyParser (from AccessibilitySnapshot submodule)
├── TouchInjector (synthetic tap system)
│   ├── SyntheticTouchFactory (UITouch creation via private APIs)
│   ├── SyntheticEventFactory (UIEvent manipulation)
│   └── IOHIDEventBuilder (low-level HID event creation via IOKit)
├── TapVisualizerView (visual tap feedback overlay)
├── Polling Timer (hierarchy change detection via hash comparison)
└── Debounce Timer (300ms debounce for accessibility notifications)
```

**Auto-Start Mechanism**:

AccraHost uses ObjC `+load` for automatic initialization:

```
AccraHostLoader/
├── AccraHostAutoStart.h  (public header)
└── AccraHostAutoStart.m  (+load implementation → AccraHost_autoStartFromLoad)
```

When the framework loads:
1. `+load` is called automatically by the runtime
2. Reads configuration from environment variables or Info.plist:
   - `ACCRA_HOST_DISABLE` / `AccraHostDisableAutoStart` - skip startup
   - `ACCRA_HOST_PORT` / `AccraHostPort` - server port (default: 0 = auto)
   - `ACCRA_HOST_POLLING_INTERVAL` / `AccraHostPollingInterval` - update interval (default: 1.0s, min: 0.5s)
3. Creates a Task on MainActor to configure and start AccraHost singleton
4. Begins polling for hierarchy changes

**Threading Model**:
- Entire class marked `@MainActor`
- All UIKit operations on main thread
- Network callbacks dispatch to main actor
- Socket accept/read on dedicated GCD queues

**TCP Server (SimpleSocketServer)**:
- BSD socket implementation using `socket()`, `bind()`, `listen()`, `accept()`
- IPv6 dual-stack socket (accepts both IPv4 and IPv6)
- Fixed port from configuration (default: 1455)
- Newline-delimited JSON protocol (0x0A separator)
- Multiple concurrent client support
- SIGPIPE handling to prevent crashes on closed connections

### Touch Injection System

**Purpose**: Synthesize tap events on the iOS device to allow remote interaction.

**Architecture**:
```
TouchInjector.tapWithResult(at: CGPoint)
│
├── 1. checkViewInteractivity(view)
│   ├── isUserInteractionEnabled
│   ├── isHidden / alpha check
│   ├── notEnabled accessibility trait
│   └── parent hierarchy walk
│
├── 2. injectTap() [Low-level - preferred]
│   ├── SyntheticTouchFactory.createTouch()    → UITouch via private APIs
│   ├── IOHIDEventBuilder.createEvent()        → IOHIDEvent via dlopen(IOKit)
│   ├── SyntheticEventFactory.createEventForTouch()  → Fresh UIEvent per phase
│   └── UIApplication.shared.sendEvent()       → began, then ended
│
└── 3. fallbackTap() [High-level - if injection fails]
    ├── accessibilityActivate()
    ├── UIControl.sendActions(for: .touchUpInside)
    └── Responder chain walk for UIControl
```

**TapResult enum** provides detailed failure information:
- `.success` - Tap dispatched successfully
- `.viewNotInteractive(reason:)` - View failed interactivity checks
- `.noViewAtPoint` - No view at the given coordinates
- `.noKeyWindow` - No key window available
- `.injectionFailed` - All injection methods failed

**iOS 26 Fix**: Creates a fresh `UIEvent` for each touch phase (began, ended) instead of reusing the same event object. iOS 26's stricter validation rejects reused events.

### Screenshot Capture

AccraHost captures screenshots using `UIGraphicsImageRenderer`:
1. Finds the foreground window scene
2. Uses `drawHierarchy(in:afterScreenUpdates:)` to capture the full visual hierarchy (including SwiftUI)
3. Encodes as PNG, then base64
4. Returns `ScreenshotPayload` with dimensions and timestamp
5. Screenshots are automatically broadcast alongside hierarchy changes during polling

### AccraClient

**Purpose**: macOS client for discovering and connecting to AccraHost instances.

**Architecture**:
```
AccraClient (ObservableObject, @MainActor)
├── DeviceDiscovery
│   └── NWBrowser (Bonjour browsing for "_a11ybridge._tcp")
├── DeviceConnection
│   ├── NWConnection (service resolution only)
│   └── BSD socket (actual data transport)
└── Published Properties
    ├── discoveredDevices: [DiscoveredDevice]
    ├── connectedDevice: DiscoveredDevice?
    ├── connectionState: ConnectionState
    ├── currentHierarchy: HierarchyPayload?
    ├── currentScreenshot: ScreenshotPayload?
    └── serverInfo: ServerInfo?
```

**Dual API Design**:

1. **SwiftUI (Reactive)**: `@Published` properties trigger view updates
2. **Callbacks (Imperative)**: Closures for CLI and non-SwiftUI usage
3. **Async/Await**: `waitForActionResult(timeout:)` and `waitForScreenshot(timeout:)` for scripting

**Auto-Subscribe on Connect**: When a connection is established, AccraClient automatically sends `subscribe`, `requestHierarchy`, and `requestScreenshot` messages.

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
   └── NWConnection resolves Bonjour service to host:port
   └── BSD socket connects to 127.0.0.1:port

2. TCP connection established
   └── AccraHost sends ServerMessage.info

3. AccraClient receives info
   └── serverInfo = info
   └── connectionState = .connected
   └── Sends: subscribe, requestHierarchy, requestScreenshot
```

### Hierarchy Update Flow

```
1. Polling timer fires (configurable interval, default 1.0s)

2. AccraHost.checkForChanges()
   └── parser.parseAccessibilityHierarchy(in: rootView)
   └── flattenToElements() → AccessibilityElementData[]
   └── Compute hash of elements array

3. If hash changed:
   └── Create HierarchyPayload(timestamp, elements, tree)
   └── Broadcast hierarchy to all connected clients
   └── Capture and broadcast screenshot
```

### Action Flow (tap/activate)

```
1. Client sends activate/tap message

2. AccraHost receives message
   └── Refresh hierarchy cache
   └── Find target element (by identifier or traversalIndex)
   └── Check element interactivity (traits-based)

3. TouchInjector.tapWithResult(at: activationPoint)
   └── Hit-test to find view at point
   └── Check view interactivity (enabled, visible, parents)
   └── Try synthetic event injection (UITouch + IOHIDEvent)
   └── Fall back to accessibilityActivate / sendActions

4. AccraHost sends actionResult
   └── success: true/false
   └── method: syntheticTap / accessibilityActivate / elementNotFound
   └── message: optional error description
   └── Show TapVisualizerView overlay on success
```

## Network Protocol

See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for complete protocol specification.

**Summary**:
- Protocol version: 2.0
- Transport: TCP socket (BSD sockets, not WebSocket)
- Discovery: Bonjour/mDNS (`_a11ybridge._tcp`) or USB IPv6 tunnel
- Encoding: Newline-delimited JSON (UTF-8)
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
- Hierarchy updates debounced by 300ms

### AccraClient (macOS)
- `@MainActor` for SwiftUI `@Published` properties
- NWBrowser for discovery on main queue
- BSD socket read loop on background queue
- Message processing dispatched to main actor

## Error Handling

### Connection Errors
- Network unavailable → `.failed("Network error")`
- Host unreachable → `.failed("Connection refused")`
- Unexpected disconnect → `onDisconnected?(error)`

### Protocol Errors
- Invalid JSON → Logged, message dropped
- Unknown message type → Logged, message dropped
- Missing required field → Error response sent

### Action Errors
- Element not found → `ActionResult(success: false, method: .elementNotFound)`
- Element not interactive → `ActionResult(success: false, message: "reason")`
- View not interactive → `TapResult.viewNotInteractive(reason:)`
- Injection failed → Falls back to high-level methods

## Configuration

### Environment Variables (highest priority)
| Variable | Description | Default |
|----------|-------------|---------|
| `ACCRA_HOST_DISABLE` | "true"/"1"/"yes" to disable auto-start | not set |
| `ACCRA_HOST_PORT` | Fixed port number, 0 = auto | 0 |
| `ACCRA_HOST_POLLING_INTERVAL` | Polling interval in seconds | 1.0 |

### Info.plist Keys (fallback)
```xml
<key>AccraHostPort</key>
<integer>1455</integer>
<key>AccraHostPollingInterval</key>
<real>1.0</real>
<key>AccraHostDisableAutoStart</key>
<false/>
<key>NSLocalNetworkUsageDescription</key>
<string>Accessibility inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_a11ybridge._tcp</string>
</array>
```
