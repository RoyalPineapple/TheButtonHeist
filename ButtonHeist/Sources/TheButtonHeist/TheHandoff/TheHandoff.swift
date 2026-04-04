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

    /// Why a connection failed — typed so callers can map to the right FenceError
    /// without string parsing or callback interception.
    public enum ConnectionFailure: Equatable {
        case error(String)
        case authFailed(String)
        case sessionLocked(String)

        var asFenceError: FenceError {
            switch self {
            case .error(let message): return .connectionFailed(message)
            case .authFailed(let reason): return .authFailed(reason)
            case .sessionLocked(let message): return .sessionLocked(message)
            }
        }
    }

    /// Explicit connection lifecycle state machine. The device is carried in
    /// `.connecting` and `.connected` so `connectedDevice` cannot drift from
    /// the phase — impossible states like "connected but no device" are
    /// unrepresentable. The keepalive task lives in `.connected` because it
    /// only runs while connected — transitioning out cancels it implicitly.
    public enum ConnectionPhase {
        case disconnected
        case connecting(device: DiscoveredDevice)
        case connected(device: DiscoveredDevice, keepaliveTask: Task<Void, Never>)
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
    public private(set) var serverInfo: ServerInfo?
    public private(set) var currentInterface: Interface?
    public private(set) var currentScreen: ScreenPayload?
    public private(set) var recordingPhase: RecordingPhase = .idle
    public private(set) var reconnectPolicy: ReconnectPolicy = .disabled

    // MARK: - State Transitions

    private func transitionToConnecting(device: DiscoveredDevice) {
        connectionPhase = .connecting(device: device)
    }

    private func transitionToConnected(device: DiscoveredDevice, keepaliveTask: Task<Void, Never>) {
        connectionPhase = .connected(device: device, keepaliveTask: keepaliveTask)
    }

    private func transitionToFailed(_ failure: ConnectionFailure) {
        if case .connected(_, let keepaliveTask) = connectionPhase {
            keepaliveTask.cancel()
        }
        connectionPhase = .failed(failure)
    }

    private func transitionToDisconnected() {
        if case .connected(_, let keepaliveTask) = connectionPhase {
            keepaliveTask.cancel()
        }
        connectionPhase = .disconnected
        serverInfo = nil
        currentInterface = nil
        currentScreen = nil
        recordingPhase = .idle
    }

    private func transitionRecordingTo(_ phase: RecordingPhase) {
        recordingPhase = phase
    }

    // MARK: - Derived State

    public var isConnected: Bool {
        if case .connected = connectionPhase { return true }
        return false
    }

    public var connectedDevice: DiscoveredDevice? {
        if case .connected(let device, _) = connectionPhase { return device }
        return nil
    }

    public var isRecording: Bool {
        recordingPhase == .recording
    }

    // MARK: - Discovery Callbacks

    public var onDeviceFound: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    public var onConnected: ((ServerInfo) -> Void)?
    public var onDisconnected: ((DisconnectReason) -> Void)?
    public var onInterface: ((Interface, String?) -> Void)?
    public var onActionResult: ((ActionResult, String?) -> Void)?
    public var onScreen: ((ScreenPayload, String?) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    public var onAuthApproved: ((String?) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?
    public var onInteraction: ((InteractionEvent) -> Void)?

    // MARK: - Configuration

    public var token: String?
    public var observeMode: Bool = false
    /// Explicit driver ID override (e.g. from BUTTONHEIST_DRIVER_ID env var).
    /// When nil, a persistent auto-generated ID is used instead.
    public var driverId: String?
    public var autoSubscribe: Bool = true
    /// Interval between auto-reconnect attempts. Default is 1 second.
    var reconnectInterval: TimeInterval = 1.0

    // MARK: - Injectable Closures

    var makeDiscovery: () -> any DeviceDiscovering = { DeviceDiscovery() }
    var makeConnection: (DiscoveredDevice, String?, String) -> any DeviceConnecting = {
        DeviceConnection(device: $0, token: $1, driverId: $2)
    }

    // MARK: - Private

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
        if let existing = (try? String(contentsOf: fileURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
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

            try? await Task.sleep(for: .milliseconds(100))
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
                let keepaliveTask = self.makeKeepaliveTask()
                self.transitionToConnected(device: device, keepaliveTask: keepaliveTask)
            case .disconnected(let reason):
                // .failed phase already cancelled keepalive; clean up remaining state
                // via transitionToDisconnected rather than manual field clearing
                if case .failed = self.connectionPhase {
                    self.transitionToDisconnected()
                } else {
                    self.transitionToDisconnected()
                }
                self.onDisconnected?(reason)
                if case .enabled(let filter, let existingReconnectTask) = self.reconnectPolicy {
                    existingReconnectTask?.cancel()
                    let reconnectTask = Task<Void, Never> { [weak self] in
                        await self?.runAutoReconnect(filter: filter)
                    }
                    self.reconnectPolicy = .enabled(filter: filter, reconnectTask: reconnectTask)
                }
            case .message(let message, let requestId):
                self.handleServerMessage(message, requestId: requestId)
            }
        }

        connection?.connect()
    }

    func handleServerMessage(_ message: ServerMessage, requestId: String?) {
        switch message {
        case .info(let info):
            serverInfo = info
            if autoSubscribe {
                connection?.send(.subscribe)
                connection?.send(.requestInterface)
                connection?.send(.requestScreen)
            }
            onConnected?(info)
        case .interface(let payload):
            if requestId == nil {
                currentInterface = payload
            }
            onInterface?(payload, requestId)
        case .actionResult(let result):
            onActionResult?(result, requestId)
        case .screen(let payload):
            if requestId == nil {
                currentScreen = payload
            }
            onScreen?(payload, requestId)
        case .recordingStarted:
            transitionRecordingTo(.recording)
            onRecordingStarted?()
        case .recording(let payload):
            transitionRecordingTo(.idle)
            onRecording?(payload)
        case .recordingError(let message):
            transitionRecordingTo(.idle)
            onRecordingError?(message)
        case .error(let message):
            transitionToFailed(.error(message))
            onError?(message)
        case .authApproved(let payload):
            token = payload.token
            onAuthApproved?(payload.token)
        case .sessionLocked(let payload):
            transitionToFailed(.sessionLocked(payload.message))
            onSessionLocked?(payload)
        case .authFailed(let reason):
            transitionToFailed(.authFailed(reason))
            onAuthFailed?(reason)
        case .interaction(let event):
            onInteraction?(event)
        case .status(let payload):
            logger.info("Received status payload: appName=\(payload.identity.appName, privacy: .public)")
        case .protocolMismatch(let payload):
            onError?("Protocol mismatch: expected \(payload.expectedProtocolVersion), got \(payload.receivedProtocolVersion)")
        case .serverHello, .authRequired, .pong, .recordingStopped:
            break
        }
    }

    public func disconnect() {
        if case .enabled(let filter, let reconnectTask) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectPolicy = .enabled(filter: filter, reconnectTask: nil)
        }
        // keepaliveTask cancellation handled by transitionToDisconnected
        connection?.disconnect()
        connection = nil
        transitionToDisconnected()
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
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                self?.connection?.send(.ping)
            }
        }
    }

    // MARK: - Session Management (discovery → connect → reconnect)

    /// Status callback for session management progress messages.
    public var onStatus: ((String) -> Void)?

    /// Discover a device (optionally matching a filter) and connect to it.
    /// Starts discovery if not already active, polls until a matching device appears
    /// or the timeout expires. Polls `connectionPhase` directly instead of
    /// intercepting callbacks — the state machine carries the outcome.
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

        let connectionStart = DispatchTime.now().uptimeNanoseconds
        let connectionTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        while true {
            switch connectionPhase {
            case .connected:
                onStatus?("Connected to \(displayName(for: device))")
                return
            case .failed(let failure):
                throw failure.asFenceError
            case .disconnected:
                throw FenceError.connectionFailed("Disconnected during connection attempt")
            case .connecting:
                break
            }
            if DispatchTime.now().uptimeNanoseconds - connectionStart > connectionTimeout {
                throw FenceError.connectionTimeout
            }
            try await Task.sleep(for: .milliseconds(100))
        }
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
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(reconnectInterval))
            guard !Task.isCancelled else { return }
            if let device = discoveredDevices.first(matching: filter) {
                onStatus?("Reconnecting to \(device.name)...")
                connect(to: device)
                let deadline = Date().addingTimeInterval(10)
                while !isConnected {
                    if Task.isCancelled || Date() > deadline { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if Task.isCancelled { return }
                if isConnected {
                    onStatus?("Reconnected to \(device.name)")
                    return
                }
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

// MARK: - Custom Equatable (tasks excluded from comparison)

extension TheHandoff.ConnectionPhase: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting(let lhsDevice), .connecting(let rhsDevice)):
            return lhsDevice == rhsDevice
        case (.connected(let lhsDevice, _), .connected(let rhsDevice, _)):
            return lhsDevice == rhsDevice
        case (.failed(let lhsFailure), .failed(let rhsFailure)):
            return lhsFailure == rhsFailure
        default:
            return false
        }
    }
}

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
