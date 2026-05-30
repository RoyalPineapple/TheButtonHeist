import Foundation

// MARK: - Event Enums

/// Synchronous outcome for handing a client message to the transport.
enum DeviceSendOutcome: Equatable, Sendable {
    case enqueued
    case failed(DeviceSendFailure)
}

enum DeviceSendFailure: Error, LocalizedError, Equatable, Sendable {
    case notConnected
    case encodingFailed(String)
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connection is closed"
        case .encodingFailed(let message):
            return "Failed to encode request: \(message)"
        case .transportFailed(let message):
            return "Transport send failed: \(message)"
        }
    }
}

/// Events emitted by a device connection during its lifecycle.
enum ConnectionEvent {
    case connected
    case disconnected(DisconnectReason)
    case sendFailed(DeviceSendFailure, requestId: String?)
    case message(ServerMessage, requestId: String?)
}

/// Events emitted by a device discovery session as services appear and disappear.
enum DiscoveryEvent {
    case found(DiscoveredDevice)
    case lost(DiscoveredDevice)
    case stateChanged(isReady: Bool)
}

// MARK: - Protocols

/// Manages a single connection to a discovered device, sending and receiving messages.
@ButtonHeistActor
protocol DeviceConnecting: AnyObject {
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)? { get set }
    func connect()
    func disconnect()
    @discardableResult
    func send(_ message: ClientMessage, requestId: String?) -> DeviceSendOutcome
}

/// Connection surface used by passive reachability probes. Raw socket
/// readiness is intentionally kept out of the authenticated lifecycle event
/// stream consumed by TheHandoff.
@ButtonHeistActor
protocol TransportReachabilityConnecting: DeviceConnecting {
    var onTransportReady: (@ButtonHeistActor () -> Void)? { get set }
}

/// Discovers Button Heist services on the local network via Bonjour or direct address.
@ButtonHeistActor
protocol DeviceDiscovering: AnyObject {
    var discoveredDevices: [DiscoveredDevice] { get }
    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)? { get set }
    func start()
    func stop()
}
