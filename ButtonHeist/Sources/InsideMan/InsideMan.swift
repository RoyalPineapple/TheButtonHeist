// swiftlint:disable file_length
#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheGoods
import Wheelman
import os.log

/// Debug logging helper - uses NSLog for maximum visibility
private func serverLog(_ message: String) {
    NSLog("[InsideMan] %@", message)
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class InsideMan { // swiftlint:disable:this type_body_length

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
    private let port: UInt16
    private let sessionId = UUID()
    private let parser = AccessibilityHierarchyParser()
    private let safeCracker = SafeCracker()
    private var cachedElements: [AccessibilityMarker] = []

    // MARK: - Interactive Object Storage

    private struct WeakObject {
        weak var object: NSObject?
    }

    /// Weak references to interactive accessibility objects from the last parse,
    /// keyed by traversal index.
    private var interactiveObjects: [Int: WeakObject] = [:]

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
            Task { @MainActor in
                serverLog("Client \(clientId) connected")
                self?.handleClientConnected(clientId)
            }
        }

        server.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                serverLog("Client \(clientId) disconnected")
                self?.subscribedClients.remove(clientId)
            }
        }

        server.onDataReceived = { [weak self] data, respond in
            Task { @MainActor in
                self?.handleClientMessage(data, respond: respond)
            }
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

    private var shortId: String {
        String(sessionId.uuidString.prefix(8)).lowercased()
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let deviceName = UIDevice.current.name
        let serviceName = "\(appName)-\(deviceName)#\(shortId)"

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        // Publish device identifiers in TXT record for pre-connection filtering
        var txtDict: [String: Data] = [:]
        if let simUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
           let data = simUDID.data(using: .utf8) {
            txtDict["simudid"] = data
        }
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString,
           let data = vendorId.data(using: .utf8) {
            txtDict["vendorid"] = data
        }
        if !txtDict.isEmpty {
            service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        }

        netService = service
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

    // swiftlint:disable:next cyclomatic_complexity
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
        case .requestInterface:
            serverLog("Interface requested")
            sendInterface(respond: respond)
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
        case .requestScreen:
            handleScreen(respond: respond)

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
        case .touchDrawPath(let target):
            handleTouchDrawPath(target, respond: respond)
        case .touchDrawBezier(let target):
            handleTouchDrawBezier(target, respond: respond)
        case .typeText(let target):
            handleTypeText(target, respond: respond)
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
            screenHeight: screenBounds.height,
            instanceId: sessionId.uuidString,
            listeningPort: socketServer?.listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString
        )
        sendMessage(.info(info), respond: respond)
    }

    private func sendInterface(respond: @escaping (Data) -> Void) {
        guard let hierarchyTree = refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), respond: respond)
            return
        }

        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
        sendMessage(.interface(payload), respond: respond)

        // Also send screen capture with initial interface
        broadcastScreen()
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
        guard let hierarchyTree = refreshAccessibilityData() else { return }

        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
        let message = ServerMessage.interface(payload)

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
        guard let hierarchyTree = refreshAccessibilityData() else { return }

        let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        // Compute hash of current hierarchy
        let currentHash = elements.hashValue

        // Only broadcast if hierarchy changed
        if currentHash != lastHierarchyHash {
            lastHierarchyHash = currentHash

            // Broadcast hierarchy with tree
            let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
            if let data = try? JSONEncoder().encode(ServerMessage.interface(payload)) {
                socketServer?.broadcastToAll(data)
            }

            // Also broadcast screen when hierarchy changes
            broadcastScreen()

            serverLog("Polling detected change, broadcast interface + screen")
        }
    }

    private func broadcastScreen() {
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

        let screenPayload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: window.bounds.width,
            height: window.bounds.height
        )

        if let data = try? JSONEncoder().encode(ServerMessage.screen(screenPayload)) {
            socketServer?.broadcastToAll(data)
        }
    }

    // MARK: - Accessibility Data Refresh

    /// Refresh the accessibility hierarchy. Provides a visitor closure to the parser
    /// that captures weak references to interactive objects for action dispatch.
    /// Returns the hierarchy tree for callers that need it (e.g., sendInterface).
    @discardableResult
    private func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
        guard let rootView = getRootView() else { return nil }
        var newInteractiveObjects: [Int: WeakObject] = [:]
        let hierarchyTree = parser.parseAccessibilityHierarchy(in: rootView) { _, index, object in
            if object.accessibilityRespondsToUserInteraction
                || object.accessibilityTraits.contains(.adjustable)
                || !(object.accessibilityCustomActions ?? []).isEmpty {
                newInteractiveObjects[index] = WeakObject(object: object)
            }
        }
        interactiveObjects = newInteractiveObjects
        cachedElements = hierarchyTree.flattenToElements()
        return hierarchyTree
    }

    // MARK: - Activation Methods

    /// Calls accessibilityActivate() on the live object at the given traversal index.
    private func activate(elementAt index: Int) -> Bool {
        interactiveObjects[index]?.object?.accessibilityActivate() ?? false
    }

    /// Calls accessibilityIncrement() on the live object at the given traversal index.
    private func increment(elementAt index: Int) {
        interactiveObjects[index]?.object?.accessibilityIncrement()
    }

    /// Calls accessibilityDecrement() on the live object at the given traversal index.
    private func decrement(elementAt index: Int) {
        interactiveObjects[index]?.object?.accessibilityDecrement()
    }

    /// Performs a custom action by name on the live object at the given traversal index.
    private func performCustomAction(named name: String, elementAt index: Int) -> Bool {
        guard let actions = interactiveObjects[index]?.object?.accessibilityCustomActions else {
            return false
        }
        for action in actions where action.name == name {
            if let handler = action.actionHandler {
                return handler(action)
            }
            if let target = action.target {
                _ = (target as AnyObject).perform(action.selector, with: action)
                return true
            }
        }
        return false
    }

    /// Returns names of custom actions on the live object at the given traversal index.
    private func customActionNames(elementAt index: Int) -> [String] {
        interactiveObjects[index]?.object?.accessibilityCustomActions?.map { $0.name } ?? []
    }

    /// Returns whether a live interactive object exists at the given traversal index.
    private func hasInteractiveObject(at index: Int) -> Bool {
        interactiveObjects[index]?.object != nil
    }

    /// Resolve the traversal index for an ActionTarget.
    private func resolveTraversalIndex(for target: ActionTarget) -> Int? {
        if let index = target.order {
            return index
        }
        if let identifier = target.identifier {
            return cachedElements.firstIndex { $0.identifier == identifier }
        }
        return nil
    }

    // MARK: - Action Handlers

    private func findElement(for target: ActionTarget) -> AccessibilityMarker? {
        if let identifier = target.identifier {
            return cachedElements.first { $0.identifier == identifier }
        }
        if let index = target.order, index >= 0, index < cachedElements.count {
            return cachedElements[index]
        }
        return nil
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
        refreshAccessibilityData()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Element not found for target"
            )), respond: respond)
            return
        }

        if let interactivityError = checkElementInteractivity(element) {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: interactivityError
            )), respond: respond)
            return
        }

        let point = element.activationPoint

        // Guard: element must be in interactive cache
        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .activate,
                message: "Element does not support activation"
            )), respond: respond)
            return
        }

        // Try accessibilityActivate via the live object reference
        if activate(elementAt: index) {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .activate)), respond: respond)
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
            method: .activate,
            message: "Activation failed"
        )), respond: respond)
    }

    private func handleIncrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        refreshAccessibilityData()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .increment,
                message: "Element does not support increment"
            )), respond: respond)
            return
        }

        increment(elementAt: index)
        TapVisualizerView.showTap(at: element.activationPoint)
        sendMessage(.actionResult(ActionResult(success: true, method: .increment)), respond: respond)
    }

    private func handleDecrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
        refreshAccessibilityData()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .decrement,
                message: "Element does not support decrement"
            )), respond: respond)
            return
        }

        decrement(elementAt: index)
        TapVisualizerView.showTap(at: element.activationPoint)
        sendMessage(.actionResult(ActionResult(success: true, method: .decrement)), respond: respond)
    }

    // MARK: - Touch Gesture Handlers

    private func handleTouchTap(_ target: TouchTapTarget, respond: @escaping (Data) -> Void) {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }

        // If we have an element target, try activation via live object first
        if let elementTarget = target.elementTarget,
           let index = resolveTraversalIndex(for: elementTarget),
           activate(elementAt: index) {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .activate)), respond: respond)
            return
        }

        // Fall back to synthetic tap
        if safeCracker.tap(at: point) {
            TapVisualizerView.showTap(at: point)
            sendMessage(.actionResult(ActionResult(success: true, method: .syntheticTap)), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(success: false, method: .syntheticTap, message: "Touch tap failed")), respond: respond)
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

    private func handleTouchDrawPath(_ target: DrawPathTarget, respond: @escaping (Data) -> Void) {
        let cgPoints = target.points.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Path requires at least 2 points"
            )), respond: respond)
            return
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        Task { @MainActor in
            let success = await self.safeCracker.drawPath(points: cgPoints, duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticDrawPath)), respond: respond)
        }
    }

    private func handleTouchDrawBezier(_ target: DrawBezierTarget, respond: @escaping (Data) -> Void) {
        guard !target.segments.isEmpty else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Bezier path requires at least 1 segment"
            )), respond: respond)
            return
        }

        let samplesPerSegment = target.samplesPerSegment ?? 20
        let pathPoints = BezierSampler.sampleBezierPath(
            startPoint: target.startPoint,
            segments: target.segments,
            samplesPerSegment: samplesPerSegment
        )
        let cgPoints = pathPoints.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Sampled bezier produced fewer than 2 points"
            )), respond: respond)
            return
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        Task { @MainActor in
            let success = await self.safeCracker.drawPath(points: cgPoints, duration: duration)
            self.sendMessage(.actionResult(ActionResult(success: success, method: .syntheticDrawPath)), respond: respond)
        }
    }

    // MARK: - Text Entry Handler

    private func handleTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) {
        Task { @MainActor in
            await self.performTypeText(target, respond: respond)
        }
    }

    private func performTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) async {
        let interKeyDelay: UInt64 = 30_000_000 // 30ms

        // Step 1: If elementTarget provided, tap to focus and wait for keyboard
        if let elementTarget = target.elementTarget {
            refreshAccessibilityData()
            guard let element = findElement(for: elementTarget) else {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .elementNotFound,
                    message: "Target element not found"
                )), respond: respond)
                return
            }

            let point = element.activationPoint
            if !safeCracker.tap(at: point) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Failed to tap target element to bring up keyboard"
                )), respond: respond)
                return
            }
            TapVisualizerView.showTap(at: point)

            // Wait for keyboard to appear (up to 2 seconds)
            var keyboardAppeared = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if safeCracker.isKeyboardVisible() {
                    keyboardAppeared = true
                    break
                }
            }

            if !keyboardAppeared {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Keyboard did not appear. Ensure the software keyboard is enabled (Simulator > I/O > Keyboard > uncheck 'Connect Hardware Keyboard')."
                )), respond: respond)
                return
            }
        } else {
            if !safeCracker.isKeyboardVisible() {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Keyboard not visible. Provide an elementTarget to focus a text field, or ensure the keyboard is already showing."
                )), respond: respond)
                return
            }
        }

        // Step 2: Delete characters if requested
        if let deleteCount = target.deleteCount, deleteCount > 0 {
            if !(await safeCracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay)) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Could not get UIKeyboardImpl instance for delete. Keyboard may not be active."
                )), respond: respond)
                return
            }
        }

        // Step 3: Type text if provided
        if let text = target.text, !text.isEmpty {
            if !(await safeCracker.typeText(text, interKeyDelay: interKeyDelay)) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Could not get UIKeyboardImpl instance for typing. Keyboard may not be active."
                )), respond: respond)
                return
            }
        }

        // Step 5: Read back value if elementTarget provided
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        var fieldValue: String?
        if let elementTarget = target.elementTarget {
            refreshAccessibilityData()
            if let element = findElement(for: elementTarget) {
                fieldValue = element.value
            }
        }

        sendMessage(.actionResult(ActionResult(
            success: true,
            method: .typeText,
            value: fieldValue
        )), respond: respond)
    }

    // MARK: - Shared Helpers

    private func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        if let d = duration {
            return d
        } else if let velocity = velocity, velocity > 0 {
            var totalLength: Double = 0
            for i in 1..<points.count {
                let dx = points[i].x - points[i-1].x
                let dy = points[i].y - points[i-1].y
                totalLength += sqrt(dx * dx + dy * dy)
            }
            return totalLength / velocity
        } else {
            return 0.5
        }
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
            refreshAccessibilityData()
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
        refreshAccessibilityData()

        guard findElement(for: target.elementTarget) != nil else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target.elementTarget),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .customAction,
                message: "Element does not support custom actions"
            )), respond: respond)
            return
        }

        let success = performCustomAction(named: target.actionName, elementAt: index)
        sendMessage(.actionResult(ActionResult(
            success: success,
            method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found"
        )), respond: respond)
    }

    private func handleScreen(respond: @escaping (Data) -> Void) {
        serverLog("Screen requested")

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
            sendMessage(.error("Failed to encode screen as PNG"), respond: respond)
            return
        }

        let base64String = pngData.base64EncodedString()
        let payload = ScreenPayload(
            pngData: base64String,
            width: window.bounds.width,
            height: window.bounds.height
        )

        sendMessage(.screen(payload), respond: respond)
        serverLog("Screen sent: \(pngData.count) bytes")
    }

    // MARK: - Conversion

    private func convertMarker(_ marker: AccessibilityMarker, index: Int) -> UIElement {
        let frame = marker.shape.frame
        return UIElement(
            order: index,
            description: marker.description,
            label: marker.label,
            value: marker.value,
            identifier: marker.identifier,
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            actions: buildActions(for: index, element: marker)
        )
    }

    private func buildActions(for index: Int, element: AccessibilityMarker) -> [ElementAction] {
        var actions: [ElementAction] = []
        if hasInteractiveObject(at: index) {
            actions.append(.activate)
        }
        if element.traits.contains(.adjustable), hasInteractiveObject(at: index) {
            actions.append(.increment)
            actions.append(.decrement)
        }
        for name in customActionNames(elementAt: index) {
            actions.append(.custom(name))
        }
        return actions
    }

    // MARK: - Tree Conversion

    private func convertHierarchyNode(_ node: AccessibilityHierarchy) -> ElementNode {
        switch node {
        case let .element(_, traversalIndex):
            return .element(order: traversalIndex)
        case let .container(container, children):
            let containerData = convertContainer(container)
            let childNodes = children.map { convertHierarchyNode($0) }
            return .container(containerData, children: childNodes)
        }
    }

    private func convertContainer(_ container: AccessibilityContainer) -> Group {
        let (typeName, label, value, identifier): (String, String?, String?, String?)
        switch container.type {
        case let .semanticGroup(l, v, id):
            typeName = "semanticGroup"
            label = l; value = v; identifier = id
        case .list:
            typeName = "list"
            label = nil; value = nil; identifier = nil
        case .landmark:
            typeName = "landmark"
            label = nil; value = nil; identifier = nil
        case let .dataTable(rowCount: _, columnCount: _):
            typeName = "dataTable"
            label = nil; value = nil; identifier = nil
        case .tabBar:
            typeName = "tabBar"
            label = nil; value = nil; identifier = nil
        }
        return Group(
            type: typeName,
            label: label,
            value: value,
            identifier: identifier,
            frameX: container.frame.origin.x,
            frameY: container.frame.origin.y,
            frameWidth: container.frame.size.width,
            frameHeight: container.frame.size.height
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
#endif // DEBUG
#endif // canImport(UIKit)
