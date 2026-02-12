import Foundation
import Wheelman
import TheGoods
import os.log

private let logger = Logger(subsystem: "com.buttonheist", category: "client")

/// Client for discovering and connecting to iOS apps running InsideMan
@MainActor
public final class HeistClient: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published public private(set) var connectedDevice: DiscoveredDevice?
    @Published public private(set) var serverInfo: ServerInfo?
    @Published public private(set) var currentInterface: Interface?
    @Published public private(set) var currentScreen: ScreenPayload?
    @Published public private(set) var isDiscovering: Bool = false
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // MARK: - Callbacks (for non-SwiftUI usage)

    public var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?
    public var onConnected: ((ServerInfo) -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onInterfaceUpdate: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?

    // MARK: - Private

    private var discovery: DeviceDiscovery?
    private var connection: DeviceConnection?

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
            logger.info("Device found callback: \(device.name)")
            self?.discoveredDevices.append(device)
            self?.onDeviceDiscovered?(device)
        }
        discovery?.onDeviceLost = { [weak self] device in
            logger.info("Device lost callback: \(device.name)")
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

        connectionState = .connecting
        connection = DeviceConnection(device: device)

        connection?.onConnected = { [weak self] in
            self?.connectionState = .connected
            self?.connectedDevice = device
            self?.connection?.send(.subscribe)
            self?.connection?.send(.requestInterface)
            self?.connection?.send(.requestScreen)
        }

        connection?.onDisconnected = { [weak self] error in
            self?.connectionState = .disconnected
            self?.connectedDevice = nil
            self?.serverInfo = nil
            self?.currentInterface = nil
            self?.currentScreen = nil
            self?.onDisconnected?(error)
        }

        connection?.onServerInfo = { [weak self] info in
            self?.serverInfo = info
            self?.onConnected?(info)
        }

        connection?.onInterface = { [weak self] payload in
            self?.currentInterface = payload
            self?.onInterfaceUpdate?(payload)
        }

        connection?.onActionResult = { [weak self] result in
            self?.onActionResult?(result)
        }

        connection?.onScreen = { [weak self] payload in
            self?.currentScreen = payload
            self?.onScreen?(payload)
        }

        connection?.onError = { [weak self] message in
            self?.connectionState = .failed(message)
        }

        connection?.connect()
    }

    public func disconnect() {
        connection?.disconnect()
        connection = nil
        connectionState = .disconnected
        connectedDevice = nil
        serverInfo = nil
        currentInterface = nil
        currentScreen = nil
    }

    // MARK: - Commands

    public func requestInterface() {
        connection?.send(.requestInterface)
    }

    /// Send a message to the connected device
    public func send(_ message: ClientMessage) {
        connection?.send(message)
    }

    /// Wait for an action result with timeout
    public func waitForActionResult(timeout: TimeInterval) async throws -> ActionResult {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            // Set up timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            // Set up callback
            onActionResult = { result in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Wait for a screen capture response with timeout
    public func waitForScreen(timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onScreen = { payload in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: payload)
                }
            }
        }
    }

    public enum ActionError: Error, LocalizedError {
        case timeout
        case notConnected

        public var errorDescription: String? {
            switch self {
            case .timeout:
                return "Action timed out"
            case .notConnected:
                return "Not connected to device"
            }
        }
    }

    // MARK: - Display Names

    /// Compute display name for a device, with disambiguation if multiple devices have the same app
    /// Prefers app name, appends device name in parentheses only when needed
    public func displayName(for device: DiscoveredDevice) -> String {
        let appName = device.appName

        // Check if disambiguation is needed (multiple devices with same app name)
        let sameAppDevices = discoveredDevices.filter { $0.appName == appName }

        if sameAppDevices.count > 1 {
            return "\(appName) (\(device.deviceName))"
        } else {
            return appName
        }
    }

    /// Display name for the currently connected device
    public var connectedDeviceDisplayName: String? {
        guard let device = connectedDevice else { return nil }
        return displayName(for: device)
    }
}
