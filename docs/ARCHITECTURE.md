# ButtonHeist Architecture

This document describes the internal architecture of ButtonHeist and how its components interact.

## System Overview

ButtonHeist is a distributed system that lets AI agents (and humans) inspect and control iOS apps. Its main components are:

1. **TheGoods** - Cross-platform shared types (messages, models)
2. **Wheelman** - Cross-platform networking library (TCP server/client, Bonjour discovery)
3. **InsideMan** - iOS framework embedded in the app being inspected
4. **ButtonHeist** - macOS client framework (single import for Mac consumers)
5. **ButtonHeistMCP** - MCP server that bridges AI agents to the iOS app

```
┌─────────────────────────────────────────────────────────────────────┐
│                              macOS                                   │
│                                                                      │
│  ┌──────────────┐                                                   │
│  │  AI Agent    │ (Claude Code, or any MCP client)                  │
│  └──────┬───────┘                                                   │
│         │ MCP (JSON-RPC 2.0 over stdio)                             │
│  ┌──────┴───────┐                                                   │
│  │buttonheist-  │ Persistent connection — no per-call overhead      │
│  │  mcp server  │                                                   │
│  └──────┬───────┘                                                   │
│         │                                                            │
│  ┌──────┴───────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Stakeout   │  │     CLI      │  │ Python/Shell │              │
│  │     (GUI)    │  │              │  │   Scripts    │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                       │
│         └─────────────────┼─────────────────┘                       │
│                           │                                          │
│                  ┌────────┴────────┐                                │
│                  │   ButtonHeist   │ (import ButtonHeist)           │
│                  │   HeistClient   │                                │
│                  └────────┬────────┘                                │
│                           │                                          │
│            ┌──────────────┼──────────────┐                          │
│            │              │              │                          │
│      ┌─────┴─────┐  ┌─────┴─────┐  ┌─────┴─────┐                   │
│      │  Device   │  │  Device   │  │    BSD    │                   │
│      │ Discovery │  │Connection │  │  Socket   │                   │
│      │(NWBrowser)│  │   Mgmt    │  │  Client   │                   │
│      └───────────┘  └───────────┘  └─────┬─────┘                   │
│                  Wheelman (networking)     │                         │
└──────────────────────────────────────────┼──────────────────────────┘
                                           │
                    WiFi (Bonjour + TCP) or USB (IPv6 + TCP)
                                           │
┌──────────────────────────────────────────┼──────────────────────────┐
│                           ┌──────────────┴──────────────┐           │
│                           │         InsideMan           │           │
│                           │        (Framework)          │           │
│                           └──────────────┬──────────────┘           │
│                                          │                          │
│           ┌──────────────┬───────────────┼───────────────┐          │
│           │              │               │               │          │
│     ┌─────┴─────┐  ┌────┴──────┐  ┌─────┴─────┐  ┌─────┴─────┐    │
│     │ NetService│  │SimpleSocket│  │   A11y    │  │SafeCracker│    │
│     │ (Bonjour) │  │Server(TCP)│  │  Parser   │  │(Gestures) │    │
│     └───────────┘  └───────────┘  └───────────┘  └───────────┘    │
│                  Wheelman (networking)                               │
│                              iOS Device                              │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Details

### TheGoods

**Purpose**: Shared types and protocol definitions for cross-platform communication.

**Key Types**:
- `ClientMessage` - Messages from client to server (15 cases including 7 touch gestures)
- `ServerMessage` - Messages from server to client (6 cases)
- `UIElement` - Flat UI element representation
- `ElementNode` - Recursive tree structure with containers
- `Group` - Container metadata (type, label, frame)
- `Snapshot` - Container for hierarchy snapshots (flat list + optional tree)
- `ServerInfo` - Device and app metadata
- `ActionResult` - Action outcome with method and optional message
- `ScreenshotPayload` - Base64-encoded PNG with dimensions

**Design Decisions**:
- All types are `Codable` and `Sendable` for JSON serialization and concurrency safety
- No platform-specific imports (UIKit/AppKit)
- Protocol version 2.0 included for compatibility

### InsideMan

**Purpose**: iOS server that captures and broadcasts UI element snapshot and handles remote interaction.

**Architecture**:
```
InsideMan (singleton, @MainActor)
├── SimpleSocketServer (from Wheelman; BSD socket TCP server, IPv6 dual-stack)
│   └── Client connections (file descriptors)
├── NetService (Bonjour advertisement)
├── AccessibilityHierarchyParser (from AccessibilitySnapshot submodule)
├── SafeCracker (multi-touch gesture simulation)
│   ├── SyntheticTouchFactory (UITouch creation via private APIs)
│   ├── SyntheticEventFactory (UIEvent manipulation)
│   └── IOHIDEventBuilder (multi-finger HID event creation via IOKit)
├── TapVisualizerView (visual tap feedback overlay)
├── Polling Timer (hierarchy change detection via hash comparison)
└── Debounce Timer (300ms debounce for UI notifications)
```

**Auto-Start Mechanism**:

InsideMan uses ObjC `+load` for automatic initialization:

```
InsideManLoader/
├── InsideManAutoStart.h  (public header)
└── InsideManAutoStart.m  (+load implementation → InsideMan_autoStartFromLoad)
```

When the framework loads:
1. `+load` is called automatically by the runtime
2. Reads configuration from environment variables or Info.plist:
   - `INSIDEMAN_DISABLE` / `InsideManDisableAutoStart` - skip startup
   - `INSIDEMAN_PORT` / `InsideManPort` - server port (default: 0 = auto)
   - `INSIDEMAN_POLLING_INTERVAL` / `InsideManPollingInterval` - update interval (default: 1.0s, min: 0.5s)
3. Creates a Task on MainActor to configure and start InsideMan singleton
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

### SafeCracker (Touch Gesture System)

**Purpose**: Synthesize touch gestures on the iOS device to allow remote interaction. Supports single-finger gestures (tap, long press, swipe, drag) and multi-touch gestures (pinch, rotate, two-finger tap).

**Architecture**:
```
SafeCracker (stateful, @MainActor)
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

InsideMan captures screenshots using `UIGraphicsImageRenderer`:
1. Finds the foreground window scene
2. Uses `drawHierarchy(in:afterScreenUpdates:)` to capture the full visual hierarchy (including SwiftUI)
3. Encodes as PNG, then base64
4. Returns `ScreenshotPayload` with dimensions and timestamp
5. Screenshots are automatically broadcast alongside hierarchy changes during polling

### Wheelman

**Purpose**: Cross-platform (iOS+macOS) networking library. Provides TCP server, client connections, and Bonjour discovery.

**Key Types**:
- `SimpleSocketServer` - BSD socket TCP server (IPv6 dual-stack), used by InsideMan on iOS
- `DeviceConnection` - BSD socket TCP client with Bonjour service resolution
- `DeviceDiscovery` - NWBrowser-based Bonjour browsing for `_buttonheist._tcp`
- `DiscoveredDevice` - Discovered device metadata (id, name, endpoint)

### ButtonHeistMCP (AI Agent Interface)

**Purpose**: Model Context Protocol server that lets AI agents drive iOS apps. Wraps HeistClient in an MCP-compliant JSON-RPC 2.0 interface over stdio.

**Architecture**:
```
buttonheist-mcp (executable)
├── StdioTransport (MCP SDK)
│   └── JSON-RPC 2.0 over stdin/stdout
├── Server (MCP SDK, actor)
│   ├── ListTools handler → 13 tool definitions
│   └── CallTool handler → dispatches to HeistClient
├── HeistClient (@MainActor)
│   ├── DeviceDiscovery (auto-connect on startup)
│   └── Persistent TCP connection to iOS device
└── Logging (stderr, never stdout)
```

**Key Design Decisions**:
- **Persistent connection**: The MCP server connects to the iOS device on startup and maintains the connection for the lifetime of the process. This eliminates the 5-10 second Bonjour discovery + TCP connect overhead that would occur with per-invocation CLI calls.
- **@MainActor entry point**: HeistClient is `@MainActor`. Rather than bridging between actor contexts with `MainActor.run`, the entire `main()` function is `@MainActor`, and the MCP Server actor hops via `await` when calling tool handlers.
- **Separate package**: ButtonHeistMCP is a standalone Swift 6.0 package (the main ButtonHeist package is Swift 5.9). It depends on `ButtonHeist` (local path) and the MCP Swift SDK.
- **13 tools**: Read tools (`get_snapshot`, `get_screenshot`) and interaction tools (`tap`, `long_press`, `swipe`, `drag`, `pinch`, `rotate`, `two_finger_tap`, `activate`, `increment`, `decrement`, `perform_custom_action`).

### ButtonHeist (macOS Client Framework)

**Purpose**: Single-import macOS framework. Re-exports TheGoods and Wheelman, provides the high-level `HeistClient` class.

**Usage**: `import ButtonHeist` gives access to all types (HeistClient, UIElement, Snapshot, DiscoveredDevice, etc.)

**Architecture**:
```
HeistClient (ObservableObject, @MainActor)
├── DeviceDiscovery (from Wheelman)
│   └── NWBrowser (Bonjour browsing for "_buttonheist._tcp")
├── DeviceConnection (from Wheelman)
│   ├── NWConnection (service resolution only)
│   └── BSD socket (actual data transport)
└── Published Properties
    ├── discoveredDevices: [DiscoveredDevice]
    ├── connectedDevice: DiscoveredDevice?
    ├── connectionState: ConnectionState
    ├── currentSnapshot: Snapshot?
    ├── currentScreenshot: ScreenshotPayload?
    └── serverInfo: ServerInfo?
```

**Dual API Design**:

1. **SwiftUI (Reactive)**: `@Published` properties trigger view updates
2. **Callbacks (Imperative)**: Closures for CLI and non-SwiftUI usage
3. **Async/Await**: `waitForActionResult(timeout:)` and `waitForScreenshot(timeout:)` for scripting

**Auto-Subscribe on Connect**: When a connection is established, HeistClient automatically sends `subscribe`, `requestSnapshot`, and `requestScreenshot` messages.

**Connection State Machine**:
```
disconnected ──connect()──► connecting ──success──► connected
     ▲                          │                      │
     │                          │                      │
     └────────────disconnect()──┴──────────failure─────┘
```

## Data Flow

### MCP Agent Flow

```
1. MCP client (e.g. Claude Code) starts buttonheist-mcp process
   └── stdio transport: stdin/stdout for JSON-RPC 2.0

2. buttonheist-mcp startup
   └── HeistClient.startDiscovery() via Bonjour
   └── Connects to first discovered device
   └── MCP Server starts listening on stdin

3. MCP client sends initialize handshake
   └── Server responds with capabilities (13 tools)

4. MCP client calls tools/call (e.g. get_snapshot)
   └── Server actor → await → @MainActor handleToolCall()
   └── HeistClient.send(.requestSnapshot)
   └── Wait for onSnapshotUpdate callback
   └── Return JSON result via MCP

5. MCP client calls tools/call (e.g. tap)
   └── Build ClientMessage from tool arguments
   └── HeistClient.send(message)
   └── Wait for ActionResult
   └── Return success/failure via MCP
```

### Discovery Flow

```
1. InsideMan loads (ObjC +load)
   └── SimpleSocketServer.start(port: 1455)
   └── NetService.publish("_buttonheist._tcp")

2. HeistClient.startDiscovery()
   └── NWBrowser.start(for: "_buttonheist._tcp")

3. NWBrowser finds service
   └── HeistClient.discoveredDevices.append(device)
```

### Connection Flow

```
1. HeistClient.connect(to: device)
   └── NWConnection resolves Bonjour service to host:port
   └── BSD socket connects to 127.0.0.1:port

2. TCP connection established
   └── InsideMan sends ServerMessage.info

3. HeistClient receives info
   └── serverInfo = info
   └── connectionState = .connected
   └── Sends: subscribe, requestSnapshot, requestScreenshot
```

### Hierarchy Update Flow

```
1. Polling timer fires (configurable interval, default 1.0s)

2. InsideMan.checkForChanges()
   └── parser.parseAccessibilityHierarchy(in: rootView)
   └── flattenToElements() → UIElement[]
   └── Compute hash of elements array

3. If hash changed:
   └── Create Snapshot(timestamp, elements, tree)
   └── Broadcast hierarchy to all connected clients
   └── Capture and broadcast screenshot
```

### Action Flow (touch gestures)

```
1. Client sends touch gesture message (touchTap, touchDrag, touchPinch, etc.)

2. InsideMan receives message
   └── Resolve target point (from element activation point or explicit coordinates)
   └── For element targets: refresh hierarchy, find element, get activation point

3. SafeCracker performs gesture
   └── tap(at:) / longPress(at:) / swipe(from:to:) / drag(from:to:)
   └── pinch(center:scale:) / rotate(center:angle:) / twoFingerTap(at:)
   └── Each dispatches UITouch + IOHIDEvent via UIApplication.sendEvent()

4. InsideMan sends actionResult
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
- Discovery: Bonjour/mDNS (`_buttonheist._tcp`) or USB IPv6 tunnel
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

### InsideMan (iOS)
- `@MainActor` for UIKit compatibility
- Parser must run on main thread
- Socket accept/read on GCD queues
- Message handling dispatched to main
- Hierarchy updates debounced by 300ms

### HeistClient (macOS)
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
| `INSIDEMAN_DISABLE` | "true"/"1"/"yes" to disable auto-start | not set |
| `INSIDEMAN_PORT` | Fixed port number, 0 = auto | 0 |
| `INSIDEMAN_POLLING_INTERVAL` | Polling interval in seconds | 1.0 |

### Info.plist Keys (fallback)
```xml
<key>InsideManPort</key>
<integer>1455</integer>
<key>InsideManPollingInterval</key>
<real>1.0</real>
<key>InsideManDisableAutoStart</key>
<false/>
<key>NSLocalNetworkUsageDescription</key>
<string>element inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```
