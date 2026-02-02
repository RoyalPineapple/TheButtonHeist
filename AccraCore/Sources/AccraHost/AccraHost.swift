#if canImport(UIKit)
import UIKit
import AccessibilitySnapshotParser
import AccraCore
import os.log

/// Debug logging helper - uses NSLog for maximum visibility
private func serverLog(_ message: String) {
    NSLog("[AccraHost] %@", message)
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class AccraHost {

    // MARK: - Singleton

    public static let shared = AccraHost()

    // MARK: - Properties

    private var socketServer: SimpleSocketServer?
    private var netService: NetService?
    private var subscribedClients: Set<Int> = []
    private var clientFileDescriptors: [Int: Int32] = [:]

    private let port: UInt16
    private let parser = AccessibilityHierarchyParser()
    private let touchInjector = TouchInjector()
    private var cachedElements: [AccessibilityElement] = []

    private var isRunning = false

    // Debounce for hierarchy updates
    private var updateDebounceTask: Task<Void, Never>?
    private let updateDebounceInterval: UInt64 = 300_000_000 // 300ms in nanoseconds

    // Polling for automatic updates (disabled by default)
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    private var isPollingEnabled = false
    private var lastHierarchyHash: Int = 0

    // MARK: - Initialization

    public init(port: UInt16 = 0) {
        self.port = port
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        serverLog("Starting AccraHost with SimpleSocketServer...")

        let server = SimpleSocketServer()

        server.onClientConnected = { [weak self] clientId in
            serverLog("Client \(clientId) connected")
            self?.handleClientConnected(clientId)
        }

        server.onClientDisconnected = { [weak self] clientId in
            serverLog("Client \(clientId) disconnected")
            self?.subscribedClients.remove(clientId)
            self?.clientFileDescriptors.removeValue(forKey: clientId)
        }

        server.onDataReceived = { [weak self] data, respond in
            self?.handleClientMessage(data, respond: respond)
        }

        let actualPort = try server.start(port: port)
        self.socketServer = server
        isRunning = true

        serverLog("Server listening on port \(actualPort)")
        advertiseService(port: actualPort)

        // Start observing accessibility changes
        startAccessibilityObservation()

        serverLog("Server started successfully")
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        stopPolling()

        socketServer?.stop()
        socketServer = nil

        netService?.stop()
        netService = nil

        subscribedClients.removeAll()
        clientFileDescriptors.removeAll()

        stopAccessibilityObservation()

        serverLog("Server stopped")
    }

    /// Notify the bridge that the UI has changed and subscribers should receive an update.
    /// Call this from your app whenever state changes that affect the accessibility hierarchy.
    public func notifyChange() {
        guard isRunning else { return }
        scheduleHierarchyUpdate()
    }

    /// Enable polling for automatic hierarchy updates.
    /// - Parameter interval: Polling interval in seconds (default 1.0, minimum 0.5)
    public func startPolling(interval: TimeInterval = 1.0) {
        let clampedInterval = max(0.5, interval)
        pollingInterval = UInt64(clampedInterval * 1_000_000_000)
        isPollingEnabled = true
        startPollingLoop()
        serverLog(" Polling enabled (interval: \(clampedInterval)s)")
    }

    /// Disable polling for automatic updates
    public func stopPolling() {
        isPollingEnabled = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private Methods - Service Advertisement

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)-\(UIDevice.current.name)"

        netService = NetService(
            domain: "local.",
            type: accraServiceType,
            name: serviceName,
            port: Int32(port)
        )
        netService?.publish()
        serverLog("Advertising as '\(serviceName)' on port \(port)")
    }

    // MARK: - Private Methods - Client Handling

    private func handleClientConnected(_ clientId: Int) {
        // Send server info immediately
        sendServerInfo(respond: { [weak self] data in
            self?.socketServer?.broadcastToAll(data)
        })
    }

    private func handleClientMessage(_ data: Data, respond: @escaping (Data) -> Void) {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            serverLog("Failed to decode client message")
            if let str = String(data: data, encoding: .utf8) {
                serverLog("Raw message: \(str.prefix(200))")
            }
            return
        }

        serverLog("Received message: \(message)")

        switch message {
        case .requestHierarchy:
            serverLog("Hierarchy requested")
            sendHierarchy(respond: respond)
        case .subscribe:
            serverLog("Client subscribed to updates")
            // Note: with socket server we broadcast to all, so subscribed is implicit
        case .unsubscribe:
            serverLog("Client unsubscribed from updates")
        case .ping:
            sendMessage(.pong, respond: respond)

        // Action handling
        case .activate(let target):
            handleActivate(target, respond: respond)
        case .increment(let target):
            handleIncrement(target, respond: respond)
        case .decrement(let target):
            handleDecrement(target, respond: respond)
        case .tap(let target):
            handleTap(target, respond: respond)
        case .performCustomAction(let target):
            handleCustomAction(target, respond: respond)
        case .requestScreenshot:
            handleScreenshot(respond: respond)
        }
    }

    private func sendServerInfo(respond: @escaping (Data) -> Void) {
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
        sendMessage(.info(info), respond: respond)
    }

    private func sendHierarchy(respond: @escaping (Data) -> Void) {
        guard let rootView = getRootView() else {
            sendMessage(.error("Could not access root view"), respond: respond)
            return
        }

        cachedElements = parser.parseAccessibilityElements(in: rootView)
        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
        sendMessage(.hierarchy(payload), respond: respond)
    }

    private func sendMessage(_ message: ServerMessage, respond: @escaping (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(message) else {
            serverLog("Failed to encode message")
            return
        }
        serverLog("Sending \(data.count) bytes")
        respond(data)
    }

    private func getRootView() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return nil
        }

        // Find the main app window, skipping overlay windows (high windowLevel)
        // Overlay windows like TapVisualizerView use windowLevel > statusBar
        let appWindow = windowScene.windows.first { window in
            window.windowLevel <= .statusBar && window.rootViewController?.view != nil
        }

        return appWindow?.rootViewController?.view
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
        guard let rootView = getRootView() else { return }

        cachedElements = parser.parseAccessibilityElements(in: rootView)
        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
        let message = ServerMessage.hierarchy(payload)

        // Update hash for polling comparison
        lastHierarchyHash = elements.hashValue

        if let data = try? JSONEncoder().encode(message) {
            socketServer?.broadcastToAll(data)
        }

        serverLog("Broadcast hierarchy update")
    }

    // MARK: - Polling

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while isPollingEnabled && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollingInterval)
                if !Task.isCancelled && isPollingEnabled {
                    checkForChanges()
                }
            }
        }
    }

    private func checkForChanges() {
        guard let rootView = getRootView() else { return }

        cachedElements = parser.parseAccessibilityElements(in: rootView)
        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }

        // Compute hash of current hierarchy
        let currentHash = elements.hashValue

        // Only broadcast if hierarchy changed
        if currentHash != lastHierarchyHash {
            lastHierarchyHash = currentHash
            let payload = HierarchyPayload(timestamp: Date(), elements: elements)
            let message = ServerMessage.hierarchy(payload)

            if let data = try? JSONEncoder().encode(message) {
                socketServer?.broadcastToAll(data)
            }
            serverLog("Polling detected change, broadcast to clients")
        }
    }

    // MARK: - Action Handlers

    private func findElement(for target: ActionTarget) -> AccessibilityElement? {
        if let identifier = target.identifier {
            return cachedElements.first { $0.identifier == identifier }
        }
        if let index = target.traversalIndex, index >= 0, index < cachedElements.count {
            return cachedElements[index]
        }
        return nil
    }

    private func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        // Refresh hierarchy to get fresh closures
        if let rootView = getRootView() {
            cachedElements = parser.parseAccessibilityElements(in: rootView)
        }

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Element not found for target"
            )), respond: respond)
            return
        }

        // Try accessibility activate first
        if let activate = element.activate {
            if activate() {
                TapVisualizerView.showTap(at: element.activationPoint)
                sendMessage(.actionResult(ActionResult(
                    success: true,
                    method: .accessibilityActivate
                )), respond: respond)
                return
            }
        }

        // Fallback to synthetic tap at activation point
        if touchInjector.tap(at: element.activationPoint) {
            TapVisualizerView.showTap(at: element.activationPoint)
            sendMessage(.actionResult(ActionResult(
                success: true,
                method: .syntheticTap
            )), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .accessibilityActivate,
            message: "Both accessibilityActivate and synthetic tap failed"
        )), respond: respond)
    }

    private func handleIncrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        if let rootView = getRootView() {
            cachedElements = parser.parseAccessibilityElements(in: rootView)
        }

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        if let increment = element.increment {
            increment()
            TapVisualizerView.showTap(at: element.activationPoint)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityIncrement)), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementDeallocated,
                message: "Element no longer available"
            )), respond: respond)
        }
    }

    private func handleDecrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        if let rootView = getRootView() {
            cachedElements = parser.parseAccessibilityElements(in: rootView)
        }

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        if let decrement = element.decrement {
            decrement()
            TapVisualizerView.showTap(at: element.activationPoint)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityDecrement)), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementDeallocated,
                message: "Element no longer available"
            )), respond: respond)
        }
    }

    private func handleTap(_ target: TapTarget, respond: @escaping (Data) -> Void) {
        // Refresh hierarchy for fresh closures
        if let rootView = getRootView() {
            cachedElements = parser.parseAccessibilityElements(in: rootView)
        }

        if let elementTarget = target.elementTarget {
            guard let element = findElement(for: elementTarget) else {
                sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
                return
            }
            // Use activate closure if available
            if let activate = element.activate, activate() {
                TapVisualizerView.showTap(at: element.activationPoint)
                sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityActivate)), respond: respond)
                return
            }
            // Fall back to synthetic tap at activation point
            let success = touchInjector.tap(at: element.activationPoint)
            if success {
                TapVisualizerView.showTap(at: element.activationPoint)
            }
            sendMessage(.actionResult(ActionResult(success: success, method: .syntheticTap)), respond: respond)
            return
        }

        if let point = target.point {
            // Find accessibility element containing this point
            if let element = findElementAtPoint(point) {
                serverLog("Found element at point: \(element.identifier ?? "no-id")")
                // Use activate closure if available
                if let activate = element.activate, activate() {
                    TapVisualizerView.showTap(at: point)
                    sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityActivate)), respond: respond)
                    return
                }
            }
            // Fall back to TouchInjector
            let success = touchInjector.tap(at: point)
            if success {
                TapVisualizerView.showTap(at: point)
            }
            sendMessage(.actionResult(ActionResult(success: success, method: .syntheticTap)), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .elementNotFound,
            message: "No target specified"
        )), respond: respond)
    }

    private func findElementAtPoint(_ point: CGPoint) -> AccessibilityElement? {
        // Find the smallest element whose frame contains the point
        // Smaller elements are more specific (e.g., button vs container)
        var bestMatch: AccessibilityElement?
        var bestArea: CGFloat = .greatestFiniteMagnitude

        for element in cachedElements {
            let frame = element.shape.frame
            if frame.contains(point) {
                let area = frame.width * frame.height
                if area < bestArea {
                    bestArea = area
                    bestMatch = element
                }
            }
        }
        return bestMatch
    }

    private func handleCustomAction(_ target: CustomActionTarget, respond: @escaping (Data) -> Void) {
        if let rootView = getRootView() {
            cachedElements = parser.parseAccessibilityElements(in: rootView)
        }

        guard let element = findElement(for: target.elementTarget) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        if let performAction = element.performCustomAction {
            let success = performAction(target.actionName)
            sendMessage(.actionResult(ActionResult(
                success: success,
                method: .customAction,
                message: success ? nil : "Action '\(target.actionName)' not found or failed"
            )), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementDeallocated,
                message: "Element no longer available"
            )), respond: respond)
        }
    }

    private func handleScreenshot(respond: @escaping (Data) -> Void) {
        serverLog("Screenshot requested")

        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: {
                  $0.windowLevel <= .statusBar && $0.rootViewController?.view != nil
              }) else {
            sendMessage(.error("Could not access app window"), respond: respond)
            return
        }

        // Use UIGraphicsImageRenderer with drawHierarchy - same as AccessibilitySnapshot library
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            // drawHierarchy captures the full visual appearance including SwiftUI content
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screenshot as PNG"), respond: respond)
            return
        }

        let base64String = pngData.base64EncodedString()
        let payload = ScreenshotPayload(
            pngData: base64String,
            width: window.bounds.width,
            height: window.bounds.height
        )

        sendMessage(.screenshot(payload), respond: respond)
        serverLog("Screenshot sent: \(pngData.count) bytes")
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

// MARK: - Auto-Start Entry Point

/// Called from Objective-C +load method to auto-start the server.
/// Configuration via environment variables (highest priority) or Info.plist:
/// - ACCRA_HOST_DISABLE / AccraHostDisableAutoStart: Set to true to disable
/// - ACCRA_HOST_POLLING_INTERVAL / AccraHostPollingInterval: Polling interval in seconds
@_cdecl("AccraHost_autoStartFromLoad")
public func accraHostAutoStartFromLoad() {
    // Check ACCRA_HOST_DISABLE environment variable
    if let envValue = ProcessInfo.processInfo.environment["ACCRA_HOST_DISABLE"],
       ["true", "1", "yes"].contains(envValue.lowercased()) {
        serverLog("Auto-start disabled via ACCRA_HOST_DISABLE")
        return
    }

    // Check Info.plist AccraHostDisableAutoStart
    if let disable = Bundle.main.object(forInfoDictionaryKey: "AccraHostDisableAutoStart") as? Bool, disable {
        serverLog("Auto-start disabled via Info.plist")
        return
    }

    // Get polling interval (default 1.0, minimum 0.5)
    var interval: TimeInterval = 1.0
    if let envInterval = ProcessInfo.processInfo.environment["ACCRA_HOST_POLLING_INTERVAL"],
       let parsed = TimeInterval(envInterval) {
        interval = max(0.5, parsed)
    } else if let plistInterval = Bundle.main.object(forInfoDictionaryKey: "AccraHostPollingInterval") as? Double {
        interval = max(0.5, plistInterval)
    }

    Task { @MainActor in
        do {
            try AccraHost.shared.start()
            AccraHost.shared.startPolling(interval: interval)
            serverLog("Auto-start completed (polling: \(interval)s)")
        } catch {
            serverLog("Auto-start failed: \(error)")
        }
    }
}
#endif
