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
    /// unrepresentable.
    public enum ConnectionPhase: Equatable {
        case disconnected
        case connecting(device: DiscoveredDevice)
        case connected(device: DiscoveredDevice)
        case failed(ConnectionFailure)
    }

    /// Whether auto-reconnect fires on disconnect. Replaces the old boolean
    /// guard + callback-wrapping pattern — the disconnect handler checks this
    /// directly instead of mutating `onDisconnected`.
    public enum ReconnectPolicy: Equatable {
        case disabled
        case enabled(filter: String?)
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

    // MARK: - Derived State

    public var isConnected: Bool {
        if case .connected = connectionPhase { return true }
        return false
    }

    public var connectedDevice: DiscoveredDevice? {
        if case .connected(let device) = connectionPhase { return device }
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

    // MARK: - Injectable Closures

    var makeDiscovery: () -> any DeviceDiscovering = { DeviceDiscovery() }
    var makeConnection: (DiscoveredDevice, String?, String) -> any DeviceConnecting = {
        DeviceConnection(device: $0, token: $1, driverId: $2)
    }

    // MARK: - Private

    private var discovery: (any DeviceDiscovering)?
    private var connection: (any DeviceConnecting)?
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

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
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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
                let probed = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
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

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return discoveredDevices.filter { reachableIDs.contains($0.id) }
    }

    // MARK: - Connection

    public func connect(to device: DiscoveredDevice) {
        disconnect()
        connectionPhase = .connecting(device: device)

        connection = makeConnection(device, token, effectiveDriverId)
        connection?.observeMode = observeMode

        connection?.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .transportReady:
                break
            case .connected:
                self.connectionPhase = .connected(device: device)
                self.startKeepalive()
            case .disconnected(let reason):
                self.serverInfo = nil
                self.currentInterface = nil
                self.currentScreen = nil
                self.recordingPhase = .idle
                // Preserve .failed state (e.g., from sessionLocked)
                if case .failed = self.connectionPhase {
                    // keep .failed
                } else {
                    self.connectionPhase = .disconnected
                }
                self.onDisconnected?(reason)
                if case .enabled(let filter) = self.reconnectPolicy {
                    self.reconnectTask?.cancel()
                    self.reconnectTask = Task { [weak self] in
                        await self?.runAutoReconnect(filter: filter)
                    }
                }
            case .message(let msg, let requestId):
                self.handleServerMessage(msg, requestId: requestId)
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
            recordingPhase = .recording
            onRecordingStarted?()
        case .recording(let payload):
            recordingPhase = .idle
            onRecording?(payload)
        case .recordingError(let msg):
            recordingPhase = .idle
            onRecordingError?(msg)
        case .error(let msg):
            connectionPhase = .failed(.error(msg))
            onError?(msg)
        case .authApproved(let payload):
            token = payload.token
            onAuthApproved?(payload.token)
        case .sessionLocked(let payload):
            connectionPhase = .failed(.sessionLocked(payload.message))
            onSessionLocked?(payload)
        case .authFailed(let reason):
            connectionPhase = .failed(.authFailed(reason))
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
        reconnectTask?.cancel()
        reconnectTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.disconnect()
        connection = nil
        connectionPhase = .disconnected
        serverInfo = nil
        currentInterface = nil
        currentScreen = nil
        recordingPhase = .idle
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    public func forceDisconnect() {
        guard isConnected else { return }
        logger.warning("Force-disconnecting stale connection")
        disconnect()
        onDisconnected?(.localDisconnect)
        if case .enabled(let filter) = reconnectPolicy {
            reconnectTask?.cancel()
            reconnectTask = Task { [weak self] in
                await self?.runAutoReconnect(filter: filter)
            }
        }
    }

    // MARK: - Commands

    public func send(_ message: ClientMessage, requestId: String? = nil) {
        connection?.send(message, requestId: requestId)
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
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
        startDiscovery()

        let discoveryTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        let device = try await resolveReachableDevice(filter: filter, discoveryTimeout: discoveryTimeout)

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
            try await Task.sleep(nanoseconds: 100_000_000)
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
        reconnectPolicy = .enabled(filter: filter)
    }

    private func runAutoReconnect(filter: String?) async {
        onStatus?("Device disconnected — watching for reconnection...")
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if let device = discoveredDevices.first(matching: filter) {
                onStatus?("Reconnecting to \(device.name)...")
                connect(to: device)
                let deadline = Date().addingTimeInterval(10)
                while !isConnected {
                    if Task.isCancelled || Date() > deadline { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if Task.isCancelled { return }
                if isConnected {
                    onStatus?("Reconnected to \(device.name)")
                    return
                }
            }
        }
        onStatus?("Auto-reconnect gave up after 60 attempts")
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
