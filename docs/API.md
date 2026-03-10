# ButtonHeist API Reference

Complete API documentation for TheInsideJob (iOS), TheMastermind (macOS), TheFence (orchestration), and the CLI.

## TheInsideJob

**Import**: `import TheInsideJob`
**Platform**: iOS 17.0+
**Location**: `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift`

### Overview

TheInsideJob automatically starts when your app loads via ObjC `+load`. No manual initialization is required - just link the framework and configure your Info.plist.

### Auto-Start Behavior

When the TheInsideJob framework loads:
1. Reads configuration from environment variables or Info.plist
2. Creates a TCP server on an OS-assigned port
3. Begins Bonjour advertisement as `_buttonheist._tcp`
4. Starts polling for UI element snapshot changes

### Configuration

**Environment variables (highest priority):**
```bash
INSIDEJOB_POLLING_INTERVAL=1.0       # Polling interval in seconds (min: 0.5)
INSIDEJOB_DISABLE=true               # Disable auto-start
INSIDEJOB_DISABLE_FINGERPRINTS=true  # Suppress visual tap/gesture indicators
INSIDEJOB_TOKEN=my-secret-token      # Auth token (fresh UUID auto-generated each launch if not set)
INSIDEJOB_ID=my-instance             # Human-readable instance identifier
INSIDEJOB_SESSION_TIMEOUT=30         # Session release timeout in seconds (default: 30, min: 1)
INSIDEJOB_SESSION_LEASE=30           # Session lease timeout — no pings within window releases session (default: 30, min: 10)
INSIDEJOB_RESTRICT_WATCHERS=1        # Require valid token for watch (observer) connections (default: auto-approve)
```

**Info.plist (fallback):**
```xml
<key>InsideJobPollingInterval</key>
<real>1.0</real>
<key>InsideJobDisableAutoStart</key>
<false/>
<key>InsideJobDisableFingerprints</key>
<false/>
<key>InsideJobToken</key>
<string>my-secret-token</string>
<key>InsideJobInstanceId</key>
<string>my-instance</string>
```

**Client-side:** Set `BUTTONHEIST_TOKEN` environment variable to authenticate with the server.

### TheInsideJob Class

Main server class. Use the shared singleton instance.

```swift
@MainActor
public final class TheInsideJob
```

#### Properties

##### shared

```swift
public static var shared: TheInsideJob
```

Singleton instance. Automatically initialized on framework load.

##### isRunning

```swift
private var isRunning: Bool
```

Whether the server is currently running. This property is private; external code should not need to check server state directly.

#### Methods

##### configure(token:instanceId:)

```swift
public static func configure(token: String? = nil, instanceId: String? = nil)
```

Configure the shared instance with an auth token and instance identifier. Must be called before `start()` if not using Info.plist/environment variables.

**Parameters**:
- `token`: Auth token for client authentication. If nil, auto-generated at startup.
- `instanceId`: Human-readable instance identifier. If nil, falls back to a short UUID prefix.

**Note**: Normally not needed - use Info.plist or environment variable configuration instead.

##### start()

```swift
public func start() throws
```

Start the TCP server and begin Bonjour advertisement.

**Note**: Called automatically on framework load. Manual calls are rarely needed.

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

### Interaction Philosophy: Activation-First

TheInsideJob follows an **activation-first** strategy for all element interactions:

1. **Try `accessibilityActivate()` first** -- TheBagman calls the element's native accessibility activation method via the live object reference. This is the most reliable path because it mirrors how VoiceOver activates controls and respects custom activation behavior.

2. **Fall back to synthetic tap** -- If activation returns `false` or the element does not support it, TheSafecracker injects a synthetic tap at the element's activation point. This is a low-level escape hatch that cannot confirm the gesture was actually handled by the target view.

The same pattern applies to `increment`/`decrement` (native accessibility API first). The `one_finger_tap` command is a pure synthetic tap with no activation-first logic — it is a low-level escape hatch for when coordinate-precise touch injection is needed.

**Why activation-first matters:**
- Native activation respects custom `accessibilityActivate()` overrides
- It works correctly with complex controls (e.g., custom toggle implementations)
- Synthetic taps can miss if the coordinate is occluded by an overlay or the view hierarchy has changed

When a synthetic tap fallback occurs, a debug log is emitted so the behavior is observable.

### Touch Gesture & Text Input System (TheSafecracker)

TheInsideJob uses `TheSafecracker` internally for handling all touch gesture and text input commands. TheSafecracker is an **internal** type -- only TheInsideJob creates and holds the instance. It supports single-finger gestures, multi-touch gestures via synthetic UITouch/IOHIDEvent injection, and text entry via UIKeyboardImpl. TheSafecracker never holds live UIView pointers; it receives only screen coordinates and action outcomes from TheBagman.

**Supported gestures:**
- `one_finger_tap` - Single tap at a point (low-level escape hatch; prefer `activate` for element interactions)
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
- `windowForPoint()` filters out `FingerprintWindow` instances by type check

### Fingerprint Tracking

Visual interaction feedback for taps and continuous gestures. All overlays are displayed via a passthrough `FingerprintWindow` (does not intercept touches). Recordings include the overlay because `captureScreenForRecording()` draws all windows, including `FingerprintWindow`.

**Instant fingerprints** (`showFingerprint(at:)`):
- On successful tap/activate, a 40pt white circle appears at the interaction point
- Scales up to 1.5x and fades out over 0.8 seconds

**Continuous gesture tracking** (`beginTrackingFingerprints` / `updateTrackingFingerprints` / `endTrackingFingerprints`):
- Active during swipe, drag, long press, pinch, rotate, and draw path gestures
- Shows one circle per finger (e.g., 2 circles for pinch/rotate)
- Fast animate in: 0.12 seconds (scale from 0.1x to 1.0x)
- Circles follow touch positions in real-time via `TheSafecracker.onGestureMove` callback
- Slow animate out: 0.6 seconds (scale to 1.5x + fade)

**Recording integration**:
- `FingerprintWindow`: Live UIView-based overlay for on-device display (window level `statusBar + 100`)
- Recordings include fingerprints because `captureScreenForRecording()` draws all windows (including `FingerprintWindow`) via `drawHierarchy`

---

## TheMastermind (macOS Client)

**Import**: `import ButtonHeist`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/TheButtonHeist/TheMastermind.swift`

### TheMastermind

Main client class. Uses the `@Observable` macro for SwiftUI integration.

```swift
@Observable
@ButtonHeistActor
public final class TheMastermind
```

#### Observable Properties

##### discoveredDevices

```swift
public private(set) var discoveredDevices: [DiscoveredDevice]
```

Devices found via Bonjour discovery. Updated automatically when discovery is active.

##### connectedDevice

```swift
public private(set) var connectedDevice: DiscoveredDevice?
```

Currently connected device, or nil if disconnected.

##### connectionState

```swift
public private(set) var connectionState: ConnectionState
```

Current connection state. See `ConnectionState` enum.

##### currentInterface

```swift
public private(set) var currentInterface: Interface?
```

Most recent UI element snapshot received from the connected device.

##### currentScreen

```swift
public private(set) var currentScreen: ScreenPayload?
```

Most recent screenshot received from the connected device.

##### serverInfo

```swift
public private(set) var serverInfo: ServerInfo?
```

Server information received after connecting.

##### isDiscovering

```swift
public private(set) var isDiscovering: Bool
```

Whether Bonjour discovery is currently active.

##### isRecording

```swift
public private(set) var isRecording: Bool
```

Whether a screen recording is currently in progress.

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

##### onRecordingStarted

```swift
public var onRecordingStarted: (() -> Void)?
```

Called when recording has begun.

##### onRecording

```swift
public var onRecording: ((RecordingPayload) -> Void)?
```

Called when a completed recording is received.

##### onRecordingError

```swift
public var onRecordingError: ((String) -> Void)?
```

Called when recording fails.

##### onDisconnected

```swift
public var onDisconnected: ((DisconnectReason) -> Void)?
```

Called when disconnected. The `DisconnectReason` indicates why the connection was closed (see [DisconnectReason](#disconnectreason)).

##### onAuthApproved

```swift
public var onAuthApproved: ((String?) -> Void)?
```

Called when the connection is approved (via token match or on-device UI). For driver connections, the token is provided so the client can store it for future connections. For observer connections, the token is `nil`. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#ui-approval-flow) for details.

> **Note:** These callbacks are on `TheMastermind`. At the network layer, `DeviceConnection` and `DeviceDiscovery` use a single `onEvent` callback with typed enums (`ConnectionEvent`, `DiscoveryEvent`) instead of individual properties. See [DeviceConnecting](#deviceconnecting) and [DeviceDiscovering](#devicediscovering).

##### onSessionLocked

```swift
public var onSessionLocked: ((SessionLockedPayload) -> Void)?
```

Called when the server rejects the connection because another driver holds the active session. The `connectionState` will be set to `.failed` with the payload message. See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#session-locking) for details.

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

##### waitForRecording(timeout:)

```swift
public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload
```

Wait asynchronously for a recording to complete with timeout.

**Parameters**:
- `timeout`: Maximum wait time in seconds (default: 120).

**Throws**: `ActionError.timeout` if no recording received within timeout, or `RecordingError.serverError` if recording fails.

##### displayName(for:)

```swift
public func displayName(for device: DiscoveredDevice) -> String
```

Compute a display name for a device. Returns just the app name if unique among discovered devices, or "AppName (DeviceName)" if disambiguation is needed.

#### ActionError

```swift
public enum ActionError: Error, LocalizedError {
    case timeout
}
```

---

## TheFence (Orchestration Layer)

**Import**: `import ButtonHeist`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence.swift`

### Overview

TheFence is the shared orchestration layer for all command dispatch. Both the CLI (`buttonheist session`) and the MCP server (`buttonheist-mcp`) are thin wrappers over it.

### TheFence Class

```swift
@ButtonHeistActor
public final class TheFence
```

#### Configuration

```swift
public struct Configuration {
    public var deviceFilter: String?        // Target device by name/ID/UDID
    public var connectionTimeout: TimeInterval // Default: 30
    public var token: String?               // Auth token (falls back to BUTTONHEIST_TOKEN env)
    public var autoReconnect: Bool          // Auto-reconnect on disconnect (default: true)
}
```

#### Properties

##### supportedCommands
```swift
public static let supportedCommands: [String]  // From Command.allCases
```

##### onStatus
```swift
public var onStatus: ((String) -> Void)?
```
Called with status messages during connection lifecycle (searching, connecting, reconnecting).

##### onAuthApproved
```swift
public var onAuthApproved: ((String?) -> Void)?
```
Called when the connection is approved. Token is `nil` for observer connections.

#### Methods

##### start()
```swift
public func start() async throws
```
Discover a device, connect, and set up auto-reconnect. Idempotent if already connected.

##### stop()
```swift
public func stop()
```
Disconnect and stop discovery.

##### execute(request:)
```swift
public func execute(request: [String: Any]) async throws -> FenceResponse
```
Execute a command. The `request` dictionary must contain a `command` key. Auto-connects if not already connected. Returns a typed `FenceResponse`.

### Command

```swift
public enum Command: String, CaseIterable, Sendable {
    case help, status, quit, exit
    case listDevices = "list_devices"
    case getInterface = "get_interface"
    // ... 29 total cases
}
```

Single source of truth for the 29 supported commands. Each case has a `rawValue` matching the wire-format string (e.g., `.oneFingerTap` → `"one_finger_tap"`). `Command.allCases` replaces the former hand-maintained string array.

**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift`

### FenceResponse

```swift
public enum FenceResponse
```

Typed response enum with `humanFormatted() -> String` and `jsonDict() -> [String: Any]?` serialization.

#### Cases

| Case | Description |
|------|-------------|
| `ok(message:)` | Generic success with message |
| `error(_:)` | Error with message |
| `help(commands:)` | List of supported commands |
| `status(connected:deviceName:)` | Connection status |
| `devices(_:)` | List of discovered devices |
| `interface(_:)` | UI element snapshot |
| `action(result:)` | Action outcome with delta |
| `screenshot(path:width:height:)` | Screenshot saved to path |
| `screenshotData(pngData:width:height:)` | Screenshot as base64 PNG |
| `recording(path:payload:)` | Recording saved to path |
| `recordingData(payload:)` | Recording as base64 video |

### FenceError

```swift
public enum FenceError: Error, LocalizedError
```

#### Cases

| Case | Description |
|------|-------------|
| `invalidRequest(_:)` | Invalid JSON or missing command |
| `noDeviceFound` | No devices found within timeout |
| `noMatchingDevice(filter:available:)` | No device matching the filter |
| `connectionTimeout` | Connection timed out |
| `connectionFailed(_:)` | Connection failed |
| `sessionLocked(_:)` | Session held by another driver |
| `authFailed(_:)` | Authentication failed |
| `notConnected` | Not connected to device |
| `actionTimeout` | Action timed out, connection lost |
| `actionFailed(_:)` | Action failed with server error message |

### DisconnectReason

```swift
public enum DisconnectReason: Error, LocalizedError
```

Structured reason for why a connection was closed. Passed via `ConnectionEvent.disconnected` on `DeviceConnection` and to `onDisconnected` callbacks on `TheMastermind`.

#### Cases

| Case | Description |
|------|-------------|
| `networkError(_:)` | Underlying network error (wraps the original `Error`) |
| `bufferOverflow` | Server exceeded max buffer size |
| `serverClosed` | Connection closed by server |
| `authFailed(_:)` | Authentication failed with reason |
| `sessionLocked(_:)` | Session locked by another driver |
| `localDisconnect` | Disconnected by client |
| `certificateMismatch` | TLS certificate fingerprint did not match expected value from Bonjour TXT |

---

## ButtonHeistMCP (MCP Server)

**Location**: `ButtonHeistMCP/`
**Binary**: `buttonheist-mcp`
**Platform**: macOS 14.0+

### Overview

MCP server exposing 14 purpose-built tools backed by TheFence. `activate` is the primary interaction tool — it uses the activation-first pattern (accessibility activation, then synthetic tap fallback). Low-level touch gestures are grouped under `gesture` as escape hatches. Build with:

```bash
cd ButtonHeistMCP && swift build -c release
```

### Tools

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `get_interface` | Get UI element hierarchy | — |
| `activate` | **Primary interaction tool.** Activate a UI element (activation-first pattern) | `identifier`, `order` |
| `type_text` | Type text / delete characters | `text`, `deleteCount`, `identifier`, `order` |
| `swipe` | Swipe on element or between coordinates | `identifier`/`order` + `direction`, or `startX`/`startY`/`endX`/`endY` |
| `get_screen` | Capture PNG screenshot | `output` (file path, optional) |
| `wait_for_idle` | Wait for animations to settle | `timeout` |
| `start_recording` | Start H.264/MP4 screen recording | `fps`, `scale`, `maxDuration`, `inactivityTimeout` |
| `stop_recording` | Stop recording (returns metadata) | `output` (file path, optional) |
| `list_devices` | List discovered iOS devices | — |
| `gesture` | Low-level touch gestures (prefer `activate`) | `type` (required): `one_finger_tap`, `drag`, `long_press`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier` |
| `accessibility_action` | Specialized accessibility actions | `type` (required): `increment`, `decrement`, `perform_custom_action`, `edit_action`, `dismiss_keyboard` |
| `scroll` | Scroll a scroll view by one page in a direction | `direction` (required), `identifier`, `order` |
| `scroll_to_visible` | Scroll until target element is fully visible | `identifier`, `order` |
| `scroll_to_edge` | Scroll to an edge of the nearest scroll view | `edge` (required), `identifier`, `order` |

All tools use strict schemas (`additionalProperties: false`) — only documented parameters are accepted.

#### activate

The primary way to interact with buttons, links, and controls. Uses the activation-first pattern: tries `accessibilityActivate()` (like VoiceOver double-tap) first, falls back to synthetic tap at the element's activation point. Provide `identifier` or `order` from `get_interface`.

#### gesture

Low-level touch gesture escape hatch. For element interactions, prefer `activate` instead. The `type` field selects the gesture:

- `one_finger_tap` — Synthetic tap at x/y coordinates
- `drag` — Requires `endX`, `endY`
- `long_press` — Optional `duration` (seconds, default 1.0)
- `pinch` — Requires `scale` (>1 zoom in, <1 zoom out)
- `rotate` — Requires `angle` (radians)
- `two_finger_tap` — Two-finger tap
- `draw_path` — Requires `points` array of `{x, y}` objects
- `draw_bezier` — Requires `curves` array of bezier curve objects

#### accessibility_action

Specialized accessibility actions. For general element interaction, use `activate` instead. The `type` field selects the action:

- `increment` / `decrement` — For sliders, steppers. Requires `identifier` or `order`
- `perform_custom_action` — Requires `identifier`/`order` and `actionName`
- `edit_action` — Requires `action`: `copy`, `paste`, `cut`, `select`, `selectAll`
- `dismiss_keyboard` — No additional params

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | Idle timeout in seconds (default: 60). Disconnects from device after inactivity; next tool call auto-reconnects |

### Response Handling

- Screenshots are returned as inline MCP image content items alongside the JSON payload.
- Recording video data is replaced with a size summary to keep responses readable.
- Error responses set `isError: true` on the MCP result.

---

## TheScore Types

**Import**: `import TheScore`
**Platform**: iOS 17.0+ / macOS 14.0+
**Location**: `ButtonHeist/Sources/TheScore/Messages.swift`

### Constants

```swift
public let buttonHeistServiceType = "_buttonheist._tcp"
public let protocolVersion = "5.0"  // Protocol v5.0 with envelope correlation, watch mode, and TLS transport
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

Represents a discovered TheInsideJob device.

#### Properties

- `id: String` - Unique identifier
- `name: String` - Service name (v3 format: "AppName#instanceId")
- `endpoint: NWEndpoint` - Network endpoint for connection
- `simulatorUDID: String?` - Simulator UDID from Bonjour TXT record (nil on physical devices)
- `vendorIdentifier: String?` - Vendor identifier from Bonjour TXT record
- `instanceId: String?` - Instance identifier from Bonjour TXT record
- `certFingerprint: String?` - TLS certificate SHA-256 fingerprint from Bonjour TXT record (format: `sha256:<hex>`, v5.0+)

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
- `scroll(ScrollTarget)` - Scroll the nearest scroll view ancestor by one page
- `scrollToVisible(ActionTarget)` - Scroll until the target element is visible in the viewport
- `scrollToEdge(ScrollToEdgeTarget)` - Scroll the nearest scroll view ancestor to an edge
- `resignFirstResponder` - Dismiss keyboard
- `waitForIdle(WaitForIdleTarget)` - Wait for animations to settle
- `requestScreen` - Request PNG screenshot
- `startRecording(RecordingConfig)` - Start screen recording (H.264/MP4)
- `stopRecording` - Stop active screen recording

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
- `recordingStarted` - Recording has begun
- `recordingStopped` - Recording stop acknowledged
- `recording(RecordingPayload)` - Completed recording (H.264/MP4 as base64)
- `recordingError(String)` - Recording failed

### AuthenticatePayload

```swift
public struct AuthenticatePayload: Codable, Sendable
```

#### Properties

- `token: String` - Auth token for authentication
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

### ScrollDirection

```swift
public enum ScrollDirection: String, Codable, Sendable
```

#### Cases

- `up` - Scroll up (reveal content above)
- `down` - Scroll down (reveal content below)
- `left` - Scroll left (reveal content to the left)
- `right` - Scroll right (reveal content to the right)
- `next` - Scroll to next page (vertical)
- `previous` - Scroll to previous page (vertical)

### ScrollTarget

```swift
public struct ScrollTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget?` - Element to scroll from (bubbles up to nearest scroll view ancestor)
- `direction: ScrollDirection` - Scroll direction

### ScrollEdge

```swift
public enum ScrollEdge: String, Codable, Sendable
```

#### Cases

- `top` - Scroll to top edge
- `bottom` - Scroll to bottom edge
- `left` - Scroll to left edge
- `right` - Scroll to right edge

### ScrollToEdgeTarget

```swift
public struct ScrollToEdgeTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget?` - Element whose nearest scroll view ancestor to scroll
- `edge: ScrollEdge` - Which edge to scroll to

### ServerInfo

```swift
public struct ServerInfo: Codable, Sendable
```

Device and app metadata received after connecting.

#### Properties

- `protocolVersion: String` - Protocol version (e.g., "5.0")
- `appName: String` - App display name
- `bundleIdentifier: String` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points
- `screenSize: CGSize` - Computed from width/height
- `instanceId: String?` - Per-launch session UUID
- `instanceIdentifier: String?` - Human-readable instance identifier (from `INSIDEJOB_ID` env var, or shortId fallback)
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
- `scroll` - Scroll view scrolled by one page
- `scrollToVisible` - Scroll view adjusted to make element visible
- `scrollToEdge` - Scroll view scrolled to an edge
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

### RecordingConfig

```swift
public struct RecordingConfig: Codable, Sendable
```

Recording configuration sent with `startRecording`.

#### Properties

- `fps: Int?` - Frames per second (default: 8, range: 1-15)
- `scale: Double?` - Resolution scale factor (default: 1.0, range: 0.25-1.0)
- `inactivityTimeout: Double?` - Seconds of inactivity before auto-stop (default: 5.0)
- `maxDuration: Double?` - Maximum recording duration in seconds (default: 60.0)

### RecordingPayload

```swift
public struct RecordingPayload: Codable, Sendable
```

Completed recording payload.

#### Properties

- `videoData: String` - Base64-encoded H.264/MP4 video data
- `width: Int` - Video width in pixels
- `height: Int` - Video height in pixels
- `duration: Double` - Recording duration in seconds
- `frameCount: Int` - Total frames captured
- `fps: Int` - Frames per second used during recording
- `startTime: Date` - When recording started
- `endTime: Date` - When recording ended
- `stopReason: StopReason` - Why recording stopped (`.manual`, `.inactivity`, `.maxDuration`, `.fileSizeLimit`)
- `interactionLog: [InteractionEvent]?` - Ordered log of interactions recorded during the session (nil if no interactions occurred)

### InteractionEvent

```swift
public struct InteractionEvent: Codable, Sendable
```

A single recorded interaction event captured during a Stakeout recording.

#### Properties

- `timestamp: Double` - Time offset from recording start in seconds
- `command: ClientMessage` - The command that triggered this interaction
- `result: ActionResult` - The result returned to the client
- `interfaceDelta: InterfaceDelta?` - Compact delta describing what changed in the hierarchy (from result.interfaceDelta)

---

## CLI Reference

**Location**: `ButtonHeistCLI/`
**Version**: 0.0.1

All subcommands that connect to a device accept these connection options:

| Option | Description |
|--------|-------------|
| `--device <filter>` | Target a specific device by name, ID prefix, simulator UDID, or vendor ID |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter (overridden by `--device`) |
| `BUTTONHEIST_TOKEN` | Auth token for TheInsideJob |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking (distinguishes drivers sharing the same token) |
| `BUTTONHEIST_SESSION_TIMEOUT` | Default idle timeout in seconds for `buttonheist session` (overridden by `--session-timeout`) |

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

### buttonheist activate

Activate a UI element — the primary interaction command. Uses the activation-first pattern: tries `accessibilityActivate()` (like VoiceOver double-tap) first, then falls back to synthetic tap at the element's activation point. This is the most reliable way to interact with buttons, links, and controls.

```
USAGE: buttonheist activate [OPTIONS]

OPTIONS:
  --identifier <id>       Element accessibility identifier
  --index <n>             Element traversal order index
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

Examples:
```bash
buttonheist activate --identifier loginButton
buttonheist activate --index 3
```

### buttonheist action

Perform accessibility actions on UI elements. For activating elements (buttons, links, controls), use `buttonheist activate` instead.

```
USAGE: buttonheist action [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Traversal index
  --type <type>           Action type: activate, increment, decrement, one_finger_tap, custom
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
  one_finger_tap          Tap at a point or element
  long_press              Long press at a point or element
  swipe                   Swipe between two points or in a direction
  drag                    Drag from one point to another
  pinch                   Pinch/zoom at a point or element
  rotate                  Rotate at a point or element
  two_finger_tap          Tap with two fingers at a point or element
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

### buttonheist scroll

Scroll the nearest scroll view ancestor by one page.

```
USAGE: buttonheist scroll [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier (scroll bubbles up to nearest scroll view)
  --index <n>             Element index
  --direction <dir>       Scroll direction: up, down, left, right, next, previous
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist scroll_to_visible

Scroll until a target element is fully visible in the viewport.

```
USAGE: buttonheist scroll_to_visible [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Element index
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist scroll_to_edge

Scroll the nearest scroll view ancestor to an edge.

```
USAGE: buttonheist scroll_to_edge [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Element index
  --edge <edge>           Target edge: top, bottom, left, right
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist session

Start a persistent interactive session that accepts commands on stdin and writes responses to stdout. Interactive mode accepts plain-text commands (e.g. `tap myButton`). JSON input is always accepted (e.g. `{"command":"one_finger_tap"}`). Output is human-readable by default, compact JSON when piped.

```
USAGE: buttonheist session [OPTIONS]

OPTIONS:
  -f, --format <format>           Output format: human, json (default: human)
  -t, --timeout <seconds>         Timeout waiting for device (default: 0 = no timeout)
  --session-timeout <seconds>     Idle timeout — exit if no command received (0 = disabled)
  --token <token>                 Auth token from a previous connection
  --device <filter>               Target a specific device
```

The `--session-timeout` flag exits the session if no commands are received within the specified period. This prevents abandoned agent processes from holding sessions indefinitely. Also configurable via the `BUTTONHEIST_SESSION_TIMEOUT` environment variable.

**Human-friendly input:** In interactive mode, commands can be typed as plain text with positional arguments. Command aliases provide shortcuts for common operations. Use `help` to see all available commands.

| Shorthand | Resolves to |
|-----------|------------|
| `tap <id>` | `one_finger_tap` |
| `ui` | `get_interface` |
| `screen` | `get_screen` |
| `type "text"` | `type_text` |
| `press <id>` | `long_press` |
| `devices` | `list_devices` |
| `idle` | `wait_for_idle` |
| `record` | `start_recording` |

Elements can be targeted by accessibility identifier (`tap myButton`), by order number (`tap #3`), or by coordinates (`tap 100 200`). Key=value pairs work for any parameter (`press identifier=btn duration=2`).

**JSON input:** Each line of stdin can also be a JSON object with a `command` field. Each command produces exactly one response. Use `--format json` to force JSON output.

```bash
# Start an interactive session
buttonheist session

# Plain-text commands
echo 'tap myButton' | buttonheist session --format json

# JSON commands still work
echo '{"command":"get_interface"}' | buttonheist session --format json

# Start a session with a 5-minute idle timeout (for agent use)
buttonheist session --format json --session-timeout 300
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

### buttonheist record

Record the screen as H.264/MP4 video. Recording auto-stops on inactivity.

```
USAGE: buttonheist record [OPTIONS]

OPTIONS:
  -o, --output <path>         Output file path (default: recording.mp4)
  --fps <n>                   Frames per second (default: 8, range: 1-15)
  --scale <factor>            Resolution scale (default: 1.0, range: 0.25-1.0)
  --max-duration <seconds>    Maximum recording duration (default: 60)
  --inactivity-timeout <secs> Auto-stop after N seconds of inactivity (default: 5)
  -t, --timeout <seconds>     Timeout waiting for recording to complete (default: 120)
  -q, --quiet                 Suppress status messages
  --device <filter>           Target a specific device
```

### buttonheist stop_recording

Explicitly stop an in-progress recording. The recording payload is broadcast to all connected clients, so the original `record` process (running in background) receives it and writes the file.

```
USAGE: buttonheist stop_recording [OPTIONS]

OPTIONS:
  --timeout <seconds>     Connection timeout (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist watch

Watch a live session as a read-only observer. Streams JSON events to stdout until killed with Ctrl+C. Does not require a token by default and does not claim a session lock — multiple observers can observe simultaneously alongside an active driver.

```
USAGE: buttonheist watch [OPTIONS]

OPTIONS:
  --device <filter>       Target a specific device by name, ID prefix, or index
  -t, --timeout <seconds> Connection timeout (default: 30)
  --token <token>         Auth token (only needed if server requires INSIDEJOB_RESTRICT_WATCHERS)
```

**Output**: Newline-delimited JSON objects, each with a `type` field:

| Type | Description |
|------|-------------|
| `"info"` | Connection established, contains `ServerInfo` |
| `"interface"` | UI hierarchy update |
| `"interaction"` | Driver performed an action (contains command, result, delta) |

**Examples:**
```bash
# Watch the first available device
buttonheist watch

# Watch a specific device
buttonheist watch --device my-simulator

# Pipe to jq for formatted output
buttonheist watch | jq .

# Watch with auth (when server requires it)
buttonheist watch --token my-secret-token
```

---

## Usage Examples

### Minimal iOS Integration

Just import the framework - it auto-starts:

```swift
import SwiftUI
import TheInsideJob

@main
struct MyApp: App {
    // TheInsideJob auto-starts via ObjC +load

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Info.plist:**
```xml
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
import TheScore

struct InspectorView: View {
    @State private var client = TheMastermind()

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
import TheScore

class Inspector {
    let client = TheMastermind()

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

        client.onDisconnected = { reason in
            print("Disconnected: \(reason)")
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
buttonheist --device a1b2 activate --identifier myButton
buttonheist --device DEADBEEF-1234 screenshot --output screen.png

# Get hierarchy as JSON via session
echo '{"command":"get_interface"}' | buttonheist session --format json

# Activate a button (primary interaction command)
buttonheist activate --identifier loginButton
buttonheist activate --index 3

# Accessibility actions (increment, decrement, custom)
buttonheist action --type increment --identifier volumeSlider
buttonheist action --type decrement --identifier volumeSlider
buttonheist action --type custom --identifier myCell --custom-action "Delete"

# Capture screenshot
buttonheist screenshot --output screen.png

# Touch gestures (low-level escape hatches)
buttonheist touch one_finger_tap --x 100 --y 200
buttonheist touch one_finger_tap --identifier loginButton
buttonheist touch long_press --identifier myButton --duration 1.0
buttonheist touch swipe --identifier list --direction up
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two_finger_tap --identifier zoomControl

# Text entry
buttonheist type --text "Hello World" --identifier nameField
buttonheist type --delete 5 --text "World!" --identifier nameField

# Scroll commands
buttonheist scroll --identifier "buttonheist.longList.item-5" --direction up
buttonheist scroll --index 3 --direction down
buttonheist scroll_to_visible --identifier "buttonheist.longList.last"
buttonheist scroll_to_edge --identifier "buttonheist.longList.item-0" --edge bottom
```
