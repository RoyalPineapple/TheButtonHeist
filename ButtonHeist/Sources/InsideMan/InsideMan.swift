#if canImport(UIKit)
import UIKit
import AccessibilitySnapshotParser
import TheGoods
import os.log

/// Debug logging helper - uses NSLog for maximum visibility
private func serverLog(_ message: String) {
    NSLog("[InsideMan] %@", message)
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class InsideMan {

    // MARK: - Singleton

    /// Shared instance - use `configure(port:)` before first access if custom port needed
    public static var shared: InsideMan = InsideMan()

    /// Configure the shared instance with a specific port. Must be called before start().
    public static func configure(port: UInt16) {
        shared = InsideMan(port: port)
    }

    // MARK: - Properties

    private var socketServer: SimpleSocketServer?
    private var netService: NetService?
    private var subscribedClients: Set<Int> = []
    private var clientFileDescriptors: [Int: Int32] = [:]

    private let port: UInt16
    private let parser = AccessibilityHierarchyParser()
    private let safeCracker = SafeCracker()
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

        serverLog("Starting InsideMan with SimpleSocketServer...")

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
            type: buttonHeistServiceType,
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
        case .performCustomAction(let target):
            handleCustomAction(target, respond: respond)
        case .requestScreenshot:
            handleScreenshot(respond: respond)

        // Touch gesture handling
        case .touchTap(let target):
            handleTouchTap(target, respond: respond)
        case .touchLongPress(let target):
            handleTouchLongPress(target, respond: respond)
        case .touchSwipe(let target):
            handleTouchSwipe(target, respond: respond)
        case .touchDrag(let target):
            handleTouchDrag(target, respond: respond)
        case .touchPinch(let target):
            handleTouchPinch(target, respond: respond)
        case .touchRotate(let target):
            handleTouchRotate(target, respond: respond)
        case .touchTwoFingerTap(let target):
            handleTouchTwoFingerTap(target, respond: respond)
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

        // Parse full tree structure
        let hierarchyTree = parser.parseAccessibilityHierarchy(in: rootView)

        // Flatten for backwards compatibility and action handling
        let flatElements = hierarchyTree.flattenToElements()
        cachedElements = flatElements

        let elements = flatElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = HierarchyPayload(timestamp: Date(), elements: elements, tree: tree)
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

        // Parse full tree structure
        let hierarchyTree = parser.parseAccessibilityHierarchy(in: rootView)
        let flatElements = hierarchyTree.flattenToElements()
        cachedElements = flatElements

        let elements = flatElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = HierarchyPayload(timestamp: Date(), elements: elements, tree: tree)
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

        // Parse full tree structure
        let hierarchyTree = parser.parseAccessibilityHierarchy(in: rootView)
        let flatElements = hierarchyTree.flattenToElements()
        cachedElements = flatElements

        let elements = flatElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        // Compute hash of current hierarchy
        let currentHash = elements.hashValue

        // Only broadcast if hierarchy changed
        if currentHash != lastHierarchyHash {
            lastHierarchyHash = currentHash

            // Broadcast hierarchy with tree
            let payload = HierarchyPayload(timestamp: Date(), elements: elements, tree: tree)
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

    /// Find the UIView at a given point using hit testing
    private func findViewAtPoint(_ point: CGPoint) -> UIView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }
        let windowPoint = window.convert(point, from: nil)
        return window.hitTest(windowPoint, with: nil)
    }

    /// Check if an AccessibilityMarker element is interactive based on traits
    /// - Returns: nil if interactive, or an error string if not interactive
    private func checkElementInteractivity(_ element: AccessibilityMarker) -> String? {
        // Check for notEnabled trait (disabled element)
        if element.traits.contains(.notEnabled) {
            return "Element is disabled (has 'notEnabled' trait)"
        }

        // Check for commonly non-interactive element types
        // Note: We don't strictly block static traits because some views
        // may have tap gestures without accessibility traits (e.g., SwiftUI .onTapGesture)
        let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
        let hasInteractiveTraits = element.traits.contains(.button) ||
                                   element.traits.contains(.link) ||
                                   element.traits.contains(.adjustable) ||
                                   element.traits.contains(.searchField) ||
                                   element.traits.contains(.keyboardKey)

        // If element only has static traits and no interactive traits, warn but don't block
        if staticTraitsOnly && !hasInteractiveTraits && element.customActions.isEmpty {
            serverLog("Warning: Element '\(element.description)' has only static traits, tap may not work")
        }

        return nil  // Element is considered interactive
    }

    private func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        // Refresh hierarchy
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

        // Check if element is interactive based on traits
        if let interactivityError = checkElementInteractivity(element) {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: interactivityError
            )), respond: respond)
            return
        }

        let point = element.activationPoint

        // Try accessibilityActivate first
        if let view = findViewAtPoint(point), view.accessibilityActivate() {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityActivate)), respond: respond)
            return
        }

        // Fall back to synthetic touch injection
        if safeCracker.tap(at: point) {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .syntheticTap)), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .accessibilityActivate,
            message: "Activation failed"
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

        // Find the view at the element's activation point and call accessibilityIncrement
        if let view = findViewAtPoint(element.activationPoint) {
            view.accessibilityIncrement()
            TapVisualizerView.showTap(at: element.activationPoint)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityIncrement)), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Could not find view for increment"
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

        // Find the view at the element's activation point and call accessibilityDecrement
        if let view = findViewAtPoint(element.activationPoint) {
            view.accessibilityDecrement()
            TapVisualizerView.showTap(at: element.activationPoint)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityDecrement)), respond: respond)
        } else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Could not find view for decrement"
            )), respond: respond)
        }
    }

    // MARK: - Touch Gesture Handlers

    private func handleTouchTap(_ target: TouchTapTarget, respond: @escaping (Data) -> Void) {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }

        // Try accessibilityActivate first
        if let view = findViewAtPoint(point), view.accessibilityActivate() {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .accessibilityActivate)), respond: respond)
            return
        }

        // Fall back to synthetic tap
        if safeCracker.tap(at: point) {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .syntheticTap)), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(success: false, method: .syntheticTap)), respond: respond)
    }

    private func handleTouchLongPress(_ target: LongPressTarget, respond: @escaping (Data) -> Void) {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }

        Task { @MainActor in
            let success = await self.safeCracker.longPress(at: point, duration: target.duration)
            if success { TapVisualizerView.showTap(at: point) }
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticLongPress)), respond: respond)
        }
    }

    private func handleTouchSwipe(_ target: SwipeTarget, respond: @escaping (Data) -> Void) {
        guard let startPoint = resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY, respond: respond) else { return }

        // Resolve end point from explicit coordinates or direction
        let endPoint: CGPoint
        if let endX = target.endX, let endY = target.endY {
            endPoint = CGPoint(x: endX, y: endY)
        } else if let direction = target.direction {
            let dist = target.distance ?? 200.0
            switch direction {
            case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
            case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
            case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
            case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
            }
        } else {
            sendMessage(.actionResult(ActionResult(success: false, method: .syntheticSwipe, message: "No end point or direction")), respond: respond)
            return
        }

        let duration = target.duration ?? 0.15

        Task { @MainActor in
            let success = await self.safeCracker.swipe(from: startPoint, to: endPoint, duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticSwipe)), respond: respond)
        }
    }

    private func handleTouchDrag(_ target: DragTarget, respond: @escaping (Data) -> Void) {
        guard let startPoint = resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY, respond: respond) else { return }

        let duration = target.duration ?? 0.5

        Task { @MainActor in
            let success = await self.safeCracker.drag(from: startPoint, to: target.endPoint, duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticDrag)), respond: respond)
        }
    }

    private func handleTouchPinch(_ target: PinchTarget, respond: @escaping (Data) -> Void) {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }

        let spread = target.spread ?? 100.0
        let duration = target.duration ?? 0.5

        Task { @MainActor in
            let success = await self.safeCracker.pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticPinch)), respond: respond)
        }
    }

    private func handleTouchRotate(_ target: RotateTarget, respond: @escaping (Data) -> Void) {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }

        let radius = target.radius ?? 100.0
        let duration = target.duration ?? 0.5

        Task { @MainActor in
            let success = await self.safeCracker.rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticRotate)), respond: respond)
        }
    }

    private func handleTouchTwoFingerTap(_ target: TwoFingerTapTarget, respond: @escaping (Data) -> Void) {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }

        let spread = target.spread ?? 40.0
        let success = safeCracker.twoFingerTap(at: center, spread: CGFloat(spread))
        sendMessage(.actionResult(ActionResult(success: success, method: .syntheticTwoFingerTap)), respond: respond)
    }

    /// Resolve a screen point from an element target or explicit coordinates.
    /// Sends an error response and returns nil if resolution fails.
    private func resolvePoint(
        from elementTarget: ActionTarget?,
        pointX: Double?,
        pointY: Double?,
        respond: @escaping (Data) -> Void
    ) -> CGPoint? {
        if let elementTarget {
            if let rootView = getRootView() {
                cachedElements = parser.parseAccessibilityElements(in: rootView)
            }
            guard let element = findElement(for: elementTarget) else {
                sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
                return nil
            }
            return element.activationPoint
        } else if let x = pointX, let y = pointY {
            return CGPoint(x: x, y: y)
        } else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound, message: "No target specified")), respond: respond)
            return nil
        }
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

        // Find the view and perform the custom action
        guard let view = findViewAtPoint(element.activationPoint) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Could not find view for custom action"
            )), respond: respond)
            return
        }

        // Find the custom action by name and perform it
        if let customActions = view.accessibilityCustomActions {
            for action in customActions {
                if action.name == target.actionName {
                    // UIAccessibilityCustomAction's handler returns Bool indicating success
                    if let handler = action.actionHandler {
                        let success = handler(action)
                        sendMessage(.actionResult(ActionResult(
                            success: success,
                            method: .customAction,
                            message: success ? nil : "Custom action failed"
                        )), respond: respond)
                        return
                    }
                    // For target/selector based actions
                    if let actionTarget = action.target {
                        _ = (actionTarget as AnyObject).perform(action.selector, with: action)
                        sendMessage(.actionResult(ActionResult(
                            success: true,
                            method: .customAction
                        )), respond: respond)
                        return
                    }
                }
            }
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .customAction,
            message: "Action '\(target.actionName)' not found"
        )), respond: respond)
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

    // MARK: - Tree Conversion

    private func convertHierarchyNode(_ node: AccessibilityHierarchy) -> AccessibilityHierarchyNode {
        switch node {
        case let .element(_, traversalIndex):
            return .element(traversalIndex: traversalIndex)
        case let .container(container, children):
            let containerData = convertContainer(container)
            let childNodes = children.map { convertHierarchyNode($0) }
            return .container(containerData, children: childNodes)
        }
    }

    private func convertContainer(_ container: AccessibilityContainer) -> AccessibilityContainerData {
        let (typeName, label, value, identifier, traits): (String, String?, String?, String?, [String])
        switch container.type {
        case let .semanticGroup(l, v, id):
            typeName = "semanticGroup"
            label = l; value = v; identifier = id; traits = []
        case .list:
            typeName = "list"
            label = nil; value = nil; identifier = nil; traits = []
        case .landmark:
            typeName = "landmark"
            label = nil; value = nil; identifier = nil; traits = []
        case let .dataTable(rowCount: _, columnCount: _):
            typeName = "dataTable"
            label = nil; value = nil; identifier = nil; traits = []
        case .tabBar:
            typeName = "semanticGroup"
            label = nil; value = nil; identifier = nil; traits = ["tabBar"]
        }
        return AccessibilityContainerData(
            containerType: typeName,
            label: label,
            value: value,
            identifier: identifier,
            frameX: container.frame.origin.x,
            frameY: container.frame.origin.y,
            frameWidth: container.frame.size.width,
            frameHeight: container.frame.size.height,
            traits: traits
        )
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
/// - INSIDEMAN_DISABLE / InsideManDisableAutoStart: Set to true to disable
/// - INSIDEMAN_PORT / InsideManPort: Fixed port number (0 = auto, default)
/// - INSIDEMAN_POLLING_INTERVAL / InsideManPollingInterval: Polling interval in seconds
@_cdecl("InsideMan_autoStartFromLoad")
public func insideManAutoStartFromLoad() {
    NSLog("[InsideMan] ========== AUTO-START BEGIN ==========")
    NSLog("[InsideMan] Bundle ID: %@", Bundle.main.bundleIdentifier ?? "unknown")
    NSLog("[InsideMan] Device: %@", UIDevice.current.name)
    NSLog("[InsideMan] System: %@ %@", UIDevice.current.systemName, UIDevice.current.systemVersion)

    // Check INSIDEMAN_DISABLE environment variable
    if let envValue = ProcessInfo.processInfo.environment["INSIDEMAN_DISABLE"],
       ["true", "1", "yes"].contains(envValue.lowercased()) {
        NSLog("[InsideMan] Auto-start disabled via INSIDEMAN_DISABLE")
        return
    }

    // Check Info.plist InsideManDisableAutoStart
    if let disable = Bundle.main.object(forInfoDictionaryKey: "InsideManDisableAutoStart") as? Bool, disable {
        NSLog("[InsideMan] Auto-start disabled via Info.plist")
        return
    }

    // Get fixed port (0 = auto-assign)
    var port: UInt16 = 0
    if let envPort = ProcessInfo.processInfo.environment["INSIDEMAN_PORT"],
       let parsed = UInt16(envPort) {
        port = parsed
    } else if let plistPort = Bundle.main.object(forInfoDictionaryKey: "InsideManPort") as? Int {
        port = UInt16(clamping: plistPort)
    }

    // Get polling interval (default 1.0, minimum 0.5)
    var interval: TimeInterval = 1.0
    if let envInterval = ProcessInfo.processInfo.environment["INSIDEMAN_POLLING_INTERVAL"],
       let parsed = TimeInterval(envInterval) {
        interval = max(0.5, parsed)
    } else if let plistInterval = Bundle.main.object(forInfoDictionaryKey: "InsideManPollingInterval") as? Double {
        interval = max(0.5, plistInterval)
    }

    NSLog("[InsideMan] Starting with port: %d, polling interval: %f", port, interval)

    Task { @MainActor in
        NSLog("[InsideMan] MainActor task executing...")
        do {
            // Configure shared instance with port if specified
            if port != 0 {
                InsideMan.configure(port: port)
            }
            try InsideMan.shared.start()
            InsideMan.shared.startPolling(interval: interval)
            NSLog("[InsideMan] ========== AUTO-START SUCCESS ==========")
        } catch {
            NSLog("[InsideMan] ========== AUTO-START FAILED: %@ ==========", String(describing: error))
        }
    }
}
#endif
