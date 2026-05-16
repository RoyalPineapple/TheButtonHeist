import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "bookkeeper")

/// Stable client-side phase for connection and request failures.
///
/// This is not part of the wire protocol. It classifies existing local errors
/// so CLI/MCP surfaces and tests can reason about failures without parsing
/// human messages.
public enum FailurePhase: String, Sendable, Equatable, CaseIterable {
    case discovery
    case setup
    case transport
    case authentication = "auth"
    case session
    case request
    case recording
    case protocolNegotiation = "protocol"
    case tls
    case client
    case server
}

/// Typed connection-attempt failure preserved from the lower-level disconnect cause.
public struct ConnectionFailure: Equatable, Sendable {
    public let message: String
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let hint: String?

    public init(
        message: String,
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.message = message
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }
}

extension ConnectionFailure {
    init(disconnectReason reason: DisconnectReason) {
        self.init(
            message: reason.connectionFailureMessage,
            errorCode: reason.failureCode,
            phase: reason.phase,
            retryable: reason.retryable,
            hint: reason.hint
        )
    }
}

/// Errors thrown by TheFence during command dispatch, connection, and action execution.
public enum FenceError: Error, LocalizedError {
    case invalidRequest(String)
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)
    case connectionFailure(ConnectionFailure)
    case sessionLocked(String)
    case authFailed(String)
    case notConnected
    case actionTimeout
    case actionFailed(String)
    case serverError(ServerError)

    private static let actionTimeoutRecoveryHint =
        "The app may be busy on its main thread, processing a long-running UI update, " +
        "or sending a large response. The connection is preserved; retry the command on the same session."

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
        case .connectionFailure(let failure):
            return failure.message
        case .sessionLocked(let message):
            return """
                Session locked: \(message)
                  Another driver is currently connected. Wait for it to disconnect
                  or for the session to time out.
                  If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID
                  or restart the app to release it.
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
                  \(Self.actionTimeoutRecoveryHint)
                """
        case .actionFailed(let message):
            return "Action failed: \(message)"
        case .serverError(let serverError):
            return "Action failed: \(serverError.message)"
        }
    }

    public var errorCode: String {
        switch self {
        case .invalidRequest:
            return "request.invalid"
        case .noDeviceFound:
            return "discovery.no_device_found"
        case .noMatchingDevice:
            return "discovery.no_matching_device"
        case .connectionTimeout:
            return "setup.timeout"
        case .connectionFailed:
            return "connection.failed"
        case .connectionFailure(let failure):
            return failure.errorCode
        case .sessionLocked:
            return "session.locked"
        case .authFailed:
            return "auth.failed"
        case .notConnected:
            return "connection.not_connected"
        case .actionTimeout:
            return "request.timeout"
        case .actionFailed:
            return "request.action_failed"
        case .serverError(let serverError):
            return serverError.errorCode
        }
    }

    public var phase: FailurePhase {
        switch self {
        case .invalidRequest, .notConnected, .actionTimeout, .actionFailed:
            return .request
        case .noDeviceFound, .noMatchingDevice:
            return .discovery
        case .connectionTimeout:
            return .setup
        case .connectionFailed:
            return .transport
        case .connectionFailure(let failure):
            return failure.phase
        case .sessionLocked:
            return .session
        case .authFailed:
            return .authentication
        case .serverError(let serverError):
            return serverError.phase
        }
    }

    public var retryable: Bool {
        switch self {
        case .noDeviceFound, .connectionTimeout, .connectionFailed, .sessionLocked,
             .notConnected, .actionTimeout:
            return true
        case .connectionFailure(let failure):
            return failure.retryable
        case .invalidRequest, .noMatchingDevice, .authFailed, .actionFailed:
            return false
        case .serverError(let serverError):
            return serverError.retryable
        }
    }

    public var hint: String? {
        switch self {
        case .invalidRequest:
            return "Fix the request shape or arguments before retrying."
        case .noDeviceFound:
            return "Start the app and confirm it advertises a Button Heist session."
        case .noMatchingDevice:
            return "Check the device filter or target name against 'buttonheist list'."
        case .connectionTimeout:
            return "Is the app running? Check 'buttonheist list' to see available devices."
        case .connectionFailed:
            return "Is the app running? Check 'buttonheist list' to see available devices."
        case .connectionFailure(let failure):
            return failure.hint
        case .sessionLocked:
            return "Wait for the current driver to disconnect or for the session to time out. " +
                "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        case .authFailed:
            return "Retry without --token to request a fresh session."
        case .notConnected:
            return "Check that the app is running, then retry the command. Use 'buttonheist list' to see available devices."
        case .actionTimeout:
            return Self.actionTimeoutRecoveryHint
        case .actionFailed:
            return nil
        case .serverError(let serverError):
            return serverError.hint
        }
    }
}

public extension ServerError {
    var errorCode: String {
        kind.errorCode
    }

    var phase: FailurePhase {
        kind.phase
    }

    var retryable: Bool {
        kind.retryable
    }

    var hint: String? {
        kind.hint
    }
}

private extension ErrorKind {
    var errorCode: String {
        switch self {
        case .elementNotFound:
            return "request.element_not_found"
        case .timeout:
            return "request.timeout"
        case .unsupported:
            return "request.unsupported"
        case .inputError:
            return "request.input_error"
        case .validationError:
            return "request.validation_error"
        case .actionFailed:
            return "request.action_failed"
        case .authFailure:
            return "auth.failed"
        case .recording:
            return "recording.failed"
        case .general:
            return "server.general"
        }
    }

    var phase: FailurePhase {
        switch self {
        case .elementNotFound, .timeout, .unsupported, .inputError,
             .validationError, .actionFailed:
            return .request
        case .authFailure:
            return .authentication
        case .recording:
            return .recording
        case .general:
            return .server
        }
    }

    var retryable: Bool {
        switch self {
        case .timeout:
            return true
        case .elementNotFound, .unsupported, .inputError, .validationError,
             .actionFailed, .authFailure, .recording, .general:
            return false
        }
    }

    var hint: String? {
        switch self {
        case .elementNotFound:
            return "Refresh the interface and verify the target's accessibility properties."
        case .timeout:
            return "The request timed out; retry on the same session if the app is responsive."
        case .unsupported:
            return "Use a supported command or target for this element."
        case .inputError:
            return "Fix the request input before retrying."
        case .validationError:
            return "Fix the request so it satisfies the server-side validation rules."
        case .actionFailed:
            return nil
        case .authFailure:
            return "Retry without a token to request a fresh session."
        case .recording:
            return "Stop any in-progress recording and retry after resolving the recording error."
        case .general:
            return nil
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
        case .disconnected(let reason): self = .connectionFailure(ConnectionFailure(disconnectReason: reason))
        case .authFailed(let reason): self = .authFailed(reason)
        case .sessionLocked(let message): self = .sessionLocked(message)
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        }
    }
}

/// Named timeout constants for TheFence operations.
enum Timeouts {
    /// Standard action timeout (15 seconds)
    static let actionSeconds: TimeInterval = 15
    /// Long action timeout (30 seconds)
    static let longActionSeconds: TimeInterval = 30
    /// Explore timeout (60 seconds) — scrolls entire screen, needs headroom
    static let exploreSeconds: TimeInterval = 60
}

/// Centralized command dispatch layer. Both the CLI and MCP server are thin wrappers over TheFence.
@ButtonHeistActor
public final class TheFence {
    /// Connection and session configuration for TheFence.
    public struct Configuration {
        /// Substring filter for Bonjour device names. `nil` matches any device.
        var deviceFilter: String?
        /// Seconds to wait for initial connection before failing `start()`.
        var connectionTimeout: TimeInterval
        /// Auth token sent with `client_hello`. Agents use the task slug; omit to
        /// fall back to the `BUTTONHEIST_TOKEN` environment variable.
        var token: String?
        /// When true, TheHandoff re-establishes the connection on drop.
        var autoReconnect: Bool
        /// Resolved `.buttonheist.json` config (device filter, token, output paths).
        /// Supplied by the CLI/MCP entry points from discovered config files.
        var fileConfig: ButtonHeistFileConfig?
        /// Direct host:port target with optional TLS fingerprint from config.
        var directDevice: DiscoveredDevice?
        /// Extra client-side headroom beyond a server-owned wait timeout.
        var postActionExpectationTimeoutBuffer: TimeInterval

        init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil,
            directDevice: DiscoveredDevice? = nil,
            postActionExpectationTimeoutBuffer: TimeInterval = 5
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
            self.directDevice = directDevice
            self.postActionExpectationTimeoutBuffer = postActionExpectationTimeoutBuffer
        }
    }

    static let supportedCommands: [String] = Command.allCases.map(\.rawValue)

    /// Fires on informational status strings (e.g. `BUTTONHEIST_TOKEN=<value>`
    /// on server-generated token, connection events).
    public var onStatus: (@ButtonHeistActor (String) -> Void)? {
        didSet { handoff.onStatus = onStatus }
    }

    /// Fires when the server approves authentication. The parameter is the
    /// approved token, or `nil` when the server accepted a previously-held
    /// session.
    public var onAuthApproved: (@ButtonHeistActor (String?) -> Void)?

    var config: Configuration
    let handoff = TheHandoff()
    let bookKeeper = TheBookKeeper()
    /// Heist playback re-entrancy state. `.playing` carries the wall-clock
    /// timestamp playback started so callers can reason about how long the
    /// current playback has been running.
    enum PlaybackPhase {
        case idle
        case playing(startedAt: Date)
    }
    var playbackPhase: PlaybackPhase = .idle

    /// Durable post-action snapshot of the most recently observed interface,
    /// keyed by heistId. This is the only mirror of post-action interface
    /// state on the client — the request trackers above are scoped to
    /// in-flight requests and don't retain the last delivered value. The
    /// cache feeds heist-evidence recording (so the activated element from
    /// the old screen survives a screen change) and `elementDisappeared`
    /// expectation validation (which resolves removed heistIds against it).
    private var lastInterfaceCache: [String: HeistElement] = [:]

    // MARK: - Pending Request Tracking

    private let actionTracker = PendingRequestTracker<ActionResult>()
    private let interfaceTracker = PendingRequestTracker<Interface>()
    private let screenTracker = PendingRequestTracker<ScreenPayload>()
    private let recordingStartTracker = PendingRequestTracker<Bool>()
    private let recordingTracker = PendingRequestTracker<RecordingPayload>()

    /// State of the in-flight `start_recording` acknowledgement wait, if any.
    enum RecordingStartWait {
        case idle
        case waiting(syntheticId: String)
    }
    private var recordingStartWait: RecordingStartWait = .idle

    /// State of the in-flight `stop_recording` wait, if any. `.waiting`
    /// carries the synthetic request ID used to key the recording tracker.
    enum RecordingWait {
        case idle
        case waiting(syntheticId: String)
    }
    private var recordingWait: RecordingWait = .idle

    public init(configuration: Configuration) {
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

        handoff.onRecordingStarted = { [weak self] in
            self?.resolveRecordingStart(.success(true))
        }

        handoff.onRecordingError = { [weak self] message in
            self?.resolveRecordingStart(.failure(FenceError.actionFailed("Recording failed: \(message)")))
        }

        handoff.onRequestError = { [weak self] serverError, requestId in
            guard let self else { return }
            let error = FenceError.serverError(serverError)
            self.actionTracker.resolve(requestId: requestId, result: .failure(error))
            self.interfaceTracker.resolve(requestId: requestId, result: .failure(error))
            self.screenTracker.resolve(requestId: requestId, result: .failure(error))
        }

        handoff.onBackgroundDelta = { [weak self] delta in
            self?.enqueueBackgroundDelta(delta)
        }

        handoff.onDisconnected = { [weak self] reason in
            self?.backgroundDeltas.removeAll()
            self?.cancelAllPendingRequests(
                error: FenceError.connectionFailure(ConnectionFailure(disconnectReason: reason))
            )
        }
    }

    /// Bounded FIFO of background deltas received from the server.
    ///
    /// Expectation checks peek through this queue and acknowledge only the
    /// delta that actually matches. This prevents a mismatched expectation from
    /// destroying the only evidence of a background change.
    private var backgroundDeltas: [InterfaceDelta] = []
    private static let maxBackgroundDeltas = 20

    private func enqueueBackgroundDelta(_ delta: InterfaceDelta) {
        backgroundDeltas.append(delta)
        if backgroundDeltas.count > Self.maxBackgroundDeltas {
            backgroundDeltas.removeFirst(backgroundDeltas.count - Self.maxBackgroundDeltas)
        }
    }

    /// Return and clear the oldest queued background delta, if any.
    public func drainBackgroundDelta() -> InterfaceDelta? {
        guard !backgroundDeltas.isEmpty else { return nil }
        return backgroundDeltas.removeFirst()
    }

    /// Return and clear all queued background deltas in arrival order.
    public func drainBackgroundDeltas() -> [InterfaceDelta] {
        let deltas = backgroundDeltas
        backgroundDeltas.removeAll()
        return deltas
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
        backgroundDeltas.removeAll()
        cancelAllPendingRequests()
        handoff.disconnect()
        handoff.stopDiscovery()
    }

    /// Execute a command from a dictionary request. Auto-connects if not
    /// already connected.
    ///
    /// Reads as a pipeline: parse → optional wait-only background match
    /// → dispatch → record post-dispatch effects → validate/wait against the
    /// caller's expectation. Each step is its own private method.
    public func execute(request: [String: Any]) async throws -> FenceResponse {
        let parsed: ParsedRequest
        do {
            parsed = try parseRequest(request)
        } catch let error as SchemaValidationError {
            return .error(error.message)
        }
        if let immediate = parsed.immediateResponse { return immediate }

        if parsed.command == .waitForChange,
           let backgroundResponse = responseIfBackgroundExpectationMet(
            parsed.expectation, requestId: parsed.requestId
           ) {
            return backgroundResponse
        }

        let preDispatchBackgroundCount = backgroundDeltas.count
        let dispatched = try await dispatchCommand(parsed)
        lastLatencyMs = dispatched.durationMs
        logResponse(requestId: parsed.requestId, response: dispatched.response, durationMs: dispatched.durationMs)

        let postRecord = recordPostDispatchEffects(
            parsed: parsed,
            response: dispatched.response
        )
        return try await validateActionResponse(
            dispatched.response,
            command: parsed.command,
            expectation: parsed.expectation,
            expectationTimeout: parsed.expectationTimeout,
            preActionCache: postRecord.preActionCache,
            postDispatchBackgroundStartIndex: preDispatchBackgroundCount
        )
    }

    // MARK: - Execute Pipeline

    private struct ParsedRequest {
        let command: Command
        let requestId: String
        let originalRequest: [String: Any]
        let dispatchArgs: [String: Any]
        let expectation: ActionExpectation?
        let expectationTimeout: Double?
        /// Non-nil when the command short-circuits before dispatch (help/quit/exit).
        let immediateResponse: FenceResponse?
    }

    private struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    private struct PostRecordOutcome {
        let preActionCache: [String: HeistElement]
    }

    /// Parse and validate a raw request dictionary into typed fields.
    /// Returns an ImmediateResponse-bearing `ParsedRequest` for help/quit/exit
    /// so the caller short-circuits without logging or dispatching.
    private func parseRequest(_ request: [String: Any]) throws -> ParsedRequest {
        let commandString = try request.requiredSchemaString("command")
        guard let command = Command(rawValue: commandString) else {
            return ParsedRequest(
                command: .help,
                requestId: "",
                originalRequest: request,
                dispatchArgs: request,
                expectation: nil,
                expectationTimeout: nil,
                immediateResponse: .error("Unknown command: \(commandString). Use 'help' for available commands.")
            )
        }
        if let immediate = handleImmediateCommand(command) {
            return ParsedRequest(
                command: command,
                requestId: "",
                originalRequest: request,
                dispatchArgs: request,
                expectation: nil,
                expectationTimeout: nil,
                immediateResponse: immediate
            )
        }
        let requestId = (request["requestId"] as? String) ?? UUID().uuidString
        logCommand(requestId: requestId, command: command, request: request)
        let expectation = try parseExpectation(request)
        let expectationTimeout = expectation == nil ? nil : try request.schemaNumber("timeout")

        var dispatchArgs = request
        dispatchArgs["_requestId"] = requestId

        return ParsedRequest(
            command: command,
            requestId: requestId,
            originalRequest: request,
            dispatchArgs: dispatchArgs,
            expectation: expectation,
            expectationTimeout: expectationTimeout,
            immediateResponse: nil
        )
    }

    /// Ensure the connection is up if the command needs it, then dispatch
    /// the command and capture wall-clock duration.
    private func dispatchCommand(_ parsed: ParsedRequest) async throws -> DispatchResult {
        try await ensureConnectedIfNeeded(for: parsed.command)
        return try await dispatchWithErrorLogging(
            command: parsed.command,
            args: parsed.dispatchArgs,
            requestId: parsed.requestId
        )
    }

    /// Update the interface cache, write heist evidence, and replay any
    /// post-record cache replacement that follows a screen change.
    /// Returns the pre-action cache snapshot for downstream expectation
    /// validation (elementDisappeared resolves removed heistIds against it).
    private func recordPostDispatchEffects(
        parsed: ParsedRequest,
        response: FenceResponse
    ) -> PostRecordOutcome {
        let preActionCache = lastInterfaceCache
        let cacheUpdate = updateInterfaceCache(for: response, preActionCache: preActionCache)
        recordHeistEvidence(
            command: parsed.command,
            request: parsed.originalRequest,
            response: response,
            cacheUpdate: cacheUpdate
        )
        applyPostRecordCacheUpdate(cacheUpdate)
        return PostRecordOutcome(preActionCache: preActionCache)
    }

    private struct ResponseCacheUpdate {
        /// Snapshot of the cache to record heist evidence against. Includes
        /// pre-action elements (so the activated element from the old screen
        /// survives a screen change) merged with any newly-arrived elements.
        let evidenceCache: [String: HeistElement]?
        /// On a screen change, the new screen's elements that should
        /// replace the cache after evidence is recorded. `nil` when the
        /// cache should be left as-is.
        let postRecordReplacement: [HeistElement]?
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
        requestId: String,
        startingAt startIndex: Int = 0
    ) -> FenceResponse? {
        guard let expectation else { return nil }
        let boundedStartIndex = min(max(startIndex, 0), backgroundDeltas.count)

        var matched: (index: Int, result: ActionResult, validation: ExpectationResult)?
        for index in backgroundDeltas.indices.dropFirst(boundedStartIndex) {
            let backgroundDelta = backgroundDeltas[index]
            let syntheticResult = ActionResult(
                success: true,
                method: .waitForChange,
                message: "expectation already met by background change",
                interfaceDelta: backgroundDelta
            )
            let validation = expectation.validate(against: syntheticResult)
            if validation.met {
                matched = (index, syntheticResult, validation)
                break
            }
        }

        guard let matched else { return nil }
        backgroundDeltas.remove(at: matched.index)
        let response = FenceResponse.action(result: matched.result, expectation: matched.validation)
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
        } catch let error as SchemaValidationError {
            return DispatchResult(
                response: .error(error.message),
                durationMs: elapsedMilliseconds(since: start)
            )
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
                evidenceCache: lastInterfaceCache.isEmpty ? nil : lastInterfaceCache,
                postRecordReplacement: nil
            )
        }
        guard let actionResult = response.actionResult,
              case .screenChanged(let payload)? = actionResult.interfaceDelta else {
            return ResponseCacheUpdate(
                evidenceCache: lastInterfaceCache.isEmpty ? nil : lastInterfaceCache,
                postRecordReplacement: nil
            )
        }
        return updateInterfaceCache(for: actionResult, newInterface: payload.newInterface, preActionCache: preActionCache)
    }

    private func updateInterfaceCache(
        for actionResult: ActionResult,
        newInterface: Interface,
        preActionCache: [String: HeistElement]
    ) -> ResponseCacheUpdate {
        // Only reachable when interfaceDelta is .screenChanged (caller's guard).
        // Below assumes newInterface is the screenChange payload.
        lastInterfaceCache.removeAll()
        for element in newInterface.elements {
            lastInterfaceCache[element.heistId] = element
        }
        // Evidence cache is union of pre-action elements + the new screen's
        // elements so the activated element from the old screen survives long
        // enough for the recorder to resolve its heistId to a matcher.
        var evidenceCache = preActionCache
        for element in newInterface.elements {
            evidenceCache[element.heistId] = element
        }
        return ResponseCacheUpdate(
            evidenceCache: evidenceCache.isEmpty ? nil : evidenceCache,
            postRecordReplacement: newInterface.elements
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
            interfaceCache: cacheUpdate.evidenceCache ?? [:]
        )
    }

    private func applyPostRecordCacheUpdate(_ cacheUpdate: ResponseCacheUpdate) {
        guard let elements = cacheUpdate.postRecordReplacement else { return }
        lastInterfaceCache.removeAll()
        for element in elements {
            lastInterfaceCache[element.heistId] = element
        }
    }

    private func validateActionResponse(
        _ response: FenceResponse,
        command: Command,
        expectation: ActionExpectation?,
        expectationTimeout: Double?,
        preActionCache: [String: HeistElement],
        postDispatchBackgroundStartIndex: Int
    ) async throws -> FenceResponse {
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return .action(result: actionResult, expectation: delivery)
            }
            if let expectation {
                // wait_for_change sends the expectation to the iOS server; a
                // successful result means the server observed or already held it.
                if command == .waitForChange {
                    return .action(
                        result: actionResult,
                        expectation: ExpectationResult(
                            met: actionResult.success,
                            expectation: expectation,
                            actual: actionResult.message ?? actionResult.interfaceDelta?.kindRawValue
                        )
                    )
                }
                let validation = expectation.validate(
                    against: actionResult, preActionElements: preActionCache
                )
                if validation.met {
                    return .action(result: actionResult, expectation: validation)
                }
                return try await waitForPostActionExpectation(
                    expectation,
                    initialResult: actionResult,
                    initialValidation: validation,
                    timeout: expectationTimeout,
                    backgroundStartIndex: postDispatchBackgroundStartIndex
                )
            }
        }

        return response
    }

    private func waitForPostActionExpectation(
        _ expectation: ActionExpectation,
        initialResult: ActionResult,
        initialValidation: ExpectationResult,
        timeout: Double?,
        backgroundStartIndex: Int
    ) async throws -> FenceResponse {
        if let backgroundResponse = responseIfBackgroundExpectationMet(
            expectation,
            requestId: UUID().uuidString,
            startingAt: backgroundStartIndex
        ) {
            updateInterfaceCacheForExpectationWait(backgroundResponse)
            return backgroundResponse
        }

        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        do {
            let waitResult = try await sendAndAwaitAction(
                .waitForChange(target),
                timeout: target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
            )
            lastActionHistory = .completed(waitResult)
            let waitValidation: ExpectationResult = if waitResult.method == .waitForChange {
                ExpectationResult(
                    met: waitResult.success,
                    expectation: expectation,
                    actual: waitResult.message ?? waitResult.interfaceDelta?.kindRawValue
                )
            } else {
                expectation.validate(against: waitResult)
            }
            let response = FenceResponse.action(
                result: waitResult,
                expectation: waitValidation
            )
            updateInterfaceCacheForExpectationWait(response)
            return response
        } catch FenceError.actionTimeout {
            return .action(result: initialResult, expectation: initialValidation)
        }
    }

    private func updateInterfaceCacheForExpectationWait(_ response: FenceResponse) {
        let cacheUpdate = updateInterfaceCache(for: response, preActionCache: lastInterfaceCache)
        applyPostRecordCacheUpdate(cacheUpdate)
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
        do {
            try await handoff.waitForConnectionResult(timeout: config.connectionTimeout)
        } catch let error as TheHandoff.ConnectionError {
            throw FenceError(error)
        }
        handoff.onStatus?("Connected to \(device.name)")
    }

    // MARK: - Interface Cache

    private func updateInterfaceCache(_ elements: [HeistElement]) {
        for element in elements {
            lastInterfaceCache[element.heistId] = element
        }
    }

    // MARK: - Response Logging

    private func logResponse(requestId: String, response: FenceResponse, durationMs: Int) {
        let responseStatus: ResponseStatus
        let artifactPath: String?
        let errorMessage: String?
        switch response {
        case .error(let message, _):
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
        case .activate, .increment, .decrement, .performCustomAction, .rotor:
            return try await handleAccessibilityAction(command: command, args: args)
        case .typeText:
            return try await handleTypeText(args)
        case .editAction:
            return try await handleEditAction(args)
        case .setPasteboard:
            return try await handleSetPasteboard(args)
        case .getPasteboard:
            return try await handleGetPasteboard()
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
        lastActionHistory = .completed(result)
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
        } catch let error as CancellationError {
            throw error
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
            heistId: try dictionary.schemaString("heistId"),
            matcher: try elementMatcher(dictionary),
            ordinal: try dictionary.schemaInteger("ordinal")
        )
    }

    func elementMatcher(_ dictionary: [String: Any]) throws -> ElementMatcher {
        return ElementMatcher(
            label: try dictionary.schemaString("label"),
            identifier: try dictionary.schemaString("identifier"),
            value: try dictionary.schemaString("value"),
            traits: try parseTraitNames(try dictionary.schemaStringArray("traits"), field: "traits"),
            excludeTraits: try parseTraitNames(try dictionary.schemaStringArray("excludeTraits"), field: "excludeTraits")
        )
    }

    /// Parse an array of trait name strings into typed `HeistTrait` values.
    /// Throws `FenceError.invalidRequest` with the list of valid names when an
    /// unknown name is encountered. Returns `nil` when `names` is `nil` so
    /// callers can pass a missing field through unchanged.
    private func parseTraitNames(_ names: [String]?, field: String) throws -> [HeistTrait]? {
        try names?.enumerated().map { index, name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: name as Any,
                    expected: SchemaValidationError.expectedEnum(HeistTrait.self)
                )
            }
            return trait
        }
    }

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    // MARK: - Last Action / Latency Tracking

    /// Two-phase action history: `.unrun` before any action has completed,
    /// `.completed` once one has. Display state derives from the active case;
    /// no caller has to guard a nullable to know whether an action ever ran.
    enum LastActionHistory {
        case unrun
        case completed(ActionResult)
    }

    var lastActionHistory: LastActionHistory = .unrun

    /// Convenience read of the last completed action's result, if any.
    var lastActionResult: ActionResult? {
        if case .completed(let result) = lastActionHistory { return result }
        return nil
    }
    /// Round-trip time in milliseconds for the last action command that
    /// completed (request issued → response received).
    private(set) var lastLatencyMs: Int = 0

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

    func startRecordingAndWait(config: RecordingConfig, timeout: TimeInterval = Timeouts.actionSeconds) async throws {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !handoff.isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }
        guard case .idle = recordingStartWait else {
            throw FenceError.invalidRequest("start_recording already waiting for acknowledgement")
        }

        let syntheticId = "recording-start"
        recordingStartWait = .waiting(syntheticId: syntheticId)
        defer { recordingStartWait = .idle }

        var didSendStart = false
        do {
            _ = try await recordingStartTracker.wait(requestId: syntheticId, timeout: timeout) {
                didSendStart = true
                self.handoff.send(.startRecording(config), requestId: UUID().uuidString)
            }
        } catch {
            if didSendStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    private func resolveRecordingStart(_ result: Result<Bool, Error>) {
        guard case .waiting(let syntheticId) = recordingStartWait else { return }
        recordingStartTracker.resolve(requestId: syntheticId, result: result)
    }

    /// Run a recording from start to completion as a single async unit.
    ///
    /// Sends `start_recording`, waits for the server acknowledgement, then
    /// awaits the resulting `RecordingPayload`. On any error path after the
    /// start request is sent, sends `stop_recording` so the iOS-side recording
    /// is not stranded. Cleanup is best-effort: if it fails, the original error
    /// still propagates.
    public func recordToCompletion(
        config: RecordingConfig,
        timeout: TimeInterval
    ) async throws -> RecordingPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !handoff.isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }

        // Cancellation that arrived before we could send the start request: do
        // nothing to clean up server-side, since nothing was started.
        try Task.checkCancellation()

        var didStart = false
        do {
            try await startRecordingAndWait(config: config, timeout: timeout)
            didStart = true
            return try await waitForRecording(timeout: timeout)
        } catch let error as CancellationError {
            if didStart {
                cleanUpServerRecording()
            }
            throw error
        } catch {
            if didStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    /// Best-effort drain of an in-flight server-side recording. Used as the
    /// cleanup branch of `recordToCompletion` — failures are intentionally
    /// swallowed so the caller's original error still surfaces.
    private func cleanUpServerRecording() {
        guard handoff.isConnected else { return }
        handoff.send(.stopRecording, requestId: UUID().uuidString)
    }

    /// Internal overload exposing `afterRegister` for test injection. The hook
    /// fires synchronously after the recording callback is registered, letting
    /// tests deliver a payload deterministically without sleeping.
    func waitForRecording(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws -> RecordingPayload {
        guard case .idle = recordingWait else {
            throw FenceError.invalidRequest("stop_recording already waiting for completion")
        }
        let syntheticId = "recording"
        recordingWait = .waiting(syntheticId: syntheticId)
        // Recording errors normally resolve the start acknowledgement. Once stop_recording is waiting,
        // temporarily route them to the completion waiter, then restore the start handler.
        let previousOnRecording = handoff.onRecording
        let previousOnRecordingError = handoff.onRecordingError
        defer {
            recordingWait = .idle
            handoff.onRecording = previousOnRecording
            handoff.onRecordingError = previousOnRecordingError
        }

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
        recordingStartTracker.cancelAll(error: error)
        recordingTracker.cancelAll(error: error)
    }

}
