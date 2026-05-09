import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "handoff")

/// Client-side session manager that owns the full device lifecycle:
/// discovery, connection, keepalive, and auto-reconnect.
///
/// TheFence owns a TheHandoff and delegates connection management here.
/// All discovery, connection, keepalive, and reconnect logic lives here.
@ButtonHeistActor
public final class TheHandoff {

    // MARK: - State Machine Types

    /// Why a connection attempt failed. TheHandoff's own error type —
    /// callers (TheFence) map this to their error domain at the boundary.
    public enum ConnectionError: Error, LocalizedError {
        case connectionFailed(String)
        case authFailed(String)
        case sessionLocked(String)
        case timeout
        case noDeviceFound
        case noMatchingDevice(filter: String, available: [String])

        public var errorDescription: String? {
            switch self {
            case .connectionFailed(let message): return message
            case .authFailed(let reason): return "Authentication failed: \(reason)"
            case .sessionLocked(let message): return "Session locked: \(message)"
            case .timeout: return "Connection timed out"
            case .noDeviceFound: return "No device found"
            case .noMatchingDevice(let filter, let available):
                return "No device matching '\(filter)' (available: \(available.joined(separator: ", ")))"
            }
        }
    }

    /// Why a connection failed — used as the associated value in ConnectionPhase.failed.
    public enum ConnectionFailure: Equatable {
        case error(String)
        case authFailed(String)
        case sessionLocked(String)

        var asConnectionError: ConnectionError {
            switch self {
            case .error(let message): return .connectionFailed(message)
            case .authFailed(let reason): return .authFailed(reason)
            case .sessionLocked(let message): return .sessionLocked(message)
            }
        }
    }

    /// State carried while connected: device, keepalive task, and the
    /// session-scoped data that only makes sense during a live connection.
    /// Bundling these into the phase makes "connected but no server info" a
    /// transient inner state rather than a sibling-of-phase race.
    public struct ConnectedSession {
        public let device: DiscoveredDevice
        let keepaliveTask: Task<Void, Never>
        public var serverInfo: ServerInfo?
        public var currentInterface: Interface?
        public var currentScreen: ScreenPayload?
        public var recordingPhase: RecordingPhase

        init(
            device: DiscoveredDevice,
            keepaliveTask: Task<Void, Never>,
            serverInfo: ServerInfo? = nil,
            currentInterface: Interface? = nil,
            currentScreen: ScreenPayload? = nil,
            recordingPhase: RecordingPhase = .idle
        ) {
            self.device = device
            self.keepaliveTask = keepaliveTask
            self.serverInfo = serverInfo
            self.currentInterface = currentInterface
            self.currentScreen = currentScreen
            self.recordingPhase = recordingPhase
        }
    }

    /// Explicit connection lifecycle state machine. The device is carried in
    /// `.connecting` and `.connected` so `connectedDevice` cannot drift from
    /// the phase — impossible states like "connected but no device" are
    /// unrepresentable. `.connected` carries the full session payload so
    /// session-scoped data clears automatically on transition.
    public enum ConnectionPhase {
        case disconnected
        case connecting(device: DiscoveredDevice)
        case connected(ConnectedSession)
        case failed(ConnectionFailure)
    }

    /// Whether auto-reconnect fires on disconnect. The reconnect task lives
    /// inside `.enabled` because it only runs when the policy is active and
    /// a disconnect has occurred.
    public enum ReconnectPolicy {
        case disabled
        case enabled(filter: String?, reconnectTask: Task<Void, Never>?)
    }

    /// Recording lifecycle state machine. Replaces the old `isRecording: Bool`
    /// so the type system distinguishes idle from active recording.
    public enum RecordingPhase: Equatable {
        case idle
        case recording
    }

    // MARK: - State

    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var isDiscovering: Bool = false
    public private(set) var connectionPhase: ConnectionPhase = .disconnected
    public private(set) var reconnectPolicy: ReconnectPolicy = .disabled
    private var missedPongCount: Int = 0

    /// Continuations awaiting a terminal connection-phase transition. Each
    /// continuation is resumed exactly once when the phase next becomes
    /// `.connected`, `.failed`, or `.disconnected`. Resumption clears the
    /// list so a subsequent transition sees no stale awaiters.
    private var phaseAwaiters: [CheckedContinuation<Void, Error>] = []

    // MARK: - State Transitions

    private func transitionToConnecting(device: DiscoveredDevice) {
        connectionPhase = .connecting(device: device)
    }

    private func transitionToConnected(device: DiscoveredDevice, keepaliveTask: Task<Void, Never>) {
        connectionPhase = .connected(ConnectedSession(device: device, keepaliveTask: keepaliveTask))
        resumePhaseAwaiters(with: .success(()))
    }

    private func transitionToFailed(_ failure: ConnectionFailure) {
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        connectionPhase = .failed(failure)
        resumePhaseAwaiters(with: .failure(failure.asConnectionError))
    }

    private func transitionToDisconnected() {
        if case .connected(let session) = connectionPhase {
            session.keepaliveTask.cancel()
        }
        connectionPhase = .disconnected
        resumePhaseAwaiters(
            with: .failure(ConnectionError.connectionFailed(
                "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
            ))
        )
    }

    private func resumePhaseAwaiters(with result: Result<Void, Error>) {
        let waiters = phaseAwaiters
        phaseAwaiters = []
        for continuation in waiters {
            continuation.resume(with: result)
        }
    }

    /// Mutate the connected session in place. No-op when not connected.
    private func mutateConnectedSession(_ body: (inout ConnectedSession) -> Void) {
        guard case .connected(var session) = connectionPhase else { return }
        body(&session)
        connectionPhase = .connected(session)
    }

    // MARK: - Derived State

    public var isConnected: Bool {
        if case .connected = connectionPhase { return true }
        return false
    }

    public var connectedDevice: DiscoveredDevice? {
        if case .connected(let session) = connectionPhase { return session.device }
        return nil
    }

    public var serverInfo: ServerInfo? {
        if case .connected(let session) = connectionPhase { return session.serverInfo }
        return nil
    }

    public var currentInterface: Interface? {
        if case .connected(let session) = connectionPhase { return session.currentInterface }
        return nil
    }

    public var currentScreen: ScreenPayload? {
        if case .connected(let session) = connectionPhase { return session.currentScreen }
        return nil
    }

    public var recordingPhase: RecordingPhase {
        if case .connected(let session) = connectionPhase { return session.recordingPhase }
        return .idle
    }

    public var isRecording: Bool {
        recordingPhase == .recording
    }

    // MARK: - Discovery Callbacks

    // All callbacks below fire on `@ButtonHeistActor`.

    /// A device matching the filter appeared on the network.
    public var onDeviceFound: ((DiscoveredDevice) -> Void)?
    /// A previously-known device is no longer advertising.
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    /// Handshake completed successfully; `ServerInfo` carries server version + capabilities.
    public var onConnected: ((ServerInfo) -> Void)?
    /// The connection has dropped. `DisconnectReason` indicates whether this was local, remote, or error-driven.
    public var onDisconnected: ((DisconnectReason) -> Void)?
    /// A `get_interface` response arrived. The trailing `String?` is the originating requestId (nil for unsolicited pushes).
    public var onInterface: ((Interface, String?) -> Void)?
    /// An action command (tap, swipe, type, etc.) produced a result. Trailing `String?` is the originating requestId.
    public var onActionResult: ((ActionResult, String?) -> Void)?
    /// A `get_screen` response arrived. Trailing `String?` is the originating requestId.
    public var onScreen: ((ScreenPayload, String?) -> Void)?
    /// The server acknowledged that screen recording has begun.
    public var onRecordingStarted: (() -> Void)?
    /// A completed recording is delivered (as base64 payload + metadata).
    public var onRecording: ((RecordingPayload) -> Void)?
    /// Recording failed mid-capture; the string is the server-reported reason.
    public var onRecordingError: ((String) -> Void)?
    /// General protocol/transport error reported by the server.
    public var onError: ((String) -> Void)?
    /// Error response for a specific in-flight request.
    public var onRequestError: ((String, String) -> Void)?
    /// Auth approved. The parameter is the approved token, or nil when reusing a persistent session.
    public var onAuthApproved: ((String?) -> Void)?
    /// Another agent currently owns the session. Payload carries details for the operator to resolve.
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    /// Auth rejected by server; the string is the reason.
    public var onAuthFailed: ((String) -> Void)?
    /// A user interaction event (tap, swipe) captured on the device.
    public var onInteraction: ((InteractionEvent) -> Void)?
    /// The server pushed an interface delta between commands (the UI changed
    /// without a direct action request). Drained by `TheFence` for session state.
    public var onBackgroundDelta: ((InterfaceDelta) -> Void)?

    // MARK: - Configuration

    public var token: String?
    public var observeMode: Bool = false
    /// Explicit driver ID override (e.g. from BUTTONHEIST_DRIVER_ID env var).
    /// When nil, a persistent auto-generated ID is used instead.
    public var driverId: String?
    public var autoSubscribe: Bool = true

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

    public init() {}

    // MARK: - Discovery

    public func startDiscovery() {
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

    public func stopDiscovery() {
        discovery?.stop()
        discovery = nil
        isDiscovering = false
        discoveredDevices = []
    }

    // MARK: - Reachability Probing

    /// Discover devices and validate each deduped advertisement as it appears.
    public func discoverReachableDevices(
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

    public func connect(to device: DiscoveredDevice) {
        disconnect()
        transitionToConnecting(device: device)

        connection = makeConnection(device, token, effectiveDriverId)
        connection?.observeMode = observeMode

        connection?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .transportReady:
                break
            case .connected:
                self.missedPongCount = 0
                let keepaliveTask = self.makeKeepaliveTask()
                self.transitionToConnected(device: device, keepaliveTask: keepaliveTask)
            case .disconnected(let reason):
                if case .failed = self.connectionPhase {
                    self.onDisconnected?(reason)
                    return
                }
                self.transitionToDisconnected()
                self.onDisconnected?(reason)
                if case .enabled(let filter, let existingReconnectTask) = self.reconnectPolicy {
                    existingReconnectTask?.cancel()
                    let reconnectTask = Task<Void, Never> { [weak self] in
                        await self?.runAutoReconnect(filter: filter)
                    }
                    self.reconnectPolicy = .enabled(filter: filter, reconnectTask: reconnectTask)
                }
            case .message(let message, let requestId, let backgroundDelta):
                self.handleServerMessage(message, requestId: requestId, backgroundDelta: backgroundDelta)
            }
        }

        connection?.connect()
    }

    func handleServerMessage(_ message: ServerMessage, requestId: String?, backgroundDelta: InterfaceDelta? = nil) {
        if let backgroundDelta {
            onBackgroundDelta?(backgroundDelta)
        }
        switch message {
        case .info(let info):
            mutateConnectedSession { $0.serverInfo = info }
            if autoSubscribe {
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
                    onRequestError?(serverError.message, requestId)
                } else {
                    transitionToFailed(.error(serverError.message))
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
            transitionToFailed(.error(message))
            onError?(message)
        case .pong:
            missedPongCount = 0
        case .recordingStopped:
            mutateConnectedSession { $0.recordingPhase = .idle }
        case .serverHello, .authRequired:
            break
        }
    }

    public func disconnect() {
        if case .enabled(let filter, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        }
        connection?.disconnect()
        connection = nil
        transitionToDisconnected()
    }

    /// Suspend until the connection phase transitions to `.connected` (returns),
    /// `.failed` (throws the mapped `ConnectionError`), or `.disconnected`
    /// (throws `ConnectionError.connectionFailed`). If the phase is already
    /// terminal at call time, returns or throws immediately without suspending.
    ///
    /// The `timeout` is enforced by scheduling a cancellable timeout task that
    /// fails any registered awaiters with `ConnectionError.timeout`.
    /// Cancelling the calling task aborts the wait and propagates
    /// `CancellationError`.
    public func waitForConnectionResult(timeout: TimeInterval) async throws {
        // Fast path: already terminal.
        switch connectionPhase {
        case .connected:
            return
        case .failed(let failure):
            throw failure.asConnectionError
        case .disconnected:
            throw ConnectionError.connectionFailed(
                "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
            )
        case .connecting:
            break
        }

        let timeoutDuration: Duration = .nanoseconds(UInt64(max(timeout, 5) * 1_000_000_000))
        let timeoutTask = Task { @ButtonHeistActor [weak self] in
            guard await Task.cancellableSleep(for: timeoutDuration) else { return }
            self?.failPhaseAwaitersWithTimeout()
        }
        defer { timeoutTask.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                phaseAwaiters.append(continuation)
            }
        } onCancel: {
            Task { @ButtonHeistActor [weak self] in
                self?.cancelPhaseAwaiters()
            }
        }
    }

    /// Resume every registered awaiter with a `CancellationError`. Called
    /// from the cancellation handler of `waitForConnectionResult`.
    private func cancelPhaseAwaiters() {
        resumePhaseAwaiters(with: .failure(CancellationError()))
    }

    /// Resume every registered awaiter with `ConnectionError.timeout`.
    /// Scheduled by `waitForConnectionResult` and runs on the actor when the
    /// timeout duration elapses without a phase transition.
    private func failPhaseAwaitersWithTimeout() {
        resumePhaseAwaiters(with: .failure(ConnectionError.timeout))
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    public func forceDisconnect() {
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

    public func send(_ message: ClientMessage, requestId: String? = nil) {
        connection?.send(message, requestId: requestId)
    }

    // MARK: - Keepalive

    private func makeKeepaliveTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard await Task.cancellableSleep(for: Self.keepaliveInterval) else { break }
                guard !Task.isCancelled else { break }
                self?.connection?.send(.ping)
                self?.missedPongCount += 1
                if let count = self?.missedPongCount, count >= Self.maxMissedPongs {
                    logger.warning("No pong received for \(count) consecutive pings — forcing disconnect")
                    self?.forceDisconnect()
                    break
                }
            }
        }
    }

    // MARK: - Session Management (discovery → connect → reconnect)

    /// Status callback for session management progress messages.
    public var onStatus: ((String) -> Void)?

    /// Discover a device (optionally matching a filter) and connect to it.
    /// Starts discovery if not already active, polls until a matching device appears
    /// or the timeout expires. Suspends on `waitForConnectionResult` for the
    /// connection outcome.
    public func connectWithDiscovery(filter: String?, timeout: TimeInterval = 30) async throws {
        onStatus?("Searching for iOS devices...")
        let startedDiscovery = !hasActiveDiscoverySession
        if startedDiscovery { startDiscovery() }

        let discoveryTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        let device: DiscoveredDevice
        do {
            device = try await resolveReachableDevice(filter: filter, discoveryTimeout: discoveryTimeout)
        } catch {
            if startedDiscovery { stopDiscovery() }
            throw error
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        connect(to: device)
        try await waitForConnectionResult(timeout: timeout)
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
    public func setupAutoReconnect(filter: String?) {
        guard case .disabled = reconnectPolicy else { return }
        reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
    }

    private func runAutoReconnect(filter: String?) async {
        onStatus?("Device disconnected — watching for reconnection...")
        var consecutiveMisses = 0
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            // Backoff grows while no device is visible; resets after each connection attempt
            let delay = min(reconnectInterval * pow(2.0, Double(min(consecutiveMisses, 5))), 30.0)
            let jitter = Double.random(in: 0...(delay * 0.2))
            guard await Task.cancellableSleep(for: .seconds(delay + jitter)) else { return }
            guard !Task.isCancelled else { return }
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

    // MARK: - Display Names

    /// Compute display name with disambiguation when multiple devices have the same app
    public func displayName(for device: DiscoveredDevice) -> String {
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
    public static func == (lhs: Self, rhs: Self) -> Bool {
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
