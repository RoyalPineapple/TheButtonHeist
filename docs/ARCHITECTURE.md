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
│     │ NetService│  │SimpleSocket│  │   A11y    │  │ SimFinger │    │
│     │ (Bonjour) │  │Server(TCP)│  │  Parser   │  │(Gestures) │    │
│     └───────────┘  └───────────┘  └───────────┘  └───────────┘    │
│                                                                      │
│                              iOS Device                              │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Details

### AccraCore

**Purpose**: Shared types and protocol definitions for cross-platform communication.

**Key Types**:
- `ClientMessage` - Messages from client to server (15 cases including 7 touch gestures)
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
├── SimFinger (multi-touch gesture simulation)
│   ├── SyntheticTouchFactory (UITouch creation via private APIs)
│   ├── SyntheticEventFactory (UIEvent manipulation)
│   └── IOHIDEventBuilder (multi-finger HID event creation via IOKit)
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

### SimFinger (Touch Gesture System)

**Purpose**: Synthesize touch gestures on the iOS device to allow remote interaction. Supports single-finger gestures (tap, long press, swipe, drag) and multi-touch gestures (pinch, rotate, two-finger tap).

**Architecture**:
```
SimFinger (stateful, @MainActor)
│
├── Single-Finger Gestures
│   ├── tap(at:)           → touchDown + touchUp
│   ├── longPress(at:)     → touchDown + delay + touchUp
│   ├── swipe(from:to:)    → touchDown + interpolated moves + touchUp
│   └── drag(from:to:)     → touchDown + interpolated moves + touchUp (slower)
│
├── Multi-Touch Gestures
│   ├── pinch(center:scale:)    → 2-finger spread/squeeze
│   ├── rotate(center:angle:)   → 2-finger rotation
│   └── twoFingerTap(at:)       → 2-finger simultaneous tap
│
├── N-Finger Primitives
│   ├── touchesDown(at: [CGPoint])  → Create N touches + HID event + sendEvent
│   ├── moveTouches(to: [CGPoint])  → Update all active touches
│   └── touchesUp()                 → End all active touches
│
└── Touch Stack
    ├── SyntheticTouchFactory     → UITouch creation via direct IMP invocation
    │   ├── performIntSelector    → setPhase:, setTapCount: (raw Int)
    │   ├── performBoolSelector   → _setIsFirstTouchForView:, setIsTap: (raw Bool)
    │   ├── performDoubleSelector → setTimestamp: (raw Double)
    │   └── setHIDEvent           → _setHidEvent: (raw pointer)
    ├── IOHIDEventBuilder         → Hand event with per-finger child events
    │   ├── @convention(c) typed function pointers via dlsym
    │   └── Finger identity/index for multi-touch tracking
    └── SyntheticEventFactory     → Fresh UIEvent per touch phase
```

**Key Design Decisions**:
- **Direct IMP invocation**: `perform(_:with:)` boxes non-object types (Int, Bool, Double, UnsafeMutableRawPointer) as NSNumber objects, corrupting values passed to private ObjC methods. All private API calls use `method(for:)` + `unsafeBitCast` to `@convention(c)` typed function pointers.
- **`@convention(c)` for dlsym**: C function pointers from `dlsym` are 8 bytes; Swift closures are 16 bytes. All IOKit function pointer variables use `@convention(c)` for `unsafeBitCast` compatibility.
- **Fresh UIEvent per phase**: iOS 26's stricter validation rejects reused event objects. Each touch phase (began, moved, ended) creates a new UIEvent.
- **Overlay window filtering**: `getKeyWindow()` filters by `windowLevel <= .normal` to skip the TapVisualizerView overlay window.

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

### Action Flow (touch gestures)

```
1. Client sends touch gesture message (touchTap, touchDrag, touchPinch, etc.)

2. AccraHost receives message
   └── Resolve target point (from element activation point or explicit coordinates)
   └── For element targets: refresh hierarchy, find element, get activation point

3. SimFinger performs gesture
   └── tap(at:) / longPress(at:) / swipe(from:to:) / drag(from:to:)
   └── pinch(center:scale:) / rotate(center:angle:) / twoFingerTap(at:)
   └── Each dispatches UITouch + IOHIDEvent via UIApplication.sendEvent()

4. AccraHost sends actionResult
   └── success: true/false
   └── method: syntheticTap / syntheticDrag / syntheticPinch / etc.
   └── message: optional error description
   └── Show TapVisualizerView overlay on successful taps
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
