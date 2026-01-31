#if canImport(UIKit)
import UIKit
import Network
import AccessibilitySnapshotParser
import AccessibilityBridgeProtocol

/// Server that exposes accessibility hierarchy over WebSocket
@MainActor
public final class AccessibilityBridgeServer {

    // MARK: - Singleton

    public static let shared = AccessibilityBridgeServer()

    // MARK: - Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var netService: NetService?
    private var subscribedConnections: Set<ObjectIdentifier> = []

    private let port: UInt16
    private let parser = AccessibilityHierarchyParser()

    private var isRunning = false

    // Debounce for hierarchy updates
    private var updateDebounceTask: Task<Void, Never>?
    private let updateDebounceInterval: UInt64 = 300_000_000 // 300ms in nanoseconds

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

        let listenerPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: parameters, on: listenerPort)

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

        print("[AccessibilityBridge] Server starting...")
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

        print("[AccessibilityBridge] Server stopped")
    }

    // MARK: - Private Methods - Listener

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                print("[AccessibilityBridge] Listening on port \(port.rawValue)")
                advertiseService(port: port.rawValue)
            }
        case .failed(let error):
            print("[AccessibilityBridge] Listener failed: \(error)")
        case .cancelled:
            print("[AccessibilityBridge] Listener cancelled")
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
        print("[AccessibilityBridge] Advertising as '\(serviceName)' on port \(port)")
    }

    // MARK: - Private Methods - Connections

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

        // Send server info immediately
        sendServerInfo(to: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        switch state {
        case .ready:
            print("[AccessibilityBridge] Client connected")
        case .failed(let error):
            print("[AccessibilityBridge] Connection failed: \(error)")
            removeConnection(connection)
        case .cancelled:
            print("[AccessibilityBridge] Client disconnected")
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        subscribedConnections.remove(ObjectIdentifier(connection))
    }

    private func sendServerInfo(to connection: NWConnection) {
        let screenBounds = UIScreen.main.bounds
        let info = ServerInfo(
            protocolVersion: protocolVersion,
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            screenWidth: screenBounds.width,
            screenHeight: screenBounds.height
        )
        send(.info(info), to: connection)
    }

    // MARK: - Private Methods - Message Handling

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
            print("[AccessibilityBridge] Hierarchy requested")
            sendHierarchy(to: connection)
        case .subscribe:
            print("[AccessibilityBridge] Client subscribed to updates")
            subscribedConnections.insert(ObjectIdentifier(connection))
        case .unsubscribe:
            print("[AccessibilityBridge] Client unsubscribed from updates")
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

        let markers = parser.parseAccessibilityElements(in: rootView)
        let elements = markers.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
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
        // Observe VoiceOver focus changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
        // Observe VoiceOver status changes (when enabled/disabled)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
        // Note: layoutChangedNotification and screenChangedNotification are for
        // POSTING accessibility notifications, not observing them.
        // Additional change detection would require app-level integration.
    }

    private func stopAccessibilityObservation() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilityDidChange() {
        scheduleHierarchyUpdate()
    }

    private func scheduleHierarchyUpdate() {
        updateDebounceTask?.cancel()
        updateDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: updateDebounceInterval)
            if !Task.isCancelled {
                broadcastHierarchyUpdate()
            }
        }
    }

    private func broadcastHierarchyUpdate() {
        guard !subscribedConnections.isEmpty else { return }
        guard let rootView = getRootView() else { return }

        let markers = parser.parseAccessibilityElements(in: rootView)
        let elements = markers.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
        let message = ServerMessage.hierarchy(payload)

        for connection in connections where subscribedConnections.contains(ObjectIdentifier(connection)) {
            send(message, to: connection)
        }

        print("[AccessibilityBridge] Broadcast hierarchy update to \(subscribedConnections.count) client(s)")
    }

    // MARK: - Conversion

    private func convertMarker(_ marker: AccessibilityMarker, index: Int) -> AccessibilityElementData {
        let frame = marker.shape.frame
        return AccessibilityElementData(
            traversalIndex: index,
            description: marker.description,
            label: marker.label,
            value: marker.value,
            traits: formatTraits(marker.traits),
            identifier: marker.identifier,
            hint: marker.hint,
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            activationPointX: marker.activationPoint.x,
            activationPointY: marker.activationPoint.y,
            customActions: marker.customActions.map { $0.name }
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
        if traits.contains(.searchField) { result.append("searchField") }
        if traits.contains(.playsSound) { result.append("playsSound") }
        if traits.contains(.keyboardKey) { result.append("keyboardKey") }
        if traits.contains(.summaryElement) { result.append("summaryElement") }
        if traits.contains(.notEnabled) { result.append("notEnabled") }
        if traits.contains(.updatesFrequently) { result.append("updatesFrequently") }
        if traits.contains(.startsMediaSession) { result.append("startsMediaSession") }
        if traits.contains(.allowsDirectInteraction) { result.append("allowsDirectInteraction") }
        if traits.contains(.causesPageTurn) { result.append("causesPageTurn") }
        return result
    }
}

// MARK: - Shape Helper

private extension AccessibilityMarker.Shape {
    var frame: CGRect {
        switch self {
        case let .frame(rect): return rect
        case let .path(path): return path.bounds
        }
    }
}
#endif
