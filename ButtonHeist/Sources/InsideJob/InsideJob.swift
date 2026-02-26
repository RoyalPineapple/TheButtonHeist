#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import CryptoKit
import TheScore
import Wheelman
import os.log

let insideJobLogger = Logger(subsystem: "com.buttonheist.insidejob", category: "server")

/// Weak reference wrapper for interactive accessibility objects.
struct WeakObject {
    weak var object: NSObject?
}

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class InsideJob {

    // MARK: - Singleton

    /// Shared instance - use `configure(token:instanceId:)` before first access.
    /// Once configured, subsequent calls to `configure()` are no-ops.
    nonisolated(unsafe) private static var _shared: InsideJob?

    /// The shared InsideJob singleton. Lazily created on first access.
    public static var shared: InsideJob {
        if let existing = _shared { return existing }
        let instance = InsideJob()
        _shared = instance
        return instance
    }

    /// Configure the shared instance. Must be called before `start()`.
    /// Second and subsequent calls are no-ops.
    public static func configure(token: String? = nil, instanceId: String? = nil) {
        if _shared != nil {
            insideJobLogger.warning("InsideJob.configure() called after already created — ignoring")
            return
        }
        _shared = InsideJob(token: token, instanceId: instanceId)
    }

    // MARK: - Properties

    private var transport: ServerTransport?
    let muscle: TheMuscle
    private let instanceId: String?
    private let sessionId = UUID()
    let bagman = TheBagman()
    let theSafecracker = TheSafecracker()

    private var isRunning = false
    private var isSuspended = false

    // Screen recording
    var stakeout: TheStakeout?

    // MARK: - Timing Constants

    /// Debounce interval before broadcasting hierarchy updates (300ms).
    private static let debounceInterval: UInt64 = 300_000_000

    /// Default polling interval for automatic hierarchy updates (1s).
    private static let defaultPollingInterval: UInt64 = 1_000_000_000

    // Debounce for hierarchy updates
    var updateDebounceTask: Task<Void, Never>?
    let updateDebounceInterval: UInt64 = InsideJob.debounceInterval

    // Polling for automatic updates (disabled by default)
    var pollingTask: Task<Void, Never>?
    var pollingInterval: UInt64 = InsideJob.defaultPollingInterval
    var isPollingEnabled = false

    // MARK: - Initialization

    public init(token: String? = nil, instanceId: String? = nil) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.theSafecracker.bagman = self.bagman
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() throws {
        guard !isRunning else { return }

        insideJobLogger.info("Starting InsideJob with ServerTransport...")

        let t = ServerTransport()
        wireTransport(t)

        let actualPort = try t.start()
        self.transport = t
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

        transport?.stop()
        transport = nil

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

    // MARK: - Transport Wiring

    private func wireTransport(_ t: ServerTransport) {
        muscle.sendToClient = { [weak t] data, clientId in t?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak t] clientId in t?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak t] clientId in t?.disconnect(clientId: clientId) }
        muscle.disconnectClientsForSession = { [weak t] clientIds in
            for clientId in clientIds { t?.disconnect(clientId: clientId) }
        }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }
        muscle.onSessionActiveChanged = { [weak t] isActive in
            t?.updateTXTRecord(["sessionactive": isActive ? "1" : "0"])
        }

        t.onClientConnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) connected, awaiting auth")
                self?.muscle.sendAuthRequired(clientId: clientId)
            }
        }

        t.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) disconnected")
                self?.muscle.handleClientDisconnected(clientId)
            }
        }

        t.onDataReceived = { [weak self] clientId, data, respond in
            Task { @MainActor in
                await self?.handleClientMessage(clientId, data: data, respond: respond)
            }
        }

        t.onUnauthenticatedData = { [weak self] clientId, data, respond in
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

        // Token hash for pre-connection filtering (SHA256, first 8 bytes hex)
        let tokenHash = SHA256.hash(data: Data(muscle.authToken.utf8))
        let tokenHashPrefix = tokenHash.prefix(8).map { String(format: "%02x", $0) }.joined()

        transport?.advertise(
            serviceName: serviceName,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            tokenHash: tokenHashPrefix,
            instanceId: effectiveInstanceId
        )
    }

    // MARK: - Client Handling

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    private func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            insideJobLogger.error("Failed to decode client message")
            if String(data: data, encoding: .utf8) != nil {
                insideJobLogger.debug("Unparsable message: \(data.count) bytes")
            }
            sendMessage(.error("Malformed message — could not decode"), respond: respond)
            return
        }

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        // Protocol messages
        case .authenticate:
            break // Already authenticated via onUnauthenticatedData path
        case .requestInterface:
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(respond: respond)
        case .subscribe:
            muscle.subscribe(clientId: clientId)
        case .unsubscribe:
            muscle.unsubscribe(clientId: clientId)
        case .ping:
            muscle.noteClientActivity(clientId)
            sendMessage(.pong, respond: respond)

        // Observation
        case .requestScreen:
            handleScreen(respond: respond)
        case .waitForIdle(let target):
            await handleWaitForIdle(target, respond: respond)

        // Recording
        case .startRecording(let config):
            handleStartRecording(config, respond: respond)
        case .stopRecording:
            handleStopRecording(respond: respond)

        // All interactions delegate to TheSafecracker via performInteraction
        default:
            await dispatchInteraction(message, respond: respond)
        }
    }

    /// Route interaction messages to TheSafecracker through the standard
    /// refresh-snapshot-execute-delta pipeline.
    private func dispatchInteraction(_ message: ClientMessage, respond: @escaping (Data) -> Void) async {
        switch message {
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
        default:
            insideJobLogger.error("Unhandled message type in dispatchInteraction")
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .activate,
                message: "Unhandled command"
            )), respond: respond)
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
        bagman.refreshAccessibilityData()
        let beforeElements = bagman.snapshotElements()

        let result = await interaction()

        let actionResult: ActionResult
        if result.success {
            actionResult = await bagman.actionResultWithDelta(
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

        // Record interaction to TheStakeout if recording is active.
        // Uses the delta already computed in actionResult to avoid duplicating full interface snapshots.
        if let stakeout, stakeout.state == .recording {
            let event = InteractionEvent(
                timestamp: stakeout.recordingElapsed,
                command: command,
                result: actionResult,
                interfaceDelta: actionResult.interfaceDelta
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
            listeningPort: transport?.listeningPort,
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
        muscle.broadcastToSubscribed(data)
    }

    /// Send data to all connected clients (used for recording completion broadcasts).
    func broadcastToAll(_ data: Data) {
        transport?.broadcastToAll(data)
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

        transport?.stop()
        transport = nil

        muscle.tearDown()

        stopAccessibilityObservation()

        bagman.clearCache()

        insideJobLogger.info("Server suspended")
    }

    private func resume() {
        guard isRunning, isSuspended else { return }
        isSuspended = false

        insideJobLogger.info("Resuming server...")

        do {
            let t = ServerTransport()
            wireTransport(t)

            let actualPort = try t.start()
            self.transport = t

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
