// swiftlint:disable file_length
#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import CryptoKit
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

    /// Shared instance - use `configure(port:token:instanceId:)` before first access
    public static var shared: InsideMan = InsideMan()

    /// Configure the shared instance. Must be called before start().
    public static func configure(port: UInt16, token: String? = nil, instanceId: String? = nil) {
        shared = InsideMan(port: port, token: token, instanceId: instanceId)
    }

    // MARK: - Properties

    private var socketServer: SimpleSocketServer?
    private var netService: NetService?
    private var subscribedClients: Set<Int> = []
    private let port: UInt16
    private let muscle: TheMuscle
    private let instanceId: String?
    private let sessionId = UUID()
    private let parser = AccessibilityHierarchyParser()
    private let theSafecracker = TheSafecracker()
    private var cachedElements: [AccessibilityElement] = []

    // MARK: - Interactive Object Storage

    private struct WeakObject {
        weak var object: NSObject?
    }

    /// Weak references to interactive accessibility objects from the last parse,
    /// keyed by traversal index.
    private var interactiveObjects: [Int: WeakObject] = [:]

    private var isRunning = false
    private var isSuspended = false

    // Screen recording
    private var stakeout: Stakeout?

    // Debounce for hierarchy updates
    private var updateDebounceTask: Task<Void, Never>?
    private let updateDebounceInterval: UInt64 = 300_000_000 // 300ms in nanoseconds

    // Polling for automatic updates (disabled by default)
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    private var isPollingEnabled = false
    private var lastHierarchyHash: Int = 0

    // MARK: - Initialization

    public init(port: UInt16 = 0, token: String? = nil, instanceId: String? = nil) {
        self.port = port
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        serverLog("Starting InsideMan with SimpleSocketServer...")

        let server = SimpleSocketServer()
        wireServer(server)

        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil
        let bindAllOverride = ProcessInfo.processInfo.environment["INSIDEMAN_BIND_ALL"]
            .map { ["true", "1", "yes"].contains($0.lowercased()) } ?? false
        let bindToLoopback = isSimulator && !bindAllOverride

        // Simulators share localhost — use random port to avoid collisions.
        // Fixed ports are only useful on physical devices (for USB tunneling).
        let effectivePort = isSimulator ? 0 : port
        let actualPort = try server.start(port: effectivePort, bindToLoopback: bindToLoopback)
        self.socketServer = server
        isRunning = true

        if bindToLoopback {
            serverLog("Server listening on loopback port \(actualPort) (simulator)")
        } else {
            serverLog("Server listening on port \(actualPort)")
        }
        serverLog("Auth token: \(muscle.authToken)")
        if let instanceId {
            serverLog("Instance ID: \(instanceId)")
        }
        advertiseService(port: actualPort)

        // Prevent the screen from locking while InsideMan is running
        UIApplication.shared.isIdleTimerDisabled = true

        startAccessibilityObservation()
        startLifecycleObservation()

        serverLog("Server started successfully")
    }

    private func wireServer(_ server: SimpleSocketServer) {
        muscle.sendToClient = { [weak server] data, clientId in server?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak server] clientId in server?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak server] clientId in server?.disconnect(clientId: clientId) }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }

        server.onClientConnected = { [weak self] clientId in
            Task { @MainActor in
                serverLog("Client \(clientId) connected, awaiting auth")
                self?.muscle.sendAuthRequired(clientId: clientId)
            }
        }

        server.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                serverLog("Client \(clientId) disconnected")
                self?.subscribedClients.remove(clientId)
                self?.muscle.handleClientDisconnected(clientId)
            }
        }

        server.onDataReceived = { [weak self] clientId, data, respond in
            Task { @MainActor in
                await self?.handleClientMessage(clientId, data: data, respond: respond)
            }
        }

        server.onUnauthenticatedData = { [weak self] clientId, data, respond in
            Task { @MainActor in
                self?.muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
            }
        }
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        isSuspended = false
        stopPolling()

        socketServer?.stop()
        socketServer = nil

        netService?.stop()
        netService = nil

        subscribedClients.removeAll()
        muscle.tearDown()

        stopAccessibilityObservation()
        stopLifecycleObservation()

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

    private var effectiveInstanceId: String {
        instanceId ?? shortId
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)#\(effectiveInstanceId)"

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        // Publish identifiers in TXT record for pre-connection filtering
        var txtDict: [String: Data] = [:]
        if let simUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
           let data = simUDID.data(using: .utf8) {
            txtDict["simudid"] = data
        }

        // Token hash for pre-connection filtering (SHA256, first 8 bytes hex)
        let tokenHash = SHA256.hash(data: Data(muscle.authToken.utf8))
        let tokenHashPrefix = tokenHash.prefix(8).map { String(format: "%02x", $0) }.joined()
        if let data = tokenHashPrefix.data(using: .utf8) {
            txtDict["tokenhash"] = data
        }

        // Instance ID for human-readable identification
        if let data = effectiveInstanceId.data(using: .utf8) {
            txtDict["instanceid"] = data
        }

        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.publish()
        serverLog("Advertising as '\(serviceName)' on port \(port)")
    }

    // MARK: - Private Methods - Client Handling

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            serverLog("Failed to decode client message")
            if String(data: data, encoding: .utf8) != nil {
                serverLog("Unparsable message: \(data.count) bytes")
            }
            return
        }

        serverLog("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        case .authenticate:
            break // Already authenticated via onUnauthenticatedData path
        case .requestInterface:
            serverLog("Interface requested by client \(clientId)")
            await sendInterface(respond: respond)
        case .subscribe:
            subscribedClients.insert(clientId)
            serverLog("Client \(clientId) subscribed (\(subscribedClients.count) subscribers)")
        case .unsubscribe:
            subscribedClients.remove(clientId)
            serverLog("Client \(clientId) unsubscribed (\(subscribedClients.count) subscribers)")
        case .ping:
            sendMessage(.pong, respond: respond)

        // Action handling — notify stakeout of real interactions (not pings/subscribes/queries)
        case .activate(let target):
            stakeout?.noteActivity()
            await handleActivate(target, respond: respond)
        case .increment(let target):
            stakeout?.noteActivity()
            await handleIncrement(target, respond: respond)
        case .decrement(let target):
            stakeout?.noteActivity()
            await handleDecrement(target, respond: respond)
        case .performCustomAction(let target):
            stakeout?.noteActivity()
            await handleCustomAction(target, respond: respond)
        case .requestScreen:
            handleScreen(respond: respond)

        // Touch gesture handling
        case .touchTap(let target):
            stakeout?.noteActivity()
            await handleTouchTap(target, respond: respond)
        case .touchLongPress(let target):
            stakeout?.noteActivity()
            await handleTouchLongPress(target, respond: respond)
        case .touchSwipe(let target):
            stakeout?.noteActivity()
            await handleTouchSwipe(target, respond: respond)
        case .touchDrag(let target):
            stakeout?.noteActivity()
            await handleTouchDrag(target, respond: respond)
        case .touchPinch(let target):
            stakeout?.noteActivity()
            await handleTouchPinch(target, respond: respond)
        case .touchRotate(let target):
            stakeout?.noteActivity()
            await handleTouchRotate(target, respond: respond)
        case .touchTwoFingerTap(let target):
            stakeout?.noteActivity()
            await handleTouchTwoFingerTap(target, respond: respond)
        case .touchDrawPath(let target):
            stakeout?.noteActivity()
            await handleTouchDrawPath(target, respond: respond)
        case .touchDrawBezier(let target):
            stakeout?.noteActivity()
            await handleTouchDrawBezier(target, respond: respond)
        case .typeText(let target):
            stakeout?.noteActivity()
            await handleTypeText(target, respond: respond)
        case .editAction(let target):
            stakeout?.noteActivity()
            await handleEditAction(target, respond: respond)
        case .resignFirstResponder:
            stakeout?.noteActivity()
            await handleResignFirstResponder(respond: respond)
        case .waitForIdle(let target):
            stakeout?.noteActivity()
            await handleWaitForIdle(target, respond: respond)

        // Recording
        case .startRecording(let config):
            handleStartRecording(config, respond: respond)
        case .stopRecording:
            handleStopRecording(respond: respond)
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
            instanceIdentifier: effectiveInstanceId,
            listeningPort: socketServer?.listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString
        )
        sendMessage(.info(info), respond: respond)
    }

    private func sendInterface(respond: @escaping (Data) -> Void) async {
        // If animating, wait briefly for fast animations to end.
        if hasActiveAnimations() {
            _ = await waitForAnimationsToSettle(timeout: 0.5)
        }

        guard let hierarchyTree = refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), respond: respond)
            return
        }

        let elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
        sendMessage(.interface(payload), respond: respond)
    }

    private func sendMessage(_ message: ServerMessage, respond: @escaping (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(message) else {
            serverLog("Failed to encode message")
            return
        }
        serverLog("Sending \(data.count) bytes")
        respond(data)
    }

    /// Returns all windows that should be included in the accessibility traversal,
    /// sorted by windowLevel descending (frontmost first).
    /// Excludes our own overlay windows (FingerprintWindow).
    private func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return []
        }

        return windowScene.windows
            .filter { window in
                !(window is FingerprintWindow) &&
                !window.isHidden &&
                window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
            .map { ($0, $0 as UIView) }
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
        NotificationCenter.default.removeObserver(
            self,
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDidChange() {
        scheduleHierarchyUpdate()
    }

    // MARK: - App Lifecycle

    private func startLifecycleObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    private func stopLifecycleObservation() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        serverLog("App entering background, suspending server")
        suspend()
    }

    @objc private func appWillEnterForeground() {
        serverLog("App entering foreground, resuming server")
        resume()
    }

    private func suspend() {
        guard isRunning, !isSuspended else { return }
        isSuspended = true

        pollingTask?.cancel()
        pollingTask = nil

        updateDebounceTask?.cancel()
        updateDebounceTask = nil

        socketServer?.stop()
        socketServer = nil

        netService?.stop()
        netService = nil

        subscribedClients.removeAll()
        muscle.tearDown()

        stopAccessibilityObservation()

        cachedElements.removeAll()
        interactiveObjects.removeAll()
        lastHierarchyHash = 0

        serverLog("Server suspended")
    }

    private func resume() {
        guard isRunning, isSuspended else { return }
        isSuspended = false

        serverLog("Resuming server...")

        do {
            let server = SimpleSocketServer()
            wireServer(server)

            let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil
            let bindAllOverride = ProcessInfo.processInfo.environment["INSIDEMAN_BIND_ALL"]
                .map { ["true", "1", "yes"].contains($0.lowercased()) } ?? false
            let bindToLoopback = isSimulator && !bindAllOverride
            let effectivePort = isSimulator ? 0 : port

            let actualPort = try server.start(port: effectivePort, bindToLoopback: bindToLoopback)
            self.socketServer = server

            serverLog("Server resumed on port \(actualPort)")
            advertiseService(port: actualPort)

            startAccessibilityObservation()

            if isPollingEnabled {
                startPollingLoop()
            }

            serverLog("Server resume complete")
        } catch {
            serverLog("Failed to resume server: \(error)")
            isRunning = false
            isSuspended = false
        }
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
        guard !subscribedClients.isEmpty else { return }
        guard let hierarchyTree = refreshAccessibilityData() else { return }

        let elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
        let message = ServerMessage.interface(payload)

        // Update hash for polling comparison
        lastHierarchyHash = elements.hashValue

        if let data = try? JSONEncoder().encode(message) {
            broadcastToSubscribed(data)
        }

        serverLog("Broadcast hierarchy update to \(subscribedClients.count) subscriber(s)")
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
        guard !subscribedClients.isEmpty else { return }
        guard let hierarchyTree = refreshAccessibilityData() else { return }

        let elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }

        // Compute hash of current hierarchy
        let currentHash = elements.hashValue

        // Only broadcast if hierarchy changed
        if currentHash != lastHierarchyHash {
            lastHierarchyHash = currentHash

            // Broadcast hierarchy with tree
            let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
            if let data = try? JSONEncoder().encode(ServerMessage.interface(payload)) {
                broadcastToSubscribed(data)
            }

            // Also broadcast screen when hierarchy changes
            broadcastScreen()

            // Notify stakeout of screen change (for inactivity timeout)
            stakeout?.noteScreenChange()

            serverLog("Polling detected change, broadcast to \(subscribedClients.count) subscriber(s)")
        }
    }

    /// Capture the screen by compositing all traversable windows.
    private func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = getTraversableWindows()
        guard let background = windows.last else { return nil }
        let bounds = background.window.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
            for (window, _) in windows.reversed() {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        return (image, bounds)
    }

    private func broadcastScreen() {
        guard !subscribedClients.isEmpty else { return }
        guard let (image, bounds) = captureScreen(),
              let pngData = image.pngData() else { return }

        let screenPayload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        if let data = try? JSONEncoder().encode(ServerMessage.screen(screenPayload)) {
            broadcastToSubscribed(data)
        }
    }

    /// Send data only to clients that have explicitly subscribed.
    private func broadcastToSubscribed(_ data: Data) {
        for clientId in subscribedClients {
            socketServer?.send(data, to: clientId)
        }
    }

    // MARK: - Screen Recording

    /// Capture the screen including the fingerprint overlay (for recordings).
    /// Unlike captureScreen(), this includes FingerprintWindow so
    /// tap/swipe indicators are visible in the video.
    private func captureScreenForRecording() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return nil
        }

        let allWindows = windowScene.windows
            .filter { !$0.isHidden && $0.bounds.size != .zero }
            .sorted { $0.windowLevel < $1.windowLevel }

        guard let background = allWindows.first else { return nil }
        let bounds = background.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            for window in allWindows {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
    }

    private func handleStartRecording(_ config: RecordingConfig, respond: @escaping (Data) -> Void) {
        if stakeout?.state == .recording {
            sendMessage(.recordingError("Recording already in progress"), respond: respond)
            return
        }

        let recorder = Stakeout()
        recorder.captureFrame = { [weak self] in
            self?.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            switch result {
            case .success(let payload):
                if let data = try? JSONEncoder().encode(ServerMessage.recording(payload)) {
                    self?.socketServer?.broadcastToAll(data)
                }
            case .failure(let error):
                if let data = try? JSONEncoder().encode(ServerMessage.recordingError(error.localizedDescription)) {
                    self?.socketServer?.broadcastToAll(data)
                }
            }
            self?.stakeout = nil
        }

        stakeout = recorder
        do {
            try recorder.startRecording(config: config)
            sendMessage(.recordingStarted, respond: respond)
        } catch {
            sendMessage(.recordingError(error.localizedDescription), respond: respond)
            stakeout = nil
        }
    }

    private func handleStopRecording(respond: @escaping (Data) -> Void) {
        guard let stakeout, stakeout.state == .recording else {
            sendMessage(.recordingError("No recording in progress"), respond: respond)
            return
        }
        stakeout.stopRecording(reason: .manual)
        // Response comes asynchronously via onRecordingComplete
    }

    /// If recording, capture a bonus frame to ensure the action's visual effect is captured.
    private func captureActionFrame() {
        stakeout?.captureActionFrame()
    }

    /// If recording, note interaction points so Stakeout composites fingerprints into frames.
    private func noteInteraction(at point: CGPoint) {
        stakeout?.noteInteraction(at: point)
    }

    private func noteInteraction(at points: [CGPoint]) {
        stakeout?.noteInteraction(at: points)
    }

    /// Wire up the gesture move callback for recording overlay during continuous gestures.
    private func wireGestureTracking() {
        theSafecracker.onGestureMove = { [weak self] points in
            self?.stakeout?.updateInteractionPositions(points)
        }
    }

    /// Clear the gesture move callback after a continuous gesture completes.
    private func clearGestureTracking() {
        theSafecracker.onGestureMove = nil
    }

    // MARK: - Accessibility Data Refresh

    /// Refresh the accessibility hierarchy. Provides a visitor closure to the parser
    /// that captures weak references to interactive objects for action dispatch.
    /// Returns the hierarchy tree for callers that need it (e.g., sendInterface).
    @discardableResult
    private func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
        let windows = getTraversableWindows()
        guard !windows.isEmpty else { return nil }

        var allHierarchy: [AccessibilityHierarchy] = []
        var newInteractiveObjects: [Int: WeakObject] = [:]
        var allElements: [AccessibilityElement] = []

        for (window, rootView) in windows {
            let baseIndex = allElements.count
            let windowTree = parser.parseAccessibilityHierarchy(in: rootView) { _, index, object in
                let globalIndex = baseIndex + index
                if object.accessibilityRespondsToUserInteraction
                    || object.accessibilityTraits.contains(.adjustable)
                    || !(object.accessibilityCustomActions ?? []).isEmpty {
                    newInteractiveObjects[globalIndex] = WeakObject(object: object)
                }
            }
            let windowElements = windowTree.flattenToElements()

            // Wrap each window's tree in a container node when multiple windows are present
            if windows.count > 1 {
                let windowName = NSStringFromClass(type(of: window))
                let container = AccessibilityContainer(
                    type: .semanticGroup(
                        label: windowName,
                        value: "windowLevel: \(window.windowLevel.rawValue)",
                        identifier: nil
                    ),
                    frame: window.frame
                )
                let reindexed = windowTree.reindexed(offset: baseIndex)
                allHierarchy.append(.container(container, children: reindexed))
            } else {
                allHierarchy.append(contentsOf: windowTree)
            }

            allElements.append(contentsOf: windowElements)
        }

        interactiveObjects = newInteractiveObjects
        cachedElements = allElements
        return allHierarchy
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

    // MARK: - Animation Detection

    /// Animation key prefixes to ignore during detection.
    /// These are persistent or internal animations that don't indicate meaningful UI transitions.
    private static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
    ]

    /// Poll interval for checking animation state (10ms).
    private static let animationPollInterval: UInt64 = 10_000_000

    /// Returns true if any layer in the traversable window hierarchy has active animations.
    private func hasActiveAnimations() -> Bool {
        getTraversableWindows().contains { layerTreeHasAnimations($0.window.layer) }
    }

    /// Iterative (stack-based) walk of the layer tree checking for animation keys.
    private func layerTreeHasAnimations(_ root: CALayer) -> Bool {
        var stack: [CALayer] = [root]
        while let layer = stack.popLast() {
            if let keys = layer.animationKeys(), !keys.isEmpty {
                let hasRelevantAnimation = keys.contains { key in
                    !Self.ignoredAnimationKeyPrefixes.contains { key.hasPrefix($0) }
                }
                if hasRelevantAnimation {
                    return true
                }
            }
            if let sublayers = layer.sublayers {
                stack.append(contentsOf: sublayers)
            }
        }
        return false
    }

    /// Wait until all animations in the traversable window hierarchy have completed,
    /// or until the timeout expires.
    /// - Returns: true if animations settled before timeout, false if timed out
    private func waitForAnimationsToSettle(timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.animationPollInterval)
            if !hasActiveAnimations() {
                return true
            }
        }
        return false
    }

    // MARK: - Interface Delta

    /// Convert current cachedElements to wire HeistElements for delta comparison.
    private func snapshotElements() -> [HeistElement] {
        cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
    }

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    /// Waits briefly for animations to settle (0.5s). If the screen changed and animations
    /// are still active (e.g. navigation spring), waits 1s more and re-snapshots.
    private func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        beforeElements: [HeistElement]
    ) async -> ActionResult {
        guard success else {
            return ActionResult(success: false, method: method, message: message, value: value)
        }

        // Quick check: if no animations, just yield briefly for the tree to update.
        if !hasActiveAnimations() {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        } else {
            // Animations active — wait for them to end (fast for toggles/menus)
            // or cap at 0.5s (avoids blocking on long simulator springs).
            _ = await waitForAnimationsToSettle(timeout: 0.5)
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms layout
        }

        var afterTree = refreshAccessibilityData()
        var afterElements = snapshotElements()
        var delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)

        // If the screen changed and animations are still running (navigation push),
        // the source screen is still sliding out. Wait a fixed 1s for the destination
        // to fully appear, then re-snapshot. This is cheaper than polling
        // refreshAccessibilityData() repeatedly during the transition.
        if delta.kind != .noChange && hasActiveAnimations() {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            afterTree = refreshAccessibilityData()
            afterElements = snapshotElements()
            delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)
        }

        // Capture a recording frame after the action completes
        captureActionFrame()

        return ActionResult(
            success: true,
            method: method,
            message: message,
            value: value,
            interfaceDelta: delta
        )
    }

    /// Compare two element snapshots and return a compact delta.
    private func computeDelta(
        before: [HeistElement],
        after: [HeistElement],
        afterTree: [AccessibilityHierarchy]?
    ) -> InterfaceDelta {
        // Quick check: if hash is identical, nothing changed
        if before.hashValue == after.hashValue && before == after {
            return InterfaceDelta(kind: .noChange, elementCount: after.count)
        }

        // Build identifier sets for screen-change detection
        let oldIDs = Set(before.compactMap(\.identifier))
        let newIDs = Set(after.compactMap(\.identifier))
        let commonIDs = oldIDs.intersection(newIDs)
        let maxCount = max(oldIDs.count, newIDs.count, 1)

        // Screen change: fewer than 50% of identifiers overlap
        if commonIDs.count < maxCount / 2 {
            let tree = afterTree?.map { convertHierarchyNode($0) }
            let fullInterface = Interface(timestamp: Date(), elements: after, tree: tree)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: after.count,
                newInterface: fullInterface
            )
        }

        // Element-level diff
        let oldByID = Dictionary(grouping: before.filter { $0.identifier != nil }, by: { $0.identifier! })
        let newByID = Dictionary(grouping: after.filter { $0.identifier != nil }, by: { $0.identifier! })

        let addedIDs = newIDs.subtracting(oldIDs)
        let added = addedIDs.flatMap { newByID[$0] ?? [] }

        let removedIDs = oldIDs.subtracting(newIDs)
        let removedOrders = removedIDs.flatMap { oldByID[$0] ?? [] }.map(\.order)

        var valueChanges: [ValueChange] = []
        // Identifier-based comparison: check value, description, and label
        for id in commonIDs {
            if let oldEl = oldByID[id]?.first, let newEl = newByID[id]?.first {
                if oldEl.value != newEl.value {
                    valueChanges.append(ValueChange(
                        order: newEl.order,
                        identifier: id,
                        oldValue: oldEl.value,
                        newValue: newEl.value
                    ))
                } else if oldEl.description != newEl.description || oldEl.label != newEl.label {
                    valueChanges.append(ValueChange(
                        order: newEl.order,
                        identifier: id,
                        oldValue: oldEl.description,
                        newValue: newEl.description
                    ))
                }
            }
        }

        // Order-based comparison for elements without identifiers
        // (catches segmented controls, unlabeled buttons, etc.)
        let minCount = min(before.count, after.count)
        for i in 0..<minCount {
            let oldEl = before[i]
            let newEl = after[i]
            if oldEl.identifier != nil && newEl.identifier != nil { continue }
            if oldEl.description != newEl.description
                || oldEl.label != newEl.label
                || oldEl.value != newEl.value {
                valueChanges.append(ValueChange(
                    order: newEl.order,
                    identifier: newEl.identifier,
                    oldValue: oldEl.description,
                    newValue: newEl.description
                ))
            }
        }

        if added.isEmpty && removedOrders.isEmpty && valueChanges.isEmpty {
            if before.count != after.count {
                return InterfaceDelta(
                    kind: .elementsChanged,
                    elementCount: after.count,
                    added: after.count > before.count ? Array(after.suffix(after.count - before.count)) : nil,
                    removedOrders: after.count < before.count ? Array(after.count..<before.count) : nil
                )
            }
            return InterfaceDelta(kind: .noChange, elementCount: after.count)
        }

        if added.isEmpty && removedOrders.isEmpty {
            return InterfaceDelta(
                kind: .valuesChanged,
                elementCount: after.count,
                valueChanges: valueChanges.isEmpty ? nil : valueChanges
            )
        }

        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: after.count,
            added: added.isEmpty ? nil : added,
            removedOrders: removedOrders.isEmpty ? nil : removedOrders,
            valueChanges: valueChanges.isEmpty ? nil : valueChanges
        )
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

    private func findElement(for target: ActionTarget) -> AccessibilityElement? {
        if let identifier = target.identifier {
            return cachedElements.first { $0.identifier == identifier }
        }
        if let index = target.order, index >= 0, index < cachedElements.count {
            return cachedElements[index]
        }
        return nil
    }

    /// Check if an AccessibilityElement element is interactive based on traits
    /// - Returns: nil if interactive, or an error string if not interactive
    private func checkElementInteractivity(_ element: AccessibilityElement) -> String? {
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

    private func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

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
            theSafecracker.showFingerprint(at: point)
            noteInteraction(at: point)
            let result = await actionResultWithDelta(success: true, method: .activate, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        // Fall back to synthetic touch injection
        if theSafecracker.tap(at: point) {
            theSafecracker.showFingerprint(at: point)
            noteInteraction(at: point)
            let result = await actionResultWithDelta(success: true, method: .syntheticTap, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .activate,
            message: "Activation failed"
        )), respond: respond)
    }

    private func handleIncrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

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
        theSafecracker.showFingerprint(at: element.activationPoint)
        noteInteraction(at: element.activationPoint)
        let result = await actionResultWithDelta(success: true, method: .increment, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleDecrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

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
        theSafecracker.showFingerprint(at: element.activationPoint)
        noteInteraction(at: element.activationPoint)
        let result = await actionResultWithDelta(success: true, method: .decrement, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Edit Action Handler

    private func handleEditAction(_ target: EditActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard let action = TheSafecracker.EditAction(rawValue: target.action) else {
            let valid = TheSafecracker.EditAction.allCases.map(\.rawValue).joined(separator: ", ")
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .editAction,
                message: "Unknown edit action '\(target.action)'. Valid: \(valid)"
            )), respond: respond)
            return
        }

        let success = theSafecracker.performEditAction(action)
        let result = await actionResultWithDelta(success: success, method: .editAction, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Resign First Responder Handler

    private func handleResignFirstResponder(respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        let success = theSafecracker.resignFirstResponder()
        let result = await actionResultWithDelta(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Wait For Idle Handler

    private func handleWaitForIdle(_ target: WaitForIdleTarget, respond: @escaping (Data) -> Void) async {
        let timeout = min(target.timeout ?? 5.0, 60.0)
        let settled = await waitForAnimationsToSettle(timeout: timeout)

        guard let hierarchyTree = refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), respond: respond)
            return
        }

        let elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)

        let result = ActionResult(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeout)s, UI may still be animating",
            interfaceDelta: InterfaceDelta(
                kind: .screenChanged,
                elementCount: elements.count,
                newInterface: payload
            ),
            animating: settled ? nil : true
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Touch Gesture Handlers

    private func handleTouchTap(_ target: TouchTapTarget, respond: @escaping (Data) -> Void) async {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        // If we have an element target, try activation via live object first
        if let elementTarget = target.elementTarget,
           let index = resolveTraversalIndex(for: elementTarget),
           activate(elementAt: index) {
            theSafecracker.showFingerprint(at: point)
            noteInteraction(at: point)
            let result = await actionResultWithDelta(success: true, method: .activate, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        // Fall back to synthetic tap
        if theSafecracker.tap(at: point) {
            theSafecracker.showFingerprint(at: point)
            noteInteraction(at: point)
            let result = await actionResultWithDelta(success: true, method: .syntheticTap, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(success: false, method: .syntheticTap, message: "Touch tap failed")), respond: respond)
    }

    private func handleTouchLongPress(_ target: LongPressTarget, respond: @escaping (Data) -> Void) async {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        wireGestureTracking()
        let success = await theSafecracker.longPress(at: point, duration: clampDuration(target.duration))
        clearGestureTracking()
        if success {
            noteInteraction(at: point)
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticLongPress, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchSwipe(_ target: SwipeTarget, respond: @escaping (Data) -> Void) async {
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

        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()
        let duration = clampDuration(target.duration ?? 0.15)

        wireGestureTracking()
        let success = await theSafecracker.swipe(from: startPoint, to: endPoint, duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: endPoint)
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticSwipe, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchDrag(_ target: DragTarget, respond: @escaping (Data) -> Void) async {
        guard let startPoint = resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let duration = clampDuration(target.duration ?? 0.5)
        wireGestureTracking()
        let success = await theSafecracker.drag(from: startPoint, to: target.endPoint, duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: target.endPoint)
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticDrag, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchPinch(_ target: PinchTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let spread = target.spread ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        let angle: CGFloat = .pi / 4
        let p1 = CGPoint(x: center.x + cos(angle) * CGFloat(spread), y: center.y + sin(angle) * CGFloat(spread))
        let p2 = CGPoint(x: center.x - cos(angle) * CGFloat(spread), y: center.y - sin(angle) * CGFloat(spread))
        wireGestureTracking()
        let success = await theSafecracker.pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: [p1, p2])
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticPinch, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchRotate(_ target: RotateTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let radius = target.radius ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        let p1 = CGPoint(x: center.x + CGFloat(radius), y: center.y)
        let p2 = CGPoint(x: center.x - CGFloat(radius), y: center.y)
        wireGestureTracking()
        let success = await theSafecracker.rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: [p1, p2])
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticRotate, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchTwoFingerTap(_ target: TwoFingerTapTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let spread = target.spread ?? 40.0
        let halfSpread = CGFloat(spread) / 2
        let p1 = CGPoint(x: center.x - halfSpread, y: center.y)
        let p2 = CGPoint(x: center.x + halfSpread, y: center.y)
        let success = theSafecracker.twoFingerTap(at: center, spread: CGFloat(spread))
        if success {
            theSafecracker.showFingerprint(at: p1)
            theSafecracker.showFingerprint(at: p2)
            noteInteraction(at: [p1, p2])
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticTwoFingerTap, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchDrawPath(_ target: DrawPathTarget, respond: @escaping (Data) -> Void) async {
        let cgPoints = target.points.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Path requires at least 2 points"
            )), respond: respond)
            return
        }

        refreshAccessibilityData()
        let beforeElements = snapshotElements()
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        wireGestureTracking()
        let success = await theSafecracker.drawPath(points: cgPoints, duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: cgPoints.last ?? cgPoints[0])
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticDrawPath, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleTouchDrawBezier(_ target: DrawBezierTarget, respond: @escaping (Data) -> Void) async {
        guard !target.segments.isEmpty else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Bezier path requires at least 1 segment"
            )), respond: respond)
            return
        }

        let samplesPerSegment = min(target.samplesPerSegment ?? 20, 1000)
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

        refreshAccessibilityData()
        let beforeElements = snapshotElements()
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        wireGestureTracking()
        let success = await theSafecracker.drawPath(points: cgPoints, duration: duration)
        clearGestureTracking()
        if success {
            noteInteraction(at: cgPoints.last ?? cgPoints[0])
        }
        let result = await actionResultWithDelta(success: success, method: .syntheticDrawPath, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Text Entry Handler

    private func handleTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) async {
        await performTypeText(target, respond: respond)
    }

    private func performTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) async {
        let interKeyDelay: UInt64 = 30_000_000 // 30ms
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

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
            if !theSafecracker.tap(at: point) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Failed to tap target element to bring up keyboard"
                )), respond: respond)
                return
            }
            theSafecracker.showFingerprint(at: point)
            noteInteraction(at: point)

            // Wait for keyboard to appear (up to 2 seconds)
            var keyboardAppeared = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if theSafecracker.isKeyboardVisible() {
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
            if !theSafecracker.isKeyboardVisible() {
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
            if !(await theSafecracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay)) {
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
            if !(await theSafecracker.typeText(text, interKeyDelay: interKeyDelay)) {
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

        let result = await actionResultWithDelta(
            success: true,
            method: .typeText,
            value: fieldValue,
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Input Validation

    private func clampDuration(_ value: Double?) -> Double {
        min(max(value ?? 0.5, 0.01), 60.0)
    }

    private func clampCoordinate(_ value: Double) -> Double {
        min(max(value, -10000), 10000)
    }

    // MARK: - Shared Helpers

    private func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        let result: Double
        if let d = duration {
            result = d
        } else if let velocity = velocity, velocity > 0 {
            var totalLength: Double = 0
            for i in 1..<points.count {
                let dx = points[i].x - points[i-1].x
                let dy = points[i].y - points[i-1].y
                totalLength += sqrt(dx * dx + dy * dy)
            }
            result = totalLength / velocity
        } else {
            result = 0.5
        }
        return clampDuration(result)
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

    private func handleCustomAction(_ target: CustomActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

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
        let result = await actionResultWithDelta(
            success: success,
            method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found",
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    private func handleScreen(respond: @escaping (Data) -> Void) {
        serverLog("Screen requested")

        guard let (image, bounds) = captureScreen() else {
            sendMessage(.error("Could not access app window"), respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screen as PNG"), respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        sendMessage(.screen(payload), respond: respond)
        serverLog("Screen sent: \(pngData.count) bytes")
    }

    // MARK: - Conversion

    private func convertElement(_ element: AccessibilityElement, index: Int) -> HeistElement {
        let frame = element.shape.frame
        return HeistElement(
            order: index,
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: traitNames(element.traits),
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            activationPointX: element.activationPoint.x,
            activationPointY: element.activationPoint.y,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: element.customContent.isEmpty ? nil : element.customContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            actions: buildActions(for: index, element: element)
        )
    }

    private func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        var names: [String] = []
        if traits.contains(.button) { names.append("button") }
        if traits.contains(.link) { names.append("link") }
        if traits.contains(.image) { names.append("image") }
        if traits.contains(.staticText) { names.append("staticText") }
        if traits.contains(.header) { names.append("header") }
        if traits.contains(.adjustable) { names.append("adjustable") }
        if traits.contains(.searchField) { names.append("searchField") }
        if traits.contains(.selected) { names.append("selected") }
        if traits.contains(.notEnabled) { names.append("notEnabled") }
        if traits.contains(.keyboardKey) { names.append("keyboardKey") }
        if traits.contains(.summaryElement) { names.append("summaryElement") }
        if traits.contains(.updatesFrequently) { names.append("updatesFrequently") }
        if traits.contains(.playsSound) { names.append("playsSound") }
        if traits.contains(.startsMediaSession) { names.append("startsMediaSession") }
        if traits.contains(.allowsDirectInteraction) { names.append("allowsDirectInteraction") }
        if traits.contains(.causesPageTurn) { names.append("causesPageTurn") }
        if traits.contains(.tabBar) { names.append("tabBar") }
        return names
    }

    private func buildActions(for index: Int, element: AccessibilityElement) -> [ElementAction] {
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

private extension AccessibilityElement.Shape {
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
/// - INSIDEMAN_TOKEN / InsideManToken: Auth token (auto-generated if not set)
/// - INSIDEMAN_ID / InsideManInstanceId: Human-readable instance identifier
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

    // Get auth token
    var token: String?
    if let envToken = ProcessInfo.processInfo.environment["INSIDEMAN_TOKEN"] {
        token = envToken
    } else if let plistToken = Bundle.main.object(forInfoDictionaryKey: "InsideManToken") as? String {
        token = plistToken
    }

    // Get instance ID
    var instanceId: String?
    if let envId = ProcessInfo.processInfo.environment["INSIDEMAN_ID"] {
        instanceId = envId
    } else if let plistId = Bundle.main.object(forInfoDictionaryKey: "InsideManInstanceId") as? String {
        instanceId = plistId
    }

    NSLog("[InsideMan] Starting with port: %d, polling interval: %f", port, interval)

    Task { @MainActor in
        NSLog("[InsideMan] MainActor task executing...")
        do {
            InsideMan.configure(port: port, token: token, instanceId: instanceId)
            try InsideMan.shared.start()
            InsideMan.shared.startPolling(interval: interval)
            NSLog("[InsideMan] ========== AUTO-START SUCCESS ==========")
        } catch {
            NSLog("[InsideMan] ========== AUTO-START FAILED: %@ ==========", String(describing: error))
        }
    }
}

// MARK: - AccessibilityHierarchy Reindexing

extension Array where Element == AccessibilityHierarchy {
    func reindexed(offset: Int) -> [AccessibilityHierarchy] {
        guard offset != 0 else { return self }
        return map { node in
            switch node {
            case let .element(element, index):
                return .element(element, traversalIndex: index + offset)
            case let .container(container, children):
                return .container(container, children: children.reindexed(offset: offset))
            }
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
