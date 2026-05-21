import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "bookkeeper")

struct SessionConnectionSnapshot {
    let connected: Bool
    let phase: SessionConnectionPhase
    let device: SessionDevicePayload?
    let lastFailure: SessionFailurePayload?
}

struct RecordingSnapshot {
    let isRecording: Bool
    let isWaitingForCompletion: Bool
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
    private let sessionConnectionState = SessionConnectionState(handoff: TheHandoff())
    var handoff: TheHandoff {
        sessionConnectionState.handoff
    }
    var sessionConnectionSnapshot: SessionConnectionSnapshot {
        sessionConnectionState.snapshot
    }
    let bookKeeper: TheBookKeeper
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
    private var backgroundAccessibilityState = BackgroundAccessibilityState()

    private let pendingRequests = PendingRequestTrackers()

    private var recording = RecordingCoordinator()
    var recordingSnapshot: RecordingSnapshot {
        recording.snapshot
    }
    var isRecording: Bool {
        recordingSnapshot.isRecording
    }
    /// Test-visible state for deterministic recording completion injection.
    var isWaitingForRecordingCompletion: Bool {
        recordingSnapshot.isWaitingForCompletion
    }

    public init(configuration: Configuration) {
        self.config = configuration
        self.bookKeeper = TheBookKeeper(baseDirectory: configuration.bookKeeperBaseDirectory)
        let configuredToken = configuration.token ?? EnvironmentKey.buttonheistToken.value
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

    private var configuredAuthTokenForStatus: String? {
        config.token ?? EnvironmentKey.buttonheistToken.value
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
        _ = pendingRequests.resolveTransientResponse(message, requestId: requestId)
    }

    private func handleSendFailure(_ failure: DeviceSendFailure, requestId: String?) {
        guard let requestId else { return }
        pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
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
        backgroundAccessibilityState.reset()
        commandExecutionState.reset()
        cancelAllPendingRequests(error: error)
        recording.reset()
    }

    private func handleRecordingEvent(_ event: RecordingEvent) {
        recording.handleEvent(event)
    }

    private func enqueueBackgroundAccessibilityTrace(_ trace: AccessibilityTrace) {
        backgroundAccessibilityState.enqueue(trace)
    }

    /// Return and clear the oldest queued background accessibility trace, if any.
    public func drainBackgroundAccessibilityTrace() -> AccessibilityTrace? {
        backgroundAccessibilityState.drainTrace()
    }

    /// Return and clear all queued background accessibility traces in arrival order.
    public func drainBackgroundAccessibilityTraces() -> [AccessibilityTrace] {
        backgroundAccessibilityState.drainTraces()
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

    /// Execute an operation that has already been normalized by the shared command catalog.
    ///
    /// This keeps adapters from rebuilding command dictionaries after routing.
    public func execute(operation: NormalizedOperation) async throws -> FenceResponse {
        let parsed: ParsedRequest
        do {
            parsed = try parseRequest(operation: operation)
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

        let preDispatchBackgroundCount = backgroundAccessibilityState.pendingTraceCount
        let preDispatchCaptureRef = backgroundAccessibilityState.latestRef
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
            let captureRef = backgroundAccessibilityState.append(interface: fullInterface)
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

    func handleImmediateCommand(_ command: Command) -> FenceResponse? {
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
        for pendingTrace in backgroundAccessibilityState.pendingTraces(startingAt: startIndex) {
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
                preActionElements: backgroundAccessibilityState.elementLookup(captureRef: pendingTrace.firstRef)
            )
            if validation.met {
                matched = (pendingTrace, syntheticResult, validation)
                break
            }
        }

        guard let matched else { return nil }
        guard let pendingTrace = backgroundAccessibilityState.removePendingTrace(at: matched.pendingTrace.index) else {
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
            ?? lookupCaptureRef.flatMap { backgroundAccessibilityState.capture(ref: $0) }
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
                let preActionElements = backgroundAccessibilityState.elementLookup(captureRef: preActionCaptureRef)
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
        return backgroundAccessibilityState.ingest(trace)
    }

    private func finishAccessibilityDelivery(_ captureRef: AccessibilityTrace.CaptureRef?) {
        backgroundAccessibilityState.markDelivered(through: captureRef)
    }

    func beginRecordingAccessibilityHistoryRetention() {
        backgroundAccessibilityState.beginRecordingRetention()
    }

    func endRecordingAccessibilityHistoryRetention() {
        backgroundAccessibilityState.endRecordingRetention()
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
        case (.oneFingerTap, .gesture(.oneFingerTap(let payload))):
            return try await handleOneFingerTap(payload)
        case (.longPress, .gesture(.longPress(let payload))):
            return try await handleLongPress(payload)
        case (.swipe, .gesture(.swipe(let payload))):
            return try await handleSwipe(payload)
        case (.drag, .gesture(.drag(let payload))):
            return try await handleDrag(payload)
        case (.pinch, .gesture(.pinch(let payload))):
            return try await handlePinch(payload)
        case (.rotate, .gesture(.rotate(let payload))):
            return try await handleRotate(payload)
        case (.twoFingerTap, .gesture(.twoFingerTap(let payload))):
            return try await handleTwoFingerTap(payload)
        case (.drawPath, .gesture(.drawPath(let payload))):
            return try await handleDrawPath(payload)
        case (.drawBezier, .gesture(.drawBezier(let payload))):
            return try await handleDrawBezier(payload)
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
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        do {
            return try await pendingRequests.waitForAction(requestId: requestId, timeout: timeout) {
                let outcome = self.handoff.send(message, requestId: requestId)
                if case .failed(let failure) = outcome {
                    self.pendingRequests.resolveAction(
                        requestId: requestId,
                        result: Result<ActionResult, Error>.failure(FenceError(failure))
                    )
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw mapCaughtError(error)
        }
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        do {
            return try await pendingRequests.waitForInterface(requestId: requestId, timeout: timeout) {
                let outcome = self.handoff.send(message, requestId: requestId)
                if case .failed(let failure) = outcome {
                    self.pendingRequests.resolveInterface(
                        requestId: requestId,
                        result: Result<Interface, Error>.failure(FenceError(failure))
                    )
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw mapCaughtError(error)
        }
    }

    func sendAndAwaitScreen(_ message: ClientMessage, timeout: TimeInterval) async throws -> ScreenPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        do {
            return try await pendingRequests.waitForScreen(requestId: requestId, timeout: timeout) {
                let outcome = self.handoff.send(message, requestId: requestId)
                if case .failed(let failure) = outcome {
                    self.pendingRequests.resolveScreen(
                        requestId: requestId,
                        result: Result<ScreenPayload, Error>.failure(FenceError(failure))
                    )
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

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    private(set) var commandExecutionState = CommandExecutionState()

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
        try await pendingRequests.waitForAction(requestId: requestId, timeout: timeout)
    }

    func waitForInterface(requestId: String, timeout: TimeInterval = 10.0) async throws -> Interface {
        try await pendingRequests.waitForInterface(requestId: requestId, timeout: timeout)
    }

    func waitForScreen(requestId: String, timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await pendingRequests.waitForScreen(requestId: requestId, timeout: timeout)
    }

    // Recording responses do not carry request IDs. The recording lifecycle
    // carries the active start/completion wait so disconnect handling can fail
    // it immediately instead of letting the caller time out.
    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await waitForRecording(timeout: timeout, afterRegister: nil)
    }

    func stopRecordingAndWait(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        return try await waitForRecording(timeout: timeout) {
            let outcome = self.handoff.send(.stopRecording, requestId: nil)
            if case .failed(let failure) = outcome {
                self.recording.resolveActiveCompletion(.failure(FenceError(failure)))
            }
        }
    }

    func startRecordingAndWait(config: RecordingConfig, timeout: TimeInterval = Timeouts.actionSeconds) async throws {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }
        let wait = try recording.beginStartWait()
        defer { recording.finishStartWait(wait) }

        var didSendStart = false
        do {
            try await wait.wait(timeout: timeout) {
                let outcome = self.handoff.send(.startRecording(config), requestId: nil)
                switch outcome {
                case .enqueued:
                    didSendStart = true
                case .failed(let failure):
                    wait.resolve(.failure(FenceError(failure)))
                }
            }
        } catch {
            if didSendStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    /// Run a recording from start to completion as a single async unit.
    ///
    /// Sends `start_recording`, waits for the server acknowledgement, then
    /// awaits the resulting `RecordingPayload`. On any error path after the
    /// start request is sent, sends `stop_recording` so the iOS-side recording
    /// is not stranded. Stop cleanup is secondary: if it fails, the original
    /// error still propagates.
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
        handoff.send(.stopRecording, requestId: nil)
    }

    /// Internal overload exposing `afterRegister` for test injection. The hook
    /// fires synchronously after the recording callback is registered, letting
    /// tests deliver a payload deterministically without sleeping.
    func waitForRecording(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws -> RecordingPayload {
        let wait = try recording.beginCompletionWait()
        defer { recording.finishCompletionWait(wait) }
        return try await wait.wait(timeout: timeout, afterRegister: afterRegister)
    }

    private func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
        recording.cancelAll(error: error)
    }

}
