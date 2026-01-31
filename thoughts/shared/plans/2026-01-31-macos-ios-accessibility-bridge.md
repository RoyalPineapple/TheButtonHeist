# macOS-iOS Accessibility Bridge Implementation Plan

## Overview

Build a system that allows a macOS companion app to receive and display accessibility hierarchy data from an iOS app running in the Simulator or on a physical device. Uses Bonjour for service discovery and WebSocket for real-time communication.

## Current State Analysis

### Existing Assets

**From `a11y-hierarchy-parsing` branch of AccessibilitySnapshot:**
- `AccessibilityElement` - Codable struct with all element properties
- `AccessibilityHierarchy` - Codable enum (`.element` / `.container`) tree structure
- `AccessibilityContainer` - Codable container metadata
- `AccessibilityHierarchy+Codable.swift` - UIKit type Codable extensions for:
  - `UIAccessibilityTraits` (human-readable array)
  - `UIAccessibilityContainerType` (human-readable string)
  - `Shape` (frame or path with PathElement serialization)

**From research:**
- Window access pattern for SwiftUI lifecycle apps works
- `AccessibilityHierarchyParser.parseAccessibilityHierarchy(in:)` returns `[AccessibilityHierarchy]`

### Key Discoveries
- `AccessibilityHierarchyParser.swift:293-331` - New `parseAccessibilityHierarchy` method returns tree structure
- `AccessibilityHierarchy.swift:20-55` - Tree node enum, already Codable
- `AccessibilityElement.swift:22-231` - Full element data, already Codable

## Desired End State

```
┌─────────────────────────────────────────────────────────────┐
│  macOS Accessibility Inspector App                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Devices: [iPhone 17 Simulator ▼]  [Refresh] [Auto ✓]   ││
│  ├─────────────────────────────────────────────────────────┤│
│  │ ▼ Container: list                                       ││
│  │   ├─ [1] "Globe icon" image                            ││
│  │   ├─ [2] "Greeting" staticText                         ││
│  │   └─ ▼ Container: semanticGroup                        ││
│  │       ├─ [3] "Inspect" button                          ││
│  │       └─ [4] "Explore" button                          ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘

                            │
                            │ WebSocket (JSON)
                            │
┌─────────────────────────────────────────────────────────────┐
│  iOS App (Simulator or Device)                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ AccessibilityBridgeServer                               ││
│  │   - Bonjour advertisement                               ││
│  │   - WebSocket server                                    ││
│  │   - UIAccessibility observation                         ││
│  │   - AccessibilityHierarchyParser integration            ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Verification:**
- macOS app discovers iOS apps on the local network
- Selecting a device shows its accessibility hierarchy
- Hierarchy updates automatically when iOS UI changes

## What We're NOT Doing

- Simulating VoiceOver gestures (future work)
- Executing accessibility actions (future work)
- Screenshot capture (future work)
- USB connectivity (Bonjour works over USB via Xcode connection)
- Multiple simultaneous device connections (single device for now)

## Implementation Approach

1. Create a shared Swift Package for protocol/models (cross-platform)
2. Build iOS server component as a drop-in integration
3. Build macOS client app with SwiftUI

## Phase 1: Shared Protocol Package

### Overview
Create `AccessibilityBridgeProtocol` Swift Package with shared data types and message protocol.

### Changes Required:

#### 1. Package Structure
**Path**: `porto/AccessibilityBridgeProtocol/`

```
AccessibilityBridgeProtocol/
├── Package.swift
└── Sources/
    └── AccessibilityBridgeProtocol/
        ├── Messages.swift          # Protocol messages
        ├── ServiceInfo.swift       # Bonjour service info
        └── Re-exports.swift        # Re-export AccessibilitySnapshot types
```

#### 2. Package.swift
**File**: `porto/AccessibilityBridgeProtocol/Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccessibilityBridgeProtocol",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AccessibilityBridgeProtocol", targets: ["AccessibilityBridgeProtocol"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "AccessibilityBridgeProtocol",
            dependencies: [
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ]
        )
    ]
)
```

#### 3. Messages.swift
**File**: `porto/AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Messages.swift`

```swift
import Foundation
#if canImport(UIKit)
import AccessibilitySnapshotParser
#endif

/// Bonjour service type for discovery
public let accessibilityBridgeServiceType = "_a11ybridge._tcp"

/// Protocol version for compatibility checking
public let protocolVersion = "1.0"

// MARK: - Client -> Server Messages

public enum ClientMessage: Codable {
    /// Request current accessibility hierarchy
    case requestHierarchy

    /// Subscribe to automatic updates
    case subscribe

    /// Unsubscribe from automatic updates
    case unsubscribe

    /// Ping for keepalive
    case ping
}

// MARK: - Server -> Client Messages

public enum ServerMessage: Codable {
    /// Server info on connection
    case info(ServerInfo)

    /// Accessibility hierarchy response/update
    case hierarchy(HierarchyPayload)

    /// Pong response
    case pong

    /// Error message
    case error(String)
}

public struct ServerInfo: Codable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenSize: CGSize

    public init(
        protocolVersion: String,
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenSize: CGSize
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenSize = screenSize
    }
}

public struct HierarchyPayload: Codable {
    public let timestamp: Date
    public let hierarchy: [AccessibilityHierarchyNode]

    public init(timestamp: Date, hierarchy: [AccessibilityHierarchyNode]) {
        self.timestamp = timestamp
        self.hierarchy = hierarchy
    }
}

// MARK: - Cross-Platform Hierarchy Types

/// Platform-agnostic version of AccessibilityHierarchy for macOS consumption
public enum AccessibilityHierarchyNode: Codable, Equatable {
    case element(AccessibilityElementData, traversalIndex: Int)
    case container(AccessibilityContainerData, children: [AccessibilityHierarchyNode])
}

/// Platform-agnostic element data
public struct AccessibilityElementData: Codable, Equatable {
    public var description: String
    public var label: String?
    public var value: String?
    public var traits: [String]  // Human-readable trait names
    public var identifier: String?
    public var hint: String?
    public var frame: CGRect
    public var activationPoint: CGPoint
    public var customActions: [String]  // Action names

    public init(
        description: String,
        label: String?,
        value: String?,
        traits: [String],
        identifier: String?,
        hint: String?,
        frame: CGRect,
        activationPoint: CGPoint,
        customActions: [String]
    ) {
        self.description = description
        self.label = label
        self.value = value
        self.traits = traits
        self.identifier = identifier
        self.hint = hint
        self.frame = frame
        self.activationPoint = activationPoint
        self.customActions = customActions
    }
}

/// Platform-agnostic container data
public struct AccessibilityContainerData: Codable, Equatable {
    public var type: String  // "list", "landmark", "semanticGroup", etc.
    public var label: String?
    public var value: String?
    public var identifier: String?
    public var frame: CGRect
    public var traits: [String]

    public init(
        type: String,
        label: String?,
        value: String?,
        identifier: String?,
        frame: CGRect,
        traits: [String]
    ) {
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.frame = frame
        self.traits = traits
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Package builds for iOS: `swift build --package-path AccessibilityBridgeProtocol`
- [ ] Package builds for macOS: `swift build --package-path AccessibilityBridgeProtocol`
- [ ] Types are Codable: Encode/decode round-trip test passes

#### Manual Verification:
- [ ] N/A for this phase

---

## Phase 2: iOS Server Component

### Overview
Create `AccessibilityBridgeServer` that runs inside the iOS app, advertises via Bonjour, and serves hierarchy data over WebSocket.

### Changes Required:

#### 1. AccessibilityBridgeServer.swift
**File**: `porto/AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Server/AccessibilityBridgeServer.swift`

```swift
#if canImport(UIKit)
import UIKit
import Network
import AccessibilitySnapshotParser

/// Server that exposes accessibility hierarchy over WebSocket
@MainActor
public final class AccessibilityBridgeServer {

    // MARK: - Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var netService: NetService?
    private var subscribedConnections: Set<ObjectIdentifier> = []

    private let port: UInt16
    private let parser = AccessibilityHierarchyParser()

    private var isRunning = false

    // MARK: - Initialization

    public init(port: UInt16 = 0) {
        self.port = port
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        // Create WebSocket listener
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleListenerState(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener.start(queue: .main)
        self.listener = listener
        isRunning = true

        // Start observing accessibility changes
        startAccessibilityObservation()
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil

        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        netService?.stop()
        netService = nil

        stopAccessibilityObservation()
    }

    // MARK: - Private Methods

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                advertiseService(port: port.rawValue)
            }
        case .failed(let error):
            print("[AccessibilityBridge] Listener failed: \(error)")
        default:
            break
        }
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)-\(UIDevice.current.name)"

        netService = NetService(
            domain: "local.",
            type: accessibilityBridgeServiceType,
            name: serviceName,
            port: Int32(port)
        )
        netService?.publish()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection = connection else { return }
            Task { @MainActor in
                self?.handleConnectionState(state, for: connection)
            }
        }

        connection.start(queue: .main)
        receiveMessage(on: connection)

        // Send server info
        sendServerInfo(to: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        switch state {
        case .ready:
            print("[AccessibilityBridge] Client connected")
        case .failed, .cancelled:
            connections.removeAll { $0 === connection }
            subscribedConnections.remove(ObjectIdentifier(connection))
        default:
            break
        }
    }

    private func sendServerInfo(to connection: NWConnection) {
        let info = ServerInfo(
            protocolVersion: protocolVersion,
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            screenSize: UIScreen.main.bounds.size
        )
        send(.info(info), to: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, isComplete, error in
            guard let self = self, let connection = connection else { return }

            if let data = data, let message = try? JSONDecoder().decode(ClientMessage.self, from: data) {
                Task { @MainActor in
                    self.handleClientMessage(message, from: connection)
                }
            }

            if error == nil {
                Task { @MainActor in
                    self.receiveMessage(on: connection)
                }
            }
        }
    }

    private func handleClientMessage(_ message: ClientMessage, from connection: NWConnection) {
        switch message {
        case .requestHierarchy:
            sendHierarchy(to: connection)
        case .subscribe:
            subscribedConnections.insert(ObjectIdentifier(connection))
        case .unsubscribe:
            subscribedConnections.remove(ObjectIdentifier(connection))
        case .ping:
            send(.pong, to: connection)
        }
    }

    private func sendHierarchy(to connection: NWConnection) {
        guard let rootView = getRootView() else {
            send(.error("Could not access root view"), to: connection)
            return
        }

        let hierarchy = parser.parseAccessibilityHierarchy(in: rootView)
        let nodes = hierarchy.map { convertToNode($0) }
        let payload = HierarchyPayload(timestamp: Date(), hierarchy: nodes)
        send(.hierarchy(payload), to: connection)
    }

    private func send(_ message: ServerMessage, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func getRootView() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootView = window.rootViewController?.view else {
            return nil
        }
        return rootView
    }

    // MARK: - Accessibility Observation

    private func startAccessibilityObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
        // Add more observation as needed
    }

    private func stopAccessibilityObservation() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilityDidChange() {
        broadcastHierarchyUpdate()
    }

    private func broadcastHierarchyUpdate() {
        guard !subscribedConnections.isEmpty else { return }
        guard let rootView = getRootView() else { return }

        let hierarchy = parser.parseAccessibilityHierarchy(in: rootView)
        let nodes = hierarchy.map { convertToNode($0) }
        let payload = HierarchyPayload(timestamp: Date(), hierarchy: nodes)
        let message = ServerMessage.hierarchy(payload)

        for connection in connections where subscribedConnections.contains(ObjectIdentifier(connection)) {
            send(message, to: connection)
        }
    }

    // MARK: - Conversion

    private func convertToNode(_ hierarchy: AccessibilityHierarchy) -> AccessibilityHierarchyNode {
        switch hierarchy {
        case let .element(element, index):
            return .element(convertElement(element), traversalIndex: index)
        case let .container(container, children):
            return .container(
                convertContainer(container),
                children: children.map { convertToNode($0) }
            )
        }
    }

    private func convertElement(_ element: AccessibilityElement) -> AccessibilityElementData {
        AccessibilityElementData(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: formatTraits(element.traits),
            identifier: element.identifier,
            hint: element.hint,
            frame: element.shape.frame,
            activationPoint: element.activationPoint,
            customActions: element.customActions.map { $0.name }
        )
    }

    private func convertContainer(_ container: AccessibilityContainer) -> AccessibilityContainerData {
        AccessibilityContainerData(
            type: formatContainerType(container.type),
            label: container.label,
            value: container.value,
            identifier: container.identifier,
            frame: container.frame,
            traits: formatTraits(container.traits)
        )
    }

    private func formatTraits(_ traits: UIAccessibilityTraits) -> [String] {
        var result: [String] = []
        if traits.contains(.button) { result.append("button") }
        if traits.contains(.link) { result.append("link") }
        if traits.contains(.image) { result.append("image") }
        if traits.contains(.staticText) { result.append("staticText") }
        if traits.contains(.header) { result.append("header") }
        if traits.contains(.adjustable) { result.append("adjustable") }
        if traits.contains(.selected) { result.append("selected") }
        if traits.contains(.tabBar) { result.append("tabBar") }
        return result
    }

    private func formatContainerType(_ type: UIAccessibilityContainerType) -> String {
        switch type {
        case .none: return "none"
        case .list: return "list"
        case .landmark: return "landmark"
        case .dataTable: return "dataTable"
        case .semanticGroup: return "semanticGroup"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Shape Helper

private extension AccessibilityElement.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}
#endif
```

#### 2. Integration Example
**File**: Add to `test-aoo/test-aoo/test_aooApp.swift`

```swift
// At top of file
import AccessibilityBridgeProtocol

// In App init:
init() {
    // Start accessibility bridge server
    Task { @MainActor in
        do {
            try AccessibilityBridgeServer.shared.start()
        } catch {
            print("Failed to start accessibility bridge: \(error)")
        }
    }

    // Existing code...
}
```

### Success Criteria:

#### Automated Verification:
- [ ] iOS app builds with server integration
- [ ] Server starts without errors
- [ ] Bonjour service is advertised (check with `dns-sd -B _a11ybridge._tcp`)

#### Manual Verification:
- [ ] Service appears in Bonjour browser (e.g., Discovery app or `dns-sd`)
- [ ] WebSocket connection can be established (test with wscat or similar)

---

## Phase 3: macOS Client App

### Overview
Create SwiftUI macOS app that discovers iOS devices and displays their accessibility hierarchies.

### Changes Required:

#### 1. Project Structure
**Path**: `porto/AccessibilityInspector/`

```
AccessibilityInspector/
├── AccessibilityInspector.xcodeproj/
└── AccessibilityInspector/
    ├── AccessibilityInspectorApp.swift
    ├── Views/
    │   ├── ContentView.swift
    │   ├── DevicePicker.swift
    │   └── HierarchyTreeView.swift
    ├── ViewModels/
    │   └── InspectorViewModel.swift
    └── Services/
        ├── BonjourBrowser.swift
        └── WebSocketClient.swift
```

#### 2. BonjourBrowser.swift
**File**: `porto/AccessibilityInspector/AccessibilityInspector/Services/BonjourBrowser.swift`

```swift
import Foundation
import Network

@MainActor
@Observable
final class BonjourBrowser {

    struct DiscoveredDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: UInt16
    }

    private(set) var devices: [DiscoveredDevice] = []
    private var browser: NWBrowser?

    func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_a11ybridge._tcp", domain: "local."), using: parameters)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var newDevices: [DiscoveredDevice] = []

        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                // Resolve the service to get host/port
                // For simplicity, we'll extract from the endpoint
                newDevices.append(DiscoveredDevice(
                    name: name,
                    host: "localhost", // Will be resolved properly
                    port: 0
                ))
            }
        }

        devices = newDevices
    }
}
```

#### 3. WebSocketClient.swift
**File**: `porto/AccessibilityInspector/AccessibilityInspector/Services/WebSocketClient.swift`

```swift
import Foundation
import AccessibilityBridgeProtocol

@MainActor
@Observable
final class WebSocketClient {

    enum ConnectionState {
        case disconnected
        case connecting
        case connected(ServerInfo)
        case error(String)
    }

    private(set) var state: ConnectionState = .disconnected
    private(set) var hierarchy: [AccessibilityHierarchyNode] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var isSubscribed = false

    func connect(to host: String, port: UInt16) {
        disconnect()
        state = .connecting

        let url = URL(string: "ws://\(host):\(port)")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .disconnected
        hierarchy = []
        isSubscribed = false
    }

    func requestHierarchy() {
        send(.requestHierarchy)
    }

    func subscribe() {
        guard !isSubscribed else { return }
        send(.subscribe)
        isSubscribed = true
    }

    func unsubscribe() {
        guard isSubscribed else { return }
        send(.unsubscribe)
        isSubscribed = false
    }

    private func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                self?.handleReceiveResult(result)
            }
        }
    }

    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            handleMessage(message)
            receiveMessages() // Continue receiving
        case .failure(let error):
            state = .error(error.localizedDescription)
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case let .string(text) = message,
              let data = text.data(using: .utf8),
              let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            return
        }

        switch serverMessage {
        case .info(let info):
            state = .connected(info)
            // Auto-subscribe and request initial hierarchy
            subscribe()
            requestHierarchy()

        case .hierarchy(let payload):
            hierarchy = payload.hierarchy

        case .pong:
            break

        case .error(let message):
            print("Server error: \(message)")
        }
    }
}
```

#### 4. HierarchyTreeView.swift
**File**: `porto/AccessibilityInspector/AccessibilityInspector/Views/HierarchyTreeView.swift`

```swift
import SwiftUI
import AccessibilityBridgeProtocol

struct HierarchyTreeView: View {
    let nodes: [AccessibilityHierarchyNode]

    var body: some View {
        List {
            ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                HierarchyNodeView(node: node)
            }
        }
    }
}

struct HierarchyNodeView: View {
    let node: AccessibilityHierarchyNode
    @State private var isExpanded = true

    var body: some View {
        switch node {
        case let .element(element, index):
            ElementRowView(element: element, index: index)

        case let .container(container, children):
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    HierarchyNodeView(node: child)
                }
            } label: {
                ContainerRowView(container: container)
            }
        }
    }
}

struct ElementRowView: View {
    let element: AccessibilityElementData
    let index: Int

    var body: some View {
        HStack {
            Text("[\(index)]")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(element.label ?? element.description)
                .fontWeight(.medium)

            Spacer()

            if !element.traits.isEmpty {
                Text(element.traits.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ContainerRowView: View {
    let container: AccessibilityContainerData

    var body: some View {
        HStack {
            Image(systemName: containerIcon)
                .foregroundStyle(.blue)

            Text(container.type)
                .fontWeight(.semibold)

            if let label = container.label {
                Text(""\(label)"")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var containerIcon: String {
        switch container.type {
        case "list": return "list.bullet"
        case "landmark": return "mappin"
        case "dataTable": return "tablecells"
        case "semanticGroup": return "square.stack.3d.up"
        case "tabBar": return "menubar.rectangle"
        default: return "folder"
        }
    }
}
```

#### 5. ContentView.swift
**File**: `porto/AccessibilityInspector/AccessibilityInspector/Views/ContentView.swift`

```swift
import SwiftUI
import AccessibilityBridgeProtocol

struct ContentView: View {
    @State private var browser = BonjourBrowser()
    @State private var client = WebSocketClient()
    @State private var selectedDevice: BonjourBrowser.DiscoveredDevice?

    var body: some View {
        NavigationSplitView {
            // Sidebar: Device list
            List(browser.devices, selection: $selectedDevice) { device in
                Label(device.name, systemImage: "iphone")
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem {
                    Button(action: { browser.startBrowsing() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        } detail: {
            // Detail: Hierarchy tree
            if case .connected = client.state {
                VStack {
                    HStack {
                        if case let .connected(info) = client.state {
                            Text(info.appName)
                                .font(.headline)
                            Text("• \(info.deviceName)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh") {
                            client.requestHierarchy()
                        }
                    }
                    .padding()

                    HierarchyTreeView(nodes: client.hierarchy)
                }
            } else {
                ContentUnavailableView(
                    "No Device Selected",
                    systemImage: "iphone.slash",
                    description: Text("Select an iOS device from the sidebar")
                )
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onChange(of: selectedDevice) { oldValue, newValue in
            if let device = newValue {
                client.connect(to: device.host, port: device.port)
            } else {
                client.disconnect()
            }
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] macOS app builds: `xcodebuild -scheme AccessibilityInspector`
- [ ] Protocol package links correctly

#### Manual Verification:
- [ ] App launches and shows device browser
- [ ] iOS devices running the server appear in the list
- [ ] Selecting a device shows its accessibility hierarchy
- [ ] Refresh button updates the hierarchy

---

## Phase 4: Automatic Updates

### Overview
Enhance the iOS server to detect UI changes and push updates to subscribed clients.

### Changes Required:

#### 1. Improved Change Detection
Add to `AccessibilityBridgeServer.swift`:

```swift
// Use a debounced approach to avoid flooding on rapid changes
private var updateDebounceTask: Task<Void, Never>?
private let updateDebounceInterval: TimeInterval = 0.3

private func scheduleHierarchyUpdate() {
    updateDebounceTask?.cancel()
    updateDebounceTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(updateDebounceInterval))
        if !Task.isCancelled {
            broadcastHierarchyUpdate()
        }
    }
}

// Add more observers in startAccessibilityObservation():
NotificationCenter.default.addObserver(
    self,
    selector: #selector(accessibilityDidChange),
    name: UIAccessibility.layoutChangedNotification,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(accessibilityDidChange),
    name: UIAccessibility.screenChangedNotification,
    object: nil
)
```

### Success Criteria:

#### Automated Verification:
- [ ] N/A

#### Manual Verification:
- [ ] Navigate in iOS app and see macOS hierarchy update automatically
- [ ] Updates are debounced (not flooding on rapid changes)

---

## Testing Strategy

### Unit Tests:
- Protocol message encode/decode round-trip
- Hierarchy node conversion correctness
- Trait formatting correctness

### Integration Tests:
- Local server/client connection
- Bonjour discovery on same machine

### Manual Testing Steps:
1. Start iOS app in Simulator
2. Launch macOS inspector app
3. Verify device appears in sidebar
4. Select device and verify hierarchy loads
5. Navigate in iOS app, verify hierarchy updates
6. Test with physical device on same network

## Performance Considerations

- Debounce hierarchy updates to avoid flooding
- Use JSON encoding (human-readable, adequate performance)
- Consider binary encoding for large hierarchies in future
- WebSocket keeps connection alive, no polling overhead

## References

- AccessibilitySnapshot `a11y-hierarchy-parsing` branch
- Research: `research/swiftui-accessibility-insights.md`
- Research: `research/external-accessibility-client.md`
- Test app: `test-aoo/`
