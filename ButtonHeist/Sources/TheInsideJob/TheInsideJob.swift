#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore
import TheGetaway
import os.log

let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class TheInsideJob {

    // MARK: - Singleton

    /// Shared instance - use `configure(token:instanceId:)` before first access.
    /// Once configured, subsequent calls to `configure()` are no-ops.
    nonisolated(unsafe) private static var _shared: TheInsideJob?

    /// The shared TheInsideJob singleton. Lazily created on first access.
    public static var shared: TheInsideJob {
        if let existing = _shared { return existing }
        let instance = TheInsideJob()
        _shared = instance
        return instance
    }

    /// Configure the shared instance. Must be called before `start()`.
    /// Second and subsequent calls are no-ops.
    public static func configure(token: String? = nil, instanceId: String? = nil) {
        if _shared != nil {
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
            return
        }
        _shared = TheInsideJob(token: token, instanceId: instanceId)
    }

    // MARK: - Properties

    private var transport: ServerTransport?
    let muscle: TheMuscle
    private let instanceId: String?
    private let installationId: String
    private let sessionId = UUID()
    let bagman = TheBagman()
    let theSafecracker = TheSafecracker()

    private var isRunning = false
    private var isSuspended = false
    private var tlsActive = false

    // Screen recording
    var stakeout: TheStakeout?

    // MARK: - Timing Constants

    /// Debounce interval before broadcasting hierarchy updates (300ms).
    private static let debounceInterval: UInt64 = 300_000_000

    /// Default polling interval for automatic hierarchy updates (1s).
    private static let defaultPollingInterval: UInt64 = 1_000_000_000

    // Debounce for hierarchy updates
    var updateDebounceTask: Task<Void, Never>?
    let updateDebounceInterval: UInt64 = TheInsideJob.debounceInterval

    // Polling for automatic updates (disabled by default)
    var pollingTask: Task<Void, Never>?
    var pollingInterval: UInt64 = TheInsideJob.defaultPollingInterval
    var isPollingEnabled = false

    // MARK: - Initialization

    public init(token: String? = nil, instanceId: String? = nil) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.installationId = Self.loadInstallationId()
        self.theSafecracker.bagman = self.bagman
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() async throws {
        guard !isRunning else { return }

        insideJobLogger.info("Starting TheInsideJob with ServerTransport...")

        let identity: TLSIdentity?
        do {
            identity = try TLSIdentity.getOrCreate()
            insideJobLogger.info("TLS identity ready: \(identity!.fingerprint)")
        } catch {
            insideJobLogger.warning("TLS identity creation failed: \(error)")
            identity = try? TLSIdentity.createEphemeral()
        }
        self.tlsActive = identity != nil
        let t = ServerTransport(tlsIdentity: identity)
        wireTransport(t)

        let actualPort = try await t.start()
        self.transport = t
        isRunning = true

        insideJobLogger.info("Server listening on port \(actualPort)")
        insideJobLogger.info("Auth token: \(self.muscle.authToken, privacy: .sensitive)")
        if let instanceId {
            insideJobLogger.info("Instance ID: \(instanceId)")
        }
        advertiseService(port: actualPort)

        // Prevent the screen from locking while TheInsideJob is running
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

        transport?.stopAdvertising()
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

    private static func loadInstallationId() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.buttonheist.theinsidejob"
        let defaultsKey = "\(bundleId).installation-id"

        if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }

    private func advertiseService(port: UInt16) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let serviceName = "\(appName)#\(effectiveInstanceId)"

        transport?.advertise(
            serviceName: serviceName,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            installationId: installationId,
            instanceId: effectiveInstanceId,
            additionalTXT: [
                "devicename": UIDevice.current.name
            ]
        )
    }

    // MARK: - Client Handling

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    private func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let envelope = try? JSONDecoder().decode(RequestEnvelope.self, from: data) else {
            insideJobLogger.error("Failed to decode client message")
            if String(data: data, encoding: .utf8) != nil {
                insideJobLogger.debug("Unparsable message: \(data.count) bytes")
            }
            sendMessage(.error("Malformed message — could not decode"), respond: respond)
            return
        }

        let requestId = envelope.requestId
        let message = envelope.message

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        // Observers are read-only — only allow protocol and observation messages
        let isObserver = muscle.observerClients.contains(clientId)

        switch message {
        // Protocol messages
        case .authenticate, .watch:
            break // Already handled via onUnauthenticatedData path
        case .requestInterface:
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(requestId: requestId, respond: respond)
        case .subscribe:
            muscle.subscribe(clientId: clientId)
        case .unsubscribe:
            muscle.unsubscribe(clientId: clientId)
        case .ping:
            muscle.noteClientActivity(clientId)
            sendMessage(.pong, requestId: requestId, respond: respond)

        // Observation
        case .requestScreen:
            handleScreen(requestId: requestId, respond: respond)
        case .waitForIdle(let target):
            await handleWaitForIdle(target, requestId: requestId, respond: respond)

        // Recording & interactions — blocked for observers
        default:
            if isObserver {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .activate,
                    message: "Watch mode is read-only"
                )), requestId: requestId, respond: respond)
                return
            }

            switch message {
            case .startRecording(let config):
                handleStartRecording(config, requestId: requestId, respond: respond)
            case .stopRecording:
                handleStopRecording(requestId: requestId, respond: respond)
            default:
                await dispatchInteraction(message, requestId: requestId, respond: respond)
            }
        }
    }

    // MARK: - Interaction Dispatch

    /// Standard interaction pattern: refresh → snapshot → execute → delta → respond
    /// TheSafecracker handles all interaction concerns (touch visualization, element refresh for read-back).
    /// When a recording is active, captures the command and before/after interface state.
    func performInteraction(
        command: ClientMessage,
        requestId: String? = nil,
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

        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)

        // Broadcast interaction event to observers/subscribers
        if muscle.hasSubscribers {
            let event = InteractionEvent(
                timestamp: Date().timeIntervalSince1970,
                command: command,
                result: actionResult,
                interfaceDelta: actionResult.interfaceDelta
            )
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interaction(event))) {
                broadcastToSubscribed(data)
            }
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
            listeningPort: transport?.listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString,
            tlsActive: tlsActive
        )
        sendMessage(.info(info), respond: respond)
    }

    func sendMessage(_ message: ServerMessage, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        let envelope = ResponseEnvelope(requestId: requestId, message: message)
        guard let data = try? JSONEncoder().encode(envelope) else {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
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
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willTerminateNotification,
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

    @objc private func appWillTerminate() {
        insideJobLogger.info("App will terminate, stopping server advertisement")
        stop()
    }

    private func suspend() {
        guard isRunning, !isSuspended else { return }
        isSuspended = true

        pollingTask?.cancel()
        pollingTask = nil

        updateDebounceTask?.cancel()
        updateDebounceTask = nil

        transport?.stopAdvertising()
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

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let t = ServerTransport()
                self.wireTransport(t)

                let actualPort = try await t.start()
                self.transport = t

                insideJobLogger.info("Server resumed on port \(actualPort)")
                self.advertiseService(port: actualPort)

                self.startAccessibilityObservation()

                if self.isPollingEnabled {
                    self.startPollingLoop()
                }

                insideJobLogger.info("Server resume complete")
            } catch {
                insideJobLogger.error("Failed to resume server: \(error)")
                self.isRunning = false
                self.isSuspended = false
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
