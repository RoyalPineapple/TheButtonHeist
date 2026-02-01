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
}
