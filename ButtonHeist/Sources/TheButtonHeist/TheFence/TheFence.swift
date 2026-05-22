import Foundation

import TheScore

struct SessionConnectionSnapshot {
    let connected: Bool
    let phase: SessionConnectionPhase
    let device: SessionDevicePayload?
    let lastFailure: SessionFailurePayload?
}

/// Named timeout constants for TheFence operations.
enum Timeouts {
    /// Standard action timeout (15 seconds)
    static let actionSeconds: TimeInterval = 15
    /// Short health/read-control timeout (3 seconds)
    static let healthSeconds: TimeInterval = 3
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
    var sessionConnectionSnapshot: SessionConnectionSnapshot {
        SessionConnectionSnapshot(
            connected: handoff.isConnected,
            phase: sessionConnectionPhase,
            device: sessionDevicePayload,
            lastFailure: sessionFailurePayload
        )
    }
    let bookKeeper: TheBookKeeper
    let playback = FencePlaybackLifecycle()

    /// Fence-owned accessibility capture history. Captures are the retained
    /// source of truth; pending trace and lookup views are derived locally from
    /// retained captures when validation or recording needs them.
    var backgroundAccessibilityState = BackgroundAccessibilityState()

    let pendingRequests = PendingRequestTrackers()

    let recording = FenceRecordingLifecycle()
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

    private var sessionConnectionPhase: SessionConnectionPhase {
        switch handoff.connectionPhase {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .failed:
            return .failed
        }
    }

    private var sessionDevicePayload: SessionDevicePayload? {
        handoff.connectedDevice.map { device in
            SessionDevicePayload(
                deviceName: handoff.displayName(for: device),
                appName: device.appName,
                connectionType: device.connectionType,
                shortId: device.shortId
            )
        }
    }

    private var sessionFailurePayload: SessionFailurePayload? {
        handoff.connectionDiagnosticFailure.map { failure in
            SessionFailurePayload(
                errorCode: failure.failureCode,
                phase: failure.phase,
                retryable: failure.retryable,
                message: failure.errorDescription,
                hint: failure.hint
            )
        }
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
        let parsed: ParsedRequest
        do {
            parsed = try parsePlaybackOperation(operation)
        } catch let error as SchemaValidationError {
            return .error(error.message)
        }
        return try await execute(parsed: parsed)
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

    func beginRecordingAccessibilityHistoryRetention() {
        backgroundAccessibilityState.beginRecordingRetention()
    }

    func endRecordingAccessibilityHistoryRetention() {
        backgroundAccessibilityState.endRecordingRetention()
    }

    // MARK: - Command Dispatch (thin router)

    func dispatch(_ parsed: ParsedRequest) async throws -> FenceResponse {
        switch (parsed.command, parsed.payload) {
        case (.status, _):
            return .status(
                connected: handoff.isConnected,
                deviceName: handoff.connectedDevice.map { handoff.displayName(for: $0) }
            )
        case (.ping, _):
            return try await handlePing()
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

    // Expectation parsing (`parseExpectation` and its helpers) lives in
    // TheFence+ExpectationParsing.swift.

    var commandExecutionState = CommandExecutionState()

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

}
