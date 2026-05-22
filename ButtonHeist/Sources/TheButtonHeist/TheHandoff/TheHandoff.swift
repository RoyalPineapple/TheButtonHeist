import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "handoff")

/// Client-side session manager that owns the full device lifecycle:
/// discovery, connection, keepalive, and auto-reconnect.
///
/// TheFence owns a TheHandoff and delegates connection management here.
/// All discovery, connection, keepalive, and reconnect logic lives here.
@ButtonHeistActor
final class TheHandoff {

    // MARK: - State Machine Types

    /// Why a connection attempt failed. TheHandoff's own error type —
    /// callers (TheFence) map this to their error domain at the boundary.
    ///
    /// Also used as the associated value in `ConnectionPhase.failed`, which
    /// is why this enum is `Equatable`. Not every case can appear in
    /// `.failed`: the phase-producing cases are `connectionFailed` and
    /// `disconnected`; auth and session-lock failures are disconnect causes.
    /// The resolver/timeout cases
    /// (`timeout`, `noDeviceFound`, `noMatchingDevice`) are thrown directly
    /// from `DeviceResolver`/`waitForConnectionResult` and never become a
    /// phase value.
    enum ConnectionError: Error, LocalizedError, Equatable {
        case connectionFailed(String)
        case disconnected(DisconnectReason)
        case timeout
        case noDeviceFound
        case noMatchingDevice(filter: String, available: [String])

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let message): return message
            case .disconnected(.authFailed(let reason)): return "Authentication failed: \(reason)"
            case .disconnected(.authApprovalPending(let message)): return "Authentication approval pending: \(message)"
            case .disconnected(.sessionLocked(let message)): return "Session locked: \(message)"
            case .disconnected(let reason): return reason.connectionFailureMessage
            case .timeout: return "Connection timed out"
            case .noDeviceFound: return "No device found"
            case .noMatchingDevice(let filter, let available):
                return "No device matching '\(filter)' (available: \(available.joined(separator: ", ")))"
            }
        }

        var failureCode: String {
            switch self {
            case .connectionFailed:
                return "connection.failed"
            case .disconnected(let reason):
                return reason.failureCode
            case .timeout:
                return "setup.timeout"
            case .noDeviceFound:
                return "discovery.no_device_found"
            case .noMatchingDevice:
                return "discovery.no_matching_device"
            }
        }

        var phase: FailurePhase {
            switch self {
            case .connectionFailed:
                return .transport
            case .disconnected(let reason):
                return reason.phase
            case .timeout:
                return .setup
            case .noDeviceFound, .noMatchingDevice:
                return .discovery
            }
        }

        var retryable: Bool {
            switch self {
            case .connectionFailed, .timeout, .noDeviceFound:
                return true
            case .disconnected(let reason):
                return reason.retryable
            case .noMatchingDevice:
                return false
            }
        }

        var hint: String? {
            switch self {
            case .connectionFailed:
                return "Check that the app is running and reachable, then retry."
            case .disconnected(let reason):
                return reason.hint
            case .timeout:
                return "Check that the app is running with Button Heist enabled; use 'buttonheist list' to see available devices."
            case .noDeviceFound:
                return "Start the app and confirm it advertises a Button Heist session."
            case .noMatchingDevice:
                return "Check the device filter or target name against 'buttonheist list'."
            }
        }
    }

    /// State carried while connected: device, keepalive task, and the
    /// lifecycle-scoped data that only makes sense during a live connection.
    /// Bundling these into the phase makes "connected but no server info" a
    /// transient inner state rather than a sibling-of-phase race.
    ///
    /// Interface and screen payloads are forwarded as delivered server messages;
    /// this session does not mirror semantic accessibility state.
    ///
    /// `missedPongCount` lives here (and not as a top-level TheHandoff field)
    /// because it is meaningful only while a connection is live. Tying it to
    /// `.connected` means the counter is automatically discarded on transition
    /// to `.disconnected`/`.failed`, so a stale count from a prior connection
    /// can never feed into a fresh one's keepalive arithmetic.
    struct ConnectedSession {
        let attemptID: UUID
        let device: DiscoveredDevice
        let keepaliveTask: Task<Void, Never>
        var serverInfo: ServerInfo?
        var missedPongCount: Int

        init(
            attemptID: UUID,
            device: DiscoveredDevice,
            keepaliveTask: Task<Void, Never>,
            serverInfo: ServerInfo? = nil,
            missedPongCount: Int = 0
        ) {
            self.attemptID = attemptID
            self.device = device
            self.keepaliveTask = keepaliveTask
            self.serverInfo = serverInfo
            self.missedPongCount = missedPongCount
        }
    }

    /// Explicit connection lifecycle state machine. The device is carried in
    /// `.connecting` and `.connected` so `connectedDevice` cannot drift from
    /// the phase — impossible states like "connected but no device" are
    /// unrepresentable. `.connected` carries the full session payload so
    /// session-scoped data clears automatically on transition.
    struct ConnectionAttempt {
        let id: UUID
        let device: DiscoveredDevice
    }

    enum ConnectionPhase {
        case disconnected
        case connecting(ConnectionAttempt)
        case connected(ConnectedSession)
        case failed(ConnectionError)
    }

    /// Concrete device identity auto-reconnect is allowed to recover. The
    /// filter is user input; the target is the product invariant. Once a
    /// session drops, reconnect must recover that same target instead of
    /// reselecting an arbitrary newly-discovered app that happens to match
    /// the old filter.
    struct ReconnectTarget: Equatable {
        let filter: String?
        let device: DiscoveredDevice

        var displayName: String { device.name }

        func resolve(from discoveredDevices: [DiscoveredDevice]) -> DiscoveredDevice? {
            if device.reconnectsWithoutDiscovery {
                return device
            }

            return discoveredDevices.first { candidate in
                candidate.discoveryIdentity == device.discoveryIdentity && (
                    filter.map { candidate.matches(filter: $0) } ?? true
                )
            }
        }
    }

    /// Whether auto-reconnect fires on disconnect. The reconnect task lives
    /// inside `.enabled` because it only runs when the policy is active and
    /// a disconnect has occurred.
    enum ReconnectPolicy {
        case disabled
        case enabled(filter: String?, target: ReconnectTarget?, reconnectTask: Task<Void, Never>?)
    }

    // MARK: - State

    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isDiscovering: Bool = false
    private(set) var connectionPhase: ConnectionPhase = .disconnected
    private(set) var reconnectPolicy: ReconnectPolicy = .disabled
    private var connectionAttemptFailure: ConnectionError?
    private var discoverySessionID: UUID?

    /// Continuations awaiting a terminal connection-phase transition. Each
    /// continuation is tied to the connection attempt that was active when
    /// it registered. Individual cancellation/timeout resolves only that
    /// waiter; terminal transitions resolve all waiters for the attempt.
    private struct PhaseAwaiter {
        let attemptID: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var phaseAwaiters: [UUID: PhaseAwaiter] = [:]

    // MARK: - State Transitions

    private var activeConnectionAttemptID: UUID? {
        switch connectionPhase {
        case .connecting(let attempt):
            return attempt.id
        case .connected(let session):
            return session.attemptID
        case .disconnected, .failed:
            return nil
        }
    }

    private func isActiveConnectionAttempt(_ attemptID: UUID) -> Bool {
        activeConnectionAttemptID == attemptID
    }

    private func transitionToConnecting(device: DiscoveredDevice) -> UUID {
        let attempt = ConnectionAttempt(id: UUID(), device: device)
        connectionAttemptFailure = nil
        setConnectionPhase(.connecting(attempt))
        return attempt.id
    }

    private func transitionToConnected(attemptID: UUID, device: DiscoveredDevice) {
        guard case .connecting(let attempt) = connectionPhase, attempt.id == attemptID else { return }
        let keepaliveTask = makeKeepaliveTask()
        connectionAttemptFailure = nil
        setConnectionPhase(.connected(ConnectedSession(attemptID: attemptID, device: device, keepaliveTask: keepaliveTask)))
        resumePhaseAwaiters(for: attemptID, with: .success(()))
    }

    private func transitionToFailed(_ failure: ConnectionError) {
        connectionAttemptFailure = failure
        let attemptID = activeConnectionAttemptID
        let wasActive: Bool
        switch connectionPhase {
        case .connecting, .connected:
            wasActive = true
        case .disconnected, .failed:
            wasActive = false
        }
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        setConnectionPhase(.failed(failure))
        if wasActive, let attemptID {
            resumePhaseAwaiters(for: attemptID, with: .failure(failure))
        }
    }

    @discardableResult
    private func transitionToDisconnected(reason: DisconnectReason? = nil, attemptID expectedAttemptID: UUID? = nil) -> Bool {
        let attemptID = activeConnectionAttemptID
        if let expectedAttemptID, attemptID != expectedAttemptID { return false }

        let wasActive: Bool
        switch connectionPhase {
        case .connecting, .connected:
            wasActive = true
        case .disconnected, .failed:
            wasActive = false
        }
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        if wasActive {
            if let reason {
                let failure = ConnectionError.disconnected(reason)
                connectionAttemptFailure = failure
                setConnectionPhase(.disconnected)
                if let attemptID {
                    resumePhaseAwaiters(for: attemptID, with: .failure(failure))
                }
            } else {
                let failure = ConnectionError.connectionFailed(
                    "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
                )
                setConnectionPhase(.disconnected)
                if let attemptID {
                    resumePhaseAwaiters(for: attemptID, with: .failure(failure))
                }
            }
        } else {
            if reason == nil {
                // No active transition and no new cause: clear any stale attempt cause.
                // If a cause arrives after the first disconnect, keep the original cause
                // because it is the one waitForConnectionResult reports on the fast path.
                connectionAttemptFailure = nil
            }
            setConnectionPhase(.disconnected)
        }
        return wasActive
    }

    /// Tear down an in-flight connection attempt after its owner reaches a setup
    /// terminal state (for example, discovery/direct-connect timeout). This
    /// intentionally does not schedule reconnect:
    /// there was no usable session drop, only a failed setup attempt.
    func disconnectConnectionAttempt(_ attemptID: UUID, failure: ConnectionError) {
        guard activeConnectionAttemptID == attemptID else { return }
        connectionAttemptFailure = failure
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        connection?.disconnect()
        connection = nil
        setConnectionPhase(.disconnected)
        resumePhaseAwaiters(for: attemptID, with: .failure(failure))
    }

    private func setConnectionPhase(_ phase: ConnectionPhase) {
        let previousPhase = connectionPhase
        connectionPhase = phase
        guard !Self.isSameConnectionPhase(previousPhase, phase) else { return }
        onConnectionStateChanged?(phase)
    }

    private static func isSameConnectionPhase(_ lhs: ConnectionPhase, _ rhs: ConnectionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.failed, .failed):
            return true
        default:
            return false
        }
    }

    private func resumePhaseAwaiters(for attemptID: UUID, with result: Result<Void, Error>) {
        let waiterIDs = phaseAwaiters.compactMap { id, awaiter in
            awaiter.attemptID == attemptID ? id : nil
        }
        for id in waiterIDs {
            guard let awaiter = phaseAwaiters.removeValue(forKey: id) else { continue }
            awaiter.continuation.resume(with: result)
        }
    }

    /// Mutate the connected session in place. No-op when not connected.
    private func mutateConnectedSession(_ body: (inout ConnectedSession) -> Void) {
        guard case .connected(var session) = connectionPhase else { return }
        body(&session)
        connectionPhase = .connected(session)
    }

    // MARK: - Derived State

    var isConnected: Bool {
        if case .connected = connectionPhase { return true }
        return false
    }

    var connectionDiagnosticFailure: ConnectionError? {
        switch connectionPhase {
        case .failed(let failure):
            return failure
        case .disconnected:
            return connectionAttemptFailure
        case .connecting, .connected:
            return nil
        }
    }

    var connectedDevice: DiscoveredDevice? {
        if case .connected(let session) = connectionPhase { return session.device }
        return nil
    }

    var serverInfo: ServerInfo? {
        if case .connected(let session) = connectionPhase { return session.serverInfo }
        return nil
    }

    /// Test seam: how many pings have been sent on the live connection
    /// without a corresponding `.pong` reply. Resets to zero when a pong
    /// arrives, and is automatically discarded when the connection phase
    /// leaves `.connected`. Returns zero in any non-connected phase.
    var missedPongCount: Int {
        if case .connected(let session) = connectionPhase { return session.missedPongCount }
        return 0
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
    var onConnectionStateChanged: (@ButtonHeistActor (ConnectionPhase) -> Void)?
    /// Non-lifecycle server messages delivered to TheFence for request-tracker
    /// resolution. TheHandoff forwards these without retaining semantic state.
    var onServerMessage: (@ButtonHeistActor (ServerMessage, String?) -> Void)?
    /// Transport send failures reported after Network.framework processes an enqueued write.
    var onSendFailure: (@ButtonHeistActor (DeviceSendFailure, String?) -> Void)?
    /// Recording lifecycle messages from the server. TheFence owns the
    /// client-side recording phase; TheHandoff only forwards typed messages.
    var onRecordingEvent: (@ButtonHeistActor (RecordingEvent) -> Void)?
    /// Auth approved. The parameter is the approved token, or nil when reusing a persistent session.
    var onAuthApproved: (@ButtonHeistActor (String?) -> Void)?
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
    private static let keepaliveInterval: Duration = .seconds(5)
    private static let maxMissedPongs = 6

    // MARK: - Injectable Closures

    var makeDiscovery: () -> any DeviceDiscovering = { DeviceDiscovery() }
    var makeConnection: (DiscoveredDevice, String?, String) -> any DeviceConnecting = {
        DeviceConnection(device: $0, token: $1, driverId: $2)
    }

    // MARK: - Discovery / Connection Handles

    private var discovery: (any DeviceDiscovering)?
    private var connection: (any DeviceConnecting)?

    var hasActiveDiscoverySession: Bool {
        discovery != nil
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

    init() {}

    // MARK: - Discovery

    func startDiscovery() {
        logger.info("startDiscovery called, hasSession=\(self.hasActiveDiscoverySession)")
        guard discovery == nil else {
            logger.info("Already discovering, skipping")
            return
        }

        let sessionID = UUID()
        discoveredDevices.removeAll()
        isDiscovering = false
        let activeDiscovery = makeDiscovery()
        discovery = activeDiscovery
        discoverySessionID = sessionID
        activeDiscovery.onEvent = { [weak self, sessionID] event in
            guard let self, self.isCurrentDiscoverySession(sessionID) else { return }
            switch event {
            case .found(let device):
                logger.info("Device found: \(device.name)")
                self.discoveredDevices = self.discovery?.discoveredDevices ?? []
                self.onDeviceFound?(device)
            case .lost(let device):
                logger.info("Device lost: \(device.name)")
                self.discoveredDevices = self.discovery?.discoveredDevices ?? []
                self.onDeviceLost?(device)
            case .stateChanged(let isReady):
                logger.info("Discovery state changed: isReady=\(isReady)")
                self.isDiscovering = isReady
            }
        }
        activeDiscovery.start()
        logger.info("Discovery started")
    }

    func stopDiscovery() {
        let activeDiscovery = discovery
        discoverySessionID = nil
        discovery = nil
        isDiscovering = false
        discoveredDevices = []
        activeDiscovery?.stop()
    }

    private func isCurrentDiscoverySession(_ sessionID: UUID) -> Bool {
        discoverySessionID == sessionID && discovery != nil
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

        let deadline = Date().addingTimeInterval(timeout)
        var reachableIDs: Set<String> = []
        var nextProbeAt: [String: Date] = [:]

        while Date() < deadline {
            let snapshot = discoveredDevices
            let currentIDs = Set(snapshot.map(\.id))
            reachableIDs = reachableIDs.filter { currentIDs.contains($0) }
            nextProbeAt = nextProbeAt.filter { currentIDs.contains($0.key) }

            let now = Date()
            let dueDevices = snapshot.filter { device in
                !reachableIDs.contains(device.id) &&
                    (nextProbeAt[device.id] ?? .distantPast) <= now
            }

            if !dueDevices.isEmpty {
                let probed = await withTaskGroup(of: (String, Bool).self) { group in
                    for device in dueDevices {
                        group.addTask {
                            (device.id, await device.isReachable(timeout: probeTimeout))
                        }
                    }

                    var results: [(String, Bool)] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }

                let retryAt = Date().addingTimeInterval(retryInterval)
                for (id, isReachable) in probed {
                    if isReachable {
                        reachableIDs.insert(id)
                        nextProbeAt.removeValue(forKey: id)
                    } else {
                        nextProbeAt[id] = retryAt
                    }
                }
            }

            guard await Task.cancellableSleep(for: .milliseconds(100)) else { break }
        }

        return discoveredDevices.filter { reachableIDs.contains($0.id) }
    }

    // MARK: - Connection

    @discardableResult
    func connect(to device: DiscoveredDevice, cancelReconnectTaskOnReplacement: Bool = true) -> UUID {
        disconnectForReplacement(cancelReconnectTask: cancelReconnectTaskOnReplacement)
        let attemptID = transitionToConnecting(device: device)

        connection = makeConnection(device, token, effectiveDriverId)

        connection?.onEvent = { [weak self, attemptID] event in
            guard let self else { return }
            switch event {
            case .connected:
                guard self.isActiveConnectionAttempt(attemptID) else { return }
                self.transitionToConnected(attemptID: attemptID, device: device)
            case .disconnected(let reason):
                guard self.isActiveConnectionAttempt(attemptID) else { return }
                if case .failed = self.connectionPhase {
                    return
                }
                guard self.transitionToDisconnected(reason: reason, attemptID: attemptID) else { return }
                if reason.retryable {
                    self.scheduleAutoReconnectIfNeeded(disconnectedDevice: device)
                }
            case .sendFailed(let failure, let requestId):
                guard self.isActiveConnectionAttempt(attemptID) else { return }
                self.onSendFailure?(failure, requestId)
            case .message(let message, let requestId, let accessibilityTrace):
                guard self.isActiveConnectionAttempt(attemptID) else { return }
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
            mutateConnectedSession { $0.serverInfo = info }
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
                transitionToFailed(.disconnected(.authFailed(serverError.message)))
            case .authApprovalPending:
                transitionToFailed(.disconnected(.authApprovalPending(serverError.message)))
            default:
                if let requestId {
                    forwardServerMessage(message, requestId: requestId)
                } else {
                    transitionToFailed(.connectionFailed(serverError.message))
                }
            }
        case .authApproved(let payload):
            token = payload.token
            onAuthApproved?(payload.token)
        case .authApprovalPending(let payload):
            connectionAttemptFailure = .disconnected(.authApprovalPending(payload.message))
            onStatus?(payload.hint)
        case .sessionLocked(let payload):
            transitionToFailed(.disconnected(.sessionLocked(payload.message)))
        case .status(let payload):
            logger.info("Received status payload: appName=\(payload.identity.appName, privacy: .public)")
        case .protocolMismatch(let payload):
            transitionToFailed(.disconnected(.buttonHeistVersionMismatch(
                serverVersion: payload.serverButtonHeistVersion,
                clientVersion: payload.clientButtonHeistVersion
            )))
        case .pong:
            mutateConnectedSession { $0.missedPongCount = 0 }
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
        if case .enabled(let filter, _, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, target: nil, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil
        transitionToDisconnected()
    }

    @discardableResult
    private func disconnectForReplacement(cancelReconnectTask: Bool = true) -> Bool {
        let hadActiveSession = activeConnectionAttemptID != nil
        if cancelReconnectTask, case .enabled(let filter, _, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, target: nil, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil

        if hadActiveSession {
            transitionToDisconnected(reason: .localDisconnect)
        } else {
            transitionToDisconnected()
        }
        return hadActiveSession
    }

    func disableAutoReconnect() {
        if case .enabled(_, _, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
        }
        reconnectPolicy = .disabled
    }

    /// Suspend until the connection phase transitions to `.connected` (returns),
    /// `.failed` (throws the mapped `ConnectionError`), or `.disconnected`
    /// (throws `ConnectionError.connectionFailed`). If the phase is already
    /// terminal at call time, returns or throws immediately without suspending.
    ///
    /// The `timeout` is enforced by scheduling a cancellable timeout task that
    /// fails only this registered waiter with `ConnectionError.timeout`.
    /// Cancelling the calling task aborts the wait and propagates
    /// `CancellationError`.
    func waitForConnectionResult(timeout: TimeInterval) async throws {
        let attemptID: UUID
        // Fast path: already terminal.
        switch connectionPhase {
        case .connected:
            return
        case .failed(let failure):
            throw failure
        case .disconnected:
            if let failure = connectionAttemptFailure {
                throw failure
            }
            throw ConnectionError.connectionFailed(
                "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
            )
        case .connecting(let attempt):
            attemptID = attempt.id
        }

        let waiterID = UUID()
        let timeoutDuration: Duration = .seconds(max(timeout, 0))
        let timeoutTask = Task { @ButtonHeistActor [weak self] in
            guard await Task.cancellableSleep(for: timeoutDuration) else { return }
            self?.failPhaseAwaiterWithTimeout(id: waiterID, attemptID: attemptID)
        }
        defer { timeoutTask.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Early-cancel guard: if the calling task was already cancelled
                // before we registered the continuation, the cancellation
                // handler may have already run against an empty awaiter list.
                // Resume immediately rather than appending an orphaned
                // continuation that would only resolve on phase transition or
                // timeout.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard activeConnectionAttemptID == attemptID else {
                    continuation.resume(throwing: ConnectionError.connectionFailed(
                        "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
                    ))
                    return
                }
                phaseAwaiters[waiterID] = PhaseAwaiter(attemptID: attemptID, continuation: continuation)
            }
        } onCancel: {
            Task { @ButtonHeistActor [weak self] in
                self?.cancelPhaseAwaiter(id: waiterID)
            }
        }
    }

    /// Resume one registered awaiter with a `CancellationError`. Called
    /// from the cancellation handler of `waitForConnectionResult`.
    private func cancelPhaseAwaiter(id: UUID) {
        guard let awaiter = phaseAwaiters.removeValue(forKey: id) else { return }
        awaiter.continuation.resume(throwing: CancellationError())
    }

    /// Resume one registered awaiter with `ConnectionError.timeout`. Scheduled by
    /// `waitForConnectionResult` and runs on the actor when the timeout
    /// duration elapses without a phase transition.
    private func failPhaseAwaiterWithTimeout(id: UUID, attemptID: UUID) {
        let failure = ConnectionError.timeout
        guard let awaiter = phaseAwaiters.removeValue(forKey: id), awaiter.attemptID == attemptID else { return }
        awaiter.continuation.resume(throwing: failure)
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    func forceDisconnect() {
        guard isConnected else { return }
        logger.warning("Force-disconnecting stale connection")
        let reconnectDevice = connectedDevice
        if case .enabled(let filter, _, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, target: nil, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil
        transitionToDisconnected(reason: .localDisconnect)
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
        guard case .connected(var session) = connectionPhase else { return 0 }
        connection?.send(.ping)
        session.missedPongCount += 1
        let count = session.missedPongCount
        connectionPhase = .connected(session)
        return count
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
            if let connectionError = error as? ConnectionError {
                connectionAttemptFailure = connectionError
            }
            throw error
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        let attemptID = connect(to: device)
        do {
            try await waitForConnectionResult(timeout: timeout)
        } catch let error as ConnectionError where error == .timeout {
            disconnectConnectionAttempt(attemptID, failure: .timeout)
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

    /// Set up auto-reconnect: when disconnected, poll for the device and reconnect.
    /// Makes 60 attempts at 1s intervals before giving up.
    func setupAutoReconnect(filter: String?) {
        switch reconnectPolicy {
        case .disabled:
            reconnectPolicy = .enabled(filter: filter, target: nil, reconnectTask: nil)
        case .enabled(let currentFilter, _, let reconnectTask):
            guard currentFilter != filter else { return }
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, target: nil, reconnectTask: nil)
        }
    }

    private func scheduleAutoReconnectIfNeeded(disconnectedDevice: DiscoveredDevice) {
        guard case .enabled(let filter, let existingTarget, let existingReconnectTask) = reconnectPolicy else {
            return
        }
        // A running reconnect loop owns retries for its target. A failed
        // attempt must not cancel or replace that runner from inside its own
        // disconnect callback.
        guard existingReconnectTask == nil else { return }

        let target = existingTarget ?? ReconnectTarget(filter: filter, device: disconnectedDevice)
        let reconnectTask = Task<Void, Never> { [weak self, target] in
            await self?.runAutoReconnect(target: target)
        }
        reconnectPolicy = .enabled(filter: filter, target: target, reconnectTask: reconnectTask)
    }

    private func runAutoReconnect(target: ReconnectTarget) async {
        onStatus?("Device disconnected — watching for reconnection...")
        var consecutiveMisses = 0
        for _ in 0..<reconnectMaxAttempts {
            guard !Task.isCancelled else { return }
            guard isAutoReconnectCurrent(target: target) else { return }
            // Backoff grows while no device is visible; resets after each connection attempt
            let delay = min(reconnectInterval * pow(2.0, Double(min(consecutiveMisses, 5))), 30.0)
            let jitter = Double.random(in: 0...(delay * 0.2))
            guard await Task.cancellableSleep(for: .seconds(delay + jitter)) else { return }
            guard !Task.isCancelled else { return }
            guard isAutoReconnectCurrent(target: target) else { return }
            if let device = target.resolve(from: discoveredDevices) {
                consecutiveMisses = 0
                onStatus?("Reconnecting to \(device.name)...")
                let attemptID = connect(to: device, cancelReconnectTaskOnReplacement: false)
                do {
                    try await waitForConnectionResult(timeout: reconnectAttemptTimeout)
                } catch let error as ConnectionError where error == .timeout {
                    disconnectConnectionAttempt(attemptID, failure: .timeout)
                } catch is CancellationError {
                    return
                } catch {
                    // The connection event already moved the phase; continue bounded retries.
                }
                if Task.isCancelled { return }
                if isConnected {
                    onStatus?("Reconnected to \(device.name)")
                    if isAutoReconnectCurrent(target: target) {
                        reconnectPolicy = .enabled(filter: target.filter, target: target, reconnectTask: nil)
                    }
                    return
                }
            } else {
                consecutiveMisses += 1
            }
        }
        let failure = ConnectionError.connectionFailed(
            "Auto-reconnect gave up after \(reconnectMaxAttempts) attempts to \(target.displayName). Retry the connection or choose a new target."
        )
        onStatus?(failure.errorDescription ?? "Auto-reconnect gave up")
        guard isAutoReconnectCurrent(target: target) else { return }
        reconnectPolicy = .disabled
        transitionToFailed(failure)
    }

    private func isAutoReconnectCurrent(target: ReconnectTarget) -> Bool {
        guard case .enabled(_, let currentTarget?, _) = reconnectPolicy else { return false }
        return currentTarget == target
    }

    // MARK: - Display Names

    /// Compute display name with disambiguation when multiple devices have the same app
    func displayName(for device: DiscoveredDevice) -> String {
        let appName = device.appName

        let sameAppDevices = discoveredDevices.filter { $0.appName == appName }

        if sameAppDevices.count > 1 {
            let sameAppAndDevice = sameAppDevices.filter { $0.deviceName == device.deviceName }
            if sameAppAndDevice.count > 1, let shortId = device.shortId {
                return "\(appName) (\(device.deviceName)) [\(shortId)]"
            }
            return "\(appName) (\(device.deviceName))"
        } else {
            return appName
        }
    }
}

// MARK: - ReconnectPolicy Equatable (filter-only, tasks excluded)

extension TheHandoff.ReconnectPolicy: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled):
            return true
        case (.enabled(let lhsFilter, let lhsTarget, _), .enabled(let rhsFilter, let rhsTarget, _)):
            return lhsFilter == rhsFilter && lhsTarget == rhsTarget
        default:
            return false
        }
    }
}

private extension DiscoveredDevice {
    var reconnectsWithoutDiscovery: Bool {
        if case .hostPort = endpoint {
            return true
        }
        return false
    }
}
