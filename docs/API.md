# ButtonHeist API Reference

Complete API documentation for InsideMan (iOS), Wheelman (macOS), and the CLI.

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
4. Starts polling for accessibility hierarchy changes

### Configuration

**Environment variables (highest priority):**
```bash
INSIDEMAN_PORT=1455                  # Server port (0 = auto-assign)
INSIDEMAN_POLLING_INTERVAL=1.0       # Polling interval in seconds (min: 0.5)
INSIDEMAN_DISABLE=true               # Disable auto-start
```

**Info.plist (fallback):**
```xml
<key>InsideManPort</key>
<integer>1455</integer>
<key>InsideManPollingInterval</key>
<real>1.0</real>
<key>InsideManDisableAutoStart</key>
<false/>
```

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

##### configure(port:)

```swift
public static func configure(port: UInt16)
```

Configure the shared instance with a specific port. Must be called before `start()` if not using Info.plist.

**Note**: Normally not needed - use Info.plist configuration instead.

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

Enable automatic polling for accessibility changes.

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

### Touch Gesture System (SafeCracker)

InsideMan uses `SafeCracker` internally for handling all touch gesture commands. SafeCracker supports both single-finger and multi-touch gestures via synthetic UITouch/IOHIDEvent injection.

**Supported gestures:**
- `tap` - Single tap at a point
- `longPress` - Long press with configurable duration
- `swipe` - Quick swipe between two points
- `drag` - Slow drag between two points (for sliders, reordering)
- `pinch` - Two-finger pinch/zoom
- `rotate` - Two-finger rotation
- `twoFingerTap` - Simultaneous two-finger tap

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

## Wheelman

**Import**: `import Wheelman`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/Wheelman/Wheelman.swift`

### Wheelman

Main client class. Conforms to `ObservableObject` for SwiftUI integration.

```swift
@MainActor
public final class Wheelman: ObservableObject
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

##### currentHierarchy

```swift
@Published public private(set) var currentHierarchy: HierarchyPayload?
```

Most recent accessibility hierarchy received from the connected device.

##### currentScreenshot

```swift
@Published public private(set) var currentScreenshot: ScreenshotPayload?
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

##### onHierarchyUpdate

```swift
public var onHierarchyUpdate: ((HierarchyPayload) -> Void)?
```

Called when a new hierarchy is received.

##### onActionResult

```swift
public var onActionResult: ((ActionResult) -> Void)?
```

Called when an action result is received.

##### onScreenshot

```swift
public var onScreenshot: ((ScreenshotPayload) -> Void)?
```

Called when a screenshot is received.

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

Connect to a discovered device. Automatically sends `subscribe`, `requestHierarchy`, and `requestScreenshot` on connection.

**Parameters**:
- `device`: Device to connect to (from `discoveredDevices`).

##### disconnect()

```swift
public func disconnect()
```

Disconnect from the current device and clear all state.

##### requestHierarchy()

```swift
public func requestHierarchy()
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

##### waitForScreenshot(timeout:)

```swift
public func waitForScreenshot(timeout: TimeInterval = 30.0) async throws -> ScreenshotPayload
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
public let protocolVersion = "2.0"
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
- `name: String` - Service name (format: "AppName-DeviceName")
- `endpoint: NWEndpoint` - Network endpoint for connection
- `appName: String` - Extracted app name
- `deviceName: String` - Extracted device name

### ClientMessage

```swift
public enum ClientMessage: Codable
```

Messages sent from client to server.

#### Cases

- `requestHierarchy` - Request current hierarchy
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
- `requestScreenshot` - Request PNG screenshot

### ServerMessage

```swift
public enum ServerMessage: Codable
```

Messages sent from server to client.

#### Cases

- `info(ServerInfo)` - Device/app metadata on connection
- `hierarchy(HierarchyPayload)` - Accessibility hierarchy
- `pong` - Ping response
- `error(String)` - Error description
- `actionResult(ActionResult)` - Action outcome
- `screenshot(ScreenshotPayload)` - Base64-encoded PNG

### ActionTarget

```swift
public struct ActionTarget: Codable, Sendable
```

#### Properties

- `identifier: String?` - Element's accessibility identifier
- `traversalIndex: Int?` - Element's traversal index

### TouchTapTarget

```swift
public struct TouchTapTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget?` - Target element (taps at activation point)
- `pointX: Double?` - Explicit X coordinate
- `pointY: Double?` - Explicit Y coordinate
- `point: CGPoint?` - Computed CGPoint from pointX/pointY

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

- `protocolVersion: String` - Protocol version (e.g., "2.0")
- `appName: String` - App display name
- `bundleIdentifier: String` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points
- `screenSize: CGSize` - Computed from width/height

### HierarchyPayload

```swift
public struct HierarchyPayload: Codable, Sendable
```

Container for accessibility hierarchy snapshot.

#### Properties

- `timestamp: Date` - When the hierarchy was captured
- `elements: [AccessibilityElementData]` - Flat list of accessibility elements
- `tree: [AccessibilityHierarchyNode]?` - Optional tree structure with containers

### AccessibilityHierarchyNode

```swift
public indirect enum AccessibilityHierarchyNode: Codable, Equatable, Sendable
```

Recursive tree structure for accessibility hierarchy.

#### Cases

- `element(traversalIndex: Int)` - Leaf node referencing element by index
- `container(AccessibilityContainerData, children: [AccessibilityHierarchyNode])` - Container with children

### AccessibilityContainerData

```swift
public struct AccessibilityContainerData: Codable, Equatable, Hashable, Sendable
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `containerType` | `String` | "semanticGroup", "list", "landmark", or "dataTable" |
| `label` | `String?` | Container's accessibility label |
| `value` | `String?` | Container's accessibility value |
| `identifier` | `String?` | Container's accessibility identifier |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |
| `traits` | `[String]` | Trait names (e.g., `["tabBar"]`) |

### AccessibilityElementData

```swift
public struct AccessibilityElementData: Codable, Equatable, Hashable, Sendable
```

Represents a single accessibility element.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
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

```swift
public var frame: CGRect       // Frame as CGRect
public var activationPoint: CGPoint  // Activation point as CGPoint
```

### ActionResult

```swift
public struct ActionResult: Codable, Sendable
```

#### Properties

- `success: Bool` - Whether action succeeded
- `method: ActionMethod` - How action was performed
- `message: String?` - Additional context or error description

### ActionMethod

```swift
public enum ActionMethod: String, Codable, Sendable
```

#### Cases

- `accessibilityActivate` - Used accessibility activation
- `accessibilityIncrement` - Used accessibility increment
- `accessibilityDecrement` - Used accessibility decrement
- `syntheticTap` - Tap via SafeCracker
- `syntheticLongPress` - Long press via SafeCracker
- `syntheticSwipe` - Swipe via SafeCracker
- `syntheticDrag` - Drag via SafeCracker
- `syntheticPinch` - Pinch via SafeCracker
- `syntheticRotate` - Rotation via SafeCracker
- `syntheticTwoFingerTap` - Two-finger tap via SafeCracker
- `customAction` - Used custom action
- `elementNotFound` - Element could not be found
- `elementDeallocated` - Element's view was deallocated

### ScreenshotPayload

```swift
public struct ScreenshotPayload: Codable, Sendable
```

#### Properties

- `pngData: String` - Base64-encoded PNG data
- `width: Double` - Screen width in points
- `height: Double` - Screen height in points
- `timestamp: Date` - When screenshot was captured

---

## CLI Reference

**Location**: `ButtonHeistCLI/`
**Version**: 2.0.0

### buttonheist watch (default)

Watch accessibility hierarchy in real-time.

```
USAGE: buttonheist watch [OPTIONS]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit
  -q, --quiet             Suppress status messages
  -t, --timeout <seconds> Timeout waiting for device (default: 0 = no timeout)
  -v, --verbose           Show verbose output
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

Perform actions on accessibility elements.

```
USAGE: buttonheist action [OPTIONS]

OPTIONS:
  --identifier <id>       Element accessibility identifier
  --index <n>             Traversal index
  --type <type>           Action type: activate, increment, decrement, tap, custom
                          (default: activate)
  --custom-action <name>  Custom action name (required when type is 'custom')
  --x <x>                 X coordinate (for tap type)
  --y <y>                 Y coordinate (for tap type)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
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

All subcommands accept `--identifier <id>` or `--index <n>` to target an element, or coordinate options (`--x`, `--y`, `--from-x`, `--from-y`, `--to-x`, `--to-y`) for explicit positioning.

### buttonheist screenshot

Capture a screenshot from the connected device.

```
USAGE: buttonheist screenshot [OPTIONS]

OPTIONS:
  -o, --output <path>     Output file path (default: stdout as raw PNG)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
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
<string>Accessibility inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### SwiftUI Client Integration

```swift
import SwiftUI
import Wheelman
import TheGoods

struct InspectorView: View {
    @StateObject private var client = Wheelman()

    var body: some View {
        NavigationSplitView {
            List(client.discoveredDevices, selection: $selectedDevice) { device in
                Text(client.displayName(for: device))
            }
        } detail: {
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
import Wheelman
import TheGoods

class Inspector {
    let client = Wheelman()

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

        client.onActionResult = { result in
            print("Action: \(result.success ? "success" : "failed") via \(result.method)")
        }

        client.onScreenshot = { screenshot in
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
let target = ActionTarget(identifier: "loginButton", traversalIndex: nil)
client.send(.activate(target))

do {
    let result = try await client.waitForActionResult(timeout: 10)
    print("Result: \(result.success), method: \(result.method)")
} catch {
    print("Timeout waiting for action result")
}
```

### Direct TCP Connection (Python)

```python
from scripts.buttonheist_usb import ButtonHeistUSBConnection

with ButtonHeistUSBConnection() as conn:
    # Get hierarchy
    hierarchy = conn.get_hierarchy()
    for element in hierarchy['elements']:
        print(f"{element['traversalIndex']}: {element['label']}")

    # Activate element
    result = conn.activate(identifier="loginButton")
    print(f"Success: {result['success']}")

    # Tap at coordinates
    result = conn.tap(x=196.5, y=659)
```

### CLI Scripting

```bash
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
```
