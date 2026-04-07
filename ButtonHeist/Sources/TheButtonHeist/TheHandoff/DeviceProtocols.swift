import Foundation

// MARK: - Event Enums

/// Events emitted by a device connection during its lifecycle.
public enum ConnectionEvent {
    case transportReady
    case connected
    case disconnected(DisconnectReason)
    case message(ServerMessage, requestId: String?, backgroundDelta: InterfaceDelta?)
}

/// Events emitted by a device discovery session as services appear and disappear.
public enum DiscoveryEvent {
    case found(DiscoveredDevice)
    case lost(DiscoveredDevice)
    case stateChanged(isReady: Bool)
}

// MARK: - Protocols

/// Manages a single connection to a discovered device, sending and receiving messages.
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

/// Discovers Button Heist services on the local network via Bonjour or direct address.
@ButtonHeistActor
public protocol DeviceDiscovering: AnyObject {
    var discoveredDevices: [DiscoveredDevice] { get }
    var onEvent: ((DiscoveryEvent) -> Void)? { get set }
    func start()
    func stop()
}
