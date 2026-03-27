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

    // MARK: - Properties

    private var transport: ServerTransport?
    let muscle: TheMuscle
    private let instanceId: String?
    private let preferredPort: UInt16
    private let installationId: String
    private let sessionId = UUID()
    let tripwire = TheTripwire()
    let bagman: TheBagman
    let theSafecracker = TheSafecracker()

    private let allowedScopes: Set<ConnectionScope>
    private var isRunning = false
    private var isSuspended = false
    private var tlsActive = false
    private var resumeTask: Task<Void, Never>?

    // Screen recording
    var stakeout: TheStakeout?

    // MARK: - Timing Constants

    /// Default polling interval for automatic hierarchy updates (1s).
    private static let defaultPollingTimeout: TimeInterval = 2.0

    // Hierarchy invalidation (pulse-driven, replaces debounce timer)
    var hierarchyInvalidated = false
    // Polling for automatic updates (disabled by default)
    var pollingTask: Task<Void, Never>?
    var pollingTimeoutSeconds: TimeInterval = TheInsideJob.defaultPollingTimeout
    var isPollingEnabled = false

    // MARK: - Initialization

    public init(token: String? = nil, instanceId: String? = nil, allowedScopes: Set<ConnectionScope>? = nil, port: UInt16 = 0) {
        self.muscle = TheMuscle(explicitToken: token)
        self.instanceId = instanceId
        self.preferredPort = port
        self.installationId = Self.loadInstallationId()
        self.bagman = TheBagman(tripwire: self.tripwire)
        self.theSafecracker.bagman = self.bagman
        self.theSafecracker.tripwire = self.tripwire

        if let scopes = allowedScopes {
            self.allowedScopes = scopes
        } else if let envValue = ProcessInfo.processInfo.environment["INSIDEJOB_SCOPE"],
                  let parsed = ConnectionScope.parse(envValue) {
            self.allowedScopes = parsed
        } else {
            self.allowedScopes = ConnectionScope.default
        }
    }

    // MARK: - Public Methods

    /// Start the server
    public func start() async throws {
        guard !isRunning else { return }

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
        let t = ServerTransport(tlsIdentity: identity, allowedScopes: allowedScopes)
        wireTransport(t)

        let actualPort = try await t.start(port: preferredPort)
        self.transport = t
        isRunning = true

        let scopeNames = allowedScopes.map(\.rawValue).sorted().joined(separator: ", ")
        insideJobLogger.info("Connection scopes: \(scopeNames)")
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

        tripwire.onTransition = { [weak self] transition in
            self?.handlePulseTransition(transition)
        }
        tripwire.startPulse()

        insideJobLogger.info("Server started successfully")
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        isSuspended = false
        resumeTask?.cancel()
        resumeTask = nil
        hierarchyInvalidated = false
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil

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

    /// Enable settle-driven polling for automatic hierarchy updates.
    /// - Parameter timeout: Maximum seconds between settle checks (default 2.0, minimum 0.5)
    public func startPolling(interval timeout: TimeInterval = 2.0) {
        pollingTimeoutSeconds = max(0.5, timeout)
        isPollingEnabled = true
        startPollingLoop()
        insideJobLogger.info("Polling enabled (settle timeout: \(self.pollingTimeoutSeconds)s)")
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

        t.onClientConnected = { [weak self] clientId, remoteAddress in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
                if let remoteAddress {
                    self?.muscle.registerClientAddress(clientId, address: remoteAddress)
                }
                self?.muscle.sendServerHello(clientId: clientId)
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
                guard let self else { return }
                // Allow status probes after the version handshake, before full authentication.
                if let envelope = try? JSONDecoder().decode(RequestEnvelope.self, from: data),
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
                    screenName: bagman.lastScreenName
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
        bagman.refreshAccessibilityData()
        let beforeSnapshot = bagman.snapshotElements()
        let beforeCachedElements = bagman.cachedElements
        let beforeVC = tripwire.topmostViewController().map(ObjectIdentifier.init)

        let result = await interaction()

        let actionResult: ActionResult
        if result.success {
            actionResult = await bagman.actionResultWithDelta(
                success: true,
                method: result.method,
                message: result.message,
                value: result.value,
                beforeSnapshot: beforeSnapshot,
                beforeCachedElements: beforeCachedElements,
                beforeVC: beforeVC,
                target: command.actionTarget
            )
        } else {
            let kind: ErrorKind = (result.method == .elementNotFound || result.method == .elementDeallocated)
                ? .elementNotFound : .actionFailed
            actionResult = ActionResult(
                success: false,
                method: result.method,
                message: result.message,
                errorKind: kind,
                value: result.value,
                screenName: beforeSnapshot.screenName
            )
        }

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
        bagman.refreshAccessibilityData()
        let beforeSnapshot = bagman.snapshotElements()
        let beforeCachedElements = bagman.cachedElements
        let beforeVC = tripwire.topmostViewController().map(ObjectIdentifier.init)

        let result = await executeWaitFor(target)

        let actionResult: ActionResult
        if result.success {
            actionResult = await bagman.actionResultWithDelta(
                success: true,
                method: .waitFor,
                message: result.message,
                beforeSnapshot: beforeSnapshot,
                beforeCachedElements: beforeCachedElements,
                beforeVC: beforeVC
            )
        } else {
            bagman.refreshAccessibilityData()
            let afterSnapshot = bagman.snapshotElements()
            actionResult = ActionResult(
                success: false,
                method: .waitFor,
                message: result.message,
                screenName: afterSnapshot.screenName
            )
        }

        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
    }

    /// Execute the wait_for polling loop.
    private func executeWaitFor(_ target: WaitForTarget) async -> TheSafecracker.InteractionResult {
        let matcher = target.match
        let deadline = ContinuousClock.now + .seconds(target.resolvedTimeout)
        let start = CFAbsoluteTimeGetCurrent()

        // Phase 0: immediate check
        bagman.refreshAccessibilityData()
        if target.resolvedAbsent {
            if !bagman.hasMatch(matcher) {
                return .init(success: true, method: .waitFor, message: "absent confirmed after 0.0s", value: nil)
            }
        } else {
            if bagman.findMatch(matcher) != nil {
                return .init(success: true, method: .waitFor, message: "matched immediately", value: nil)
            }
        }

        // Phase 1: settle loop
        while ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            bagman.refreshAccessibilityData()
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            if target.resolvedAbsent {
                if !bagman.hasMatch(matcher) {
                    return .init(success: true, method: .waitFor, message: "absent confirmed after \(elapsed)s", value: nil)
                }
            } else {
                if bagman.findMatch(matcher) != nil {
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
        bagman.refreshAccessibilityData()
        let beforeSnapshot = bagman.snapshotElements()
        let beforeCachedElements = bagman.cachedElements
        let beforeVC = tripwire.topmostViewController().map(ObjectIdentifier.init)

        let result = await theSafecracker.executeScrollToVisible(target)

        var actionResult: ActionResult
        if result.success {
            let baseResult = await bagman.actionResultWithDelta(
                success: true,
                method: result.method,
                message: result.message,
                value: result.value,
                beforeSnapshot: beforeSnapshot,
                beforeCachedElements: beforeCachedElements,
                beforeVC: beforeVC,
                target: nil
            )
            actionResult = ActionResult(
                success: baseResult.success,
                method: baseResult.method,
                message: baseResult.message,
                value: baseResult.value,
                interfaceDelta: baseResult.interfaceDelta,
                animating: baseResult.animating,
                elementLabel: baseResult.elementLabel,
                elementValue: baseResult.elementValue,
                elementTraits: baseResult.elementTraits,
                screenName: baseResult.screenName,
                scrollSearchResult: result.scrollSearchResult
            )
        } else {
            bagman.refreshAccessibilityData()
            let afterSnapshot = bagman.snapshotElements()
            actionResult = ActionResult(
                success: false,
                method: result.method,
                message: result.message,
                value: result.value,
                screenName: afterSnapshot.screenName,
                scrollSearchResult: result.scrollSearchResult
            )
        }

        recordAndBroadcast(command: command, actionResult: actionResult, requestId: requestId, respond: respond)
    }

    /// Record to stakeout, send response, and broadcast to subscribers.
    private func recordAndBroadcast(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) {
        if let stakeout, stakeout.state == .recording {
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

        resumeTask?.cancel()
        resumeTask = nil

        pollingTask?.cancel()
        pollingTask = nil

        hierarchyInvalidated = false

        tripwire.stopPulse()

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

        resumeTask?.cancel()
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
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

                let t = ServerTransport(tlsIdentity: identity, allowedScopes: self.allowedScopes)
                self.wireTransport(t)

                let actualPort = try await t.start(port: preferredPort)

                try Task.checkCancellation()

                self.transport = t

                insideJobLogger.info("Server resumed on port \(actualPort)")
                self.advertiseService(port: actualPort)

                self.startAccessibilityObservation()

                self.tripwire.onTransition = { [weak self] transition in
                    self?.handlePulseTransition(transition)
                }
                self.tripwire.startPulse()

                if self.isPollingEnabled {
                    self.startPollingLoop()
                }

                insideJobLogger.info("Server resume complete")
            } catch is CancellationError {
                insideJobLogger.info("Server resume cancelled")
            } catch {
                insideJobLogger.error("Failed to resume server: \(error)")
                self.isSuspended = true
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
