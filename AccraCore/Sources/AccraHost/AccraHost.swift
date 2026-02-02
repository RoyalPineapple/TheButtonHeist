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
    private var cachedElements: [AccessibilityMarker] = []

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

        // Also send screenshot with initial hierarchy
        broadcastScreenshot()
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

            // Broadcast hierarchy
            let payload = HierarchyPayload(timestamp: Date(), elements: elements)
            if let data = try? JSONEncoder().encode(ServerMessage.hierarchy(payload)) {
                socketServer?.broadcastToAll(data)
            }

            // Also broadcast screenshot when hierarchy changes
            broadcastScreenshot()

            serverLog("Polling detected change, broadcast hierarchy + screenshot")
        }
    }

    private func broadcastScreenshot() {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: {
                  $0.windowLevel <= .statusBar && $0.rootViewController?.view != nil
              }) else { return }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let pngData = image.pngData() else { return }

        let screenshotPayload = ScreenshotPayload(
            pngData: pngData.base64EncodedString(),
            width: window.bounds.width,
            height: window.bounds.height
        )

        if let data = try? JSONEncoder().encode(ServerMessage.screenshot(screenshotPayload)) {
            socketServer?.broadcastToAll(data)
        }
    }

    // MARK: - Action Handlers

    private func findElement(for target: ActionTarget) -> AccessibilityMarker? {
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

    private func findElementAtPoint(_ point: CGPoint) -> AccessibilityMarker? {
        // Find the smallest element whose frame contains the point
        // Smaller elements are more specific (e.g., button vs container)
        var bestMatch: AccessibilityMarker?
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

// MARK: - Action Closures Extension

/// Extension providing action closures by finding the underlying view at runtime
private extension AccessibilityMarker {
    /// Find the view that corresponds to this marker by hit-testing at the activation point
    private func findView() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: {
                  $0.windowLevel <= .statusBar && $0.rootViewController?.view != nil
              }) else {
            return nil
        }
        return window.hitTest(activationPoint, with: nil)
    }

    /// Closure to activate the element (returns Bool indicating success)
    var activate: (() -> Bool)? {
        return {
            guard let view = self.findView() else { return false }

            // For UIControls, try sendActions first (most reliable)
            if let control = view as? UIControl {
                control.sendActions(for: .touchUpInside)
                return true
            }

            // Walk up the view hierarchy looking for UIControl
            var current: UIView? = view.superview
            while let v = current {
                if let control = v as? UIControl {
                    control.sendActions(for: .touchUpInside)
                    return true
                }
                current = v.superview
            }

            // Try accessibilityActivate on the hit view
            if view.accessibilityActivate() {
                return true
            }

            // For SwiftUI, try sending touch events directly
            if self.simulateTouchOnView(view) {
                return true
            }

            return false
        }
    }

    /// Simulate a touch on a view by sending touchesBegan/Ended
    private func simulateTouchOnView(_ view: UIView) -> Bool {
        guard let window = view.window else { return false }

        let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)

        // Create a touch event using the private API
        guard let touchClass = NSClassFromString("UITouch") as? NSObject.Type,
              let touch = touchClass.init() as? UITouch else {
            return false
        }

        // Set touch properties using KVC
        touch.setValue(point, forKey: "locationInWindow")
        touch.setValue(window, forKey: "window")
        touch.setValue(view, forKey: "view")
        touch.setValue(UITouch.Phase.began.rawValue, forKey: "phase")
        touch.setValue(Date().timeIntervalSince1970, forKey: "timestamp")

        let touches = Set([touch])
        let event = UIEvent()

        // Send touchesBegan
        view.touchesBegan(touches, with: event)

        // Update phase and send touchesEnded
        touch.setValue(UITouch.Phase.ended.rawValue, forKey: "phase")
        view.touchesEnded(touches, with: event)

        return true
    }

    /// Closure to increment adjustable elements
    var increment: (() -> Void)? {
        guard traits.contains(.adjustable) else { return nil }
        return {
            guard let view = self.findView() else { return }
            view.accessibilityIncrement()
        }
    }

    /// Closure to decrement adjustable elements
    var decrement: (() -> Void)? {
        guard traits.contains(.adjustable) else { return nil }
        return {
            guard let view = self.findView() else { return }
            view.accessibilityDecrement()
        }
    }

    /// Closure to perform a custom action by name (returns Bool indicating success)
    var performCustomAction: ((String) -> Bool)? {
        guard !customActions.isEmpty else { return nil }
        return { actionName in
            guard let view = self.findView() else { return false }
            // Get custom actions from the view
            guard let actions = view.accessibilityCustomActions else { return false }
            // Find the matching action
            if let action = actions.first(where: { $0.name == actionName }) {
                // Invoke the action via actionHandler (modern API)
                if let handler = action.actionHandler {
                    return handler(action)
                }
                // Legacy target-action approach
                if let target = action.target {
                    _ = (target as AnyObject).perform(action.selector, with: action)
                    return true
                }
            }
            return false
        }
    }
}
#endif
