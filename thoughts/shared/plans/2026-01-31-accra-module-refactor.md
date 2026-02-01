# Accra Module Refactor Implementation Plan

## Overview

Refactor the accessibility inspection system into clean, modular components with proper separation of concerns. The inter-app communication and accessibility data passing will be separate from how it's rendered, with clear module boundaries.

## Current State Analysis

### Current Module Structure
```
AccessibilityBridgeProtocol/     → Shared data models (cross-platform)
AccessibilityBridgeServer/       → iOS server (correct boundary)
AccessibilityInspector/
├── Services/BonjourBrowser.swift   → ❌ Networking in UI app
├── Services/WebSocketClient.swift  → ❌ Networking in UI app
├── Views/*                         → UI rendering
├── Design/*                        → Design tokens
└── CLI/
    └── CLIRunner.swift             → ❌ Duplicates networking code
```

### Key Issues
1. **Networking code trapped in GUI app** - BonjourBrowser and WebSocketClient should be reusable
2. **CLI duplicates networking** - CLIRunner.swift lines 66-205 duplicate discovery/connection logic
3. **No clean client API** - Consumers must implement their own networking

## Desired End State

### New Module Structure
```
AccraCore/                    → Shared types (cross-platform)
├── Messages.swift
└── Constants.swift

AccraHost/                    → iOS library
├── AccraHost.swift           → Main entry point (renamed from AccessibilityBridgeServer)
└── (internal implementation)

AccraClient/                  → macOS library (NEW)
├── AccraClient.swift         → Public API
├── DeviceDiscovery.swift     → Bonjour browsing (extracted)
├── DeviceConnection.swift    → WebSocket client (extracted)
└── DiscoveredDevice.swift    → Public model

AccraInspector/               → macOS GUI demo app
├── Views/*                   → UI only
├── Design/*                  → Design tokens
└── InspectorViewModel.swift  → Uses AccraClient

accra CLI/                    → macOS CLI demo app
├── main.swift                → ArgumentParser
└── OutputFormatter.swift     → Human/JSON formatting
```

### Verification
- [ ] `AccraClient` can be imported independently
- [ ] `AccraInspector` has zero networking code
- [ ] CLI has zero networking code
- [ ] Full loop test passes: `swift run accra --once`
- [ ] GUI connects and displays hierarchy

## What We're NOT Doing

- Changing the wire protocol (Messages.swift stays compatible)
- Changing the Bonjour service type (`_a11ybridge._tcp` stays for now)
- Refactoring AccraHost internals (just renaming)
- Adding new features to the inspector apps
- Changing the iOS test apps

## Implementation Approach

1. Create new module structure with Tuist
2. Extract and refactor networking code into AccraClient
3. Update GUI to use AccraClient
4. Update CLI to use AccraClient
5. Rename existing modules to Accra* naming
6. Clean up and verify

---

## Phase 1: Create AccraClient Framework

### Overview
Create the new AccraClient framework with a clean public API. Initially just the shell and public interface.

### Changes Required:

#### 1. Create AccraClient source directory
**Directory**: `AccraClient/Sources/`

Create the public API file:

**File**: `AccraClient/Sources/AccraClient.swift`
```swift
import Foundation
import AccraCore

/// A discovered iOS device running AccraHost
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }
}

/// Client for discovering and connecting to iOS apps running AccraHost
@MainActor
public final class AccraClient: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published public private(set) var connectedDevice: DiscoveredDevice?
    @Published public private(set) var serverInfo: ServerInfo?
    @Published public private(set) var currentHierarchy: HierarchyPayload?
    @Published public private(set) var isDiscovering: Bool = false
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // MARK: - Callbacks (for non-SwiftUI usage)

    public var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?
    public var onConnected: ((ServerInfo) -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onHierarchyUpdate: ((HierarchyPayload) -> Void)?

    // MARK: - Private

    private var discovery: DeviceDiscovery?
    private var connection: DeviceConnection?

    // MARK: - Init

    public init() {}

    // MARK: - Discovery

    public func startDiscovery() {
        // Implementation in Phase 2
    }

    public func stopDiscovery() {
        // Implementation in Phase 2
    }

    // MARK: - Connection

    public func connect(to device: DiscoveredDevice) {
        // Implementation in Phase 2
    }

    public func disconnect() {
        // Implementation in Phase 2
    }

    // MARK: - Commands

    public func requestHierarchy() {
        // Implementation in Phase 2
    }
}
```

#### 2. Update Project.swift with new target

**File**: `Project.swift`
```swift
// Add after AccraCore target:

// MARK: - macOS Client Library
.target(
    name: "AccraClient",
    destinations: .macOS,
    product: .framework,
    bundleId: "com.accra.client",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: ["AccraClient/Sources/**"],
    dependencies: [
        .target(name: "AccraCore"),
    ]
),
```

#### 3. Create directory structure
```bash
mkdir -p AccraClient/Sources
```

### Success Criteria:

#### Automated Verification:
- [ ] `tuist generate` succeeds
- [ ] `xcodebuild -scheme AccraClient build` succeeds
- [ ] Framework can be imported: `import AccraClient`

#### Manual Verification:
- [ ] AccraClient target visible in Xcode

---

## Phase 2: Extract Networking into AccraClient

### Overview
Move BonjourBrowser and WebSocketClient from AccessibilityInspector into AccraClient, adapting them to the new API.

### Changes Required:

#### 1. Create DeviceDiscovery (from BonjourBrowser)

**File**: `AccraClient/Sources/DeviceDiscovery.swift`
```swift
import Foundation
import Network
import AccraCore

@MainActor
final class DeviceDiscovery {

    private var browser: NWBrowser?
    private var discoveredDevices: [String: DiscoveredDevice] = [:]

    var onDeviceFound: ((DiscoveredDevice) -> Void)?
    var onDeviceLost: ((DiscoveredDevice) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: accraServiceType, domain: "local."),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results, changes: changes)
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.onStateChange?(state == .ready)
            }
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        discoveredDevices.removeAll()
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    let device = DiscoveredDevice(
                        id: name,
                        name: name,
                        endpoint: result.endpoint
                    )
                    discoveredDevices[name] = device
                    onDeviceFound?(device)
                }
            case .removed(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    if let device = discoveredDevices.removeValue(forKey: name) {
                        onDeviceLost?(device)
                    }
                }
            default:
                break
            }
        }
    }
}
```

#### 2. Create DeviceConnection (from WebSocketClient)

**File**: `AccraClient/Sources/DeviceConnection.swift`
```swift
import Foundation
import Network
import AccraCore

@MainActor
final class DeviceConnection {

    private var connection: NWConnection?
    private let device: DiscoveredDevice

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onServerInfo: ((ServerInfo) -> Void)?
    var onHierarchy: ((HierarchyPayload) -> Void)?
    var onError: ((String) -> Void)?

    init(device: DiscoveredDevice) {
        self.device = device
    }

    func connect() {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: device.endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }

        connection?.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onConnected?()
            receiveMessages()
        case .failed(let error):
            onDisconnected?(error)
        case .cancelled:
            onDisconnected?(nil)
        default:
            break
        }
    }

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                if let data = data {
                    self?.handleMessage(data)
                }
                if error == nil {
                    self?.receiveMessages()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            return
        }

        switch message {
        case .info(let info):
            onServerInfo?(info)
        case .hierarchy(let payload):
            onHierarchy?(payload)
        case .error(let errorMessage):
            onError?(errorMessage)
        case .pong:
            break
        }
    }
}
```

#### 3. Complete AccraClient implementation

**File**: `AccraClient/Sources/AccraClient.swift`
Update the stub methods with real implementations:

```swift
// MARK: - Discovery

public func startDiscovery() {
    guard !isDiscovering else { return }

    discovery = DeviceDiscovery()
    discovery?.onDeviceFound = { [weak self] device in
        self?.discoveredDevices.append(device)
        self?.onDeviceDiscovered?(device)
    }
    discovery?.onDeviceLost = { [weak self] device in
        self?.discoveredDevices.removeAll { $0.id == device.id }
        self?.onDeviceLost?(device)
    }
    discovery?.onStateChange = { [weak self] isReady in
        self?.isDiscovering = isReady
    }
    discovery?.start()
}

public func stopDiscovery() {
    discovery?.stop()
    discovery = nil
    isDiscovering = false
}

// MARK: - Connection

public func connect(to device: DiscoveredDevice) {
    disconnect()

    connectionState = .connecting
    connection = DeviceConnection(device: device)

    connection?.onConnected = { [weak self] in
        self?.connectionState = .connected
        self?.connectedDevice = device
        self?.connection?.send(.subscribe)
        self?.connection?.send(.requestHierarchy)
    }

    connection?.onDisconnected = { [weak self] error in
        self?.connectionState = .disconnected
        self?.connectedDevice = nil
        self?.serverInfo = nil
        self?.currentHierarchy = nil
        self?.onDisconnected?(error)
    }

    connection?.onServerInfo = { [weak self] info in
        self?.serverInfo = info
        self?.onConnected?(info)
    }

    connection?.onHierarchy = { [weak self] payload in
        self?.currentHierarchy = payload
        self?.onHierarchyUpdate?(payload)
    }

    connection?.onError = { [weak self] message in
        self?.connectionState = .failed(message)
    }

    connection?.connect()
}

public func disconnect() {
    connection?.disconnect()
    connection = nil
    connectionState = .disconnected
    connectedDevice = nil
    serverInfo = nil
    currentHierarchy = nil
}

// MARK: - Commands

public func requestHierarchy() {
    connection?.send(.requestHierarchy)
}
```

### Success Criteria:

#### Automated Verification:
- [ ] `xcodebuild -scheme AccraClient build` succeeds
- [ ] No compiler errors or warnings

#### Manual Verification:
- [ ] N/A (will test in Phase 4)

---

## Phase 3: Rename Existing Modules

### Overview
Rename AccessibilityBridgeProtocol → AccraCore and AccessibilityBridgeServer → AccraHost.

### Changes Required:

#### 1. Rename Protocol to AccraCore

**Directory rename**: `AccessibilityBridgeProtocol/` → `AccraCore/`

**File**: `AccraCore/Sources/AccraCore/Messages.swift`
- Rename constant: `accessibilityBridgeServiceType` → `accraServiceType`
- Keep value same for compatibility: `"_a11ybridge._tcp"`

**File**: `Project.swift`
```swift
// MARK: - Shared Protocol Types (cross-platform)
.target(
    name: "AccraCore",
    destinations: [.iPhone, .iPad, .mac],
    product: .framework,
    bundleId: "com.accra.core",
    deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
    infoPlist: .default,
    sources: ["AccraCore/Sources/AccraCore/**"]
),
```

#### 2. Rename Server to AccraHost

**Directory structure**: Keep sources in place, update target name

**File**: `AccraCore/Sources/AccraHost/AccraHost.swift` (rename from AccessibilityBridgeServer.swift)
- Rename class: `AccessibilityBridgeServer` → `AccraHost`
- Update imports: `import AccessibilityBridgeProtocol` → `import AccraCore`

**File**: `Project.swift`
```swift
// MARK: - iOS Host Library
.target(
    name: "AccraHost",
    destinations: [.iPhone, .iPad],
    product: .framework,
    bundleId: "com.accra.host",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .default,
    sources: ["AccraCore/Sources/AccraHost/**"],
    dependencies: [
        .target(name: "AccraCore"),
        .external(name: "AccessibilitySnapshotParser"),
    ]
),
```

#### 3. Update all imports

Files to update:
- `TestApp/Sources/*.swift`: `import AccessibilityBridgeProtocol` → `import AccraCore`
- `TestApp/Sources/*.swift`: `import AccessibilityBridgeServer` → `import AccraHost`
- `TestApp/UIKitSources/*.swift`: Same changes
- `AccessibilityInspector/**/*.swift`: `import AccessibilityBridgeProtocol` → `import AccraCore`

### Success Criteria:

#### Automated Verification:
- [ ] `tuist generate` succeeds
- [ ] `xcodebuild -scheme AccraCore build` succeeds
- [ ] `xcodebuild -scheme AccraHost -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds

#### Manual Verification:
- [ ] N/A

---

## Phase 4: Refactor GUI Inspector

### Overview
Remove networking code from AccessibilityInspector, use AccraClient instead.

### Changes Required:

#### 1. Delete old networking files
- Delete `AccessibilityInspector/Services/BonjourBrowser.swift`
- Delete `AccessibilityInspector/Services/WebSocketClient.swift`

#### 2. Rename to AccraInspector

**File**: `Project.swift`
```swift
// MARK: - macOS Inspector Demo App
.target(
    name: "AccraInspector",
    destinations: .macOS,
    product: .app,
    bundleId: "com.accra.inspector",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .extendingDefault(with: [
        "NSPrincipalClass": "NSApplication",
        "CFBundleDisplayName": "Accra Inspector",
    ]),
    sources: .sourceFilesList(globs: [
        .glob("AccraInspector/Sources/**")
    ]),
    dependencies: [
        .target(name: "AccraCore"),
        .target(name: "AccraClient"),
    ]
),
```

#### 3. Create InspectorViewModel

**File**: `AccraInspector/Sources/InspectorViewModel.swift`
```swift
import SwiftUI
import AccraCore
import AccraClient

@MainActor
final class InspectorViewModel: ObservableObject {

    let client = AccraClient()

    @Published var selectedDevice: DiscoveredDevice?
    @Published var searchText: String = ""

    var filteredElements: [AccessibilityElementData] {
        guard let elements = client.currentHierarchy?.elements else { return [] }
        guard !searchText.isEmpty else { return elements }

        return elements.filter { element in
            let label = element.label ?? element.description
            return label.localizedCaseInsensitiveContains(searchText)
        }
    }

    init() {
        client.startDiscovery()
    }

    func selectDevice(_ device: DiscoveredDevice?) {
        selectedDevice = device
        if let device = device {
            client.connect(to: device)
        } else {
            client.disconnect()
        }
    }
}
```

#### 4. Update ContentView

**File**: `AccraInspector/Sources/Views/ContentView.swift`
```swift
import SwiftUI
import AccraCore
import AccraClient

struct ContentView: View {
    @StateObject private var viewModel = InspectorViewModel()

    var body: some View {
        NavigationSplitView {
            DeviceListView(
                devices: viewModel.client.discoveredDevices,
                selectedDevice: $viewModel.selectedDevice,
                onSelect: viewModel.selectDevice
            )
        } detail: {
            if viewModel.client.connectionState == .connected {
                HierarchyListView(
                    elements: viewModel.filteredElements,
                    searchText: $viewModel.searchText
                )
            } else if case .connecting = viewModel.client.connectionState {
                ProgressView("Connecting...")
            } else {
                Text("Select a device")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DeviceListView: View {
    let devices: [DiscoveredDevice]
    @Binding var selectedDevice: DiscoveredDevice?
    let onSelect: (DiscoveredDevice?) -> Void

    var body: some View {
        List(devices, selection: $selectedDevice) { device in
            Text(device.name)
                .tag(device)
        }
        .onChange(of: selectedDevice) { _, newValue in
            onSelect(newValue)
        }
        .navigationTitle("Devices")
    }
}
```

#### 5. Move source files
```bash
mkdir -p AccraInspector/Sources/Views
mkdir -p AccraInspector/Sources/Design
mv AccessibilityInspector/AccessibilityInspector/Views/* AccraInspector/Sources/Views/
mv AccessibilityInspector/AccessibilityInspector/Design/* AccraInspector/Sources/Design/
mv AccessibilityInspector/AccessibilityInspector/AccessibilityInspectorApp.swift AccraInspector/Sources/AccraInspectorApp.swift
```

### Success Criteria:

#### Automated Verification:
- [ ] `xcodebuild -scheme AccraInspector build` succeeds
- [ ] No imports of `Network` framework in AccraInspector sources (grep check)

#### Manual Verification:
- [ ] Launch AccraInspector
- [ ] Device list shows running iOS simulators
- [ ] Selecting device shows accessibility hierarchy
- [ ] Search filters elements correctly

---

## Phase 5: Refactor CLI

### Overview
Remove duplicated networking code from CLI, use AccraClient instead.

### Changes Required:

#### 1. Create CLI sources directory
```bash
mkdir -p AccraCLI/Sources
```

#### 2. Update Project.swift (add CLI to Tuist)

**File**: `Project.swift`
```swift
// MARK: - macOS CLI Demo App
.target(
    name: "accra",
    destinations: .macOS,
    product: .commandLineTool,
    bundleId: "com.accra.cli",
    deploymentTargets: .macOS("14.0"),
    sources: ["AccraCLI/Sources/**"],
    dependencies: [
        .target(name: "AccraCore"),
        .target(name: "AccraClient"),
        .external(name: "ArgumentParser"),
    ]
),
```

#### 3. Create simplified main.swift

**File**: `AccraCLI/Sources/main.swift`
```swift
import ArgumentParser
import Foundation
import AccraCore
import AccraClient

@main
struct AccraCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accra",
        abstract: "Inspect iOS app accessibility hierarchy over the network.",
        version: "2.0.0"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @Flag(name: .shortAndLong, help: "Single snapshot then exit")
    var once: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    @MainActor
    mutating func run() async throws {
        let runner = CLIRunner(
            format: format,
            once: once,
            quiet: quiet,
            timeout: timeout,
            verbose: verbose
        )
        try await runner.run()
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
}
```

#### 4. Create CLIRunner using AccraClient

**File**: `AccraCLI/Sources/CLIRunner.swift`
```swift
import Foundation
import AccraCore
import AccraClient
import Darwin

@MainActor
final class CLIRunner {
    private let format: OutputFormat
    private let once: Bool
    private let quiet: Bool
    private let timeout: Int
    private let verbose: Bool

    private let client = AccraClient()
    private var isRunning = true
    private var hasReceivedHierarchy = false

    init(format: OutputFormat, once: Bool, quiet: Bool, timeout: Int, verbose: Bool) {
        self.format = format
        self.once = once
        self.quiet = quiet
        self.timeout = timeout
        self.verbose = verbose
    }

    func run() async throws {
        setupSignalHandler()
        setupClientCallbacks()

        if !quiet {
            log("Searching for iOS devices...")
        }

        client.startDiscovery()

        // Timeout handling
        if timeout > 0 {
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if client.connectedDevice == nil {
                    if !quiet { log("Timeout: No device found") }
                    Darwin.exit(3)
                }
            }
        }

        // Run loop
        while isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func setupSignalHandler() {
        signal(SIGINT) { _ in Darwin.exit(0) }
    }

    private func setupClientCallbacks() {
        client.onDeviceDiscovered = { [weak self] device in
            guard let self = self else { return }
            if !self.quiet {
                self.log("Found device: \(device.name)")
                self.log("Connecting...")
            }
            self.client.connect(to: device)
        }

        client.onConnected = { [weak self] info in
            guard let self = self else { return }
            if !self.quiet {
                self.log("Connected")
            }
            if self.verbose {
                self.log("App: \(info.appName) (\(info.bundleIdentifier))")
                self.log("Device: \(info.deviceName) - iOS \(info.systemVersion)")
            }
        }

        client.onHierarchyUpdate = { [weak self] payload in
            guard let self = self else { return }
            self.hasReceivedHierarchy = true
            self.outputHierarchy(payload)

            if self.once {
                self.isRunning = false
            }
        }

        client.onDisconnected = { [weak self] error in
            if let error = error {
                self?.log("Disconnected: \(error.localizedDescription)")
            }
            self?.isRunning = false
        }
    }

    private func outputHierarchy(_ payload: HierarchyPayload) {
        switch format {
        case .json:
            OutputFormatter.printJSON(payload)
        case .human:
            OutputFormatter.printHuman(payload)
        }
    }

    private func log(_ message: String) {
        fputs("\(message)\n", stderr)
    }
}
```

#### 5. Create OutputFormatter

**File**: `AccraCLI/Sources/OutputFormatter.swift`
```swift
import Foundation
import AccraCore

enum OutputFormatter {

    static func printJSON(_ payload: HierarchyPayload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(payload),
           let json = String(data: data, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }
    }

    static func printHuman(_ payload: HierarchyPayload) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = ""
        output += "Accessibility Hierarchy (\(formatter.string(from: payload.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if payload.elements.isEmpty {
            output += "  (no elements)\n"
        } else {
            for element in payload.elements {
                output += formatElement(element)
            }
        }

        output += String(repeating: "-", count: 60) + "\n"
        output += "Total: \(payload.elements.count) elements\n"

        print(output)
        fflush(stdout)
    }

    private static func formatElement(_ element: AccessibilityElementData) -> String {
        var output = ""
        let index = String(format: "[%2d]", element.traversalIndex)
        let traits = element.traits.isEmpty ? "" : " (\(element.traits.joined(separator: ", ")))"
        let label = element.label ?? element.description

        output += "  \(index) \(label)\(traits)\n"

        if let value = element.value, !value.isEmpty {
            output += "       Value: \(value)\n"
        }
        if let hint = element.hint, !hint.isEmpty {
            output += "       Hint: \(hint)\n"
        }
        if let id = element.identifier, !id.isEmpty {
            output += "       ID: \(id)\n"
        }

        let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))x\(Int(element.frameHeight))"
        output += "       Frame: \(frame)\n"

        return output
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] `xcodebuild -scheme accra build` succeeds
- [ ] No imports of `Network` framework in AccraCLI sources
- [ ] `swift run accra --help` shows help text

#### Manual Verification:
- [ ] `swift run accra --once --verbose` connects and shows hierarchy
- [ ] JSON output works: `swift run accra --once --format json`

---

## Phase 6: Update Test Apps & Cleanup

### Overview
Update iOS test apps to use new module names and clean up old files.

### Changes Required:

#### 1. Update TestApp imports

**File**: `TestApp/Sources/ContentView.swift`
- No changes needed (doesn't import bridge modules)

**File**: `TestApp/Sources/AccessibilityTestApp.swift`
- Add: `import AccraHost`
- Start host on launch

**File**: `TestApp/UIKitSources/AppDelegate.swift`
```swift
import UIKit
import AccraHost

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? AccraHost.shared.start()
        AccraHost.shared.startPolling(interval: 1.0)
        return true
    }
    // ...
}
```

#### 2. Update TestApp/Project.swift

```swift
dependencies: [
    .project(target: "AccraCore", path: ".."),
    .project(target: "AccraHost", path: ".."),
]
```

#### 3. Delete old directories
```bash
rm -rf AccessibilityInspector/
rm -rf AccessibilityBridgeProtocol/
```

#### 4. Update Workspace.swift if needed

#### 5. Final directory structure verification
```
accra/
├── Project.swift
├── Workspace.swift
├── Tuist/
├── AccraCore/
│   └── Sources/
│       ├── AccraCore/
│       │   └── Messages.swift
│       └── AccraHost/
│           └── AccraHost.swift
├── AccraClient/
│   └── Sources/
│       ├── AccraClient.swift
│       ├── DeviceDiscovery.swift
│       ├── DeviceConnection.swift
│       └── DiscoveredDevice.swift
├── AccraInspector/
│   └── Sources/
│       ├── AccraInspectorApp.swift
│       ├── InspectorViewModel.swift
│       ├── Views/
│       └── Design/
├── AccraCLI/
│   └── Sources/
│       ├── main.swift
│       ├── CLIRunner.swift
│       └── OutputFormatter.swift
└── TestApp/
    ├── Project.swift
    ├── Sources/
    └── UIKitSources/
```

### Success Criteria:

#### Automated Verification:
- [ ] `tuist generate` succeeds
- [ ] `xcodebuild -scheme AccraCore build` succeeds
- [ ] `xcodebuild -scheme AccraHost -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds
- [ ] `xcodebuild -scheme AccraClient build` succeeds
- [ ] `xcodebuild -scheme AccraInspector build` succeeds
- [ ] `xcodebuild -scheme accra build` succeeds
- [ ] `xcodebuild -scheme AccessibilityTestApp -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds
- [ ] `xcodebuild -scheme UIKitTestApp -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds

#### Manual Verification:
- [ ] Full loop test: iOS app → CLI reads hierarchy
- [ ] Full loop test: iOS app → GUI shows hierarchy
- [ ] Both SwiftUI and UIKit test apps work

---

## Testing Strategy

### Integration Tests
1. Start iOS test app in simulator
2. Run `accra --once` and verify output
3. Launch AccraInspector and verify device appears
4. Connect and verify hierarchy displays

### Regression Tests
- Verify Bonjour service type still works (`_a11ybridge._tcp`)
- Verify wire protocol compatibility (old clients work with new server)

---

## Migration Notes

- Bonjour service type kept as `_a11ybridge._tcp` for backward compatibility
- Can rename to `_accra._tcp` in future breaking change
- Old SPM Package.swift in AccessibilityInspector/ can be removed (Tuist manages everything)

---

## References

- Current architecture analysis: Agent research from this session
- Design token system: `thoughts/shared/plans/2026-01-31-accessibility-tree-design.md`
