import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "handoff")

/// Client-side coordinator for device discovery, connection, keepalive, and auto-reconnect.
///
/// TheFence owns a TheHandoff and delegates connection management here.
@ButtonHeistActor
final class TheHandoff {

    // MARK: - State

    private let connectionLifecycle = HandoffConnectionLifecycle()
    private let discoveryLifecycle = HandoffDiscoveryLifecycle()
    private let reconnectController = HandoffReconnectController()

    // MARK: - Derived State

    var connectionPhase: HandoffConnectionPhase { connectionLifecycle.phase }

    var isConnected: Bool {
        connectionLifecycle.isConnected
    }

    var connectionDiagnosticFailure: HandoffConnectionError? {
        connectionLifecycle.diagnosticFailure
    }

    var connectedDevice: DiscoveredDevice? {
        connectionLifecycle.connectedDevice
    }

    var serverInfo: ServerInfo? {
        connectionLifecycle.serverInfo
    }

    /// Test seam: how many pings have been sent on the live connection
    /// without a corresponding `.pong` reply. Resets to zero when a pong
    /// arrives, and is automatically discarded when the connection phase
    /// leaves `.connected`. Returns zero in any non-connected phase.
    var missedPongCount: Int {
        connectionLifecycle.missedPongCount
    }

    var discoveredDevices: [DiscoveredDevice] {
        discoveryLifecycle.discoveredDevices
    }

    var isDiscovering: Bool {
        discoveryLifecycle.isDiscovering
    }

    // MARK: - Discovery Callbacks

    // All callbacks below fire on `@ButtonHeistActor`.

    /// A device matching the filter appeared on the network.
    var onDeviceFound: (@ButtonHeistActor (DiscoveredDevice) -> Void)?
    /// A previously-known device is no longer advertising.
    var onDeviceLost: (@ButtonHeistActor (DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    /// Emits after each connection phase transition. Consumers derive lifecycle
    /// side effects from this state stream instead of one-off lifecycle hooks.
    var onConnectionStateChanged: (@ButtonHeistActor (HandoffConnectionPhase) -> Void)?
    /// Non-lifecycle server messages delivered to TheFence for request-tracker
    /// resolution. TheHandoff forwards these without retaining semantic state.
    var onServerMessage: (@ButtonHeistActor (ServerMessage, String?) -> Void)?
    /// Transport send failures reported after Network.framework processes an enqueued write.
    var onSendFailure: (@ButtonHeistActor (DeviceSendFailure, String?) -> Void)?
    /// Recording lifecycle messages from the server. TheFence owns the
    /// client-side recording phase; TheHandoff only forwards typed messages.
    var onRecordingEvent: (@ButtonHeistActor (RecordingEvent) -> Void)?
    /// Auth approved. The parameter is the approved token, or nil when reusing a persistent session.
    var onAuthApproved: (@ButtonHeistActor (String) -> Void)?
    /// Background UI-change evidence attached to explicit command responses.
    var onBackgroundAccessibilityTrace: (@ButtonHeistActor (AccessibilityTrace) -> Void)?

    // MARK: - Configuration

    var token: String?
    /// Explicit driver ID override (e.g. from BUTTONHEIST_DRIVER_ID env var).
    /// When nil, a persistent auto-generated ID is used instead.
    var driverId: String?

    // MARK: - Internal Reconnect Settings

    /// Interval between auto-reconnect attempts. Default is 1 second.
    var reconnectInterval: TimeInterval = 1.0
    /// Max attempts before reconnect becomes terminal. Internal so tests can
    /// drive bounded retries without waiting on the production limit.
    var reconnectMaxAttempts = 60
    /// Per-attempt connection timeout used by the reconnect runner.
    var reconnectAttemptTimeout: TimeInterval = 10
    private var autoReconnectRecoveryPolicy: AutoReconnectRecoveryPolicy {
        AutoReconnectRecoveryPolicy(maxAttempts: reconnectMaxAttempts, baseInterval: reconnectInterval)
    }
    private static let keepaliveInterval: Duration = .seconds(5)
    private static let maxMissedPongs = 6

    // MARK: - Injectable Closures

    var makeDiscovery: () -> any DeviceDiscovering = { DeviceDiscovery() }
    var makeConnection: (DiscoveredDevice, String?, String) -> any DeviceConnecting = {
        DeviceConnection(device: $0, token: $1, driverId: $2)
    }

    // MARK: - Discovery / Connection Handles

    private var connection: (any DeviceConnecting)?

    var hasActiveDiscoverySession: Bool {
        discoveryLifecycle.hasActiveSession
    }

    /// Resolved driver ID: explicit override if set, otherwise a persistent auto-generated UUID.
    var effectiveDriverId: String {
        if let driverId, !driverId.isEmpty { return driverId }
        return Self.persistentDriverId
    }

    private static let driverIdFile: URL = {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".buttonheist", isDirectory: true)
        return configDir.appendingPathComponent("driver-id")
    }()

    private static let persistentDriverId: String = {
        let fileURL = driverIdFile
        let existingValue: String?
        do {
            existingValue = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            existingValue = nil
        }
        if let existing = existingValue, !existing.isEmpty {
            repairDriverIdPermissions(fileURL)
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            logger.warning("Failed to create driver-id directory: \(error.localizedDescription)")
        }
        if !FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(generated.utf8),
            attributes: [.posixPermissions: 0o600]
        ) {
            logger.warning("Failed to persist driver-id to \(fileURL.path)")
        }
        return generated
    }()

    private static func repairDriverIdPermissions(_ fileURL: URL) {
        let fileManager = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch {
            logger.warning("Failed to repair driver-id directory permissions: \(error.localizedDescription)")
        }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            logger.warning("Failed to repair driver-id file permissions: \(error.localizedDescription)")
        }
    }

    // MARK: - Init

    init() {
        connectionLifecycle.onPhaseChanged = { [weak self] phase in
            self?.onConnectionStateChanged?(phase)
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        logger.info("startDiscovery called, hasSession=\(self.hasActiveDiscoverySession)")
        guard !discoveryLifecycle.hasActiveSession else {
            logger.info("Already discovering, skipping")
            return
        }

        discoveryLifecycle.start(
            makeDiscovery: makeDiscovery,
            onDeviceFound: { [weak self] device in self?.onDeviceFound?(device) },
            onDeviceLost: { [weak self] device in self?.onDeviceLost?(device) }
        )
        logger.info("Discovery started")
    }

    func stopDiscovery() {
        discoveryLifecycle.stop()
    }

    // MARK: - Reachability Probing

    /// Discover devices and validate each deduped advertisement as it appears.
    func discoverReachableDevices(
        timeout: TimeInterval = 3.0,
        probeTimeout: TimeInterval = 0.5,
        retryInterval: TimeInterval = 0.2
    ) async -> [DiscoveredDevice] {
        let startedTemporaryDiscovery = !hasActiveDiscoverySession
        if startedTemporaryDiscovery {
            startDiscovery()
        }
        defer {
            if startedTemporaryDiscovery {
                stopDiscovery()
            }
        }

        return await ReachableDeviceScanner(getDiscoveredDevices: { [weak self] in
            self?.discoveredDevices ?? []
        }).scan(
            timeout: timeout,
            probeTimeout: probeTimeout,
            retryInterval: retryInterval
        )
    }

    // MARK: - Connection

    @discardableResult
    func connect(to device: DiscoveredDevice, cancelReconnectTaskOnReplacement: Bool = true) -> UUID {
        disconnectForReplacement(cancelReconnectTask: cancelReconnectTaskOnReplacement)
        let attemptID = connectionLifecycle.beginConnecting(device: device)

        connection = makeConnection(device, token, effectiveDriverId)

        connection?.onEvent = { [weak self, attemptID] event in
            guard let self else { return }
            switch event {
            case .connected:
                guard self.connectionLifecycle.isActiveAttempt(attemptID) else { return }
                self.connectionLifecycle.markConnected(
                    attemptID: attemptID,
                    device: device,
                    keepaliveTask: self.makeKeepaliveTask()
                )
            case .disconnected(let reason):
                guard self.connectionLifecycle.isActiveAttempt(attemptID) else { return }
                if case .failed = self.connectionPhase {
                    return
                }
                guard self.connectionLifecycle.markDisconnected(
                    reason: reason,
                    expectedAttemptID: attemptID
                ) else { return }
                if reason.retryable {
                    self.scheduleAutoReconnectIfNeeded(disconnectedDevice: device)
                }
            case .sendFailed(let failure, let requestId):
                guard self.connectionLifecycle.isActiveAttempt(attemptID) else { return }
                self.onSendFailure?(failure, requestId)
            case .message(let message, let requestId, let accessibilityTrace):
                guard self.connectionLifecycle.isActiveAttempt(attemptID) else { return }
                self.handleServerMessage(
                    message,
                    requestId: requestId,
                    accessibilityTrace: accessibilityTrace
                )
            }
        }

        connection?.connect()
        return attemptID
    }

    func handleServerMessage(
        _ message: ServerMessage,
        requestId: String?,
        accessibilityTrace: AccessibilityTrace? = nil
    ) {
        handleBackgroundAccessibility(accessibilityTrace)
        switch message {
        case .info(let info):
            connectionLifecycle.recordServerInfo(info)
        case .interface, .actionResult, .screen:
            forwardServerMessage(message, requestId: requestId)
        case .recordingStarted:
            emitRecordingEvent(.started)
        case .recording(let payload):
            emitRecordingEvent(.completed(payload))
        case .error(let serverError):
            switch serverError.kind {
            case .recording:
                emitRecordingEvent(.failed(serverError.message))
            case .authFailure:
                connectionLifecycle.markFailed(.disconnected(.authFailed(serverError.message)))
            case .authApprovalPending:
                connectionLifecycle.markFailed(.disconnected(.authApprovalPending(serverError.message)))
            default:
                if let requestId {
                    forwardServerMessage(message, requestId: requestId)
                } else {
                    connectionLifecycle.markFailed(.connectionFailed(serverError.message))
                }
            }
        case .authApproved(let payload):
            token = payload.token
            onAuthApproved?(payload.token)
        case .authApprovalPending(let payload):
            connectionLifecycle.recordAttemptFailure(.disconnected(.authApprovalPending(payload.message)))
            onStatus?(payload.hint)
        case .sessionLocked(let payload):
            connectionLifecycle.markFailed(.disconnected(.sessionLocked(payload.message)))
        case .status(let payload):
            logger.info("Received status payload: appName=\(payload.identity.appName, privacy: .public)")
        case .protocolMismatch(let payload):
            connectionLifecycle.markFailed(.disconnected(.buttonHeistVersionMismatch(
                serverVersion: payload.serverButtonHeistVersion,
                clientVersion: payload.clientButtonHeistVersion
            )))
        case .pong:
            connectionLifecycle.markPongReceived()
            if let requestId {
                forwardServerMessage(message, requestId: requestId)
            }
        case .recordingStopped:
            emitRecordingEvent(.stopped)
        // Handshake messages are consumed inside DeviceConnection before bubbling here; no caller-visible side effect needed at this layer.
        // swiftlint:disable:next agent_wire_message_arm_no_op_break
        case .serverHello, .authRequired, .interaction:
            break
        }
    }

    private func forwardServerMessage(_ message: ServerMessage, requestId: String?) {
        onServerMessage?(message, requestId)
    }

    private func emitRecordingEvent(_ event: RecordingEvent) {
        guard isConnected else { return }
        onRecordingEvent?(event)
    }

    private func handleBackgroundAccessibility(_ accessibilityTrace: AccessibilityTrace?) {
        if let accessibilityTrace {
            onBackgroundAccessibilityTrace?(accessibilityTrace)
        }
    }

    func disconnect() {
        reconnectController.cancelRunnerAndClearTarget()
        connection?.disconnect()
        connection = nil
        connectionLifecycle.markDisconnected()
    }

    @discardableResult
    private func disconnectForReplacement(cancelReconnectTask: Bool = true) -> Bool {
        let hadActiveSession = connectionLifecycle.activeAttemptID != nil
        if cancelReconnectTask {
            reconnectController.cancelRunnerAndClearTarget()
        }
        connection?.disconnect()
        connection = nil

        if hadActiveSession {
            connectionLifecycle.markDisconnected(reason: .localDisconnect)
        } else {
            connectionLifecycle.markDisconnected()
        }
        return hadActiveSession
    }

    /// Tear down an in-flight connection attempt after its owner reaches a setup
    /// terminal state (for example, discovery/direct-connect timeout). This
    /// intentionally does not schedule reconnect: there was no usable session
    /// drop, only a failed setup attempt.
    func abortConnectionAttempt(_ attemptID: UUID, failure: HandoffConnectionError) {
        guard connectionLifecycle.disconnectAttempt(attemptID, failure: failure) else { return }
        connection?.disconnect()
        connection = nil
    }

    func disableAutoReconnect() {
        reconnectController.disable()
    }

    /// Suspend until the connection phase transitions to `.connected` (returns),
    /// `.failed` (throws the mapped `HandoffConnectionError`), or `.disconnected`
    /// (throws `HandoffConnectionError.connectionFailed`). If the phase is already
    /// terminal at call time, returns or throws immediately without suspending.
    ///
    /// The `timeout` is enforced by scheduling a cancellable timeout task that
    /// fails only this registered waiter with `HandoffConnectionError.timeout`.
    /// Cancelling the calling task aborts the wait and propagates
    /// `CancellationError`.
    func waitForConnectionResult(timeout: TimeInterval) async throws {
        try await connectionLifecycle.waitForConnectionResult(timeout: timeout)
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    func forceDisconnect() {
        guard isConnected else { return }
        logger.warning("Force-disconnecting stale connection")
        let reconnectDevice = connectedDevice
        reconnectController.cancelRunnerAndClearTarget()
        connection?.disconnect()
        connection = nil
        connectionLifecycle.markDisconnected(reason: .localDisconnect)
        if let reconnectDevice {
            scheduleAutoReconnectIfNeeded(disconnectedDevice: reconnectDevice)
        }
    }

    // MARK: - Commands

    @discardableResult
    func send(_ message: ClientMessage, requestId: String? = nil) -> DeviceSendOutcome {
        guard case .connected = connectionPhase,
              let connection else {
            return .failed(.notConnected)
        }
        return connection.send(message, requestId: requestId)
    }

    // MARK: - Keepalive

    private func makeKeepaliveTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard await Task.cancellableSleep(for: Self.keepaliveInterval) else { break }
                guard !Task.isCancelled else { break }
                guard let self else { return }
                let count = self.tickKeepalive()
                if count >= Self.maxMissedPongs {
                    logger.warning("No pong received for \(count) consecutive pings — forcing disconnect")
                    self.forceDisconnect()
                    break
                }
            }
        }
    }

    /// Send a keepalive ping and bump the missed-pong counter. Returns the
    /// new count so the keepalive task can decide whether to force a
    /// disconnect. No-op when not connected. Internal to allow tests to drive
    /// keepalive cycles without waiting on the 5s interval.
    @discardableResult
    func tickKeepalive() -> Int {
        connectionLifecycle.tickKeepalive {
            connection?.send(.ping, requestId: nil)
        }
    }

    // MARK: - Session Management (discovery → connect → reconnect)

    /// Status callback for session management progress messages.
    var onStatus: (@ButtonHeistActor (String) -> Void)?

    /// Discover a device (optionally matching a filter) and connect to it.
    /// Starts discovery if not already active, polls until a matching device appears
    /// or the bounded resolution window expires. Suspends on
    /// `waitForConnectionResult` for the connection outcome.
    func connectWithDiscovery(
        filter: String?,
        timeout: TimeInterval = 30
    ) async throws {
        disconnectForReplacement()
        onStatus?("Searching for iOS devices...")
        let startedDiscovery = !hasActiveDiscoverySession
        if startedDiscovery { startDiscovery() }

        let resolutionTimeout = Self.connectionResolutionTimeout(for: timeout)
        let discoveryTimeout = UInt64(resolutionTimeout * 1_000_000_000)
        let device: DiscoveredDevice
        do {
            device = try await resolveReachableDevice(
                filter: filter,
                discoveryTimeout: discoveryTimeout,
                reachabilityTimeout: resolutionTimeout
            )
        } catch {
            if startedDiscovery { stopDiscovery() }
            if let connectionError = error as? HandoffConnectionError {
                connectionLifecycle.recordAttemptFailure(connectionError)
            }
            throw error
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        let attemptID = connect(to: device)
        do {
            try await waitForConnectionResult(timeout: timeout)
        } catch let error as HandoffConnectionError where error == .timeout {
            abortConnectionAttempt(attemptID, failure: .timeout)
            throw error
        }
        onStatus?("Connected to \(displayName(for: device))")
    }

    private func resolveReachableDevice(
        filter: String?,
        discoveryTimeout: UInt64,
        reachabilityTimeout: TimeInterval
    ) async throws -> DiscoveredDevice {
        let resolver = DeviceResolver(
            filter: filter,
            discoveryTimeout: discoveryTimeout,
            reachabilityTimeout: reachabilityTimeout,
            getDiscoveredDevices: { [weak self] in self?.discoveredDevices ?? [] }
        )
        return try await resolver.resolve()
    }

    static func connectionResolutionTimeout(for timeout: TimeInterval) -> TimeInterval {
        min(max(timeout, 0.05), 2.0)
    }

    func setupAutoReconnect(filter: String?) {
        reconnectController.setup(filter: filter)
    }

    private func scheduleAutoReconnectIfNeeded(disconnectedDevice: DiscoveredDevice) {
        reconnectController.scheduleIfNeeded(
            disconnectedDevice: disconnectedDevice,
            policy: autoReconnectRecoveryPolicy,
            attemptTimeout: reconnectAttemptTimeout,
            runtime: self
        )
    }

    // MARK: - Display Names

    /// Compute display name with disambiguation when multiple devices have the same app
    func displayName(for device: DiscoveredDevice) -> String {
        let appName = device.appName
        let deviceSuffix = device.deviceName.isEmpty ? "" : " (\(device.deviceName))"

        let sameAppDevices = discoveredDevices.filter { $0.appName == appName }

        if sameAppDevices.count > 1 {
            let sameAppAndDevice = sameAppDevices.filter { $0.deviceName == device.deviceName }
            if sameAppAndDevice.count > 1, let shortId = device.shortId {
                return "\(appName)\(deviceSuffix) [\(shortId)]"
            }
            return "\(appName)\(deviceSuffix)"
        } else {
            return appName
        }
    }
}

extension TheHandoff: HandoffReconnectRuntime {
    func publishReconnectStatus(_ message: String) {
        onStatus?(message)
    }

    func connectForAutoReconnect(to device: DiscoveredDevice) -> UUID {
        connect(to: device, cancelReconnectTaskOnReplacement: false)
    }

    func waitForAutoReconnectResult(timeout: TimeInterval) async throws {
        try await waitForConnectionResult(timeout: timeout)
    }

    func disconnectAutoReconnectAttempt(_ attemptID: UUID, failure: HandoffConnectionError) {
        abortConnectionAttempt(attemptID, failure: failure)
    }

    func failAutoReconnect(_ failure: HandoffConnectionError) {
        connectionLifecycle.markFailed(failure)
    }
}
