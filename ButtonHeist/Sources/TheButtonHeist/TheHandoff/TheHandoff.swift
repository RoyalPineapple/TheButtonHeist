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
    /// `.failed`: the phase-producing cases are `connectionFailed`,
    /// `disconnected`, `authFailed`, and `sessionLocked`; the resolver/timeout cases
    /// (`timeout`, `noDeviceFound`, `noMatchingDevice`) are thrown directly
    /// from `DeviceResolver`/`waitForConnectionResult` and never become a
    /// phase value.
    enum ConnectionError: Error, LocalizedError, Equatable {
        case connectionFailed(String)
        case disconnected(DisconnectReason)
        case authFailed(String)
        case sessionLocked(String)
        case timeout
        case noDeviceFound
        case noMatchingDevice(filter: String, available: [String])

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let message): return message
            case .disconnected(let reason): return reason.connectionFailureMessage
            case .authFailed(let reason): return "Authentication failed: \(reason)"
            case .sessionLocked(let message): return "Session locked: \(message)"
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
            case .authFailed:
                return "auth.failed"
            case .sessionLocked:
                return "session.locked"
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
            case .authFailed:
                return .authentication
            case .sessionLocked:
                return .session
            case .timeout:
                return .setup
            case .noDeviceFound, .noMatchingDevice:
                return .discovery
            }
        }

        var retryable: Bool {
            switch self {
            case .connectionFailed, .sessionLocked, .timeout, .noDeviceFound:
                return true
            case .disconnected(let reason):
                return reason.retryable
            case .authFailed, .noMatchingDevice:
                return false
            }
        }

        var hint: String? {
            switch self {
            case .connectionFailed:
                return "Check that the app is running and reachable, then retry."
            case .disconnected(let reason):
                return reason.hint
            case .authFailed:
                return "Retry without a token to request a fresh session."
            case .sessionLocked:
                return "Wait for the current driver to disconnect or for the session to time out. " +
                    "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
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
    /// session-scoped data that only makes sense during a live connection.
    /// Bundling these into the phase makes "connected but no server info" a
    /// transient inner state rather than a sibling-of-phase race.
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
        var currentInterface: Interface?
        var currentScreen: ScreenPayload?
        var recordingPhase: RecordingPhase
        var missedPongCount: Int

        init(
            attemptID: UUID,
            device: DiscoveredDevice,
            keepaliveTask: Task<Void, Never>,
            serverInfo: ServerInfo? = nil,
            currentInterface: Interface? = nil,
            currentScreen: ScreenPayload? = nil,
            recordingPhase: RecordingPhase = .idle,
            missedPongCount: Int = 0
        ) {
            self.attemptID = attemptID
            self.device = device
            self.keepaliveTask = keepaliveTask
            self.serverInfo = serverInfo
            self.currentInterface = currentInterface
            self.currentScreen = currentScreen
            self.recordingPhase = recordingPhase
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

    /// Whether auto-reconnect fires on disconnect. The reconnect task lives
    /// inside `.enabled` because it only runs when the policy is active and
    /// a disconnect has occurred.
    enum ReconnectPolicy {
        case disabled
        case enabled(filter: String?, reconnectTask: Task<Void, Never>?)
    }

    /// Recording lifecycle state machine. Replaces the old `isRecording: Bool`
    /// so the type system distinguishes idle from active recording.
    enum RecordingPhase: Equatable {
        case idle
        case recording
    }

    // MARK: - State

    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isDiscovering: Bool = false
    private(set) var connectionPhase: ConnectionPhase = .disconnected
    private(set) var reconnectPolicy: ReconnectPolicy = .disabled
    private var connectionAttemptFailure: ConnectionError?
    private var terminalConnectionAttemptID: UUID?

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

    private func isCurrentOrTerminalConnectionAttempt(_ attemptID: UUID) -> Bool {
        if isActiveConnectionAttempt(attemptID) { return true }
        if terminalConnectionAttemptID == attemptID { return true }
        return false
    }

    private func transitionToConnecting(device: DiscoveredDevice) -> UUID {
        let attempt = ConnectionAttempt(id: UUID(), device: device)
        connectionAttemptFailure = nil
        terminalConnectionAttemptID = nil
        connectionPhase = .connecting(attempt)
        return attempt.id
    }

    private func transitionToConnected(attemptID: UUID, device: DiscoveredDevice) {
        guard case .connecting(let attempt) = connectionPhase, attempt.id == attemptID else { return }
        let keepaliveTask = makeKeepaliveTask()
        connectionAttemptFailure = nil
        terminalConnectionAttemptID = nil
        connectionPhase = .connected(ConnectedSession(attemptID: attemptID, device: device, keepaliveTask: keepaliveTask))
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
        connectionPhase = .failed(failure)
        terminalConnectionAttemptID = attemptID
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
        connectionPhase = .disconnected
        terminalConnectionAttemptID = attemptID
        if wasActive {
            if let reason {
                let failure = ConnectionError.disconnected(reason)
                connectionAttemptFailure = failure
                if let attemptID {
                    resumePhaseAwaiters(for: attemptID, with: .failure(failure))
                }
            } else {
                let failure = ConnectionError.connectionFailed(
                    "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
                )
                if let attemptID {
                    resumePhaseAwaiters(for: attemptID, with: .failure(failure))
                }
            }
        } else if reason == nil {
            // No active transition and no new cause: clear any stale attempt cause.
            // If a cause arrives after the first disconnect, keep the original cause
            // because it is the one waitForConnectionResult reports on the fast path.
            connectionAttemptFailure = nil
        }
        return wasActive
    }

    /// Tear down an in-flight connection attempt after its owner reaches a setup
    /// terminal state (for example, discovery/direct-connect timeout). This
    /// intentionally does not call `onDisconnected` or schedule reconnect:
    /// there was no usable session drop, only a failed setup attempt.
    func disconnectConnectionAttempt(_ attemptID: UUID, failure: ConnectionError) {
        guard activeConnectionAttemptID == attemptID else { return }
        connectionAttemptFailure = failure
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        connection?.disconnect()
        connection = nil
        connectionPhase = .disconnected
        terminalConnectionAttemptID = attemptID
        resumePhaseAwaiters(for: attemptID, with: .failure(failure))
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

    var connectionPhaseName: String {
        switch connectionPhase {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed:
            return "failed"
        }
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

    var currentInterface: Interface? {
        if case .connected(let session) = connectionPhase { return session.currentInterface }
        return nil
    }

    var currentScreen: ScreenPayload? {
        if case .connected(let session) = connectionPhase { return session.currentScreen }
        return nil
    }

    var recordingPhase: RecordingPhase {
        if case .connected(let session) = connectionPhase { return session.recordingPhase }
        return .idle
    }

    /// Test seam: how many pings have been sent on the live connection
    /// without a corresponding `.pong` reply. Resets to zero when a pong
    /// arrives, and is automatically discarded when the connection phase
    /// leaves `.connected`. Returns zero in any non-connected phase.
    var missedPongCount: Int {
        if case .connected(let session) = connectionPhase { return session.missedPongCount }
        return 0
    }

    var isRecording: Bool {
        recordingPhase == .recording
    }

    // MARK: - Discovery Callbacks

    // All callbacks below fire on `@ButtonHeistActor`.

    /// A device matching the filter appeared on the network.
    var onDeviceFound: (@ButtonHeistActor (DiscoveredDevice) -> Void)?
    /// A previously-known device is no longer advertising.
    var onDeviceLost: (@ButtonHeistActor (DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    /// Handshake completed successfully; `ServerInfo` carries server version + capabilities.
    var onConnected: (@ButtonHeistActor (ServerInfo) -> Void)?
    /// The connection has dropped. `DisconnectReason` indicates whether this was local, remote, or error-driven.
    var onDisconnected: (@ButtonHeistActor (DisconnectReason) -> Void)?
    /// A `get_interface` response arrived. The trailing `String?` is the originating requestId (nil for unsolicited pushes).
    var onInterface: (@ButtonHeistActor (Interface, String?) -> Void)?
    /// An action command (tap, swipe, type, etc.) produced a result. Trailing `String?` is the originating requestId.
    var onActionResult: (@ButtonHeistActor (ActionResult, String?) -> Void)?
    /// A `get_screen` response arrived. Trailing `String?` is the originating requestId.
    var onScreen: (@ButtonHeistActor (ScreenPayload, String?) -> Void)?
    /// The server acknowledged that screen recording has begun.
    var onRecordingStarted: (@ButtonHeistActor () -> Void)?
    /// A completed recording is delivered (as base64 payload + metadata).
    var onRecording: (@ButtonHeistActor (RecordingPayload) -> Void)?
    /// Recording failed mid-capture; the string is the server-reported reason.
    var onRecordingError: (@ButtonHeistActor (String) -> Void)?
    /// General protocol/transport error reported by the server.
    var onError: (@ButtonHeistActor (String) -> Void)?
    /// Error response for a specific in-flight request.
    var onRequestError: (@ButtonHeistActor (ServerError, String) -> Void)?
    /// Auth approved. The parameter is the approved token, or nil when reusing a persistent session.
    var onAuthApproved: (@ButtonHeistActor (String?) -> Void)?
    /// Another agent currently owns the session. Payload carries details for the operator to resolve.
    var onSessionLocked: (@ButtonHeistActor (SessionLockedPayload) -> Void)?
    /// Auth rejected by server; the string is the reason.
    var onAuthFailed: (@ButtonHeistActor (String) -> Void)?
    /// A user interaction event (tap, swipe) captured on the device.
    var onInteraction: (@ButtonHeistActor (InteractionEvent) -> Void)?
    /// The server pushed an interface delta between commands (the UI changed
    /// without a direct action request). Drained by `TheFence` for session state.
    var onBackgroundDelta: (@ButtonHeistActor (AccessibilityTrace.Delta) -> Void)?
    /// The server pushed capture receipts for an interface change observed
    /// between commands. This is the source-of-truth form; `onBackgroundDelta`
    /// remains as a legacy compatibility projection.
    var onBackgroundAccessibilityTrace: (@ButtonHeistActor (AccessibilityTrace) -> Void)?

    // MARK: - Configuration

    var token: String?
    var observeMode: Bool = false
    /// Explicit driver ID override (e.g. from BUTTONHEIST_DRIVER_ID env var).
    /// When nil, a persistent auto-generated ID is used instead.
    var driverId: String?
    var autoSubscribe: Bool = true

    // MARK: - Internal Reconnect Settings

    /// Interval between auto-reconnect attempts. Default is 1 second.
    var reconnectInterval: TimeInterval = 1.0
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
    private var connectionAutoSubscribe: Bool = true

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

        discoveredDevices.removeAll()
        discovery = makeDiscovery()
        discovery?.onEvent = { [weak self] event in
            guard let self else { return }
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
        discovery?.start()
        logger.info("Discovery started")
    }

    func stopDiscovery() {
        discovery?.stop()
        discovery = nil
        isDiscovering = false
        discoveredDevices = []
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
    func connect(to device: DiscoveredDevice, autoSubscribe: Bool? = nil) -> UUID {
        disconnectForReplacement()
        connectionAutoSubscribe = autoSubscribe ?? self.autoSubscribe
        let attemptID = transitionToConnecting(device: device)

        connection = makeConnection(device, token, effectiveDriverId)
        connection?.observeMode = observeMode

        connection?.onEvent = { [weak self, attemptID] event in
            guard let self else { return }
            switch event {
            // Transport-up signal is informational; the `.connected` event drives state transitions and external callbacks.
            case .transportReady:
                guard self.isActiveConnectionAttempt(attemptID) else { return }
                return
            case .connected:
                guard self.isActiveConnectionAttempt(attemptID) else { return }
                self.transitionToConnected(attemptID: attemptID, device: device)
            case .disconnected(let reason):
                guard self.isCurrentOrTerminalConnectionAttempt(attemptID) else { return }
                if case .failed = self.connectionPhase {
                    self.onDisconnected?(reason)
                    return
                }
                guard self.transitionToDisconnected(reason: reason, attemptID: attemptID) else { return }
                self.onDisconnected?(reason)
                if reason.retryable, case .enabled(let filter, let existingReconnectTask) = self.reconnectPolicy {
                    existingReconnectTask?.cancel()
                    let reconnectTask = Task<Void, Never> { [weak self] in
                        await self?.runAutoReconnect(filter: filter)
                    }
                    self.reconnectPolicy = .enabled(filter: filter, reconnectTask: reconnectTask)
                }
            case .message(let message, let requestId, let backgroundAccessibilityDelta, let accessibilityTrace):
                if self.isActiveConnectionAttempt(attemptID) {
                    self.handleServerMessage(
                        message,
                        requestId: requestId,
                        backgroundAccessibilityDelta: backgroundAccessibilityDelta,
                        accessibilityTrace: accessibilityTrace
                    )
                    return
                }
                guard let requestId, self.isCurrentOrTerminalConnectionAttempt(attemptID) else { return }
                self.handleTerminalRequestMessage(message, requestId: requestId)
            }
        }

        connection?.connect()
        return attemptID
    }

    private func handleTerminalRequestMessage(_ message: ServerMessage, requestId: String) {
        switch message {
        case .interface(let payload):
            onInterface?(payload, requestId)
        case .actionResult(let result):
            onActionResult?(result, requestId)
        case .screen(let payload):
            onScreen?(payload, requestId)
        case .error(let serverError):
            onRequestError?(serverError, requestId)
        // Terminal request recovery only completes request-scoped trackers; state-mutating messages are consumed while active.
        // swiftlint:disable:next agent_wire_message_arm_no_op_break
        case .info, .recordingStarted, .recording, .authApproved, .sessionLocked, .interaction, .status,
             .protocolMismatch, .pong, .recordingStopped, .serverHello, .authRequired:
            break
        }
    }

    func handleServerMessage(
        _ message: ServerMessage,
        requestId: String?,
        backgroundAccessibilityDelta: AccessibilityTrace.Delta? = nil,
        accessibilityTrace: AccessibilityTrace? = nil
    ) {
        handleBackgroundAccessibility(
            delta: backgroundAccessibilityDelta,
            accessibilityTrace: accessibilityTrace
        )
        switch message {
        case .info(let info):
            mutateConnectedSession { $0.serverInfo = info }
            if connectionAutoSubscribe {
                connection?.send(.subscribe)
                connection?.send(.requestInterface)
            }
            onConnected?(info)
        case .interface(let payload):
            if requestId == nil {
                mutateConnectedSession { $0.currentInterface = payload }
            }
            onInterface?(payload, requestId)
        case .actionResult(let result):
            onActionResult?(result, requestId)
        case .screen(let payload):
            if requestId == nil {
                mutateConnectedSession { $0.currentScreen = payload }
            }
            onScreen?(payload, requestId)
        case .recordingStarted:
            mutateConnectedSession { $0.recordingPhase = .recording }
            onRecordingStarted?()
        case .recording(let payload):
            mutateConnectedSession { $0.recordingPhase = .idle }
            onRecording?(payload)
        case .error(let serverError):
            switch serverError.kind {
            case .recording:
                mutateConnectedSession { $0.recordingPhase = .idle }
                onRecordingError?(serverError.message)
            case .authFailure:
                transitionToFailed(.authFailed(serverError.message))
                onAuthFailed?(serverError.message)
            default:
                if let requestId {
                    onRequestError?(serverError, requestId)
                } else {
                    transitionToFailed(.connectionFailed(serverError.message))
                    onError?(serverError.message)
                }
            }
        case .authApproved(let payload):
            token = payload.token
            onAuthApproved?(payload.token)
        case .sessionLocked(let payload):
            transitionToFailed(.sessionLocked(payload.message))
            onSessionLocked?(payload)
        case .interaction(let event):
            onInteraction?(event)
        case .status(let payload):
            logger.info("Received status payload: appName=\(payload.identity.appName, privacy: .public)")
        case .protocolMismatch(let payload):
            let message = "buttonHeistVersion mismatch: server=\(payload.serverButtonHeistVersion), client=\(payload.clientButtonHeistVersion)"
            transitionToFailed(.disconnected(.protocolMismatch(message)))
            onError?(message)
        case .pong:
            mutateConnectedSession { $0.missedPongCount = 0 }
        case .recordingStopped:
            mutateConnectedSession { $0.recordingPhase = .idle }
        // Handshake messages are consumed inside DeviceConnection before bubbling here; no caller-visible side effect needed at this layer.
        // swiftlint:disable:next agent_wire_message_arm_no_op_break
        case .serverHello, .authRequired:
            break
        }
    }

    private func handleBackgroundAccessibility(
        delta: AccessibilityTrace.Delta?,
        accessibilityTrace: AccessibilityTrace?
    ) {
        if let accessibilityTrace {
            if let onBackgroundAccessibilityTrace {
                onBackgroundAccessibilityTrace(accessibilityTrace)
            } else if let projectedDelta = accessibilityTrace.captureReceiptDelta ?? delta {
                onBackgroundDelta?(projectedDelta)
            }
            return
        }
        if let delta {
            onBackgroundDelta?(delta)
        }
    }

    func disconnect() {
        if case .enabled(let filter, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil
        transitionToDisconnected()
    }

    @discardableResult
    private func disconnectForReplacement() -> Bool {
        let hadActiveSession = activeConnectionAttemptID != nil
        if case .enabled(let filter, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil

        if hadActiveSession {
            transitionToDisconnected(reason: .localDisconnect)
            onDisconnected?(.localDisconnect)
        } else {
            transitionToDisconnected()
        }
        return hadActiveSession
    }

    func disableAutoReconnect() {
        if case .enabled(_, let reconnectTask) = reconnectPolicy {
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
        disconnect()
        onDisconnected?(.localDisconnect)
        if case .enabled(let filter, let existingReconnectTask) = reconnectPolicy {
            existingReconnectTask?.cancel()
            let reconnectTask = Task<Void, Never> { [weak self] in
                await self?.runAutoReconnect(filter: filter)
            }
            reconnectPolicy = .enabled(filter: filter, reconnectTask: reconnectTask)
        }
    }

    // MARK: - Commands

    func send(_ message: ClientMessage, requestId: String? = nil) {
        connection?.send(message, requestId: requestId)
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
    /// or the timeout expires. Suspends on `waitForConnectionResult` for the
    /// connection outcome.
    func connectWithDiscovery(
        filter: String?,
        timeout: TimeInterval = 30,
        autoSubscribe: Bool? = nil
    ) async throws {
        disconnectForReplacement()
        onStatus?("Searching for iOS devices...")
        let startedDiscovery = !hasActiveDiscoverySession
        if startedDiscovery { startDiscovery() }

        let discoveryTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        let device: DiscoveredDevice
        do {
            device = try await resolveReachableDevice(filter: filter, discoveryTimeout: discoveryTimeout)
        } catch {
            if startedDiscovery { stopDiscovery() }
            if let connectionError = error as? ConnectionError {
                connectionAttemptFailure = connectionError
            }
            throw error
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        let attemptID = connect(to: device, autoSubscribe: autoSubscribe)
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
        discoveryTimeout: UInt64
    ) async throws -> DiscoveredDevice {
        let resolver = DeviceResolver(
            filter: filter,
            discoveryTimeout: discoveryTimeout,
            getDiscoveredDevices: { [weak self] in self?.discoveredDevices ?? [] }
        )
        return try await resolver.resolve()
    }

    /// Set up auto-reconnect: when disconnected, poll for the device and reconnect.
    /// Makes 60 attempts at 1s intervals before giving up.
    func setupAutoReconnect(filter: String?) {
        switch reconnectPolicy {
        case .disabled:
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        case .enabled(let currentFilter, let reconnectTask):
            guard currentFilter != filter else { return }
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        }
    }

    private func runAutoReconnect(filter: String?) async {
        onStatus?("Device disconnected — watching for reconnection...")
        var consecutiveMisses = 0
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            guard isAutoReconnectCurrent(filter: filter) else { return }
            // Backoff grows while no device is visible; resets after each connection attempt
            let delay = min(reconnectInterval * pow(2.0, Double(min(consecutiveMisses, 5))), 30.0)
            let jitter = Double.random(in: 0...(delay * 0.2))
            guard await Task.cancellableSleep(for: .seconds(delay + jitter)) else { return }
            guard !Task.isCancelled else { return }
            guard isAutoReconnectCurrent(filter: filter) else { return }
            if let device = discoveredDevices.first(matching: filter) {
                consecutiveMisses = 0
                onStatus?("Reconnecting to \(device.name)...")
                connect(to: device)
                let deadline = Date().addingTimeInterval(10)
                while !isConnected {
                    if Task.isCancelled || Date() > deadline { break }
                    guard await Task.cancellableSleep(for: .milliseconds(100)) else { return }
                }
                if Task.isCancelled { return }
                if isConnected {
                    onStatus?("Reconnected to \(device.name)")
                    return
                }
            } else {
                consecutiveMisses += 1
            }
        }
        onStatus?("Auto-reconnect gave up after 60 attempts")
        reconnectPolicy = .disabled
    }

    private func isAutoReconnectCurrent(filter: String?) -> Bool {
        guard case .enabled(let currentFilter, _) = reconnectPolicy else { return false }
        return currentFilter == filter
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
        case (.enabled(let lhsFilter, _), .enabled(let rhsFilter, _)):
            return lhsFilter == rhsFilter
        default:
            return false
        }
    }
}
