import Foundation
import TheScore
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "wheelman")

/// Client-side session manager that owns the full device lifecycle:
/// discovery, connection, keepalive, and auto-reconnect.
///
/// TheMastermind observes TheWheelman and exposes its state as @Observable
/// properties for SwiftUI consumption. TheFence delegates its connect/reconnect
/// logic here instead of reimplementing it.
@MainActor
public final class TheWheelman {

    // MARK: - Discovery State

    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var isDiscovering: Bool = false

    // MARK: - Connection State

    public private(set) var connectedDevice: DiscoveredDevice?
    public private(set) var serverInfo: ServerInfo?
    public private(set) var isConnected: Bool = false

    // MARK: - Discovery Callbacks

    public var onDeviceFound: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?

    // MARK: - Connection Callbacks

    public var onConnected: ((ServerInfo) -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onInterface: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    public var onAuthApproved: ((String) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?

    // MARK: - Configuration

    public var token: String?
    public var forceSession: Bool = false
    public var driverId: String?
    public var autoSubscribe: Bool = true

    // MARK: - Private

    private var discovery: DeviceDiscovery?
    private var connection: DeviceConnection?
    private var keepaliveTask: Task<Void, Never>?
    private var autoReconnectInstalled = false

    // MARK: - Init

    public init() {}

    // MARK: - Discovery

    public func startDiscovery() {
        logger.info("startDiscovery called, isDiscovering=\(self.isDiscovering)")
        guard !isDiscovering else {
            logger.info("Already discovering, skipping")
            return
        }

        discoveredDevices.removeAll()
        discovery = DeviceDiscovery()
        discovery?.onDeviceFound = { [weak self] device in
            logger.info("Device found: \(device.name)")
            self?.discoveredDevices.append(device)
            self?.onDeviceFound?(device)
        }
        discovery?.onDeviceLost = { [weak self] device in
            logger.info("Device lost: \(device.name)")
            self?.discoveredDevices.removeAll { $0.id == device.id }
            self?.onDeviceLost?(device)
        }
        discovery?.onStateChange = { [weak self] isReady in
            logger.info("Discovery state changed: isReady=\(isReady)")
            self?.isDiscovering = isReady
        }
        discovery?.start()
        logger.info("Discovery started")
    }

    public func stopDiscovery() {
        discovery?.stop()
        discovery = nil
        isDiscovering = false
    }

    // MARK: - Connection

    public func connect(to device: DiscoveredDevice) {
        disconnect()

        connection = DeviceConnection(device: device, token: token, forceSession: forceSession, driverId: driverId)

        connection?.onConnected = { [weak self] in
            self?.connectedDevice = device
            self?.isConnected = true
            self?.startKeepalive()
        }

        connection?.onDisconnected = { [weak self] error in
            guard let self else { return }
            self.isConnected = false
            self.connectedDevice = nil
            self.serverInfo = nil
            self.onDisconnected?(error)
        }

        connection?.onServerInfo = { [weak self] info in
            guard let self else { return }
            self.serverInfo = info
            if self.autoSubscribe {
                self.connection?.send(.subscribe)
                self.connection?.send(.requestInterface)
                self.connection?.send(.requestScreen)
            }
            self.onConnected?(info)
        }

        connection?.onInterface = { [weak self] payload in
            self?.onInterface?(payload)
        }

        connection?.onActionResult = { [weak self] result in
            self?.onActionResult?(result)
        }

        connection?.onScreen = { [weak self] payload in
            self?.onScreen?(payload)
        }

        connection?.onRecordingStarted = { [weak self] in
            self?.onRecordingStarted?()
        }
        connection?.onRecording = { [weak self] payload in
            self?.onRecording?(payload)
        }
        connection?.onRecordingError = { [weak self] message in
            self?.onRecordingError?(message)
        }

        connection?.onError = { [weak self] message in
            self?.onError?(message)
        }

        connection?.onAuthApproved = { [weak self] approvedToken in
            self?.token = approvedToken
            self?.onAuthApproved?(approvedToken)
        }

        connection?.onSessionLocked = { [weak self] payload in
            self?.onSessionLocked?(payload)
        }

        connection?.onAuthFailed = { [weak self] reason in
            self?.onAuthFailed?(reason)
        }

        connection?.connect()
    }

    public func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.disconnect()
        connection = nil
        isConnected = false
        connectedDevice = nil
        serverInfo = nil
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    public func forceDisconnect() {
        guard isConnected else { return }
        logger.warning("Force-disconnecting stale connection")
        disconnect()
        onDisconnected?(nil)
    }

    // MARK: - Commands

    public func send(_ message: ClientMessage) {
        connection?.send(message)
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
    /// or the timeout expires.
    public func connectWithDiscovery(filter: String?, timeout: TimeInterval = 30) async throws {
        onStatus?("Searching for iOS devices...")
        startDiscovery()

        let discoveryTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        let discoveryStart = DispatchTime.now().uptimeNanoseconds
        while discoveredDevices.first(matching: filter) == nil {
            if DispatchTime.now().uptimeNanoseconds - discoveryStart > discoveryTimeout {
                if let filter {
                    throw ConnectionError.noMatchingDevice(
                        filter: filter,
                        available: discoveredDevices.map(\.name)
                    )
                }
                throw ConnectionError.noDeviceFound
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let device = discoveredDevices.first(matching: filter) else {
            throw ConnectionError.noDeviceFound
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        var connected = false
        var connectionError: Error?

        let savedOnConnected = onConnected
        let savedOnDisconnected = onDisconnected
        let savedOnAuthFailed = onAuthFailed
        let savedOnSessionLocked = onSessionLocked

        onConnected = { info in
            connected = true
            savedOnConnected?(info)
        }
        onDisconnected = { error in
            if connectionError == nil {
                connectionError = error
            }
            savedOnDisconnected?(error)
        }
        onAuthFailed = { reason in
            connectionError = ConnectionError.authFailed(reason)
            savedOnAuthFailed?(reason)
        }
        onSessionLocked = { payload in
            connectionError = ConnectionError.sessionLocked(payload.message)
            savedOnSessionLocked?(payload)
        }

        connect(to: device)

        let connectionStart = DispatchTime.now().uptimeNanoseconds
        let connectionTimeout = UInt64(max(timeout, 5) * 1_000_000_000)
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connectionStart > connectionTimeout {
                // Restore callbacks before throwing
                onConnected = savedOnConnected
                onDisconnected = savedOnDisconnected
                onAuthFailed = savedOnAuthFailed
                onSessionLocked = savedOnSessionLocked
                throw ConnectionError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Restore callbacks
        onConnected = savedOnConnected
        onDisconnected = savedOnDisconnected
        onAuthFailed = savedOnAuthFailed
        onSessionLocked = savedOnSessionLocked

        if let connectionError {
            if let wheelmanError = connectionError as? ConnectionError {
                throw wheelmanError
            }
            throw ConnectionError.connectionFailed(connectionError.localizedDescription)
        }

        onStatus?("Connected to \(displayName(for: device))")
    }

    /// Set up auto-reconnect: when disconnected, poll for the device and reconnect.
    /// Makes 60 attempts at 1s intervals before giving up.
    public func setupAutoReconnect(filter: String?) {
        guard !autoReconnectInstalled else { return }
        autoReconnectInstalled = true
        let savedOnDisconnected = onDisconnected
        onDisconnected = { [weak self] error in
            savedOnDisconnected?(error)
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onStatus?("Device disconnected — watching for reconnection...")
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if let device = self.discoveredDevices.first(matching: filter) {
                        self.onStatus?("Reconnecting to \(device.name)...")
                        self.connect(to: device)
                        let deadline = Date().addingTimeInterval(10)
                        while !self.isConnected {
                            if Date() > deadline { break }
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        if self.isConnected {
                            self.onStatus?("Reconnected to \(device.name)")
                            return
                        }
                    }
                }
                self.onStatus?("Auto-reconnect gave up after 60 attempts")
            }
        }
    }

    /// Errors from the session management lifecycle.
    public enum ConnectionError: Error, LocalizedError {
        case noDeviceFound
        case noMatchingDevice(filter: String, available: [String])
        case connectionTimeout
        case connectionFailed(String)
        case sessionLocked(String)
        case authFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noDeviceFound:
                return "No devices found within timeout. Is the app running?"
            case .noMatchingDevice(let filter, let available):
                let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
                return "No device matching '\(filter)'. Available: \(list)"
            case .connectionTimeout:
                return "Connection timed out"
            case .connectionFailed(let message):
                return "Connection failed: \(message)"
            case .sessionLocked(let message):
                return "Session locked: \(message)"
            case .authFailed(let message):
                return "Auth failed: \(message)"
            }
        }
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
