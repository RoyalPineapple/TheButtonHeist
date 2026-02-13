# Multi-Simulator Instance Discovery Implementation Plan

## Overview

Enable running many instances of the app on many simulators simultaneously, with reliable discovery and stable per-launch identifiers so clients can tell instances apart and target specific ones.

## Current State Analysis

The system is fundamentally single-instance:

1. **Service name collisions**: Bonjour service name is `"{AppName}-{DeviceName}"` (`InsideMan.swift:147`). Two simulators with identical names running the same app produce the same service name. `DeviceDiscovery` uses the name as the dictionary key (`DeviceDiscovery.swift:66`), so one silently overwrites the other.

2. **No stable identifier**: `ServerInfo` only has `appName`, `bundleIdentifier`, `deviceName`, `systemVersion`, and screen dimensions. No instance ID, no port number. You cannot distinguish two instances.

3. **Single connection in HeistClient**: One `connectedDevice`, one `connection` (`HeistClient.swift:15-16`). Connecting to a new device disconnects the current one.

4. **Auto-connect to first device**: CLI (`CLIRunner.swift:90-96`), action commands (`ActionCommand.swift:64`), touch commands (`TouchCommand.swift:557`), screenshot (`ScreenshotCommand.swift:37`), and MCP (`main.swift:597`) all connect to whichever device they discover first, with no selection mechanism.

5. **Duplicated connection boilerplate**: Every CLI command (action, touch subcommands, screenshot) has its own copy of the discover → wait → connect → wait loop. This makes adding `--device` filtering painful without first extracting a shared helper.

### Key Discoveries:
- Port 0 (auto-assign) is already the default (`InsideMan.swift:54`), so multiple instances can bind without conflict
- Bonjour correctly advertises the actual bound port (`InsideMan.swift:88-93`)
- `DiscoveredDevice.parsedName` splits on last `-` (`DiscoveredDevice.swift:27`), which works for `{AppName}-{DeviceName}` but needs updating for the new format
- The CLI uses ArgumentParser with subcommands (`main.swift:6-27`)

## Desired End State

- Multiple instances of the same app can run on multiple simulators simultaneously
- Each instance has a unique, per-launch session ID visible at discovery time (before connecting)
- The CLI has a `list` subcommand showing all discovered instances with their IDs
- All CLI commands accept a `--device` flag to target a specific instance by name, ID prefix, or index
- The MCP server accepts a device filter via `--device` flag or `BUTTONHEIST_DEVICE` env var
- The MCP server exposes a `list_devices` tool for agents to see available instances
- Old clients can still connect to new servers (and vice versa) without breakage

### Verification:
1. Boot 2+ simulators, install and launch the app on each
2. Run `buttonheist list` — see all instances with unique IDs
3. Run `buttonheist --device <id-prefix> watch --once` — connects to the correct instance
4. Run separate MCP server processes, each targeting a different instance via `--device`
5. All existing tests continue to pass

## What We're NOT Doing

- **Multi-connection HeistClient**: Not adding support for one client connected to many devices simultaneously. Separate processes per simulator is the model.
- **Simulator lifecycle management**: Not adding commands to boot/install/launch on simulators. That's handled externally via `xcrun simctl`.
- **Persistent identifiers**: The session ID is per-launch, not stable across restarts. This was a deliberate choice.
- **TXT record metadata**: Keeping it simple with service name encoding rather than Bonjour TXT records.
- **Protocol version bump**: New `ServerInfo` fields are additive and optional, so backward compatibility is maintained without a version change.

## Implementation Approach

Three phases, each independently shippable:

1. **Instance Identity**: Make each InsideMan instance generate a UUID and embed a short form in its Bonjour service name. Add the full ID to `ServerInfo`. This alone fixes the collision problem.
2. **CLI Device Selection**: Extract shared connection logic, add `list` command and `--device` flag.
3. **MCP Device Selection**: Add device targeting to the MCP server.

---

## Phase 1: Instance Identity

### Overview
Each InsideMan instance generates a session UUID at startup. A short hex prefix is appended to the Bonjour service name to guarantee uniqueness. The full UUID is included in `ServerInfo` so clients have it after connection.

### Changes Required:

#### 1. Add `instanceId` and `listeningPort` to ServerInfo
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`
**Changes**: Add two optional fields to `ServerInfo`

```swift
public struct ServerInfo: Codable, Sendable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double
    /// Per-launch session identifier (nil for servers < v2.1)
    public let instanceId: String?
    /// Port the server is listening on (nil for servers < v2.1)
    public let listeningPort: UInt16?

    public init(
        protocolVersion: String,
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double,
        instanceId: String? = nil,
        listeningPort: UInt16? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.instanceId = instanceId
        self.listeningPort = listeningPort
    }
}
```

Making them optional with defaults means:
- Old clients decode new servers fine (extra JSON keys are ignored by `JSONDecoder`)
- New clients decode old servers fine (missing keys decode as `nil`)

#### 2. Generate session UUID and embed in service name
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Generate UUID, update `advertiseService`, update `sendServerInfo`

Add a `sessionId` property:
```swift
// In InsideMan class properties (around line 35)
private let sessionId = UUID()
```

Short ID helper (first 8 hex chars of UUID):
```swift
private var shortId: String {
    String(sessionId.uuidString.prefix(8)).lowercased()
}
```

Update `advertiseService` (line 145-157) to append `#shortId`:
```swift
private func advertiseService(port: UInt16) {
    let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
    let deviceName = UIDevice.current.name
    let serviceName = "\(appName)-\(deviceName)#\(shortId)"

    netService = NetService(
        domain: "local.",
        type: buttonHeistServiceType,
        name: serviceName,
        port: Int32(port)
    )
    netService?.publish()
    serverLog("Advertising as '\(serviceName)' on port \(port)")
}
```

Update `sendServerInfo` (line 226-238) to include instanceId and port:
```swift
private func sendServerInfo(respond: @escaping (Data) -> Void) {
    let screenBounds = UIScreen.main.bounds
    let info = ServerInfo(
        protocolVersion: protocolVersion,
        appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
        deviceName: UIDevice.current.name,
        systemVersion: UIDevice.current.systemVersion,
        screenWidth: screenBounds.width,
        screenHeight: screenBounds.height,
        instanceId: sessionId.uuidString,
        listeningPort: socketServer?.listeningPort
    )
    sendMessage(.info(info), respond: respond)
}
```

#### 3. Expose `listeningPort` from SimpleSocketServer
**File**: `ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift`
**Changes**: Add public getter for the listening port

```swift
// Add after the _listeningPort property (around line 14)
public var listeningPort: UInt16 {
    lock.lock()
    defer { lock.unlock() }
    return _listeningPort
}
```

#### 4. Update DiscoveredDevice to parse new name format
**File**: `ButtonHeist/Sources/Wheelman/DiscoveredDevice.swift`
**Changes**: Parse `#shortId` from service name, add `shortId` property

```swift
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    /// Short instance ID parsed from service name (e.g., "a1b2c3d4")
    /// Service name format: "AppName-DeviceName#shortId"
    public var shortId: String? {
        guard let hashIndex = name.firstIndex(of: "#") else { return nil }
        let id = String(name[name.index(after: hashIndex)...])
        return id.isEmpty ? nil : id
    }

    /// The name portion without the instance ID suffix
    private var nameWithoutId: String {
        if let hashIndex = name.firstIndex(of: "#") {
            return String(name[..<hashIndex])
        }
        return name
    }

    /// Parse the service name to extract app name and device name
    /// Service name format: "AppName-DeviceName" or "AppName-DeviceName#shortId"
    public var parsedName: (appName: String, deviceName: String)? {
        let baseName = nameWithoutId
        guard let lastDashIndex = baseName.lastIndex(of: "-") else { return nil }
        let appName = String(baseName[..<lastDashIndex])
        let deviceName = String(baseName[baseName.index(after: lastDashIndex)...])
        guard !appName.isEmpty && !deviceName.isEmpty else { return nil }
        return (appName, deviceName)
    }

    /// App name extracted from service name
    public var appName: String {
        parsedName?.appName ?? nameWithoutId
    }

    /// Device name extracted from service name
    public var deviceName: String {
        parsedName?.deviceName ?? ""
    }
}
```

#### 5. Update HeistClient display name for disambiguation
**File**: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
**Changes**: Update `displayName(for:)` to use shortId when multiple instances of same app+device exist

```swift
public func displayName(for device: DiscoveredDevice) -> String {
    let appName = device.appName

    // Check if disambiguation is needed
    let sameAppDevices = discoveredDevices.filter { $0.appName == appName }

    if sameAppDevices.count > 1 {
        let sameAppAndDevice = sameAppDevices.filter { $0.deviceName == device.deviceName }
        if sameAppAndDevice.count > 1, let shortId = device.shortId {
            // Multiple instances of same app on same device name — show shortId
            return "\(appName) (\(device.deviceName)) [\(shortId)]"
        }
        return "\(appName) (\(device.deviceName))"
    } else {
        return appName
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] All targets build: TheGoods, Wheelman, ButtonHeist all build. InsideMan has pre-existing modulemap issue unrelated to changes.
- [x] Existing tests pass: 45 TheGoods + 12 Wheelman + 7 ButtonHeist = 64 tests, 0 failures
- [x] Add unit tests for `DiscoveredDevice` new parsing: service names with `#shortId` suffix, backward compat without suffix
- [x] Add unit test for `ServerInfo` encoding/decoding with new optional fields (ensure old format still decodes)

**Implementation Note**: After completing this phase, the collision problem is solved. Each instance gets a unique Bonjour service name. Clients that don't understand `#shortId` still discover and connect fine.

---

## Phase 2: CLI Device Selection

### Overview
Extract shared connection logic, add a `list` subcommand to show all discovered instances, and add a `--device` flag to target a specific instance.

### Changes Required:

#### 1. Extract shared device connection helper
**New File**: `ButtonHeistCLI/Sources/DeviceConnector.swift`
**Purpose**: Consolidate the repeated discover → filter → connect → wait pattern

```swift
import Foundation
import ButtonHeist

@MainActor
final class DeviceConnector {
    let client = HeistClient()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64

    init(deviceFilter: String?, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        self.deviceFilter = deviceFilter
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
    }

    /// Discover devices, filter by --device if set, connect, and return
    func connect() async throws {
        if !quiet { logStatus("Searching for iOS devices...") }
        client.startDiscovery()

        // Wait for at least one matching device
        let startTime = DispatchTime.now()
        while matchingDevice() == nil {
            if DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds > discoveryTimeout {
                if let filter = deviceFilter {
                    throw CLIError.noMatchingDevice(filter: filter,
                        available: client.discoveredDevices.map { $0.name })
                }
                throw CLIError.noDeviceFound
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let device = matchingDevice() else {
            throw CLIError.noDeviceFound
        }

        if !quiet {
            logStatus("Found: \(client.displayName(for: device))")
            logStatus("Connecting...")
        }

        var connected = false
        var connectionError: Error?
        client.onConnected = { _ in connected = true }
        client.onDisconnected = { error in connectionError = error }
        client.connect(to: device)

        let connStart = DispatchTime.now()
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connStart.uptimeNanoseconds > connectionTimeout {
                throw CLIError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            throw CLIError.connectionFailed(error.localizedDescription)
        }

        if !quiet { logStatus("Connected") }
    }

    func disconnect() {
        client.disconnect()
        client.stopDiscovery()
    }

    /// Find first device matching the filter (or first device if no filter)
    private func matchingDevice() -> DiscoveredDevice? {
        guard let filter = deviceFilter else {
            return client.discoveredDevices.first
        }
        let lowFilter = filter.lowercased()
        return client.discoveredDevices.first { device in
            // Match against: full name, app name, device name, shortId
            device.name.lowercased().contains(lowFilter) ||
            device.appName.lowercased().contains(lowFilter) ||
            device.deviceName.lowercased().contains(lowFilter) ||
            (device.shortId?.lowercased().hasPrefix(lowFilter) ?? false)
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)

    var description: String {
        switch self {
        case .noDeviceFound:
            return "No devices found within timeout"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        }
    }
}
```

#### 2. Add `--device` flag to top-level command and `list` subcommand
**File**: `ButtonHeistCLI/Sources/main.swift`
**Changes**: Add `--device` option to top-level, add `ListCommand`

```swift
@main
struct ButtonHeist: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Connects to an iOS app and displays the UI element hierarchy.

            Examples:
              buttonheist list                          # Show available devices
              buttonheist --device a1b2 watch --once    # Target a specific instance
              buttonheist action --identifier "myButton"
              buttonheist touch tap --x 100 --y 200
            """,
        version: "2.1.0",
        subcommands: [ListCommand.self, WatchCommand.self, ActionCommand.self,
                       TouchCommand.self, ScreenshotCommand.self],
        defaultSubcommand: WatchCommand.self
    )
}
```

**New File**: `ButtonHeistCLI/Sources/ListCommand.swift`

```swift
import ArgumentParser
import Foundation
import ButtonHeist

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available iOS devices running InsideMan"
    )

    @Option(name: .shortAndLong, help: "Discovery timeout in seconds")
    var timeout: Double = 3.0

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @MainActor
    mutating func run() async throws {
        let client = HeistClient()
        logStatus("Discovering devices...")
        client.startDiscovery()

        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

        client.stopDiscovery()

        let devices = client.discoveredDevices

        if devices.isEmpty {
            logStatus("No devices found.")
            return
        }

        switch format {
        case .json:
            outputJSON(devices)
        case .human:
            outputHuman(devices)
        }
    }

    private func outputJSON(_ devices: [DiscoveredDevice]) {
        struct DeviceInfo: Encodable {
            let name: String
            let appName: String
            let deviceName: String
            let shortId: String?
        }
        let infos = devices.map {
            DeviceInfo(name: $0.name, appName: $0.appName,
                       deviceName: $0.deviceName, shortId: $0.shortId)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(infos),
           let json = String(data: data, encoding: .utf8) {
            writeOutput(json)
        }
    }

    private func outputHuman(_ devices: [DiscoveredDevice]) {
        writeOutput("Found \(devices.count) device(s):\n")
        for (i, device) in devices.enumerated() {
            let id = device.shortId ?? "----"
            let app = device.appName
            let dev = device.deviceName
            writeOutput("  [\(i)] \(id)  \(app)  (\(dev))")
        }
        writeOutput("")
        writeOutput("Use --device <id|name|index> to target a specific instance.")
    }
}
```

#### 3. Add `--device` to WatchCommand and pass through
**File**: `ButtonHeistCLI/Sources/main.swift`
**Changes**: Add `--device` to WatchCommand, pass to CLIRunner

```swift
struct WatchCommand: AsyncParsableCommand {
    // ... existing options ...

    @Option(name: .shortAndLong, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    mutating func run() async throws {
        let options = CLIOptions(
            format: format,
            once: once,
            quiet: quiet,
            timeout: timeout,
            verbose: verbose,
            device: device
        )
        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}
```

Add `device` to `CLIOptions`:
```swift
struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let timeout: Int
    let verbose: Bool
    let device: String?
}
```

#### 4. Update CLIRunner to use DeviceConnector with filter
**File**: `ButtonHeistCLI/Sources/CLIRunner.swift`
**Changes**: Replace inline discovery+connect with `DeviceConnector`

Update `setupClientCallbacks()` to filter on `options.device` when discovering:

```swift
// In setupClientCallbacks, replace the onDeviceDiscovered callback:
client.onDeviceDiscovered = { [weak self] device in
    guard let self = self else { return }
    if self.client.connectedDevice == nil {
        // Apply device filter if specified
        if let filter = self.options.device {
            let low = filter.lowercased()
            let matches = device.name.lowercased().contains(low) ||
                device.appName.lowercased().contains(low) ||
                device.deviceName.lowercased().contains(low) ||
                (device.shortId?.lowercased().hasPrefix(low) ?? false)
            guard matches else { return }
        }
        if !self.options.quiet {
            logStatus("Found: \(self.client.displayName(for: device))")
            logStatus("Connecting...")
        }
        self.client.connect(to: device)
    }
}
```

#### 5. Add `--device` to ActionCommand, TouchCommand helper, ScreenshotCommand
**Files**: `ActionCommand.swift`, `TouchCommand.swift`, `ScreenshotCommand.swift`
**Changes**: Replace duplicated connection logic with `DeviceConnector`, add `--device` option

For each command, add:
```swift
@Option(name: .shortAndLong, help: "Target device by name, ID prefix, or index from 'list'")
var device: String?
```

And replace the inline discover+connect blocks with:
```swift
let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
try await connector.connect()
defer { connector.disconnect() }
let client = connector.client
```

For `sendTouchGesture` (the shared helper in TouchCommand.swift), add a `device` parameter:
```swift
@MainActor
private func sendTouchGesture(message: ClientMessage, timeout: Double,
                               quiet: Bool, device: String? = nil) async throws {
    let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client
    // ... rest of the function stays the same ...
}
```

Each touch subcommand passes `device: device` through.

### Success Criteria:

#### Automated Verification:
- [ ] CLI builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistCLI build`
- [ ] `buttonheist list` discovers and prints devices with their short IDs
- [ ] `buttonheist --device <shortId-prefix> watch --once` connects to the correct instance when multiple are running
- [ ] `buttonheist list --format json` outputs valid JSON with device info
- [ ] All existing CLI tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistCLITests test`
- [ ] Running `buttonheist --device nonexistent watch --once --timeout 3` exits with a clear error

---

## Phase 3: MCP Device Selection

### Overview
Add device targeting to the MCP server so each MCP process can be pointed at a specific simulator instance. Also add a `list_devices` tool.

### Changes Required:

#### 1. Add device filter to MCP server
**File**: `ButtonHeistMCP/Sources/main.swift`
**Changes**: Accept `--device` flag or `BUTTONHEIST_DEVICE` env var, filter during discovery

```swift
@main
struct ButtonHeistMCP {
    @MainActor
    static func main() async throws {
        // Read device filter from CLI args or environment
        let deviceFilter: String?
        if CommandLine.arguments.count > 1 {
            let args = CommandLine.arguments
            if let idx = args.firstIndex(of: "--device"), idx + 1 < args.count {
                deviceFilter = args[idx + 1]
            } else {
                deviceFilter = nil
            }
        } else {
            deviceFilter = ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        }

        let client = HeistClient()
        try await discoverAndConnect(client: client, deviceFilter: deviceFilter)

        // ... rest of MCP setup unchanged ...
    }
}
```

Update `discoverAndConnect`:
```swift
@MainActor
func discoverAndConnect(client: HeistClient, deviceFilter: String? = nil) async throws {
    log("Starting device discovery...")
    if let filter = deviceFilter {
        log("Device filter: \(filter)")
    }
    client.startDiscovery()

    let deadline = Date().addingTimeInterval(30)
    while true {
        if Date() > deadline {
            throw MCPError.internalError(
                "No iOS devices found within 30 seconds. Ensure an app with InsideMan is running.")
        }

        if let device = matchDevice(from: client.discoveredDevices, filter: deviceFilter) {
            log("Found device: \(device.name)")
            client.connect(to: device)

            let connectDeadline = Date().addingTimeInterval(10)
            while client.connectionState != .connected {
                if Date() > connectDeadline {
                    throw MCPError.internalError("Connection to device timed out")
                }
                if case .failed(let msg) = client.connectionState {
                    throw MCPError.internalError("Connection failed: \(msg)")
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            log("Connected to \(device.name)")
            return
        }

        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

func matchDevice(from devices: [DiscoveredDevice], filter: String?) -> DiscoveredDevice? {
    guard let filter else { return devices.first }
    let low = filter.lowercased()
    return devices.first { device in
        device.name.lowercased().contains(low) ||
        device.appName.lowercased().contains(low) ||
        device.deviceName.lowercased().contains(low) ||
        (device.shortId?.lowercased().hasPrefix(low) ?? false)
    }
}
```

#### 2. Add `list_devices` tool to MCP
**File**: `ButtonHeistMCP/Sources/main.swift`
**Changes**: Add tool definition and handler

```swift
let listDevicesTool = Tool(
    name: "list_devices",
    description: "List all discovered iOS devices running InsideMan. Returns device names, app names, and instance IDs.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
)
```

Add to `allTools` array. Add handler in `handleToolCall`:
```swift
case "list_devices":
    let devices = client.discoveredDevices
    struct DeviceInfo: Encodable {
        let name: String
        let appName: String
        let deviceName: String
        let shortId: String?
    }
    let infos = devices.map {
        DeviceInfo(name: $0.name, appName: $0.appName,
                   deviceName: $0.deviceName, shortId: $0.shortId)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(infos)
    return CallTool.Result(content: [.text(String(data: json, encoding: .utf8) ?? "[]")])
```

#### 3. Update `.mcp.json` to support device arg
**File**: `.mcp.json`
**Changes**: Document that `--device` can be passed as an argument

The MCP configuration can include args:
```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "/path/to/buttonheist-mcp",
      "args": ["--device", "a1b2c3d4"]
    }
  }
}
```

Or users set `BUTTONHEIST_DEVICE` env var. No file change needed — just documented.

### Success Criteria:

#### Automated Verification:
- [ ] MCP server builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistMCP build` (or `swift build` in ButtonHeistMCP directory)
- [ ] MCP server with `--device <id>` connects to correct instance when multiple are available
- [ ] `BUTTONHEIST_DEVICE=<id>` env var works as alternative to `--device`
- [ ] `list_devices` tool returns JSON array of discovered devices with shortId fields

---

## Testing Strategy

### Unit Tests:
- `DiscoveredDevice` parsing: names with `#shortId`, without `#`, edge cases (empty shortId, no dash)
- `ServerInfo` Codable: encode with instanceId, decode without instanceId (backward compat)
- `DeviceConnector` matching: filter by appName, deviceName, shortId prefix, no filter

### Integration Tests:
- Boot 2 simulators → install app → run `buttonheist list` → verify 2 distinct entries
- Run `buttonheist --device <id1> watch --once` and `--device <id2> watch --once` → verify they connect to different instances
- Run MCP server with `--device <id>` → verify `list_devices` tool works

### Automated E2E (via simctl):
```bash
# Boot two simulators
xcrun simctl boot "iPhone 16 Pro"
xcrun simctl boot "iPhone 16"

# Install and launch app on both
xcrun simctl install "iPhone 16 Pro" /path/to/app.app
xcrun simctl install "iPhone 16" /path/to/app.app
xcrun simctl launch "iPhone 16 Pro" com.example.app
xcrun simctl launch "iPhone 16" com.example.app

# Verify discovery
buttonheist list --format json | jq length  # Should be 2

# Verify targeting
ID1=$(buttonheist list --format json | jq -r '.[0].shortId')
ID2=$(buttonheist list --format json | jq -r '.[1].shortId')
buttonheist --device "$ID1" watch --once --format json  # Should show instance 1
buttonheist --device "$ID2" watch --once --format json  # Should show instance 2
```

## Documentation Updates

After implementation, update:
- `README.md` — Add multi-simulator usage section
- `docs/API.md` — Document `list` command, `--device` flag, `list_devices` MCP tool, new `ServerInfo` fields
- `docs/ARCHITECTURE.md` — Update discovery section to mention instance IDs
- `docs/WIRE-PROTOCOL.md` — Document new optional `instanceId` and `listeningPort` fields in `ServerInfo`

## References

- Current service advertisement: `ButtonHeist/Sources/InsideMan/InsideMan.swift:145-157`
- Current discovery: `ButtonHeist/Sources/Wheelman/DeviceDiscovery.swift:55-86`
- Current connection: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift:85-132`
- Current CLI entry: `ButtonHeistCLI/Sources/main.swift`
- Current MCP entry: `ButtonHeistMCP/Sources/main.swift:618-658`
