# ButtonHeist API Reference

Complete API documentation for InsideMan (iOS), HeistClient (macOS), and the CLI.

## InsideMan

**Import**: `import InsideMan`
**Platform**: iOS 17.0+
**Location**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

### Overview

InsideMan automatically starts when your app loads via ObjC `+load`. No manual initialization is required - just link the framework and configure your Info.plist.

### Auto-Start Behavior

When the InsideMan framework loads:
1. Reads configuration from environment variables or Info.plist
2. Creates a TCP server on the configured port (default: auto-assign, recommended: 1455)
3. Begins Bonjour advertisement as `_buttonheist._tcp`
4. Starts polling for UI element snapshot changes

### Configuration

**Environment variables (highest priority):**
```bash
INSIDEMAN_PORT=1455                  # Server port (0 = auto-assign)
INSIDEMAN_POLLING_INTERVAL=1.0       # Polling interval in seconds (min: 0.5)
INSIDEMAN_DISABLE=true               # Disable auto-start
INSIDEMAN_TOKEN=my-secret-token      # Auth token (auto-generated and persisted in UserDefaults if not set)
INSIDEMAN_ID=my-instance             # Human-readable instance identifier
INSIDEMAN_SESSION_TIMEOUT=30         # Session release timeout in seconds (default: 30, min: 1)
```

**Info.plist (fallback):**
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
```

**Client-side:** Set `BUTTONHEIST_TOKEN` environment variable to authenticate with the server.

### InsideMan Class

Main server class. Use the shared singleton instance.

```swift
@MainActor
public final class InsideMan
```

#### Properties

##### shared

```swift
public static var shared: InsideMan
```

Singleton instance. Automatically initialized on framework load.

##### isRunning

```swift
public private(set) var isRunning: Bool
```

Whether the server is currently running.

#### Methods

##### configure(port:token:instanceId:)

```swift
public static func configure(port: UInt16, token: String? = nil, instanceId: String? = nil)
```

Configure the shared instance with a specific port, auth token, and instance identifier. Must be called before `start()` if not using Info.plist/environment variables.

**Parameters**:
- `port`: Port to listen on. Use `0` for automatic port selection.
- `token`: Auth token for client authentication. If nil, auto-generated at startup.
- `instanceId`: Human-readable instance identifier. If nil, falls back to a short UUID prefix.

**Note**: Normally not needed - use Info.plist or environment variable configuration instead.

##### start()

```swift
public func start(port: UInt16 = 0) throws
```

Start the TCP server and begin Bonjour advertisement.

**Note**: Called automatically on framework load. Manual calls are rarely needed.

**Parameters**:
- `port`: Port to listen on. Use `0` for automatic port selection.

**Throws**: Network errors if the listener fails to start.

##### stop()

```swift
public func stop()
```

Stop the server, disconnect all clients, and stop Bonjour advertisement.

##### startPolling(interval:)

```swift
public func startPolling(interval: TimeInterval = 1.0)
```

Enable automatic polling for UI changes.

**Note**: Called automatically on framework load with 1.0 second interval.

**Parameters**:
- `interval`: Polling interval in seconds. Minimum 0.5 seconds.

##### stopPolling()

```swift
public func stopPolling()
```

Stop automatic polling.

##### notifyChange()

```swift
public func notifyChange()
```

Manually trigger a debounced hierarchy broadcast to connected clients. Uses a 300ms debounce to prevent update spam.

### Touch Gesture & Text Input System (TheSafecracker)

InsideMan uses `TheSafecracker` internally for handling all touch gesture and text input commands. TheSafecracker supports single-finger gestures, multi-touch gestures via synthetic UITouch/IOHIDEvent injection, and text entry via UIKeyboardImpl.

**Supported gestures:**
- `tap` - Single tap at a point
- `longPress` - Long press with configurable duration
- `swipe` - Quick swipe between two points
- `drag` - Slow drag between two points (for sliders, reordering)
- `pinch` - Two-finger pinch/zoom
- `rotate` - Two-finger rotation
- `twoFingerTap` - Simultaneous two-finger tap
- `drawPath` - Trace through a sequence of waypoints (polyline)

**Text input (via UIKeyboardImpl):**
- `typeText` - Inject text character-by-character via `addInputString:`
- `deleteText` - Delete characters via `deleteFromInput`
- `isKeyboardVisible` - Check if the software keyboard is showing

Text input uses the same private API approach as KIF (Keep It Functional). The iOS keyboard is rendered by a remote process, so individual key views aren't accessible from within the app. UIKeyboardImpl's `addInputString:` bypasses the visual keyboard entirely, injecting text directly into the input system. This handles all characters (uppercase, symbols, `@`, `.`, etc.) without needing keyboard mode switching.

**Injection stack:**
1. `SyntheticTouchFactory` - Creates UITouch instances via private API IMP invocation
2. `IOHIDEventBuilder` - Creates IOHIDEvent hand events with per-finger child events
3. `SyntheticEventFactory` - Creates fresh UIEvent per touch phase (iOS 26 compatible)
4. `UIApplication.sendEvent()` - Dispatches the synthetic events

**Key implementation notes:**
- All private API calls use direct IMP invocation (`method(for:)` + `@convention(c)`) to avoid `perform(_:with:)` boxing non-object types
- IOKit function pointers loaded via `dlsym` use `@convention(c)` types for correct 8-byte pointer size
- Multi-touch events use unique finger identity/index per finger for proper tracking
- `getKeyWindow()` filters overlay windows by `windowLevel <= .normal`

### Tap Visualization

On successful tap, a `TapVisualizerView` overlay shows a 40pt white circle at the tap point that scales up and fades out over 0.8 seconds. The overlay is passthrough (does not intercept touches).

---

## ButtonHeist (macOS Client)

**Import**: `import ButtonHeist`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`

### HeistClient

Main client class. Conforms to `ObservableObject` for SwiftUI integration.

```swift
@MainActor
public final class HeistClient: ObservableObject
```

#### Published Properties

##### discoveredDevices

```swift
@Published public private(set) var discoveredDevices: [DiscoveredDevice]
```

Devices found via Bonjour discovery. Updated automatically when discovery is active.

##### connectedDevice

```swift
@Published public private(set) var connectedDevice: DiscoveredDevice?
```

Currently connected device, or nil if disconnected.

##### connectionState

```swift
@Published public private(set) var connectionState: ConnectionState
```

Current connection state. See `ConnectionState` enum.

##### currentInterface

```swift
@Published public private(set) var currentInterface: Interface?
```

Most recent UI element snapshot received from the connected device.

##### currentScreen

```swift
@Published public private(set) var currentScreen: ScreenPayload?
```

Most recent screenshot received from the connected device.

##### serverInfo

```swift
@Published public private(set) var serverInfo: ServerInfo?
```

Server information received after connecting.

##### isDiscovering

```swift
@Published public private(set) var isDiscovering: Bool
```

Whether Bonjour discovery is currently active.

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

##### onInterfaceUpdate

```swift
public var onInterfaceUpdate: ((Interface) -> Void)?
```

Called when a new hierarchy is received.

##### onActionResult

```swift
public var onActionResult: ((ActionResult) -> Void)?
```

Called when an action result is received.

##### onScreen

```swift
public var onScreen: ((ScreenPayload) -> Void)?
```

Called when a screenshot is received.

##### onDisconnected

```swift
public var onDisconnected: ((Error?) -> Void)?
```

Called when disconnected. Error is nil for clean disconnections.

##### onTokenReceived

```swift
public var onTokenReceived: ((String) -> Void)?
```

Called when a token is received via on-device UI approval. The client should store this token and set it as `client.token` for future connections to skip the approval flow. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#ui-approval-flow) for details.

##### onSessionLocked

```swift
public var onSessionLocked: ((SessionLockedPayload) -> Void)?
```

Called when the server rejects the connection because another driver holds the active session. The `connectionState` will be set to `.failed` with the payload message. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#session-locking) for details.

##### forceSession

```swift
public var forceSession: Bool
```

When `true`, the next connection sends `forceSession: true` in the auth handshake, forcibly taking over any existing session. Default: `false`.

##### driverId

```swift
public var driverId: String?
```

Driver identity for session locking. When set, the server uses this to distinguish drivers that share the same auth token. Read from `BUTTONHEIST_DRIVER_ID` environment variable. When `nil`, the auth token is used as driver identity (backward-compatible).

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

Begin discovering devices via Bonjour. Clears previous devices.

##### stopDiscovery()

```swift
public func stopDiscovery()
```

Stop device discovery.

##### connect(to:)

```swift
public func connect(to device: DiscoveredDevice)
```

Connect to a discovered device. Automatically sends `subscribe`, `requestInterface`, and `requestScreen` on connection.

**Parameters**:
- `device`: Device to connect to (from `discoveredDevices`).

##### disconnect()

```swift
public func disconnect()
```

Disconnect from the current device and clear all state.

##### requestInterface()

```swift
public func requestInterface()
```

Request a single hierarchy snapshot.

##### send(_:)

```swift
public func send(_ message: ClientMessage)
```

Send any `ClientMessage` to the connected device.

##### waitForActionResult(timeout:)

```swift
public func waitForActionResult(timeout: TimeInterval) async throws -> ActionResult
```

Wait asynchronously for an action result with timeout.

**Parameters**:
- `timeout`: Maximum wait time in seconds.

**Throws**: `ActionError.timeout` if no result received within timeout.

##### waitForScreen(timeout:)

```swift
public func waitForScreen(timeout: TimeInterval = 30.0) async throws -> ScreenPayload
```

Wait asynchronously for a screenshot with timeout.

**Parameters**:
- `timeout`: Maximum wait time in seconds (default: 30).

**Throws**: `ActionError.timeout` if no screenshot received within timeout.

##### displayName(for:)

```swift
public func displayName(for device: DiscoveredDevice) -> String
```

Compute a display name for a device. Returns just the app name if unique among discovered devices, or "AppName (DeviceName)" if disambiguation is needed.

#### ActionError

```swift
public enum ActionError: Error, LocalizedError {
    case timeout
    case notConnected
}
```

---

## TheGoods Types

**Import**: `import TheGoods`
**Platform**: iOS 17.0+ / macOS 14.0+
**Location**: `ButtonHeist/Sources/TheGoods/Messages.swift`

### Constants

```swift
public let buttonHeistServiceType = "_buttonheist._tcp"
public let protocolVersion = "3.1"  // Protocol v3.1 with token auth and session locking
```

### ConnectionState

```swift
public enum ConnectionState: Equatable
```

#### Cases

- `disconnected` - No active connection
- `connecting` - Connection in progress
- `connected` - Connected to a device
- `failed(String)` - Connection failed with error message

### DiscoveredDevice

```swift
public struct DiscoveredDevice: Identifiable, Hashable, Sendable
```

Represents a discovered InsideMan device.

#### Properties

- `id: String` - Unique identifier
- `name: String` - Service name (v3 format: "AppName#instanceId")
- `endpoint: NWEndpoint` - Network endpoint for connection
- `simulatorUDID: String?` - Simulator UDID from Bonjour TXT record (nil on physical devices)
- `vendorIdentifier: String?` - Vendor identifier from Bonjour TXT record
- `tokenHash: String?` - Token hash from Bonjour TXT record (for pre-connection filtering)
- `instanceId: String?` - Instance identifier from Bonjour TXT record

#### Computed Properties

- `shortId: String?` - Short instance ID parsed from service name suffix (after `#`)
- `appName: String` - App name extracted from service name (before `#`)
- `deviceName: String` - Device name extracted from service name (empty for v3 format)

### ClientMessage

```swift
public enum ClientMessage: Codable
```

Messages sent from client to server.

#### Cases

- `authenticate(AuthenticatePayload)` - Authenticate with a token (must be first message sent)
- `requestInterface` - Request current hierarchy
- `subscribe` - Subscribe to automatic updates
- `unsubscribe` - Unsubscribe from updates
- `ping` - Keepalive
- `activate(ActionTarget)` - Activate element (VoiceOver double-tap)
- `increment(ActionTarget)` - Increment adjustable element
- `decrement(ActionTarget)` - Decrement adjustable element
- `performCustomAction(CustomActionTarget)` - Invoke named custom action
- `touchTap(TouchTapTarget)` - Tap at coordinates or element
- `touchLongPress(LongPressTarget)` - Long press at coordinates or element
- `touchSwipe(SwipeTarget)` - Swipe between two points or in a direction
- `touchDrag(DragTarget)` - Drag from one point to another
- `touchPinch(PinchTarget)` - Pinch/zoom gesture
- `touchRotate(RotateTarget)` - Rotation gesture
- `touchTwoFingerTap(TwoFingerTapTarget)` - Two-finger tap
- `touchDrawPath(DrawPathTarget)` - Draw along a path of waypoints
- `touchDrawBezier(DrawBezierTarget)` - Draw along bezier curves (sampled server-side)
- `typeText(TypeTextTarget)` - Type text via UIKeyboardImpl injection
- `editAction(EditActionTarget)` - Perform edit action (copy, paste, cut, select, selectAll)
- `resignFirstResponder` - Dismiss keyboard
- `waitForIdle(WaitForIdleTarget)` - Wait for animations to settle
- `requestScreen` - Request PNG screenshot

### ServerMessage

```swift
public enum ServerMessage: Codable
```

Messages sent from server to client.

#### Cases

- `authRequired` - Server requires authentication (sent immediately on connection)
- `authFailed(String)` - Authentication failed (sent before disconnect)
- `authApproved(AuthApprovedPayload)` - Connection approved via on-device UI (contains token for future use). See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#ui-approval-flow) for details.
- `info(ServerInfo)` - Device/app metadata (sent after successful auth)
- `interface(Interface)` - UI element snapshot
- `pong` - Ping response
- `error(String)` - Error description
- `actionResult(ActionResult)` - Action outcome
- `screen(ScreenPayload)` - Base64-encoded PNG
- `sessionLocked(SessionLockedPayload)` - Session locked by another driver (sent before disconnect). See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#session-locking).

### AuthenticatePayload

```swift
public struct AuthenticatePayload: Codable, Sendable
```

#### Properties

- `token: String` - Auth token for authentication
- `forceSession: Bool?` - When `true`, forcibly takes over any existing session (v3.1)
- `driverId: String?` - Driver identity for session locking (v3.1). When set, used instead of token for session identity.

### SessionLockedPayload

```swift
public struct SessionLockedPayload: Codable, Sendable
```

#### Properties

- `message: String` - Human-readable description of why the session is locked
- `activeConnections: Int` - Number of active connections in the current session

### ActionTarget

```swift
public struct ActionTarget: Codable, Sendable
```

#### Properties

- `identifier: String?` - Element's identifier
- `order: Int?` - Element's traversal index

### TouchTapTarget

```swift
public struct TouchTapTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget?` - Target element (taps at activation point)
- `pointX: Double?` - Explicit X coordinate
- `pointY: Double?` - Explicit Y coordinate
- `point: CGPoint?` - Computed CGPoint from pointX/pointY

### TypeTextTarget

```swift
public struct TypeTextTarget: Codable, Sendable
```

#### Properties

- `text: String?` - Text to type character-by-character (nil if only deleting)
- `deleteCount: Int?` - Number of delete key taps before typing
- `elementTarget: ActionTarget?` - Element to tap for focus and value readback

### CustomActionTarget

```swift
public struct CustomActionTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget` - Target element
- `actionName: String` - Name of the custom action

### ServerInfo

```swift
public struct ServerInfo: Codable, Sendable
```

Device and app metadata received after connecting.

#### Properties

- `protocolVersion: String` - Protocol version (e.g., "3.0")
- `appName: String` - App display name
- `bundleIdentifier: String` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points
- `screenSize: CGSize` - Computed from width/height
- `instanceId: String?` - Per-launch session UUID
- `instanceIdentifier: String?` - Human-readable instance identifier (from `INSIDEMAN_ID` env var, or shortId fallback)
- `listeningPort: UInt16?` - Port the server is listening on
- `simulatorUDID: String?` - Simulator UDID when running on iOS Simulator (nil on physical devices)
- `vendorIdentifier: String?` - `UIDevice.identifierForVendor` UUID string (stable per app install per device)

### Interface

```swift
public struct Interface: Codable, Sendable
```

Container for UI element interface data.

#### Properties

- `timestamp: Date` - When the hierarchy was captured
- `elements: [HeistElement]` - Flat list of UI elements
- `tree: [ElementNode]?` - Optional tree structure with containers

### ElementNode

```swift
public indirect enum ElementNode: Codable, Equatable, Sendable
```

Recursive tree structure for UI element snapshot.

#### Cases

- `element(order: Int)` - Leaf node referencing element by index
- `container(Group, children: [ElementNode])` - Container with children

### Group

```swift
public struct Group: Codable, Equatable, Hashable, Sendable
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `type` | `String` | "semanticGroup", "list", "landmark", or "dataTable" |
| `label` | `String?` | Container's label |
| `value` | `String?` | Container's value |
| `identifier` | `String?` | Container's identifier |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |

### HeistElement

```swift
public struct HeistElement: Codable, Equatable, Hashable, Sendable
```

Represents a single UI element captured from the accessibility hierarchy.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `order` | `Int` | VoiceOver reading order (0-based) |
| `description` | `String` | VoiceOver description |
| `label` | `String?` | Label |
| `value` | `String?` | Current value |
| `identifier` | `String?` | Identifier |
| `hint` | `String?` | Accessibility hint |
| `traits` | `[String]` | Trait names (e.g., `"button"`, `"adjustable"`, `"staticText"`) |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |
| `activationPointX` | `Double` | Activation point X (where VoiceOver would tap) |
| `activationPointY` | `Double` | Activation point Y |
| `respondsToUserInteraction` | `Bool` | Whether the element is interactive |
| `customContent` | `[HeistCustomContent]?` | Custom accessibility content |
| `actions` | `[ElementAction]` | Available actions (`"activate"`, `"increment"`, `"decrement"`, or custom action names) |

#### Computed Properties

```swift
public var frame: CGRect            // Frame as CGRect
public var activationPoint: CGPoint // Activation point as CGPoint
```

### ActionResult

```swift
public struct ActionResult: Codable, Sendable
```

#### Properties

- `success: Bool` - Whether action succeeded
- `method: ActionMethod` - How action was performed
- `message: String?` - Additional context or error description
- `value: String?` - Current text field value (populated by `typeText`)
- `interfaceDelta: InterfaceDelta?` - Compact delta describing what changed after the action
- `animating: Bool?` - `true` if UI was still animating when result was produced; `nil` means idle

### ActionMethod

```swift
public enum ActionMethod: String, Codable, Sendable
```

#### Cases

- `activate` - Used activation
- `increment` - Used increment action
- `decrement` - Used decrement action
- `syntheticTap` - Tap via TheSafecracker
- `syntheticLongPress` - Long press via TheSafecracker
- `syntheticSwipe` - Swipe via TheSafecracker
- `syntheticDrag` - Drag via TheSafecracker
- `syntheticPinch` - Pinch via TheSafecracker
- `syntheticRotate` - Rotation via TheSafecracker
- `syntheticTwoFingerTap` - Two-finger tap via TheSafecracker
- `syntheticDrawPath` - Path drawing via TheSafecracker
- `typeText` - Text injected via UIKeyboardImpl
- `customAction` - Used custom action
- `editAction` - Edit action via responder chain
- `resignFirstResponder` - Keyboard dismissed
- `waitForIdle` - Wait-for-idle completed
- `elementNotFound` - Element could not be found
- `elementDeallocated` - Element's view was deallocated

### ScreenPayload

```swift
public struct ScreenPayload: Codable, Sendable
```

Screen capture payload.

#### Properties

- `pngData: String` - Base64-encoded PNG data
- `width: Double` - Screen width in points
- `height: Double` - Screen height in points
- `timestamp: Date` - When screenshot was captured

---

## CLI Reference

**Location**: `ButtonHeistCLI/`
**Version**: 2.1.0

All subcommands that connect to a device accept these connection options:

| Option | Description |
|--------|-------------|
| `--device <filter>` | Target a specific device by name, ID prefix, simulator UDID, or vendor ID |
| `--host <address>` | Direct host address — skips Bonjour discovery |
| `--port <number>` | Direct port number — skips Bonjour discovery |
| `--force` | Force-takeover session from another driver |

When `--host` and `--port` are both provided, the CLI connects directly via TCP without Bonjour discovery, reducing latency from ~2s to ~50ms per command.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_HOST` | Default host address (overridden by `--host`) |
| `BUTTONHEIST_PORT` | Default port number (overridden by `--port`) |
| `BUTTONHEIST_DEVICE` | Default device filter (overridden by `--device`) |
| `BUTTONHEIST_TOKEN` | Auth token for InsideMan |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking (distinguishes drivers sharing the same token) |

Flags always take precedence over environment variables.

### buttonheist list

List discovered devices.

```
USAGE: buttonheist list [OPTIONS]

OPTIONS:
  -t, --timeout <seconds> Discovery timeout in seconds (default: 3)
  -f, --format <format>   Output format: human, json (default: human)
```

Human output shows device index, short ID, app name, device name, and any device identifiers (simulator UDID or vendor identifier). JSON output includes all fields.

### buttonheist watch (default)

Watch UI element snapshot in real-time.

```
USAGE: buttonheist watch [OPTIONS]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit
  -q, --quiet             Suppress status messages
  -t, --timeout <seconds> Timeout waiting for device (default: 0 = no timeout)
  -v, --verbose           Show verbose output
  --device <filter>       Target a specific device
  --host <address>        Direct host address (skip Bonjour)
  --port <number>         Direct port number (skip Bonjour)
```

In watch mode, keyboard commands are available:
- `r` or Enter - Refresh hierarchy
- `q` - Quit

Exit codes:
- `0` - Success
- `1` - Connection failed
- `2` - No device found
- `3` - Timeout

### buttonheist action

Perform actions on UI elements.

```
USAGE: buttonheist action [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Traversal index
  --type <type>           Action type: activate, increment, decrement, tap, custom
                          (default: activate)
  --custom-action <name>  Custom action name (required when type is 'custom')
  --x <x>                 X coordinate (for tap type)
  --y <y>                 Y coordinate (for tap type)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist touch

Simulate touch gestures on the connected iOS device.

```
USAGE: buttonheist touch <subcommand>

SUBCOMMANDS:
  tap                     Tap at a point or element
  longpress               Long press at a point or element
  swipe                   Swipe between two points or in a direction
  drag                    Drag from one point to another
  pinch                   Pinch/zoom at a point or element
  rotate                  Rotate at a point or element
  two-finger-tap          Tap with two fingers at a point or element
```

All subcommands accept `--identifier <id>` or `--index <n>` to target an element, or coordinate options (`--x`, `--y`, `--from-x`, `--from-y`, `--to-x`, `--to-y`) for explicit positioning, and `--device` to target a specific device.

### buttonheist type

Type text into a field by tapping keyboard keys.

```
USAGE: buttonheist type [OPTIONS]

OPTIONS:
  --text <text>           Text to type
  --delete <n>            Number of characters to delete before typing
  --identifier <id>       Element identifier (focuses field, reads value back)
  --index <n>             Element index (focuses field, reads value back)
  -t, --timeout <seconds> Timeout in seconds (default: 30)
  -q, --quiet             Suppress status messages
```

Outputs the current text field value to stdout after the operation. If no element target is provided, outputs "success".

Examples:
```bash
# Type text and get the resulting value
buttonheist type --text "Hello" --identifier "nameField"
# Output: Hello

# Delete 3 characters
buttonheist type --delete 3 --identifier "nameField"
# Output: He

# Delete and retype (correction)
buttonheist type --delete 2 --text "llo World" --identifier "nameField"
# Output: Hello World
```

### buttonheist session

Start a persistent interactive session that accepts JSON commands on stdin and emits JSON responses on stdout.

```
USAGE: buttonheist session [OPTIONS]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -t, --timeout <seconds> Timeout waiting for device (default: 0 = no timeout)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

In `--format json` mode, each line of stdin is parsed as a JSON object with a `command` field. Each command produces exactly one JSON response line on stdout.

```bash
# Start an interactive session
buttonheist session --format json

# Commands are sent as JSON lines; responses come back as JSON lines
echo '{"command":"get_interface"}' | buttonheist session --format json --once
```

This command is useful for persistent connections where multiple commands need to share a single TCP session.

### buttonheist screenshot

Capture a screenshot from the connected device.

```
USAGE: buttonheist screenshot [OPTIONS]

OPTIONS:
  -o, --output <path>     Output file path (default: stdout as raw PNG)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

---

## Usage Examples

### Minimal iOS Integration

Just import the framework - it auto-starts:

```swift
import SwiftUI
import InsideMan

@main
struct MyApp: App {
    // InsideMan auto-starts via ObjC +load

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Info.plist:**
```xml
<key>InsideManPort</key>
<integer>1455</integer>
<key>NSLocalNetworkUsageDescription</key>
<string>element inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### SwiftUI Client Integration

```swift
import SwiftUI
import ButtonHeist
import TheGoods

struct InspectorView: View {
    @StateObject private var client = HeistClient()

    var body: some View {
        NavigationSplitView {
            List(client.discoveredDevices, selection: $selectedDevice) { device in
                Text(client.displayName(for: device))
            }
        } detail: {
            if let iface = client.currentInterface {
                List(iface.elements, id: \.order) { element in
                    VStack(alignment: .leading) {
                        Text(element.description)
                        Text(element.identifier ?? "")
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
import ButtonHeist
import TheGoods

class Inspector {
    let client = HeistClient()

    init() {
        client.onDeviceDiscovered = { [weak self] device in
            print("Found: \(device.name)")
            self?.client.connect(to: device)
        }

        client.onConnected = { info in
            print("Connected to \(info.appName) on \(info.deviceName)")
        }

        client.onInterfaceUpdate = { iface in
            print("Received \(iface.elements.count) elements")
            for element in iface.elements {
                print("  \(element.order): \(element.description)")
            }
        }

        client.onActionResult = { result in
            print("Action: \(result.success ? "success" : "failed") via \(result.method)")
        }

        client.onScreen = { screenshot in
            print("Screenshot: \(screenshot.width)x\(screenshot.height)")
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

### Async/Await Action with Result

```swift
// Activate an element and wait for the result
let target = ActionTarget(identifier: "loginButton", order: nil)
client.send(.activate(target))

do {
    let result = try await client.waitForActionResult(timeout: 10)
    print("Result: \(result.success), method: \(result.method)")
} catch {
    print("Timeout waiting for action result")
}
```

### CLI Scripting

```bash
# List all discovered devices
buttonheist list
buttonheist list --format json

# Target a specific device (by short ID, UDID, or name)
buttonheist --device a1b2 watch --once
buttonheist --device DEADBEEF-1234 screenshot --output screen.png

# Get hierarchy as JSON
buttonheist --format json --once > hierarchy.json

# Activate a button
buttonheist action --identifier loginButton

# Increment a slider
buttonheist action --type increment --identifier volumeSlider

# Tap at coordinates
buttonheist action --type tap --x 196.5 --y 659

# Capture screenshot
buttonheist screenshot --output screen.png

# Perform custom action
buttonheist action --type custom --identifier myCell --custom-action "Delete"

# Touch gestures
buttonheist touch tap --x 100 --y 200
buttonheist touch tap --identifier loginButton
buttonheist touch longpress --identifier myButton --duration 1.0
buttonheist touch swipe --identifier list --direction up
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two-finger-tap --identifier zoomControl

# Text entry
buttonheist type --text "Hello World" --identifier nameField
buttonheist type --delete 5 --text "World!" --identifier nameField
```
