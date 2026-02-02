import Foundation
import Network
import AccraCore

/// A discovered iOS device running AccraHost
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    /// Parse the service name to extract app name and device name
    /// Service name format: "AppName-DeviceName"
    public var parsedName: (appName: String, deviceName: String)? {
        guard let lastDashIndex = name.lastIndex(of: "-") else { return nil }
        let appName = String(name[..<lastDashIndex])
        let deviceName = String(name[name.index(after: lastDashIndex)...])
        guard !appName.isEmpty && !deviceName.isEmpty else { return nil }
        return (appName, deviceName)
    }

    /// App name extracted from service name
    public var appName: String {
        parsedName?.appName ?? name
    }

    /// Device name extracted from service name
    public var deviceName: String {
        parsedName?.deviceName ?? ""
    }
}

/// Client for discovering and connecting to iOS apps running AccraHost
@MainActor
public final class AccraClient: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published public private(set) var connectedDevice: DiscoveredDevice?
    @Published public private(set) var serverInfo: ServerInfo?
    @Published public private(set) var currentHierarchy: HierarchyPayload?
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
    public var onHierarchyUpdate: ((HierarchyPayload) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreenshot: ((ScreenshotPayload) -> Void)?

    // MARK: - Private

    private var discovery: DeviceDiscovery?
    private var connection: DeviceConnection?

    // MARK: - Init

    public init() {}

    // MARK: - Discovery

    public func startDiscovery() {
        guard !isDiscovering else { return }

        discoveredDevices.removeAll()
        discovery = DeviceDiscovery()
        discovery?.onDeviceFound = { [weak self] device in
            self?.discoveredDevices.append(device)
            self?.onDeviceDiscovered?(device)
        }
        discovery?.onDeviceLost = { [weak self] device in
            self?.discoveredDevices.removeAll { $0.id == device.id }
            self?.onDeviceLost?(device)
        }
        discovery?.onStateChange = { [weak self] isReady in
            self?.isDiscovering = isReady
        }
        discovery?.start()
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
            self?.connection?.send(.requestHierarchy)
        }

        connection?.onDisconnected = { [weak self] error in
            self?.connectionState = .disconnected
            self?.connectedDevice = nil
            self?.serverInfo = nil
            self?.currentHierarchy = nil
            self?.onDisconnected?(error)
        }

        connection?.onServerInfo = { [weak self] info in
            self?.serverInfo = info
            self?.onConnected?(info)
        }

        connection?.onHierarchy = { [weak self] payload in
            self?.currentHierarchy = payload
            self?.onHierarchyUpdate?(payload)
        }

        connection?.onActionResult = { [weak self] result in
            self?.onActionResult?(result)
        }

        connection?.onScreenshot = { [weak self] payload in
            self?.onScreenshot?(payload)
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
        currentHierarchy = nil
    }

    // MARK: - Commands

    public func requestHierarchy() {
        connection?.send(.requestHierarchy)
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

    /// Wait for a screenshot response with timeout
    public func waitForScreenshot(timeout: TimeInterval = 30.0) async throws -> ScreenshotPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onScreenshot = { payload in
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
