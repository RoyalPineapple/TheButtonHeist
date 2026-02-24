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
│  ┌──────────────┐  ┌──────────────┐                                │
│  │     CLI      │  │ Python/Shell │                                │
│  │              │  │   Scripts    │                                │
│  └──────┬───────┘  └──────┬───────┘                                │
│         │                 │                                        │
│         └─────────────────┘                                        │
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
- `ClientMessage` - Messages from client to server (23 cases including 9 touch gestures, text input, edit actions, and idle waiting)
- `ServerMessage` - Messages from server to client (8 cases including auth challenge/failure)
- `HeistElement` - Flat UI element representation (with traits, hint, activation point, custom content)
- `ElementNode` - Recursive tree structure with containers
- `Group` - Container metadata (type, label, frame)
- `Interface` - Container for UI element interface data (flat list + optional tree)
- `ServerInfo` - Device and app metadata (incl. instanceId, listeningPort, simulatorUDID, vendorIdentifier)
- `ActionResult` - Action outcome with method, optional message, interface delta, and animation state
- `ScreenPayload` - Base64-encoded PNG with dimensions

**Design Decisions**:
- All types are `Codable` and `Sendable` for JSON serialization and concurrency safety
- No platform-specific imports (UIKit/AppKit)
- Protocol version 3.0 with token-based authentication

### InsideMan

**Purpose**: iOS server that captures and broadcasts UI element interface and handles remote interaction.

**Architecture**:
```
InsideMan (singleton, @MainActor)
├── SimpleSocketServer (from Wheelman; NWListener TCP server, IPv6 dual-stack)
│   └── Client connections (file descriptors)
├── NetService (Bonjour advertisement)
├── AccessibilityHierarchyParser (from AccessibilitySnapshot submodule)
│   └── elementVisitor closure (captures live NSObject references during parse)
├── Interactive Object Cache (weak references to accessibility nodes, keyed by traversal index)
├── SafeCracker (gesture simulation + text input, used as fallback)
│   ├── SyntheticTouchFactory (UITouch creation via private APIs)
│   ├── SyntheticEventFactory (UIEvent manipulation)
│   ├── IOHIDEventBuilder (multi-finger HID event creation via IOKit)
│   └── UIKeyboardImpl (text injection via ObjC runtime, same approach as KIF)
├── TapVisualizerView (visual tap feedback overlay)
├── Polling Timer (interface change detection via hash comparison)
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
4. Begins polling for interface changes

**Threading Model**:
- Entire class marked `@MainActor`
- All UIKit operations on main thread
- Network callbacks dispatch to main actor
- Socket accept/read on dedicated GCD queues

**TCP Server (SimpleSocketServer)**:
- Network framework implementation using `NWListener` and `NWConnection`
- IPv6 dual-stack (accepts both IPv4 and IPv6)
- Loopback-only binding on simulators (`::1`), all-interfaces on devices (`::`)
- Fixed port from configuration (default: 1455)
- Newline-delimited JSON protocol (0x0A separator)
- Max 5 concurrent connections, 30 messages/second rate limit, 10 MB buffer limit
- Token-based authentication (v3.0)

### SafeCracker (Touch Gesture & Text Input System)

**Purpose**: Synthesize touch gestures and inject text on the iOS device to allow remote interaction. Supports single-finger gestures (tap, long press, swipe, drag), multi-touch gestures (pinch, rotate, two-finger tap), and text input via UIKeyboardImpl.

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
├── Text Input (via UIKeyboardImpl)
│   ├── typeText(_:)             → addInputString: per character
│   ├── deleteText(count:)       → deleteFromInput per character
│   └── isKeyboardVisible()      → UIInputSetHostView detection
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

**Text Input Design**:
- The iOS software keyboard is rendered by a separate remote process. Individual key views are not in the app's view hierarchy — only a `_UIRemoteKeyboardPlaceholderView` placeholder exists.
- SafeCracker uses `UIKeyboardImpl.activeInstance` (via ObjC runtime) to get the keyboard controller, then calls `addInputString:` to inject text and `deleteFromInput` to delete — the same approach used by KIF (Keep It Functional).
- Keyboard visibility is detected by finding `UIInputSetHostView` (height > 100pt) in the window hierarchy.

**Key Design Decisions**:
- **Direct IMP invocation**: `perform(_:with:)` boxes non-object types (Int, Bool, Double, UnsafeMutableRawPointer) as NSNumber objects, corrupting values passed to private ObjC methods. All private API calls use `method(for:)` + `unsafeBitCast` to `@convention(c)` typed function pointers.
- **`@convention(c)` for dlsym**: C function pointers from `dlsym` are 8 bytes; Swift closures are 16 bytes. All IOKit function pointer variables use `@convention(c)` for `unsafeBitCast` compatibility.
- **Fresh UIEvent per phase**: iOS 26's stricter validation rejects reused event objects. Each touch phase (began, moved, ended) creates a new UIEvent.
- **Overlay window filtering**: `getKeyWindow()` filters by `windowLevel <= .normal` to skip the TapVisualizerView overlay window.

### Screen Capture

InsideMan captures the screen using `UIGraphicsImageRenderer`:
1. Finds the foreground window scene
2. Uses `drawHierarchy(in:afterScreenUpdates:)` to capture the full visual hierarchy (including SwiftUI)
3. Encodes as PNG, then base64
4. Returns `ScreenPayload` with dimensions and timestamp
5. Screen captures are automatically broadcast alongside interface changes during polling

### Wheelman

**Purpose**: Cross-platform (iOS+macOS) networking library. Provides TCP server, client connections, and Bonjour discovery.

**Key Types**:
- `SimpleSocketServer` - Network framework TCP server (NWListener, IPv6 dual-stack), used by InsideMan on iOS
- `DeviceConnection` - TCP client with NWConnection service resolution and data transport
- `DeviceDiscovery` - NWBrowser-based Bonjour browsing for `_buttonheist._tcp`, extracts TXT records
- `DiscoveredDevice` - Discovered device metadata (id, name, endpoint, simulatorUDID, vendorIdentifier, tokenHash, instanceId)

### ButtonHeistMCP (AI Agent Interface)

**Purpose**: Model Context Protocol server that lets AI agents drive iOS apps. Proxies tool calls to a `buttonheist session` subprocess via a single `run` tool.

**Architecture**:
```
buttonheist-mcp (executable)
├── StdioTransport (MCP SDK)
│   └── JSON-RPC 2.0 over stdin/stdout
├── Server (MCP SDK, actor)
│   ├── ListTools handler → 1 tool definition ("run")
│   └── CallTool handler → serialized through SessionPipe
├── SessionPipe (actor, serializes pipe I/O)
│   └── JSON lines over subprocess stdin/stdout
└── buttonheist session subprocess
    └── HeistClient, DeviceDiscovery, TCP connection (all in CLI)
```

**How MCP Clients Connect**:

MCP clients (Claude Code, Claude Desktop, etc.) discover and launch the server automatically. The configuration is a `.mcp.json` file in the project root:

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "SIMULATOR_UDID_HERE"]
    }
  }
}
```

The `--device` flag (or `BUTTONHEIST_DEVICE` env var) is forwarded to the `buttonheist session` subprocess, which uses it to filter which device to connect to, matching against name, app name, short ID, simulator UDID, or vendor identifier. Without a filter, it connects to the first device found.

When the MCP client starts a session, it:
1. Reads `.mcp.json` and spawns the `buttonheist-mcp` process
2. Opens a bidirectional stdio pipe (JSON-RPC 2.0 over stdin/stdout)
3. Sends `initialize` → server responds with capabilities (1 tool: `run`)
4. Sends `notifications/initialized` → server is ready
5. Tool calls are proxied as JSON lines through the `SessionPipe` actor to the `buttonheist session` subprocess, which handles all device communication

The AI agent calls the `run` tool with a `command` field and any additional parameters. The MCP server forwards the call as a JSON line to the subprocess stdin and reads the response from subprocess stdout, serialized through `SessionPipe` to prevent interleaving of concurrent calls.

**Connection lifecycle**:
```
MCP client starts session
  └── spawns buttonheist-mcp process
        └── buttonheist-mcp spawns buttonheist session subprocess
        └── session subprocess: Bonjour discovery → TCP connection to iOS device
        └── MCP Server.start(transport: StdioTransport)
        └── Ready for tool calls

Tool call (e.g. run {"command": "tap", ...})
  └── MCP client sends JSON-RPC request on stdin
  └── Server.handleToolCall() on MCP actor
  └── SessionPipe.send() → writes JSON line to subprocess stdin
  └── SessionPipe waits → reads JSON line from subprocess stdout
  └── subprocess: HeistClient sends message → TCP to iOS device
  └── subprocess: InsideMan processes gesture, sends result over TCP
  └── subprocess writes response JSON line to stdout
  └── Server returns JSON-RPC response on stdout
  └── MCP client receives result

Session ends
  └── MCP client closes stdin
  └── buttonheist-mcp exits, subprocess terminated
  └── TCP connection closed
```

**Key Design Decisions**:
- **Subprocess proxy**: All iOS device logic lives in the CLI's `session` subcommand, shared between interactive CLI use and MCP. The MCP server is a thin proxy with no direct device knowledge.
- **Single `run` tool**: Collapses individual tools into one with command dispatch, reducing token overhead in LLM context.
- **SessionPipe actor**: Serializes concurrent MCP tool calls through the subprocess pipe, preventing interleaved writes and mismatched read/response pairs.
- **Separate package**: ButtonHeistMCP depends only on the MCP Swift SDK. The ButtonHeist framework dependency has been removed from the MCP package.
- **stderr for logging**: MCP uses stdout for JSON-RPC, so all diagnostic logging goes to stderr. This ensures protocol messages are never corrupted by debug output.

### ButtonHeist (macOS Client Framework)

**Purpose**: Single-import macOS framework. Re-exports TheGoods and Wheelman, provides the high-level `HeistClient` class.

**Usage**: `import ButtonHeist` gives access to all types (HeistClient, HeistElement, Interface, DiscoveredDevice, etc.)

**Architecture**:
```
HeistClient (ObservableObject, @MainActor)
├── DeviceDiscovery (from Wheelman)
│   └── NWBrowser (Bonjour browsing for "_buttonheist._tcp")
├── DeviceConnection (from Wheelman)
│   └── NWConnection (service resolution + data transport)
└── Published Properties
    ├── discoveredDevices: [DiscoveredDevice]
    ├── connectedDevice: DiscoveredDevice?
    ├── connectionState: ConnectionState
    ├── currentInterface: Interface?
    ├── currentScreen: ScreenPayload?
    └── serverInfo: ServerInfo?
```

**Dual API Design**:

1. **SwiftUI (Reactive)**: `@Published` properties trigger view updates
2. **Callbacks (Imperative)**: Closures for CLI and non-SwiftUI usage
3. **Async/Await**: `waitForActionResult(timeout:)` and `waitForScreen(timeout:)` for scripting

**Auto-Subscribe on Connect**: When a connection is established, HeistClient automatically sends `subscribe`, `requestInterface`, and `requestScreen` messages.

**Connection State Machine**:
```
disconnected ──connect()──► connecting ──success──► connected
     ▲                          │                      │
     │                          │                      │
     └────────────disconnect()──┴──────────failure─────┘
```

## Data Flow

### MCP Agent Flow

The MCP server is the primary interface for AI agents. When an AI agent (Claude Code, Claude Desktop, or any MCP client) starts a session in a project containing `.mcp.json`, the full flow is:

```
1. MCP client reads .mcp.json, spawns buttonheist-mcp
   └── stdio transport: stdin for JSON-RPC requests, stdout for responses

2. buttonheist-mcp startup (before accepting MCP calls)
   └── spawns buttonheist session subprocess (with --format json and optional --device flag)
   └── session subprocess: HeistClient.startDiscovery() → NWBrowser for _buttonheist._tcp
   └── session subprocess: Bonjour discovers iOS device within ~2 seconds
   └── session subprocess: HeistClient.connect() → TCP connection to device
   └── MCP Server.start(transport: StdioTransport) → ready

3. MCP client sends initialize handshake
   └── Server responds with capabilities (1 tool: run)
   └── Tool appears as a native capability to the AI agent
   └── Example: Claude calls run with {"command": "get_screen"} or {"command": "tap", ...}

4. AI agent calls a read command (e.g. run {"command": "get_screen"})
   └── JSON-RPC: {"method": "tools/call", "params": {"name": "run", "arguments": {"command": "get_screen"}}}
   └── SessionPipe.send() writes JSON line to subprocess stdin
   └── subprocess: HeistClient.send(.requestScreen) → TCP to iOS device
   └── subprocess: InsideMan captures screen → base64 PNG → TCP back
   └── subprocess writes JSON response line to stdout
   └── SessionPipe reads response, Server returns image content via MCP
   └── Agent sees the app's screen as an image

5. AI agent calls an interaction command (e.g. run {"command": "tap", ...})
   └── SessionPipe.send() writes JSON line to subprocess stdin
   └── subprocess: HeistClient.send(message) → TCP to iOS device
   └── subprocess: InsideMan.SafeCracker performs the gesture
   └── subprocess: ActionResult received over TCP
   └── subprocess writes JSON response line to stdout
   └── SessionPipe reads response, Server returns success/failure to agent
   └── Agent can immediately call run {"command": "get_screen"} to verify the result

6. Session ends
   └── MCP client closes stdin pipe
   └── buttonheist-mcp exits, subprocess terminated, TCP connection closes
```

This architecture means the AI agent interacts with the iOS app as naturally as it reads files or runs commands. All device logic is shared with the CLI via the `session` subcommand — the MCP server is a thin proxy. The `SessionPipe` actor serializes concurrent tool calls, and screenshots are routed via unique temp files to avoid collisions.

### Discovery Flow

```
1. InsideMan loads (ObjC +load)
   └── SimpleSocketServer.start(port: 1455)
   └── NetService.publish("_buttonheist._tcp")
   │     Service name: "{AppName}#{instanceId}"
   │     instanceId = INSIDEMAN_ID env var, or first 8 chars of per-launch UUID
   └── NetService.setTXTRecord()
         TXT keys: "simudid" (SIMULATOR_UDID), "tokenhash" (SHA256 prefix), "instanceid"

2. HeistClient.startDiscovery()
   └── NWBrowser.start(for: "_buttonheist._tcp")

3. NWBrowser finds service
   └── Extract TXT record: .bonjour(let txtRecord) → simulatorUDID, vendorIdentifier
   └── HeistClient.discoveredDevices.append(device)
```

### Multi-Instance Discovery

When running multiple instances (e.g., multiple simulators), each instance has a unique identity:

- **Instance ID**: Configurable via `INSIDEMAN_ID` env var, or defaults to first 8 chars of a per-launch UUID. Appears in the Bonjour service name (e.g., `MyApp#a1b2c3d4`) and TXT record.
- **Simulator UDID**: The `SIMULATOR_UDID` environment variable, automatically set by the iOS Simulator. Published in the Bonjour TXT record under key `simudid`.
- **Token Hash**: SHA256 hash prefix of the auth token. Published in the TXT record under key `tokenhash` for pre-connection filtering.

Clients (CLI, MCP, GUI) can filter devices by any of these identifiers. The matching logic is case-insensitive and supports prefix matching for IDs, allowing partial UDID matching (e.g., `--device DEADBEEF`).

### Connection Flow

```
1. HeistClient.connect(to: device)
   └── NWConnection resolves Bonjour service and connects

2. TCP connection established
   └── InsideMan sends ServerMessage.authRequired

3. HeistClient receives authRequired
   └── Sends: authenticate(token)

4. InsideMan validates token
   └── On success: sends ServerMessage.info
   └── On failure: sends ServerMessage.authFailed, disconnects

5. HeistClient receives info
   └── serverInfo = info
   └── connectionState = .connected
   └── Sends: subscribe, requestInterface, requestScreen
```

### Interface Update Flow

```
1. Polling timer fires (configurable interval, default 1.0s)

2. InsideMan.refreshAccessibilityData()
   └── parser.parseAccessibilityHierarchy(in: rootView, elementVisitor: { ... })
   │     elementVisitor captures weak refs to interactive objects (keyed by index)
   └── flattenToElements() → AccessibilityMarker[]
   └── Update interactiveObjects cache
   └── Convert markers to HeistElement[] (actions derived from interactive cache)
   └── Compute hash of elements array

3. If hash changed:
   └── Create Interface(timestamp, elements, tree)
   └── Broadcast interface to all connected clients
   └── Capture and broadcast screen
```

### Action Flow (accessibility actions)

```
1. Client sends activate / increment / decrement / customAction message

2. InsideMan receives message
   └── refreshAccessibilityData() → re-parse hierarchy + rebuild interactive cache
   └── Find element by identifier or order index
   └── Resolve traversal index → look up live NSObject in interactiveObjects cache

3. Dispatch via live object reference
   └── activate:  object.accessibilityActivate()
   └── increment: object.accessibilityIncrement()
   └── decrement: object.accessibilityDecrement()
   └── custom:    find UIAccessibilityCustomAction by name → call handler or target/selector

4. Fallback (activate only): if accessibilityActivate() returns false
   └── SafeCracker.tap(at: activationPoint) → synthetic touch injection

5. InsideMan sends actionResult
   └── success: true/false
   └── method: activate / increment / decrement / customAction / syntheticTap
   └── Show TapVisualizerView overlay on success
```

### Action Flow (touch gestures)

```
1. Client sends touch gesture message (touchTap, touchDrag, touchPinch, etc.)

2. InsideMan receives message
   └── Resolve target point (from element activation point or explicit coordinates)
   └── For element targets: refreshAccessibilityData(), find element, get activation point
   └── touchTap with element target: try accessibilityActivate() first, fall back to synthetic

3. SafeCracker performs gesture
   └── tap(at:) / longPress(at:) / swipe(from:to:) / drag(from:to:)
   └── pinch(center:scale:) / rotate(center:angle:) / twoFingerTap(at:)
   └── Each dispatches UITouch + IOHIDEvent via UIApplication.sendEvent()

4. InsideMan sends actionResult
   └── success: true/false
   └── method: activate / syntheticTap / syntheticDrag / syntheticPinch / etc.
   └── message: optional error description
   └── Show TapVisualizerView overlay on successful taps
```

## Network Protocol

See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md) for complete protocol specification.

**Summary**:
- Protocol version: 3.0
- Transport: TCP socket (Network framework NWListener/NWConnection)
- Authentication: Token-based (required for all connections)
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
- Interface updates debounced by 300ms

### HeistClient (macOS)
- `@MainActor` for SwiftUI `@Published` properties
- NWBrowser for discovery on main queue
- NWConnection for data transport
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
| `INSIDEMAN_TOKEN` | Auth token for client authentication | auto-generated UUID |
| `INSIDEMAN_ID` | Human-readable instance identifier | first 8 chars of session UUID |

### Info.plist Keys (fallback)
```xml
<key>InsideManPort</key>
<integer>1455</integer>
<key>InsideManPollingInterval</key>
<real>1.0</real>
<key>InsideManDisableAutoStart</key>
<false/>
<key>InsideManToken</key>
<string>my-secret-token</string>
<key>InsideManInstanceId</key>
<string>my-instance</string>
<key>NSLocalNetworkUsageDescription</key>
<string>element inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```
