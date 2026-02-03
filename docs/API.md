# Accra API Reference

Complete API documentation for AccraHost (iOS) and AccraClient (macOS).

## AccraHost

**Import**: `import AccraHost`
**Platform**: iOS 17.0+
**Location**: `AccraCore/Sources/AccraHost/AccraHost.swift`

### Overview

AccraHost automatically starts when your app loads via ObjC `+load`. No manual initialization is required - just link the framework and configure your Info.plist.

### Auto-Start Behavior

When the AccraHost framework loads:
1. Reads port from `AccraHostPort` Info.plist key (or `ACCRA_HOST_PORT` env var)
2. Creates a TCP server on the configured port (default: 1455)
3. Begins Bonjour advertisement
4. Starts polling for accessibility hierarchy changes

### Configuration

**Info.plist (recommended):**
```xml
<key>AccraHostPort</key>
<integer>1455</integer>
```

**Environment variable:**
```bash
ACCRA_HOST_PORT=1455
```

### AccraHost Class

Main server class. Use the shared singleton instance.

```swift
@MainActor
public final class AccraHost
```

#### Properties

##### shared

```swift
public static var shared: AccraHost
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

Manually trigger a hierarchy broadcast to connected clients.

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

##### disconnect()

```swift
public func disconnect()
```

Disconnect from the current device.

##### requestHierarchy()

```swift
public func requestHierarchy()
```

Request a single hierarchy snapshot.

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

### Minimal iOS Integration

Just import the framework - it auto-starts:

```swift
import SwiftUI
import AccraHost

@main
struct MyApp: App {
    // AccraHost auto-starts via ObjC +load

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Info.plist:**
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

### SwiftUI Client Integration

```swift
import SwiftUI
import AccraClient
import AccraCore

struct InspectorView: View {
    @StateObject private var client = AccraClient()

    var body: some View {
        NavigationSplitView {
            List(client.discoveredDevices, selection: $selectedDevice) { device in
                Text(device.name)
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

### Direct TCP Connection (Python)

```python
from scripts.accra_usb import AccraUSBConnection

with AccraUSBConnection() as conn:
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
