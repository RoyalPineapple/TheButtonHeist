import Foundation

// MARK: - Event Enums

public enum ConnectionEvent {
    case transportReady
    case connected
    case disconnected(DisconnectReason)
    case message(ServerMessage, requestId: String?)
}

public enum DiscoveryEvent {
    case found(DiscoveredDevice)
    case lost(DiscoveredDevice)
    case stateChanged(isReady: Bool)
}

// MARK: - Protocols

@ButtonHeistActor
public protocol DeviceConnecting: AnyObject {
    var isConnected: Bool { get }
    var observeMode: Bool { get set }
    var onEvent: ((ConnectionEvent) -> Void)? { get set }
    func connect()
    func disconnect()
    func send(_ message: ClientMessage, requestId: String?)
}

extension DeviceConnecting {
    public func send(_ message: ClientMessage) {
        send(message, requestId: nil)
    }
}

@ButtonHeistActor
public protocol DeviceDiscovering: AnyObject {
    var discoveredDevices: [DiscoveredDevice] { get }
    var onEvent: ((DiscoveryEvent) -> Void)? { get set }
    func start()
    func stop()
}
