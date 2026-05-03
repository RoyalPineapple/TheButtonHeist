import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "bookkeeper")

/// Errors thrown by TheFence during command dispatch, connection, and action execution.
public enum FenceError: Error, LocalizedError {
    case invalidRequest(String)
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)
    case sessionLocked(String)
    case authFailed(String)
    case notConnected
    case actionTimeout
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return message
        case .noDeviceFound:
            return "No devices found within timeout. Is the app running?"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return """
                Connection timed out
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .connectionFailed(let message):
            return """
                Connection failed: \(message)
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .sessionLocked(let message):
            return """
                Session locked: \(message)
                  Another driver is currently connected. Wait for it to disconnect
                  or for the session to time out.
                """
        case .authFailed(let message):
            return """
                Auth failed: \(message)
                  Retry without --token to request a fresh session.
                """
        case .notConnected:
            return """
                Not connected to device.
                  The previous connection may have closed or timed out.
                  Hint: Check that the app is running, then retry the command. Use 'buttonheist list' to see available devices.
                """
        case .actionTimeout:
            return """
                Command timed out waiting for a response from the app.
                  The app may be busy on its main thread, processing a long-running UI update, or sending a large response.
                  The connection is preserved — retry the command on the same session.
                """
        case .actionFailed(let message):
            return "Action failed: \(message)"
        }
    }
}

private extension TheFence.Command {
    var requiresConnectionBeforeDispatch: Bool {
        switch self {
        case .getSessionState, .listDevices, .connect, .listTargets,
             .getSessionLog, .archiveSession, .startHeist, .stopHeist:
            return false
        default:
            return true
        }
    }
}

private extension FenceResponse {
    var succeededForHeistRecording: Bool {
        if case .error = self { return false }
        if let actionResult, !actionResult.success { return false }
        return true
    }
}

extension FenceError {
    init(_ connectionError: TheHandoff.ConnectionError) {
        switch connectionError {
        case .connectionFailed(let message): self = .connectionFailed(message)
        case .authFailed(let reason): self = .authFailed(reason)
        case .sessionLocked(let message): self = .sessionLocked(message)
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        }
    }
}

/// Named timeout constants for TheFence operations.
public enum Timeouts {
    /// Standard action timeout (15 seconds)
    public static let actionSeconds: TimeInterval = 15
    /// Long action timeout (30 seconds)
    public static let longActionSeconds: TimeInterval = 30
    /// Explore timeout (60 seconds) — scrolls entire screen, needs headroom
    public static let exploreSeconds: TimeInterval = 60
}

/// Centralized command dispatch layer. Both the CLI and MCP server are thin wrappers over TheFence.
@ButtonHeistActor
public final class TheFence {
    /// Connection and session configuration for TheFence.
    public struct Configuration {
        /// Substring filter for Bonjour device names. `nil` matches any device.
        public var deviceFilter: String?
        /// Seconds to wait for initial connection before failing `start()`.
        public var connectionTimeout: TimeInterval
        /// Auth token sent with `client_hello`. Agents use the task slug; omit to
        /// fall back to the `BUTTONHEIST_TOKEN` environment variable.
        public var token: String?
        /// When true, TheHandoff re-establishes the connection on drop.
        public var autoReconnect: Bool
        /// Resolved `.buttonheist.json` config (device filter, token, output paths).
        /// Supplied by the CLI/MCP entry points from discovered config files.
        public var fileConfig: ButtonHeistFileConfig?
        /// Direct host:port target with optional TLS fingerprint from config.
        public var directDevice: DiscoveredDevice?

        public init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil,
            directDevice: DiscoveredDevice? = nil
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
            self.directDevice = directDevice
        }
    }

    public static let supportedCommands: [String] = Command.allCases.map(\.rawValue)

    /// Fires on informational status strings (e.g. `BUTTONHEIST_TOKEN=<value>`
    /// on server-generated token, connection events). Fires on `@ButtonHeistActor`.
    public var onStatus: ((String) -> Void)? {
        didSet { handoff.onStatus = onStatus }
    }

    /// Fires when the server approves authentication. The parameter is the
    /// approved token, or `nil` when the server accepted a previously-held
    /// session. Fires on `@ButtonHeistActor`.
    public var onAuthApproved: ((String?) -> Void)?

    var config: Configuration
    let handoff = TheHandoff()
    let bookKeeper = TheBookKeeper()
    /// Playback phase — prevents re-entrant play_heist calls.
    enum PlaybackPhase {
        case idle
        case playing
    }
    var playbackPhase: PlaybackPhase = .idle

    /// Cached interface elements from the most recent get_interface response, keyed by heistId.
    /// Used by TheBookKeeper for heist recording and by expectation validation for elementDisappeared.
    private var lastInterfaceCache: [String: HeistElement] = [:]

    // MARK: - Pending Request Tracking

    private let actionTracker = PendingRequestTracker<ActionResult>()
    private let interfaceTracker = PendingRequestTracker<Interface>()
    private let screenTracker = PendingRequestTracker<ScreenPayload>()
    private let recordingTracker = PendingRequestTracker<RecordingPayload>()
    private var recordingWaitInFlight = false

    public init(configuration: Configuration = .init()) {
        self.config = configuration
        self.handoff.token = configuration.token ?? EnvironmentKey.buttonheistToken.value
        self.handoff.driverId = EnvironmentKey.buttonheistDriverId.value
        self.handoff.autoSubscribe = true
        self.handoff.onAuthApproved = { [weak self] token in
            if let token {
                self?.onStatus?("BUTTONHEIST_TOKEN=\(token)")
            }
            self?.onAuthApproved?(token)
        }
        wireUpResponseCallbacks()
    }

    private func wireUpResponseCallbacks() {
        handoff.onInterface = { [weak self] payload, requestId in
            guard let self, let requestId else { return }
            self.interfaceTracker.resolve(requestId: requestId, result: .success(payload))
        }

        handoff.onActionResult = { [weak self] result, requestId in
            guard let self, let requestId else { return }
            self.actionTracker.resolve(requestId: requestId, result: .success(result))
        }

        handoff.onScreen = { [weak self] payload, requestId in
            guard let self, let requestId else { return }
            self.screenTracker.resolve(requestId: requestId, result: .success(payload))
        }

        handoff.onBackgroundDelta = { [weak self] delta in
            self?.lastBackgroundDelta = delta
        }

        handoff.onDisconnected = { [weak self] reason in
            self?.cancelAllPendingRequests(
                error: FenceError.connectionFailed(reason.displayMessage)
            )
        }
    }

    /// The most recent background delta received from the server.
    /// Drained (read and cleared) by `drainBackgroundDelta()`.
    private var lastBackgroundDelta: InterfaceDelta?

    /// Return and clear the last background delta, if any.
    public func drainBackgroundDelta() -> InterfaceDelta? {
        let delta = lastBackgroundDelta
        lastBackgroundDelta = nil
        return delta
    }

    /// Connect to a device and optionally enable auto-reconnect.
    public func start() async throws {
        if handoff.isConnected {
            return
        }

        try await connect()
        if config.autoReconnect {
            let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
            handoff.setupAutoReconnect(filter: filter)
        }
    }

    /// Disconnect and cancel all pending requests.
    public func stop() {
        cancelAllPendingRequests()
        handoff.disconnect()
        handoff.stopDiscovery()
    }

    /// Execute a command from a dictionary request. Auto-connects if not already connected.
    public func execute(request: [String: Any]) async throws -> FenceResponse {
        guard let commandString = request["command"] as? String else {
            throw FenceError.invalidRequest("Invalid JSON or missing 'command' field")
        }
        guard let command = Command(rawValue: commandString) else {
            return .error("Unknown command: \(commandString). Use 'help' for available commands.")
        }
        if let immediateResponse = handleImmediateCommand(command) { return immediateResponse }
        let requestId = (request["requestId"] as? String) ?? UUID().uuidString
        logCommand(requestId: requestId, command: command, request: request)
        let parsedExpectation = try parseExpectation(request)

        if let backgroundResponse = responseIfBackgroundExpectationMet(parsedExpectation, requestId: requestId) {
            return backgroundResponse
        }

        try await ensureConnectedIfNeeded(for: command)

        var dispatchArgs = request
        dispatchArgs["_requestId"] = requestId

        let dispatched = try await dispatchWithErrorLogging(
            command: command,
            args: dispatchArgs,
            requestId: requestId
        )
        lastLatencyMs = dispatched.durationMs

        logResponse(requestId: requestId, response: dispatched.response, durationMs: lastLatencyMs)

        // Snapshot pre-action elements before updating the cache — elementDisappeared
        // expectations need to resolve removed heistIds against the pre-action state.
        let preActionCache = lastInterfaceCache
        let cacheUpdate = updateInterfaceCache(for: dispatched.response, preActionCache: preActionCache)
        recordHeistEvidence(command: command, request: request, response: dispatched.response, cacheUpdate: cacheUpdate)
        applyPostRecordCacheUpdate(cacheUpdate)
        return validateActionResponse(dispatched.response, expectation: parsedExpectation, preActionCache: preActionCache)
    }

    private struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    private struct ResponseCacheUpdate {
        let evidenceElements: [HeistElement]?
        let postRecordBookKeeperElements: [HeistElement]?
    }

    private func handleImmediateCommand(_ command: Command) -> FenceResponse? {
        switch command {
        case .help:
            return .help(commands: Self.supportedCommands)
        case .quit, .exit:
            stop()
            return .ok(message: "bye")
        default:
            return nil
        }
    }

    private func logCommand(requestId: String, command: Command, request: [String: Any]) {
        do {
            try bookKeeper.logCommand(requestId: requestId, command: command, arguments: request)
        } catch {
            logger.warning("Failed to log command \(command.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func responseIfBackgroundExpectationMet(
        _ expectation: ActionExpectation?,
        requestId: String
    ) -> FenceResponse? {
        guard let expectation, let backgroundDelta = drainBackgroundDelta() else { return nil }
        let syntheticResult = ActionResult(
            success: true,
            method: .waitForChange,
            message: "expectation already met by background change",
            interfaceDelta: backgroundDelta
        )
        let validation = expectation.validate(against: syntheticResult)
        guard validation.met else { return nil }
        let response = FenceResponse.action(result: syntheticResult, expectation: validation)
        logResponse(requestId: requestId, response: response, durationMs: 0)
        return response
    }

    private func ensureConnectedIfNeeded(for command: Command) async throws {
        guard !handoff.isConnected, command.requiresConnectionBeforeDispatch else { return }
        try await start()
    }

    private func dispatchWithErrorLogging(
        command: Command,
        args: [String: Any],
        requestId: String
    ) async throws -> DispatchResult {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await dispatch(command: command, args: args)
            return DispatchResult(response: response, durationMs: elapsedMilliseconds(since: start))
        } catch {
            let durationMs = elapsedMilliseconds(since: start)
            logErrorResponse(requestId: requestId, error: error, durationMs: durationMs)
            throw error
        }
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private func logErrorResponse(requestId: String, error: Error, durationMs: Int) {
        do {
            try bookKeeper.logResponse(
                requestId: requestId,
                status: .error,
                durationMilliseconds: durationMs,
                error: error.localizedDescription
            )
        } catch let logError {
            logger.warning("Failed to log error response for \(requestId, privacy: .public): \(logError.localizedDescription, privacy: .public)")
        }
    }

    private func updateInterfaceCache(
        for response: FenceResponse,
        preActionCache: [String: HeistElement]
    ) -> ResponseCacheUpdate {
        if case .interface(let iface, _, _, _) = response {
            updateInterfaceCache(iface.elements)
            return ResponseCacheUpdate(
                evidenceElements: lastInterfaceCache.isEmpty ? nil : Array(lastInterfaceCache.values),
                postRecordBookKeeperElements: nil
            )
        }
        guard let actionResult = response.actionResult,
              let newInterface = actionResult.interfaceDelta?.newInterface else {
            return ResponseCacheUpdate(
                evidenceElements: lastInterfaceCache.isEmpty ? nil : Array(lastInterfaceCache.values),
                postRecordBookKeeperElements: nil
            )
        }
        return updateInterfaceCache(for: actionResult, newInterface: newInterface, preActionCache: preActionCache)
    }

    private func updateInterfaceCache(
        for actionResult: ActionResult,
        newInterface: Interface,
        preActionCache: [String: HeistElement]
    ) -> ResponseCacheUpdate {
        guard actionResult.interfaceDelta?.kind == .screenChanged else {
            updateInterfaceCache(newInterface.elements)
            return ResponseCacheUpdate(
                evidenceElements: lastInterfaceCache.isEmpty ? nil : Array(lastInterfaceCache.values),
                postRecordBookKeeperElements: nil
            )
        }
        lastInterfaceCache.removeAll()
        for element in newInterface.elements {
            lastInterfaceCache[element.heistId] = element
        }
        return ResponseCacheUpdate(
            evidenceElements: Array(preActionCache.values) + newInterface.elements,
            postRecordBookKeeperElements: newInterface.elements
        )
    }

    private func recordHeistEvidence(
        command: Command,
        request: [String: Any],
        response: FenceResponse,
        cacheUpdate: ResponseCacheUpdate
    ) {
        guard case .idle = playbackPhase else { return }
        bookKeeper.recordHeistEvidence(
            command: command,
            args: request,
            succeeded: response.succeededForHeistRecording,
            interfaceElements: cacheUpdate.evidenceElements
        )
    }

    private func applyPostRecordCacheUpdate(_ cacheUpdate: ResponseCacheUpdate) {
        guard let elements = cacheUpdate.postRecordBookKeeperElements else { return }
        bookKeeper.clearInterfaceCache()
        bookKeeper.updateInterfaceCache(elements)
    }

    private func validateActionResponse(
        _ response: FenceResponse,
        expectation: ActionExpectation?,
        preActionCache: [String: HeistElement]
    ) -> FenceResponse {
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return .action(result: actionResult, expectation: delivery)
            }
            if let expectation {
                let validation = expectation.validate(
                    against: actionResult, preActionElements: preActionCache
                )
                return .action(result: actionResult, expectation: validation)
            }
        }

        return response
    }

    private func connect() async throws {
        if let directDevice = config.directDevice {
            try await connectDirect(to: directDevice)
            return
        }
        let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
        do {
            try await handoff.connectWithDiscovery(
                filter: filter,
                timeout: config.connectionTimeout
            )
        } catch let error as TheHandoff.ConnectionError {
            throw FenceError(error)
        }
    }

    private func connectDirect(to device: DiscoveredDevice) async throws {
        handoff.onStatus?("Connecting to \(device.name)...")
        handoff.connect(to: device)
        let start = DispatchTime.now().uptimeNanoseconds
        let timeout = UInt64(max(config.connectionTimeout, 5) * 1_000_000_000)
        while true {
            switch handoff.connectionPhase {
            case .connected:
                handoff.onStatus?("Connected to \(device.name)")
                return
            case .failed(let failure):
                throw FenceError(failure.asConnectionError)
            case .disconnected:
                throw FenceError(TheHandoff.ConnectionError.connectionFailed("Disconnected during connection attempt"))
            case .connecting:
                break
            }
            if DispatchTime.now().uptimeNanoseconds - start > timeout {
                throw FenceError(TheHandoff.ConnectionError.timeout)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Interface Cache

    private func updateInterfaceCache(_ elements: [HeistElement]) {
        for element in elements {
            lastInterfaceCache[element.heistId] = element
        }
        bookKeeper.updateInterfaceCache(elements)
    }

    // MARK: - Response Logging

    private func logResponse(requestId: String, response: FenceResponse, durationMs: Int) {
        let responseStatus: ResponseStatus
        let artifactPath: String?
        let errorMessage: String?
        switch response {
        case .error(let message):
            responseStatus = .error
            artifactPath = nil
            errorMessage = message
        case .screenshot(let path, _, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .recording(let path, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .archiveResult(let path, _):
            responseStatus = .ok
            artifactPath = path
            errorMessage = nil
        case .ok, .help, .status, .devices, .interface, .action,
             .screenshotData, .recordingData, .batch, .sessionState,
             .targets, .sessionLog, .heistStarted, .heistStopped,
             .heistPlayback:
            responseStatus = .ok
            artifactPath = nil
            errorMessage = nil
        }
        do {
            try bookKeeper.logResponse(
                requestId: requestId,
                status: responseStatus,
                durationMilliseconds: durationMs,
                artifact: artifactPath,
                error: errorMessage
            )
        } catch {
            logger.warning("Failed to log response for \(requestId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Command Dispatch (thin router)

    private func dispatch(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .status:
            return .status(
                connected: handoff.isConnected,
                deviceName: handoff.connectedDevice.map { handoff.displayName(for: $0) }
            )
        case .listDevices:
            return try await handleListDevices()
        case .getInterface:
            return try await handleGetInterface(args)
        case .getScreen:
            return try await handleGetScreen(args)
        case .waitForChange:
            return try await handleWaitForChange(args)
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return try await handleGesture(command: command, args: args)
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return try await handleScrollAction(command: command, args: args)
        case .waitFor:
            return try await handleWaitFor(args)
        case .activate, .increment, .decrement, .performCustomAction:
            return try await handleAccessibilityAction(command: command, args: args)
        case .typeText:
            return try await handleTypeText(args)
        case .editAction:
            return try await handleEditAction(args)
        case .setPasteboard, .getPasteboard:
            return try await handlePasteboard(command: command, args: args)
        case .dismissKeyboard:
            return try await sendAction(.resignFirstResponder)
        case .startRecording, .stopRecording:
            return command == .startRecording
                ? try await handleStartRecording(args)
                : try await handleStopRecording(args)
        case .runBatch:
            return try await handleRunBatch(args)
        case .getSessionState:
            return .sessionState(payload: currentSessionState())
        case .connect:
            return try await handleConnect(args)
        case .listTargets:
            return handleListTargets()
        case .getSessionLog, .archiveSession, .startHeist, .stopHeist, .playHeist:
            return try await handleBookKeeperCommand(command: command, args: args)
        case .help, .quit, .exit:
            return .error("Unexpected command in dispatch: \(command.rawValue)")
        }
    }

    // MARK: - Send Action (shared)

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
        lastActionResult = result
        return .action(result: result)
    }

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        try await sendAndAwait(message, tracker: actionTracker, timeout: timeout)
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        try await sendAndAwait(message, tracker: interfaceTracker, timeout: timeout)
    }

    func sendAndAwaitScreen(_ message: ClientMessage, timeout: TimeInterval) async throws -> ScreenPayload {
        try await sendAndAwait(message, tracker: screenTracker, timeout: timeout)
    }

    private func sendAndAwait<T: Sendable>(
        _ message: ClientMessage,
        tracker: PendingRequestTracker<T>,
        timeout: TimeInterval
    ) async throws -> T {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        do {
            return try await tracker.wait(requestId: requestId, timeout: timeout) {
                self.handoff.send(message, requestId: requestId)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw mapCaughtError(error)
        }
    }

    private func mapCaughtError(_ error: Error) -> FenceError {
        if let fenceError = error as? FenceError {
            return fenceError
        }
        return .actionFailed(error.localizedDescription)
    }

    func elementTarget(_ dictionary: [String: Any]) throws -> ElementTarget? {
        ElementTarget(
            heistId: dictionary.string("heistId"),
            matcher: try elementMatcher(dictionary),
            ordinal: dictionary.integer("ordinal")
        )
    }

    func elementMatcher(_ dictionary: [String: Any]) throws -> ElementMatcher {
        return ElementMatcher(
            label: dictionary.string("label"),
            identifier: dictionary.string("identifier"),
            value: dictionary.string("value"),
            traits: try parseTraitNames(dictionary["traits"] as? [String], field: "trait"),
            excludeTraits: try parseTraitNames(dictionary["excludeTraits"] as? [String], field: "excludeTrait")
        )
    }

    /// Parse an array of trait name strings into typed `HeistTrait` values.
    /// Throws `FenceError.invalidRequest` with the list of valid names when an
    /// unknown name is encountered. Returns `nil` when `names` is `nil` so
    /// callers can pass a missing field through unchanged.
    private func parseTraitNames(_ names: [String]?, field: String) throws -> [HeistTrait]? {
        try names?.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw FenceError.invalidRequest(
                    "Unknown \(field) '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
                )
            }
            return trait
        }
    }

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    // MARK: - Last Action / Latency Tracking

    var lastActionResult: ActionResult?
    /// Round-trip time in milliseconds for the last action command that
    /// completed (request issued → response received).
    public private(set) var lastLatencyMs: Int = 0

    // Batch execution (`handleRunBatch`, `BatchPolicy`, step-summary building,
    // and `currentSessionState`) lives in TheFence+Batch.swift.

    // MARK: - Config Target Conversion

    static func configTargetsAsDevices(_ config: ButtonHeistFileConfig) -> [DiscoveredDevice] {
        config.targets.compactMap { name, target in
            guard let device = DiscoveredDevice.fromHostPort(
                target.device,
                id: "config-\(name)",
                name: name,
                certFingerprint: target.certFingerprint
            ) else { return nil }
            return device
        }
    }

    // MARK: - Async Wait Methods

    func waitForActionResult(requestId: String, timeout: TimeInterval) async throws -> ActionResult {
        try await actionTracker.wait(requestId: requestId, timeout: timeout)
    }

    func waitForInterface(requestId: String, timeout: TimeInterval = 10.0) async throws -> Interface {
        try await interfaceTracker.wait(requestId: requestId, timeout: timeout)
    }

    func waitForScreen(requestId: String, timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await screenTracker.wait(requestId: requestId, timeout: timeout)
    }

    // Recording responses do not carry request IDs, so synthesize a single key
    // while a stop_recording wait is in flight. Keeping the tracker on TheFence
    // lets disconnect handling fail the wait immediately instead of timing out.
    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await waitForRecording(timeout: timeout, afterRegister: nil)
    }

    func stopRecordingAndWait(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        return try await waitForRecording(timeout: timeout) {
            self.handoff.send(.stopRecording, requestId: UUID().uuidString)
        }
    }

    private func waitForRecording(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws -> RecordingPayload {
        guard !recordingWaitInFlight else {
            throw FenceError.invalidRequest("stop_recording already waiting for completion")
        }
        recordingWaitInFlight = true
        let previousOnRecording = handoff.onRecording
        let previousOnRecordingError = handoff.onRecordingError
        defer {
            recordingWaitInFlight = false
            handoff.onRecording = previousOnRecording
            handoff.onRecordingError = previousOnRecordingError
        }

        let syntheticId = "recording"
        handoff.onRecording = { [weak self] payload in
            self?.recordingTracker.resolve(requestId: syntheticId, result: .success(payload))
        }
        handoff.onRecordingError = { [weak self] message in
            self?.recordingTracker.resolve(requestId: syntheticId, result: .failure(FenceError.actionFailed("Recording failed: \(message)")))
        }
        return try await recordingTracker.wait(requestId: syntheticId, timeout: timeout, afterRegister: afterRegister)
    }

    private func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        actionTracker.cancelAll(error: error)
        interfaceTracker.cancelAll(error: error)
        screenTracker.cancelAll(error: error)
        recordingTracker.cancelAll(error: error)
    }

}
