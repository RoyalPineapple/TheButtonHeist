#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore
import os.log

let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")

/// Server that exposes accessibility hierarchy over TCP
/// Note: All access should be from the main thread
@MainActor
public final class TheInsideJob {

    // MARK: - Singleton

    /// Shared instance - use `configure(token:instanceId:)` before first access.
    /// Once configured, subsequent calls to `configure()` are no-ops.
    private static var _shared: TheInsideJob?

    /// The shared TheInsideJob singleton. Lazily created on first access.
    public static var shared: TheInsideJob {
        if let existing = _shared { return existing }
        let instance = TheInsideJob()
        _shared = instance
        return instance
    }

    /// Configure the shared instance. Must be called before `start()`.
    /// Second and subsequent calls are no-ops.
    public static func configure(token: String? = nil, instanceId: String? = nil, allowedScopes: Set<ConnectionScope>? = nil, port: UInt16 = 0) {
        if _shared != nil {
            insideJobLogger.warning("TheInsideJob.configure() called after already created — ignoring")
            return
        }
        _shared = TheInsideJob(token: token, instanceId: instanceId, allowedScopes: allowedScopes, port: port)
    }

    // MARK: - State Machines

    enum ServerPhase {
        case stopped
        case running(transport: ServerTransport)
        case suspended
        case resuming(task: Task<Void, Never>)
    }

    enum PollingPhase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    enum RecordingPhase {
        case idle
        case recording(stakeout: TheStakeout)
    }

    // MARK: - Properties

    var serverPhase: ServerPhase = .stopped
    var pollingPhase: PollingPhase = .disabled
    var recordingPhase: RecordingPhase = .idle
    private var tlsActive = false

    let muscle: TheMuscle
    private let instanceId: String?
    private let preferredPort: UInt16
    private let installationId: String
    private let sessionId = UUID()
    let tripwire = TheTripwire()
    let bagman: TheBagman
    let theSafecracker = TheSafecracker()

    private let allowedScopes: Set<ConnectionScope>

    // MARK: - Computed State Accessors

    private var isRunning: Bool {
        switch serverPhase {
        case .running, .suspended, .resuming: return true
        case .stopped: return false
        }
    }

    private var transport: ServerTransport? {
        if case .running(let transport) = serverPhase { return transport }
        return nil
    }

    var isPollingEnabled: Bool {
        switch pollingPhase {
        case .active, .paused: return true
        case .disabled: return false
        }
    }

    var pollingTimeoutSeconds: TimeInterval {
        switch pollingPhase {
        case .active(_, let interval), .paused(let interval): return interval
        case .disabled: return Self.defaultPollingTimeout
        }
    }

    var stakeout: TheStakeout? {
        if case .recording(let stakeout) = recordingPhase { return stakeout }
        return nil
    }

    // MARK: - Timing Constants

    /// Default polling interval for automatic hierarchy updates (1s).
    private static let defaultPollingTimeout: TimeInterval = 2.0

    // Hierarchy invalidation (pulse-driven, replaces debounce timer)
    var hierarchyInvalidated = false

    // MARK: - Initialization

    public init(token: String? = nil, instanceId: String? = nil, allowedScopes: Set<ConnectionScope>? = nil, port: UInt16 = 0) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.preferredPort = port
        self.installationId = Self.loadInstallationId()
        self.bagman = TheBagman(tripwire: self.tripwire)
        self.theSafecracker.bagman = self.bagman
        self.theSafecracker.tripwire = self.tripwire
        self.bagman.safecracker = self.theSafecracker

        if let scopes = allowedScopes {
            self.allowedScopes = scopes
        } else if let envValue = EnvironmentKey.insideJobScope.value,
                  let parsed = ConnectionScope.parse(envValue) {
            self.allowedScopes = parsed
        } else {
            self.allowedScopes = ConnectionScope.default
        }
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() async throws {
        guard case .stopped = serverPhase else {
            insideJobLogger.info("start() called while already running — ignoring")
            return
        }

        insideJobLogger.info("Starting TheInsideJob with ServerTransport...")

        let identity: TLSIdentity
        do {
            identity = try TLSIdentity.getOrCreate()
            insideJobLogger.info("TLS identity ready: \(identity.fingerprint)")
        } catch {
            insideJobLogger.warning("Keychain identity failed, using ephemeral: \(error)")
            identity = try TLSIdentity.createEphemeral()
        }
        self.tlsActive = true
        let transport = ServerTransport(tlsIdentity: identity, allowedScopes: allowedScopes)
        wireTransport(transport)

        let actualPort = try await transport.start(port: preferredPort)
        serverPhase = .running(transport: transport)

        let scopeNames = allowedScopes.map(\.rawValue).sorted().joined(separator: ", ")
        insideJobLogger.info("Connection scopes: \(scopeNames)")
        insideJobLogger.info("Server listening on port \(actualPort)")
        insideJobLogger.info("Connect with session token: \(self.muscle.sessionToken, privacy: .public)")
        insideJobLogger.info("Instance ID: \(self.effectiveInstanceId)")
        advertiseService(port: actualPort)

        // Prevent the screen from locking while TheInsideJob is running
        UIApplication.shared.isIdleTimerDisabled = true

        startAccessibilityObservation()
        startLifecycleObservation()

        tripwire.onTransition = { [weak self] transition in
            self?.handlePulseTransition(transition)
        }
        tripwire.startPulse()

        insideJobLogger.info("Server started successfully")
    }

    /// Stop the server
    public func stop() {
        // Cancel any in-flight resume task
        if case .resuming(let task) = serverPhase {
            task.cancel()
        }

        // Tear down active transport if running
        if case .running(let activeTransport) = serverPhase {
            activeTransport.stopAdvertising()
            activeTransport.stop()
        }

        serverPhase = .stopped
        hierarchyInvalidated = false
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil

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

    /// Enable settle-driven polling for automatic hierarchy updates.
    /// - Parameter timeout: Maximum seconds between settle checks (default 2.0, minimum 0.5)
    public func startPolling(interval timeout: TimeInterval = 2.0) {
        if case .active(let existingTask, _) = pollingPhase {
            existingTask.cancel()
        }
        let interval = max(0.5, timeout)
        let task = makePollingTask(interval: interval)
        pollingPhase = .active(task: task, interval: interval)
        insideJobLogger.info("Polling enabled (settle timeout: \(interval)s)")
    }

    /// Disable polling for automatic updates
    public func stopPolling() {
        if case .active(let task, _) = pollingPhase {
            task.cancel()
        }
        pollingPhase = .disabled
    }

    // MARK: - Transport Wiring

    private func wireTransport(_ transport: ServerTransport) {
        muscle.sendToClient = { [weak transport] data, clientId in transport?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak transport] clientId in transport?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak transport] clientId in transport?.disconnect(clientId: clientId) }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }
        muscle.onSessionActiveChanged = { [weak transport] isActive in
            transport?.updateTXTRecord([TXTRecordKey.sessionActive.rawValue: isActive ? "1" : "0"])
        }

        transport.onClientConnected = { [weak self] clientId, remoteAddress in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
                if let remoteAddress {
                    self?.muscle.registerClientAddress(clientId, address: remoteAddress)
                }
                self?.muscle.sendServerHello(clientId: clientId)
            }
        }

        transport.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) disconnected")
                self?.muscle.handleClientDisconnected(clientId)
            }
        }

        transport.onDataReceived = { [weak self] clientId, data, respond in
            Task { @MainActor in
                await self?.handleClientMessage(clientId, data: data, respond: respond)
            }
        }

        transport.onUnauthenticatedData = { [weak self] clientId, data, respond in
            Task { @MainActor in
                guard let self else { return }
                // Allow status probes after the version handshake, before full authentication.
                if let envelope = self.decodeRequest(data),
                   case .status = envelope.message,
                   self.muscle.helloValidatedClients.contains(clientId) {
                    await self.handleClientMessage(clientId, data: data, respond: respond)
                } else {
                    self.muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
                }
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
        guard let envelope = decodeRequest(data) else {
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
        case .clientHello, .authenticate, .watch:
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
        case .status:
            let payload = makeStatusPayload()
            sendMessage(.status(payload), requestId: requestId, respond: respond)

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
                    message: "Watch mode is read-only",
                    errorKind: .unsupported,
                    screenName: bagman.lastScreenName,
                    screenId: bagman.lastScreenId
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

    private func makeStatusPayload() -> StatusPayload {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let deviceName = UIDevice.current.name
        let systemVersion = UIDevice.current.systemVersion

        let identity = StatusIdentity(
            appName: appName,
            bundleIdentifier: bundleId,
            appBuild: appBuild,
            deviceName: deviceName,
            systemVersion: systemVersion,
            buttonHeistVersion: buttonHeistVersion
        )

        let active = muscle.isSessionActive
        let watchersAllowed = active && muscle.watchersAllowed
        let activeConnections = muscle.activeSessionConnectionCount

        let session = StatusSession(
            active: active,
            watchersAllowed: watchersAllowed,
            activeConnections: activeConnections
        )

        return StatusPayload(identity: identity, session: session)
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
        bagman.refresh()
        let before = bagman.captureBeforeState()
        let result = await interaction()

        let actionResult = await bagman.actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            before: before,
            target: command.actionTarget
        )

        recordAndBroadcast(command: command, actionResult: actionResult, requestId: requestId, respond: respond)
    }

    /// Wait for an element matching a predicate to appear or disappear.
    /// Uses TheTripwire settle events to avoid busy-polling — refreshes the tree
    /// only after the UI settles.
    func performWaitFor(
        target: WaitForTarget,
        command: ClientMessage,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) async {
        stakeout?.noteActivity()
        bagman.refresh()
        let before = bagman.captureBeforeState()
        let result = await executeWaitFor(target)

        let actionResult = await bagman.actionResultWithDelta(
            success: result.success,
            method: .waitFor,
            message: result.message,
            errorKind: result.success ? nil : .timeout,
            before: before
        )

        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
    }

    /// Execute the wait_for polling loop.
    /// Uses hasTarget (existence check) — doesn't require unique match.
    /// Snapshots after each refresh so heistId lookup stays current.
    private func executeWaitFor(_ target: WaitForTarget) async -> TheSafecracker.InteractionResult {
        let elementTarget = target.elementTarget
        let deadline = ContinuousClock.now + .seconds(target.resolvedTimeout)
        let start = CFAbsoluteTimeGetCurrent()

        // Phase 0: immediate check — refresh only, no snapshot needed.
        // hasTarget uses presentedHeistIds (already populated) or walks the hierarchy directly.
        bagman.refresh()
        if target.resolvedAbsent {
            if !bagman.hasTarget(elementTarget) {
                return .init(success: true, method: .waitFor, message: "absent confirmed after 0.0s", value: nil)
            }
        } else {
            if bagman.hasTarget(elementTarget) {
                return .init(success: true, method: .waitFor, message: "matched immediately", value: nil)
            }
        }

        // Phase 1: settle loop
        while ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            bagman.refresh()
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            if target.resolvedAbsent {
                if !bagman.hasTarget(elementTarget) {
                    return .init(success: true, method: .waitFor, message: "absent confirmed after \(elapsed)s", value: nil)
                }
            } else {
                if bagman.hasTarget(elementTarget) {
                    return .init(success: true, method: .waitFor, message: "matched after \(elapsed)s", value: nil)
                }
            }
        }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let reason = target.resolvedAbsent ? "element still present" : "element not found"
        return .failure(.waitFor, message: "timed out after \(elapsed)s (\(reason))")
    }

    /// Dedicated dispatch for scroll_to_visible search. Bypasses performInteraction
    /// because the scroll loop does its own repeated refresh/settle cycles internally.
    /// Captures before/after snapshots for delta computation around the entire search.
    func performScrollToVisibleSearch(
        target: ScrollToVisibleTarget,
        command: ClientMessage,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) async {
        stakeout?.noteActivity()
        bagman.refresh()
        let before = bagman.captureBeforeState()
        let result = await bagman.executeScrollToVisible(target)

        let actionResult = await bagman.actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            errorKind: result.success ? nil : .elementNotFound,
            before: before
        ).adding(scrollSearchResult: result.scrollSearchResult)

        recordAndBroadcast(command: command, actionResult: actionResult, requestId: requestId, respond: respond)
    }

    func performExplore(
        command: ClientMessage,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) async {
        stakeout?.noteActivity()
        bagman.refresh()
        let before = bagman.captureBeforeState()

        // actionResultWithDelta runs exploreScreen and marks all elements as presented.
        // Reuse the registry state it already computed — selectElements is a pure read
        // so this is not a redundant snapshot, just a wire conversion of the same data.
        let baseResult = await bagman.actionResultWithDelta(
            success: true,
            method: .explore,
            before: before
        )
        let elements = bagman.toWire(bagman.selectElements(.all))
        let actionResult = baseResult.adding(exploreElements: elements)

        recordAndBroadcast(command: command, actionResult: actionResult, requestId: requestId, respond: respond)
    }

    /// Record to stakeout, send response, and broadcast to subscribers.
    private func recordAndBroadcast(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) {
        if let stakeout, stakeout.isRecording {
            let event = InteractionEvent(
                timestamp: stakeout.recordingElapsed,
                command: command,
                result: actionResult
            )
            stakeout.recordInteraction(event: event)
        }

        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)

        if muscle.hasSubscribers {
            let event = InteractionEvent(
                timestamp: Date().timeIntervalSince1970,
                command: command,
                result: actionResult
            )
            broadcastToSubscribed(.interaction(event))
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

    /// Encode a response envelope, logging the actual error on failure.
    /// Returns nil only when encoding fails — callers decide how to handle that.
    func encodeEnvelope(_ message: ServerMessage, requestId: String? = nil) -> Data? {
        let envelope = ResponseEnvelope(requestId: requestId, message: message)
        do {
            return try JSONEncoder().encode(envelope)
        } catch {
            insideJobLogger.error("Failed to encode message: \(error)")
            return nil
        }
    }

    /// Decode a client request, logging the actual error on failure.
    func decodeRequest(_ data: Data) -> RequestEnvelope? {
        do {
            return try JSONDecoder().decode(RequestEnvelope.self, from: data)
        } catch {
            insideJobLogger.error("Failed to decode client message: \(error)")
            return nil
        }
    }

    func sendMessage(_ message: ServerMessage, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        if let data = encodeEnvelope(message, requestId: requestId) {
            insideJobLogger.debug("Sending \(data.count) bytes")
            respond(data)
        } else if let errorData = encodeEnvelope(.error("Encoding failed"), requestId: requestId) {
            respond(errorData)
        }
    }

    /// Broadcast a message to subscribed clients, encoding once.
    func broadcastToSubscribed(_ message: ServerMessage) {
        guard let data = encodeEnvelope(message) else { return }
        muscle.broadcastToSubscribed(data)
    }

    /// Broadcast a message to all connected clients, encoding once.
    func broadcastToAll(_ message: ServerMessage) {
        guard let data = encodeEnvelope(message) else { return }
        transport?.broadcastToAll(data)
    }

    /// Send pre-encoded data to all subscribed clients.
    func broadcastToSubscribed(_ data: Data) {
        muscle.broadcastToSubscribed(data)
    }

    /// Send pre-encoded data to all connected clients.
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

    func suspend() {
        switch serverPhase {
        case .running(let activeTransport):
            activeTransport.stopAdvertising()
            activeTransport.stop()
        case .resuming(let task):
            task.cancel()
        case .stopped, .suspended:
            return
        }

        // Pause polling if active, preserving the interval for resume
        if case .active(let pollingTask, let interval) = pollingPhase {
            pollingTask.cancel()
            pollingPhase = .paused(interval: interval)
        }

        hierarchyInvalidated = false

        tripwire.stopPulse()

        muscle.tearDown()

        stopAccessibilityObservation()

        bagman.clearCache()

        serverPhase = .suspended

        insideJobLogger.info("Server suspended")
    }

    private func resume() {
        guard case .suspended = serverPhase else { return }

        insideJobLogger.info("Resuming server...")

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var startedTransport: ServerTransport?
            do {
                try Task.checkCancellation()

                let identity: TLSIdentity
                do {
                    identity = try TLSIdentity.getOrCreate()
                } catch {
                    insideJobLogger.warning("Keychain identity failed on resume, using ephemeral: \(error)")
                    identity = try TLSIdentity.createEphemeral()
                }

                try Task.checkCancellation()

                self.tlsActive = true

                let transport = ServerTransport(tlsIdentity: identity, allowedScopes: self.allowedScopes)
                self.wireTransport(transport)
                startedTransport = transport

                let actualPort = try await transport.start(port: preferredPort)

                try Task.checkCancellation()

                self.serverPhase = .running(transport: transport)
                startedTransport = nil

                insideJobLogger.info("Server resumed on port \(actualPort)")
                self.advertiseService(port: actualPort)

                self.startAccessibilityObservation()

                self.tripwire.onTransition = { [weak self] transition in
                    self?.handlePulseTransition(transition)
                }
                self.tripwire.startPulse()

                // Resume polling if it was active before suspend
                if case .paused(let interval) = self.pollingPhase {
                    let pollingTask = self.makePollingTask(interval: interval)
                    self.pollingPhase = .active(task: pollingTask, interval: interval)
                }

                insideJobLogger.info("Server resume complete")
            } catch is CancellationError {
                startedTransport?.stop()
                insideJobLogger.info("Server resume cancelled")
            } catch {
                startedTransport?.stop()
                insideJobLogger.error("Failed to resume server: \(error)")
                if case .resuming = self.serverPhase {
                    self.serverPhase = .suspended
                }
            }
        }
        serverPhase = .resuming(task: task)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
