import Foundation
import os.log

import TheScore

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
                  \(Self.authFailureRecoveryHint(for: message))
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
        case .authFailed(let message):
            return Self.authFailureRecoveryHint(for: message)
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

    private static func authFailureRecoveryHint(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("configured token") {
            return "Retry with the configured token."
        }
        return "Retry without --token to request a fresh session."
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
    struct HeistRecordingReceipt {
        let actionResult: ActionResult
        let expectation: ExpectationResult?

        var shouldRecord: Bool {
            actionResult.success && expectation?.met != false
        }
    }

    var heistRecordingReceipt: HeistRecordingReceipt? {
        guard case .action(let result, let expectation) = self else { return nil }
        return HeistRecordingReceipt(actionResult: result, expectation: expectation)
    }
}

extension FenceError {
    init(_ connectionError: TheHandoff.ConnectionError) {
        switch connectionError {
        case .connectionFailed(let message): self = .connectionFailed(message)
        case .disconnected(.authFailed(let reason)): self = .authFailed(reason)
        case .disconnected(.sessionLocked(let message)): self = .sessionLocked(message)
        case .disconnected(let reason): self = .connectionFailure(ConnectionFailure(disconnectReason: reason))
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        }
    }

    init(_ sendFailure: DeviceSendFailure) {
        switch sendFailure {
        case .notConnected:
            self = .notConnected
        case .encodingFailed(let message):
            self = .actionFailed("Failed to send request: \(message)")
        case .transportFailed(let message):
            self = .actionFailed("Transport send failed: \(message)")
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
        /// Test/config override for BookKeeper's session and artifact root.
        var bookKeeperBaseDirectory: URL?
        /// Extra client-side headroom beyond a server-owned wait timeout.
        var postActionExpectationTimeoutBuffer: TimeInterval

        init(
            deviceFilter: String? = nil,
            connectionTimeout: TimeInterval = 30,
            token: String? = nil,
            autoReconnect: Bool = true,
            fileConfig: ButtonHeistFileConfig? = nil,
            directDevice: DiscoveredDevice? = nil,
            bookKeeperBaseDirectory: URL? = nil,
            postActionExpectationTimeoutBuffer: TimeInterval = 5
        ) {
            self.deviceFilter = deviceFilter
            self.connectionTimeout = connectionTimeout
            self.token = token
            self.autoReconnect = autoReconnect
            self.fileConfig = fileConfig
            self.directDevice = directDevice
            self.bookKeeperBaseDirectory = bookKeeperBaseDirectory
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
    let bookKeeper: TheBookKeeper
    var configuredAuthTokenForStatus: String?
    /// Heist playback re-entrancy state. `.playing` carries the wall-clock
    /// timestamp playback started so callers can reason about how long the
    /// current playback has been running.
    enum PlaybackPhase {
        case idle
        case playing(startedAt: Date)
    }
    var playbackPhase: PlaybackPhase = .idle

    /// Fence-owned accessibility capture history. Captures are the retained
    /// source of truth; pending trace and lookup views are derived locally from
    /// retained captures when validation or recording needs them.
    private var accessibilityHistory = AccessibilityTrace.History(retention: .dropAfterDelivery)

    // MARK: - Pending Request Tracking

    private let actionTracker = PendingRequestTracker<ActionResult>()
    private let interfaceTracker = PendingRequestTracker<Interface>()
    private let screenTracker = PendingRequestTracker<ScreenPayload>()
    private let recordingStartTracker = PendingRequestTracker<Bool>()
    private let recordingTracker = PendingRequestTracker<RecordingPayload>()

    /// Fence-owned recording state. Handoff forwards server recording
    /// messages, but request decisions and wait ownership live here.
    enum RecordingLifecycle {
        case idle
        case starting(waitId: String)
        case recording
        case completing(waitId: String, serverRecording: Bool)
    }

    enum RecordingPendingWait {
        case start(String)
        case completion(String)
    }

    struct RecordingState {
        private(set) var lifecycle: RecordingLifecycle = .idle

        var isRecording: Bool {
            switch lifecycle {
            case .recording:
                return true
            case .completing(_, let serverRecording):
                return serverRecording
            case .idle, .starting:
                return false
            }
        }

        var isWaitingForCompletion: Bool {
            completionWaitId != nil
        }

        var startWaitId: String? {
            if case .starting(let waitId) = lifecycle {
                return waitId
            }
            return nil
        }

        var completionWaitId: String? {
            if case .completing(let waitId, _) = lifecycle {
                return waitId
            }
            return nil
        }

        var startRecordingConflictError: FenceError {
            switch lifecycle {
            case .idle:
                return .invalidRequest("Recording state changed while starting")
            case .starting:
                return .invalidRequest("start_recording already waiting for acknowledgement")
            case .recording:
                return .invalidRequest("Recording already in progress — use stop_recording first")
            case .completing:
                return .invalidRequest("stop_recording already waiting for completion")
            }
        }

        mutating func beginStartWait(syntheticId: String) -> Bool {
            guard case .idle = lifecycle else { return false }
            lifecycle = .starting(waitId: syntheticId)
            return true
        }

        mutating func finishStartWait(syntheticId: String) {
            guard case .starting(let waitId) = lifecycle, waitId == syntheticId else { return }
            lifecycle = .idle
        }

        mutating func beginCompletionWait(syntheticId: String) -> Bool {
            switch lifecycle {
            case .idle:
                lifecycle = .completing(waitId: syntheticId, serverRecording: false)
            case .recording:
                lifecycle = .completing(waitId: syntheticId, serverRecording: true)
            case .starting, .completing:
                return false
            }
            return true
        }

        mutating func finishCompletionWait(syntheticId: String) {
            guard case .completing(let waitId, _) = lifecycle, waitId == syntheticId else { return }
            lifecycle = .idle
        }

        mutating func noteStarted() -> String? {
            switch lifecycle {
            case .starting(let waitId):
                lifecycle = .recording
                return waitId
            case .completing(let waitId, _):
                lifecycle = .completing(waitId: waitId, serverRecording: true)
                return nil
            case .idle, .recording:
                lifecycle = .recording
                return nil
            }
        }

        mutating func noteFinished() {
            switch lifecycle {
            case .completing(let waitId, _):
                lifecycle = .completing(waitId: waitId, serverRecording: false)
            case .idle, .starting, .recording:
                lifecycle = .idle
            }
        }

        mutating func noteCompleted() -> String? {
            let waitId = completionWaitId
            lifecycle = .idle
            return waitId
        }

        mutating func noteFailed() -> RecordingPendingWait? {
            let pendingWait: RecordingPendingWait?
            switch lifecycle {
            case .starting(let waitId):
                pendingWait = .start(waitId)
            case .completing(let waitId, _):
                pendingWait = .completion(waitId)
            case .idle, .recording:
                pendingWait = nil
            }
            lifecycle = .idle
            return pendingWait
        }
    }
    private var recordingState = RecordingState()
    var isRecording: Bool {
        recordingState.isRecording
    }
    /// Test-visible state for deterministic recording completion injection.
    var isWaitingForRecordingCompletion: Bool {
        recordingState.isWaitingForCompletion
    }

    public init(configuration: Configuration) {
        self.config = configuration
        self.bookKeeper = TheBookKeeper(baseDirectory: configuration.bookKeeperBaseDirectory)
        let configuredToken = configuration.token ?? EnvironmentKey.buttonheistToken.value
        self.configuredAuthTokenForStatus = configuredToken
        self.handoff.token = configuredToken
        self.handoff.driverId = EnvironmentKey.buttonheistDriverId.value
        self.handoff.onAuthApproved = { [weak self] token in
            self?.handleAuthApproved(token)
        }
        wireUpResponseCallbacks()
    }

    nonisolated static func authApprovedStatusMessage(token: String?, configuredToken: String?) -> String? {
        guard let token, configuredToken == nil else { return nil }
        return "BUTTONHEIST_TOKEN=\(token)"
    }

    private func handleAuthApproved(_ token: String?) {
        if let message = Self.authApprovedStatusMessage(token: token, configuredToken: configuredAuthTokenForStatus) {
            onStatus?(message)
        }
        onAuthApproved?(token)
    }

    private func wireUpResponseCallbacks() {
        handoff.onServerMessage = { [weak self] message, requestId in
            self?.handleServerMessage(message, requestId: requestId)
        }

        handoff.onSendFailure = { [weak self] failure, requestId in
            self?.handleSendFailure(failure, requestId: requestId)
        }

        handoff.onRecordingEvent = { [weak self] event in
            self?.handleRecordingEvent(event)
        }

        handoff.onBackgroundAccessibilityTrace = { [weak self] trace in
            self?.enqueueBackgroundAccessibilityTrace(trace)
        }

        handoff.onConnectionStateChanged = { [weak self] state in
            self?.handleHandoffConnectionStateChanged(state)
        }
    }

    private func handleServerMessage(_ message: ServerMessage, requestId: String?) {
        guard let requestId else { return }
        switch message {
        case .interface(let payload):
            interfaceTracker.resolve(requestId: requestId, result: .success(payload))
        case .actionResult(let result):
            actionTracker.resolve(requestId: requestId, result: .success(result))
        case .screen(let payload):
            screenTracker.resolve(requestId: requestId, result: .success(payload))
        case .error(let serverError):
            let error = FenceError.serverError(serverError)
            actionTracker.resolve(requestId: requestId, result: .failure(error))
            interfaceTracker.resolve(requestId: requestId, result: .failure(error))
            screenTracker.resolve(requestId: requestId, result: .failure(error))
        default:
            break
        }
    }

    private func handleSendFailure(_ failure: DeviceSendFailure, requestId: String?) {
        guard let requestId else { return }
        let error = FenceError(failure)
        actionTracker.resolve(requestId: requestId, result: .failure(error))
        interfaceTracker.resolve(requestId: requestId, result: .failure(error))
        screenTracker.resolve(requestId: requestId, result: .failure(error))
    }

    private func handleHandoffConnectionStateChanged(_ state: TheHandoff.ConnectionPhase) {
        switch state {
        case .failed(let failure):
            clearClientSessionState(error: sessionStateError(for: failure))
        case .disconnected:
            guard let failure = handoff.connectionDiagnosticFailure,
                  case .disconnected = failure
            else { return }
            clearClientSessionState(error: sessionStateError(for: failure))
        case .connecting, .connected:
            break
        }
    }

    private func sessionStateError(for failure: TheHandoff.ConnectionError) -> Error {
        if case .disconnected(let reason) = failure {
            return FenceError.connectionFailure(ConnectionFailure(disconnectReason: reason))
        }
        return FenceError(failure)
    }

    func clearClientSessionState(error: Error) {
        accessibilityHistory.reset()
        accessibilityHistory.retention = .dropAfterDelivery
        commandExecutionState.reset()
        recordingState = RecordingState()
        cancelAllPendingRequests(error: error)
    }

    private func handleRecordingEvent(_ event: RecordingEvent) {
        switch event {
        case .started:
            if let syntheticId = recordingState.noteStarted() {
                recordingStartTracker.resolve(requestId: syntheticId, result: .success(true))
            }
        case .stopped:
            recordingState.noteFinished()
        case .completed(let payload):
            if let syntheticId = recordingState.noteCompleted() {
                recordingTracker.resolve(requestId: syntheticId, result: .success(payload))
            }
        case .failed(let message):
            resolveRecordingError(message, pendingWait: recordingState.noteFailed())
        }
    }

    /// Bounded FIFO of background accessibility trace boundaries received from the server.
    ///
    /// `AccessibilityTrace.History` owns the refs. `TheFence` asks for pending
    /// trace projections when draining or checking expectations.
    private static let maxBackgroundAccessibilityCursors = 20

    private func enqueueBackgroundAccessibilityTrace(_ trace: AccessibilityTrace) {
        accessibilityHistory.enqueuePendingTrace(
            trace,
            limit: Self.maxBackgroundAccessibilityCursors
        )
    }

    /// Return and clear the oldest queued background accessibility trace, if any.
    public func drainBackgroundAccessibilityTrace() -> AccessibilityTrace? {
        accessibilityHistory.drainPendingTrace()
    }

    /// Return and clear all queued background accessibility traces in arrival order.
    public func drainBackgroundAccessibilityTraces() -> [AccessibilityTrace] {
        accessibilityHistory.drainPendingTraces()
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
        clearClientSessionState(
            error: FenceError.connectionFailure(ConnectionFailure(disconnectReason: .localDisconnect))
        )
        handoff.disableAutoReconnect()
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
        } catch let error as MissingElementTarget {
            return missingElementTargetResponse(command: error.command)
        } catch let error as FenceError {
            return .error(error.coreMessage, details: error.failureDetails)
        }
        return try await execute(parsed: parsed)
    }

    func execute(playback operation: PlaybackOperation) async throws -> FenceResponse {
        let request = operation.dispatchBridgeArguments()
        let parsed: ParsedRequest
        do {
            parsed = try parsePlaybackOperation(operation, bridgeArguments: request)
        } catch let error as SchemaValidationError {
            return .error(error.message)
        }
        return try await execute(parsed: parsed)
    }

    func execute(parsed: ParsedRequest) async throws -> FenceResponse {
        if let immediate = parsed.immediateResponse { return immediate }

        logCommand(parsed)

        if parsed.command == .waitForChange,
           let backgroundResponse = responseIfBackgroundExpectationMet(
            parsed.expectationPayload.expectation, requestId: parsed.requestId
           ) {
            finishAccessibilityDelivery(backgroundResponse.deliveredCaptureRef)
            return backgroundResponse.response
        }

        let preDispatchBackgroundCount = accessibilityHistory.pendingTraceCount
        let preDispatchCaptureRef = accessibilityHistory.latestRef
        let dispatched = try await dispatchCommand(parsed)
        commandExecutionState.noteDispatchedResponse(dispatched.response, latencyMs: dispatched.durationMs)
        logResponse(requestId: parsed.requestId, response: dispatched.response, durationMs: dispatched.durationMs)

        let postDispatch = capturePostDispatchEffects(
            parsed: parsed,
            response: dispatched.response,
            preDispatchCaptureRef: preDispatchCaptureRef
        )
        let validatedResponse = try await validateActionResponse(
            dispatched.response,
            command: parsed.command,
            expectation: parsed.expectationPayload.expectation,
            expectationTimeout: parsed.expectationPayload.postActionValidationTimeout,
            preActionCaptureRef: postDispatch.preActionCaptureRef,
            postDispatchBackgroundStartIndex: preDispatchBackgroundCount
        )
        recordHeistEvidence(
            parsed,
            dispatchedResponse: dispatched.response,
            validatedResponse: validatedResponse.response,
            lookupCaptureRef: postDispatch.recordingLookupCaptureRef
        )
        finishAccessibilityDelivery(validatedResponse.deliveredCaptureRef ?? postDispatch.deliveredCaptureRef)
        return validatedResponse.response
    }

    // MARK: - Execute Pipeline

    private struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    private struct PostDispatchOutcome {
        let preActionCaptureRef: AccessibilityTrace.CaptureRef?
        let recordingLookupCaptureRef: AccessibilityTrace.CaptureRef?
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    private struct ValidatedResponse {
        let response: FenceResponse
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    private struct BackgroundExpectationResponse {
        let response: FenceResponse
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    /// Parse and validate a raw request dictionary into typed fields.
    /// Returns an ImmediateResponse-bearing `ParsedRequest` for help/quit/exit
    /// so the caller short-circuits without logging or dispatching.
    func parseRequest(_ request: [String: Any]) throws -> ParsedRequest {
        let commandString = try request.requiredSchemaString("command")
        guard let command = Command(rawValue: commandString) else {
            return ParsedRequest(
                command: .help,
                requestId: "",
                originalRequest: request,
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: .error("Unknown command: \(commandString). Use 'help' for available commands.")
            )
        }
        return try parseRequest(command: command, request: request)
    }

    func parseRequest(command: Command, request: [String: Any]) throws -> ParsedRequest {
        try validateRequestKeys(command: command, request: request)
        if let immediate = handleImmediateCommand(command) {
            return ParsedRequest(
                command: command,
                requestId: "",
                originalRequest: request,
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: immediate
            )
        }
        let requestId = (request["requestId"] as? String) ?? UUID().uuidString
        let expectationPayload = try parseExpectationPayload(request)
        let payload: RequestPayload = if command == .waitForChange {
            .waitForChange(expectationPayload)
        } else {
            try decodeRequestPayload(command: command, request: request, requestId: requestId)
        }

        return ParsedRequest(
            command: command,
            requestId: requestId,
            originalRequest: request,
            payload: payload,
            expectationPayload: expectationPayload,
            immediateResponse: nil
        )
    }

    private func validateRequestKeys(command: Command, request: [String: Any]) throws {
        let metadataKeys = Set(["command", "requestId"])
        let parameterKeys = Set(command.parameters.map(\.key))
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = request.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: request[unexpectedKey],
            expected: "valid \(command.rawValue) parameter"
        )
    }

    private func parsePlaybackOperation(
        _ operation: PlaybackOperation,
        bridgeArguments request: [String: Any]
    ) throws -> ParsedRequest {
        try parseRequest(command: operation.command, request: request)
    }

    /// Ensure the connection is up if the command needs it, then dispatch
    /// the command and capture wall-clock duration.
    private func dispatchCommand(_ parsed: ParsedRequest) async throws -> DispatchResult {
        try await ensureConnectedIfNeeded(for: parsed.command)
        return try await dispatchWithErrorLogging(
            parsed,
            requestId: parsed.requestId
        )
    }

    /// Ingest capture evidence from the just-dispatched response. The returned
    /// refs let later steps derive request-local element lookups from a concrete
    /// capture without retaining a semantic element map on TheFence.
    private func capturePostDispatchEffects(
        parsed: ParsedRequest,
        response: FenceResponse,
        preDispatchCaptureRef: AccessibilityTrace.CaptureRef?
    ) -> PostDispatchOutcome {
        if let fullInterface = fullInterfaceCapture(from: response, parsed: parsed) {
            let captureRef = accessibilityHistory.append(interface: fullInterface)
            return PostDispatchOutcome(
                preActionCaptureRef: nil,
                recordingLookupCaptureRef: nil,
                deliveredCaptureRef: captureRef
            )
        }

        guard let actionResult = response.actionResult else {
            return PostDispatchOutcome(
                preActionCaptureRef: nil,
                recordingLookupCaptureRef: nil,
                deliveredCaptureRef: nil
            )
        }

        let cursor = ingestActionTrace(actionResult)
        let beforeRef = cursor?.first ?? preDispatchCaptureRef
        return PostDispatchOutcome(
            preActionCaptureRef: beforeRef,
            recordingLookupCaptureRef: beforeRef,
            deliveredCaptureRef: cursor?.last
        )
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

    private func logCommand(_ request: ParsedRequest) {
        do {
            try bookKeeper.logCommand(request)
        } catch {
            logger.warning(
                """
                Failed to log command \(request.command.rawValue, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    private func responseIfBackgroundExpectationMet(
        _ expectation: ActionExpectation?,
        requestId: String,
        startingAt startIndex: Int = 0
    ) -> BackgroundExpectationResponse? {
        guard let expectation else { return nil }

        var matched: (pendingTrace: AccessibilityTrace.PendingTrace, result: ActionResult, validation: ExpectationResult)?
        for pendingTrace in accessibilityHistory.pendingTraces(startingAt: startIndex) {
            let trace = pendingTrace.trace
            guard trace.backgroundDelta != nil else { continue }
            let syntheticResult = ActionResult(
                success: true,
                method: .waitForChange,
                message: "expectation already met by background change",
                accessibilityTrace: trace
            )
            let validation = expectation.validate(
                against: syntheticResult,
                preActionElements: accessibilityHistory.elementLookup(captureRef: pendingTrace.firstRef)
            )
            if validation.met {
                matched = (pendingTrace, syntheticResult, validation)
                break
            }
        }

        guard let matched else { return nil }
        guard let pendingTrace = accessibilityHistory.removePendingTrace(at: matched.pendingTrace.index) else {
            return nil
        }
        let response = FenceResponse.action(result: matched.result, expectation: matched.validation)
        logResponse(requestId: requestId, response: response, durationMs: 0)
        return BackgroundExpectationResponse(response: response, deliveredCaptureRef: pendingTrace.lastRef)
    }

    private func ensureConnectedIfNeeded(for command: Command) async throws {
        guard !handoff.isConnected, command.requiresConnectionBeforeDispatch else { return }
        try await start()
    }

    private func dispatchWithErrorLogging(
        _ parsed: ParsedRequest,
        requestId: String
    ) async throws -> DispatchResult {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await dispatch(parsed)
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

    private func recordHeistEvidence(
        _ request: ParsedRequest,
        dispatchedResponse: FenceResponse,
        validatedResponse: FenceResponse,
        lookupCaptureRef: AccessibilityTrace.CaptureRef?
    ) {
        guard case .idle = playbackPhase else { return }
        guard let finalReceipt = validatedResponse.heistRecordingReceipt, finalReceipt.shouldRecord else { return }
        let targetCapture = dispatchedResponse.actionResult?.accessibilityTrace?.captures.first
            ?? lookupCaptureRef.flatMap { accessibilityHistory.capture(ref: $0) }
            ?? finalReceipt.actionResult.accessibilityTrace?.captures.first
        bookKeeper.recordHeistEvidence(
            request,
            actionResult: finalReceipt.actionResult,
            expectation: finalReceipt.expectation,
            targetCapture: targetCapture
        )
    }

    private func validateActionResponse(
        _ response: FenceResponse,
        command: Command,
        expectation: ActionExpectation?,
        expectationTimeout: Double?,
        preActionCaptureRef: AccessibilityTrace.CaptureRef?,
        postDispatchBackgroundStartIndex: Int
    ) async throws -> ValidatedResponse {
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return ValidatedResponse(
                    response: .action(result: actionResult, expectation: delivery),
                    deliveredCaptureRef: nil
                )
            }
            if let expectation {
                // wait_for_change sends the expectation to the iOS server; a
                // successful result means the server observed or already held it.
                if command == .waitForChange {
                    return ValidatedResponse(
                        response: .action(
                            result: actionResult,
                            expectation: ExpectationResult(
                                met: actionResult.success,
                                expectation: expectation,
                                actual: actionResult.message ?? actionResult.accessibilityDelta?.kindRawValue
                            )
                        ),
                        deliveredCaptureRef: nil
                    )
                }
                let preActionElements = accessibilityHistory.elementLookup(captureRef: preActionCaptureRef)
                let validation = expectation.validate(
                    against: actionResult, preActionElements: preActionElements
                )
                if validation.met {
                    return ValidatedResponse(
                        response: .action(result: actionResult, expectation: validation),
                        deliveredCaptureRef: nil
                    )
                }
                return try await waitForPostActionExpectation(
                    expectation,
                    initialResult: actionResult,
                    initialValidation: validation,
                    preActionElements: preActionElements,
                    timeout: expectationTimeout,
                    backgroundStartIndex: postDispatchBackgroundStartIndex
                )
            }
        }

        return ValidatedResponse(response: response, deliveredCaptureRef: nil)
    }

    private func waitForPostActionExpectation(
        _ expectation: ActionExpectation,
        initialResult: ActionResult,
        initialValidation: ExpectationResult,
        preActionElements: [HeistId: HeistElement],
        timeout: Double?,
        backgroundStartIndex: Int
    ) async throws -> ValidatedResponse {
        if let backgroundResponse = responseIfBackgroundExpectationMet(
            expectation,
            requestId: UUID().uuidString,
            startingAt: backgroundStartIndex
        ) {
            return ValidatedResponse(
                response: backgroundResponse.response,
                deliveredCaptureRef: backgroundResponse.deliveredCaptureRef
            )
        }

        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        do {
            let waitResult = try await sendAndAwaitAction(
                .waitForChange(target),
                timeout: target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
            )
            recordCompletedAction(waitResult)
            let waitCursor = ingestActionTrace(waitResult)
            let waitValidation: ExpectationResult = if waitResult.method == .waitForChange {
                ExpectationResult(
                    met: waitResult.success,
                    expectation: expectation,
                    actual: waitResult.message ?? waitResult.accessibilityDelta?.kindRawValue
                )
            } else {
                expectation.validate(against: waitResult, preActionElements: preActionElements)
            }
            return ValidatedResponse(
                response: .action(
                    result: waitResult,
                    expectation: waitValidation
                ),
                deliveredCaptureRef: waitCursor?.last
            )
        } catch FenceError.actionTimeout {
            return ValidatedResponse(
                response: .action(result: initialResult, expectation: initialValidation),
                deliveredCaptureRef: nil
            )
        }
    }

    private func fullInterfaceCapture(from response: FenceResponse, parsed: ParsedRequest) -> Interface? {
        guard case .getInterface = parsed.payload,
              case .interface(let iface, _) = response else {
            return nil
        }
        return iface
    }

    private func ingestActionTrace(_ actionResult: ActionResult) -> AccessibilityTrace.Cursor? {
        guard let trace = actionResult.accessibilityTrace else { return nil }
        return accessibilityHistory.ingest(trace)
    }

    private func finishAccessibilityDelivery(_ captureRef: AccessibilityTrace.CaptureRef?) {
        accessibilityHistory.markDelivered(through: captureRef)
    }

    func beginRecordingAccessibilityHistoryRetention() {
        accessibilityHistory.retention = .persistForSession
    }

    func endRecordingAccessibilityHistoryRetention() {
        accessibilityHistory.retention = .dropAfterDelivery
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
        let resolutionTimeout = TheHandoff.connectionResolutionTimeout(for: config.connectionTimeout)
        switch await device.reachability(timeout: resolutionTimeout) {
        case .reachable:
            break
        case .failed(let reason):
            throw FenceError(TheHandoff.ConnectionError.disconnected(reason))
        case .unavailable:
            throw FenceError.connectionFailure(ConnectionFailure(
                message: "Could not reach ButtonHeist server at \(device.name)",
                errorCode: "connection.endpoint_unreachable",
                phase: .transport,
                retryable: true,
                hint: "Check that the app is running at \(device.name), then retry the command."
            ))
        }

        let attemptID = handoff.connect(to: device)
        do {
            try await handoff.waitForConnectionResult(timeout: config.connectionTimeout)
        } catch let error as TheHandoff.ConnectionError where error == .timeout {
            handoff.disconnectConnectionAttempt(attemptID, failure: .timeout)
            throw FenceError(error)
        } catch let error as TheHandoff.ConnectionError {
            throw FenceError(error)
        }
        handoff.onStatus?("Connected to \(device.name)")
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
        case .recordingExpanded(let path, _, _):
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

    private func dispatch(_ parsed: ParsedRequest) async throws -> FenceResponse {
        switch (parsed.command, parsed.payload) {
        case (.status, _):
            return .status(
                connected: handoff.isConnected,
                deviceName: handoff.connectedDevice.map { handoff.displayName(for: $0) }
            )
        case (.listDevices, _):
            return try await handleListDevices()
        case (.getInterface, .getInterface(let request)):
            return try await handleGetInterface(request)
        case (.getScreen, .screen(let request)):
            return try await handleGetScreen(request)
        case (.waitForChange, .waitForChange(let payload)):
            return try await handleWaitForChange(payload)
        case (.oneFingerTap, .gesture(let payload)),
             (.longPress, .gesture(let payload)),
             (.swipe, .gesture(let payload)),
             (.drag, .gesture(let payload)),
             (.pinch, .gesture(let payload)),
             (.rotate, .gesture(let payload)),
             (.twoFingerTap, .gesture(let payload)),
             (.drawPath, .gesture(let payload)),
             (.drawBezier, .gesture(let payload)):
            return try await handleGesture(payload)
        case (.scroll, .scroll(let payload)),
             (.scrollToVisible, .scroll(let payload)),
             (.elementSearch, .scroll(let payload)),
             (.scrollToEdge, .scroll(let payload)):
            return try await handleScrollAction(payload)
        case (.waitFor, .waitFor(let target)):
            return try await handleWaitFor(target)
        case (.activate, .accessibility(let payload)),
             (.increment, .accessibility(let payload)),
             (.decrement, .accessibility(let payload)),
             (.performCustomAction, .accessibility(let payload)):
            return try await handleAccessibilityAction(payload)
        case (.rotor, .rotor(let target)):
            return try await handleRotor(target)
        case (.typeText, .typeText(let target)):
            return try await handleTypeText(target)
        case (.editAction, .editAction(let target)):
            return try await handleEditAction(target)
        case (.setPasteboard, .setPasteboard(let target)):
            return try await handleSetPasteboard(target)
        case (.getPasteboard, _):
            return try await handleGetPasteboard()
        case (.dismissKeyboard, _):
            return try await sendAction(.resignFirstResponder)
        case (.startRecording, .startRecording(let config)):
            return try await handleStartRecording(config)
        case (.stopRecording, .artifact(let request)):
            return try await handleStopRecording(request)
        case (.runBatch, .runBatch(let request)):
            return try await handleRunBatch(request)
        case (.getSessionState, _):
            return .sessionState(payload: currentSessionState())
        case (.connect, .connect(let request)):
            return try await handleConnect(request)
        case (.listTargets, _):
            return handleListTargets()
        case (.getSessionLog, _):
            return try handleGetSessionLog()
        case (.archiveSession, .archiveSession(let request)):
            return try await handleArchiveSession(request)
        case (.startHeist, .startHeist(let request)):
            return try handleStartHeist(request)
        case (.stopHeist, .stopHeist(let request)):
            return try handleStopHeist(request)
        case (.playHeist, .playHeist(let request)):
            return try await handlePlayHeist(request)
        case (.help, _), (.quit, _), (.exit, _):
            return .error("Unexpected command in dispatch: \(parsed.command.rawValue)")
        default:
            return .error("Internal payload mismatch for command: \(parsed.command.rawValue)")
        }
    }

    // MARK: - Send Action (shared)

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
        recordCompletedAction(result)
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
                let outcome = self.handoff.send(message, requestId: requestId)
                if case .failed(let failure) = outcome {
                    tracker.resolve(requestId: requestId, result: .failure(FenceError(failure)))
                }
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

    // MARK: - Command Execution State

    /// Two-phase action history: `.unrun` before any action has completed,
    /// `.completed` once one has. Display state derives from the active case;
    /// no caller has to guard a nullable to know whether an action ever ran.
    enum LastActionHistory {
        case unrun
        case completed(ActionResult)
    }

    /// Owns command-execution state derived from dispatched action responses.
    /// The last action and its measured dispatch latency move together so
    /// session-state projection cannot read from sibling lifecycle fields.
    struct CommandExecutionState {
        private(set) var lastActionHistory: LastActionHistory = .unrun
        private(set) var lastLatencyMs: Int = 0

        var lastActionResult: ActionResult? {
            if case .completed(let result) = lastActionHistory { return result }
            return nil
        }

        var lastActionPayload: SessionLastActionPayload? {
            lastActionResult.map { last in
                SessionLastActionPayload(
                    method: last.method,
                    success: last.success,
                    message: last.message,
                    latencyMs: lastLatencyMs
                )
            }
        }

        mutating func noteDispatchedResponse(_ response: FenceResponse, latencyMs: Int) {
            guard response.actionResult != nil else { return }
            lastLatencyMs = latencyMs
        }

        mutating func completeAction(_ result: ActionResult) {
            lastActionHistory = .completed(result)
        }

        mutating func reset() {
            lastActionHistory = .unrun
            lastLatencyMs = 0
        }
    }

    private var commandExecutionState = CommandExecutionState()

    var lastActionHistory: LastActionHistory {
        commandExecutionState.lastActionHistory
    }

    /// Convenience read of the last completed action's result, if any.
    var lastActionResult: ActionResult? {
        commandExecutionState.lastActionResult
    }

    var lastActionPayload: SessionLastActionPayload? {
        commandExecutionState.lastActionPayload
    }

    /// Round-trip time in milliseconds for the last action command that
    /// completed (request issued → response received).
    var lastLatencyMs: Int {
        commandExecutionState.lastLatencyMs
    }

    func recordCompletedAction(_ result: ActionResult) {
        commandExecutionState.completeAction(result)
    }

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
            let outcome = self.handoff.send(.stopRecording, requestId: UUID().uuidString)
            if case .failed(let failure) = outcome {
                self.resolveRecordingCompletion(.failure(FenceError(failure)))
            }
        }
    }

    func startRecordingAndWait(config: RecordingConfig, timeout: TimeInterval = Timeouts.actionSeconds) async throws {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }
        let syntheticId = "recording-start"
        guard recordingState.beginStartWait(syntheticId: syntheticId) else {
            throw recordingState.startRecordingConflictError
        }
        defer { recordingState.finishStartWait(syntheticId: syntheticId) }

        var didSendStart = false
        do {
            _ = try await recordingStartTracker.wait(requestId: syntheticId, timeout: timeout) {
                let outcome = self.handoff.send(.startRecording(config), requestId: UUID().uuidString)
                switch outcome {
                case .enqueued:
                    didSendStart = true
                case .failed(let failure):
                    self.recordingStartTracker.resolve(requestId: syntheticId, result: .failure(FenceError(failure)))
                }
            }
        } catch {
            if didSendStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    private func resolveRecordingStart(_ result: Result<Bool, Error>) {
        guard let syntheticId = recordingState.startWaitId else { return }
        recordingStartTracker.resolve(requestId: syntheticId, result: result)
    }

    private func resolveRecordingCompletion(_ result: Result<RecordingPayload, Error>) {
        guard let syntheticId = recordingState.completionWaitId else { return }
        recordingTracker.resolve(requestId: syntheticId, result: result)
    }

    private func resolveRecordingError(_ message: String, pendingWait: RecordingPendingWait?) {
        let error = FenceError.actionFailed("Recording failed: \(message)")
        switch pendingWait {
        case .start(let syntheticId):
            recordingStartTracker.resolve(requestId: syntheticId, result: .failure(error))
        case .completion(let syntheticId):
            recordingTracker.resolve(requestId: syntheticId, result: .failure(error))
        case nil:
            break
        }
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
        guard !isRecording else {
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
        let syntheticId = "recording"
        guard recordingState.beginCompletionWait(syntheticId: syntheticId) else {
            throw FenceError.invalidRequest("stop_recording already waiting for completion")
        }
        defer { recordingState.finishCompletionWait(syntheticId: syntheticId) }
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
