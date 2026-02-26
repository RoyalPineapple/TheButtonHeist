#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import CryptoKit
import TheScore
import Wheelman
import os.log

let insideJobLogger = Logger(subsystem: "com.buttonheist.insidejob", category: "server")

/// Weak reference wrapper for accessibility objects.
struct WeakObject {
    weak var object: NSObject?
}

/// Provides access to the parsed accessibility element cache.
/// InsideJob owns the data; TheSafecracker reads it to resolve interaction targets
/// and can trigger a refresh when it needs fresh data (e.g. after typing).
@MainActor
protocol ElementStore: AnyObject {
    var cachedElements: [AccessibilityElement] { get }
    var elementObjects: [Int: WeakObject] { get }
    @discardableResult func refreshElements() -> Bool
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class InsideJob: ElementStore {

    // MARK: - Singleton

    /// Shared instance - use `configure(token:instanceId:)` before first access
    public static var shared: InsideJob = InsideJob()

    /// Configure the shared instance. Must be called before start().
    public static func configure(token: String? = nil, instanceId: String? = nil) {
        shared = InsideJob(token: token, instanceId: instanceId)
    }

    // MARK: - Properties

    private var socketServer: SimpleSocketServer?
    private var netService: NetService?
    var subscribedClients: Set<Int> = []
    private let muscle: TheMuscle
    private let instanceId: String?
    private let sessionId = UUID()
    let parser = AccessibilityHierarchyParser()
    let theSafecracker = TheSafecracker()
    var cachedElements: [AccessibilityElement] = []

    /// Weak references to accessibility objects from the last parse, keyed by traversal index.
    var elementObjects: [Int: WeakObject] = [:]

    private var isRunning = false
    private var isSuspended = false

    // Screen recording
    var stakeout: Stakeout?

    // Debounce for hierarchy updates
    var updateDebounceTask: Task<Void, Never>?
    let updateDebounceInterval: UInt64 = 300_000_000 // 300ms in nanoseconds

    // Polling for automatic updates (disabled by default)
    var pollingTask: Task<Void, Never>?
    var pollingInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    var isPollingEnabled = false
    var lastHierarchyHash: Int = 0

    // MARK: - Initialization

    public init(token: String? = nil, instanceId: String? = nil) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.theSafecracker.elementStore = self
        // Wire gesture tracking so Stakeout can overlay finger positions in recordings
        self.theSafecracker.onGestureMove = { [weak self] points in
            self?.stakeout?.updateInteractionPositions(points)
        }
    }

    // MARK: - ElementStore Conformance

    func refreshElements() -> Bool {
        refreshAccessibilityData() != nil
    }

    // MARK: - Public Methods

    // MARK: - Environment Helpers

    /// Always bind to all interfaces — loopback binding breaks Bonjour-resolved
    /// connections which may arrive on non-loopback interfaces.
    private var shouldBindToLoopback: Bool { false }

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        insideJobLogger.info("Starting InsideJob with SimpleSocketServer...")

        let server = SimpleSocketServer()
        wireServer(server)

        let actualPort = try server.start(port: 0, bindToLoopback: shouldBindToLoopback)
        self.socketServer = server
        isRunning = true

        insideJobLogger.info("Server listening on port \(actualPort)")
        insideJobLogger.info("Auth token: \(self.muscle.authToken)")
        if let instanceId {
            insideJobLogger.info("Instance ID: \(instanceId)")
        }
        advertiseService(port: actualPort)

        // Prevent the screen from locking while InsideJob is running
        UIApplication.shared.isIdleTimerDisabled = true

        startAccessibilityObservation()
        startLifecycleObservation()

        insideJobLogger.info("Server started successfully")
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

        insideJobLogger.info("Server stopped")
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
        insideJobLogger.info("Polling enabled (interval: \(clampedInterval)s)")
    }

    /// Disable polling for automatic updates
    public func stopPolling() {
        isPollingEnabled = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Server Wiring

    private func wireServer(_ server: SimpleSocketServer) {
        muscle.sendToClient = { [weak server] data, clientId in server?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak server] clientId in server?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak server] clientId in server?.disconnect(clientId: clientId) }
        muscle.disconnectClientsForSession = { [weak server] clientIds in
            for clientId in clientIds { server?.disconnect(clientId: clientId) }
        }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }

        server.onClientConnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) connected, awaiting auth")
                self?.muscle.sendAuthRequired(clientId: clientId)
            }
        }

        server.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) disconnected")
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

    // MARK: - Service Advertisement

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
        insideJobLogger.info("Advertising as '\(serviceName)' on port \(port)")
    }

    // MARK: - Client Handling

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            insideJobLogger.error("Failed to decode client message")
            if String(data: data, encoding: .utf8) != nil {
                insideJobLogger.debug("Unparsable message: \(data.count) bytes")
            }
            return
        }

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        case .authenticate:
            break // Already authenticated via onUnauthenticatedData path
        case .requestInterface:
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(respond: respond)
        case .subscribe:
            subscribedClients.insert(clientId)
            insideJobLogger.info("Client \(clientId) subscribed (\(self.subscribedClients.count) subscribers)")
        case .unsubscribe:
            subscribedClients.remove(clientId)
            insideJobLogger.info("Client \(clientId) unsubscribed (\(self.subscribedClients.count) subscribers)")
        case .ping:
            muscle.noteClientActivity(clientId)
            sendMessage(.pong, respond: respond)
        case .requestScreen:
            handleScreen(respond: respond)
        case .waitForIdle(let target):
            await handleWaitForIdle(target, respond: respond)

        // Recording
        case .startRecording(let config):
            handleStartRecording(config, respond: respond)
        case .stopRecording:
            handleStopRecording(respond: respond)

        // Interaction dispatch — TheSafecracker handles all actions, gestures, and text entry
        case .activate(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeActivate(target) }
        case .increment(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeIncrement(target) }
        case .decrement(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeDecrement(target) }
        case .performCustomAction(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeCustomAction(target) }
        case .editAction(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeEditAction(target) }
        case .resignFirstResponder:
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeResignFirstResponder() }
        case .touchTap(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeTap(target) }
        case .touchLongPress(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeLongPress(target) }
        case .touchSwipe(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeSwipe(target) }
        case .touchDrag(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeDrag(target) }
        case .touchPinch(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executePinch(target) }
        case .touchRotate(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeDrawPath(target) }
        case .touchDrawBezier(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeDrawBezier(target) }
        case .typeText(let target):
            await performInteraction(command: message, respond: respond) { await self.theSafecracker.executeTypeText(target) }
        case .scroll(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeScroll(target) }
        case .scrollToVisible(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeScrollToVisible(target) }
        case .scrollToEdge(let target):
            await performInteraction(command: message, respond: respond) { self.theSafecracker.executeScrollToEdge(target) }
        }
    }

    // MARK: - Interaction Dispatch

    /// Standard interaction pattern: refresh → snapshot → execute → delta → respond
    /// TheSafecracker handles all interaction concerns (touch visualization, element refresh for read-back).
    /// When a recording is active, captures the command and before/after interface state.
    private func performInteraction(
        command: ClientMessage,
        respond: @escaping (Data) -> Void,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async {
        stakeout?.noteActivity()
        refreshAccessibilityData()
        let beforeTimestamp = Date()
        let beforeElements = snapshotElements()

        let result = await interaction()

        let actionResult: ActionResult
        if result.success {
            actionResult = await actionResultWithDelta(
                success: true,
                method: result.method,
                message: result.message,
                value: result.value,
                beforeElements: beforeElements
            )
        } else {
            actionResult = ActionResult(
                success: false,
                method: result.method,
                message: result.message,
                value: result.value
            )
        }

        // Record interaction to Stakeout if recording is active
        if let stakeout, stakeout.state == .recording {
            if !result.success {
                refreshAccessibilityData()
            }
            let afterElements = snapshotElements()
            let event = InteractionEvent(
                timestamp: stakeout.recordingElapsed,
                command: command,
                result: actionResult,
                interfaceBefore: Interface(timestamp: beforeTimestamp, elements: beforeElements),
                interfaceAfter: Interface(timestamp: Date(), elements: afterElements)
            )
            stakeout.recordInteraction(event: event)
        }

        sendMessage(.actionResult(actionResult), respond: respond)
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

    func sendMessage(_ message: ServerMessage, respond: @escaping (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(message) else {
            insideJobLogger.error("Failed to encode message")
            return
        }
        insideJobLogger.debug("Sending \(data.count) bytes")
        respond(data)
    }

    /// Send data only to clients that have explicitly subscribed.
    func broadcastToSubscribed(_ data: Data) {
        for clientId in subscribedClients {
            socketServer?.send(data, to: clientId)
        }
    }

    /// Send data to all connected clients (used for recording completion broadcasts).
    func broadcastToAll(_ data: Data) {
        socketServer?.broadcastToAll(data)
    }

    // MARK: - Accessibility Observation

    private func startAccessibilityObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: UIAccessibility.elementFocusedNotification,
            object: nil
        )
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
        insideJobLogger.info("App entering background, suspending server")
        suspend()
    }

    @objc private func appWillEnterForeground() {
        insideJobLogger.info("App entering foreground, resuming server")
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
        elementObjects.removeAll()
        lastHierarchyHash = 0

        insideJobLogger.info("Server suspended")
    }

    private func resume() {
        guard isRunning, isSuspended else { return }
        isSuspended = false

        insideJobLogger.info("Resuming server...")

        do {
            let server = SimpleSocketServer()
            wireServer(server)

            let actualPort = try server.start(port: 0, bindToLoopback: shouldBindToLoopback)
            self.socketServer = server

            insideJobLogger.info("Server resumed on port \(actualPort)")
            advertiseService(port: actualPort)

            startAccessibilityObservation()

            if isPollingEnabled {
                startPollingLoop()
            }

            insideJobLogger.info("Server resume complete")
        } catch {
            insideJobLogger.error("Failed to resume server: \(error)")
            isRunning = false
            isSuspended = false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
