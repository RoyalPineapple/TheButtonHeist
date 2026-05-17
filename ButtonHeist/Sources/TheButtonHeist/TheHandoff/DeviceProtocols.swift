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

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connection is closed"
        case .encodingFailed(let message):
            return "Failed to encode request: \(message)"
        }
    }
}

/// Events emitted by a device connection during its lifecycle.
enum ConnectionEvent {
    case transportReady
    case connected
    case disconnected(DisconnectReason)
    case message(
        ServerMessage,
        requestId: String?,
        backgroundAccessibilityDelta: AccessibilityTrace.Delta?,
        accessibilityTrace: AccessibilityTrace?
    )
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
    var isConnected: Bool { get }
    var observeMode: Bool { get set }
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)? { get set }
    func connect()
    func disconnect()
    @discardableResult
    func send(_ message: ClientMessage, requestId: String?) -> DeviceSendOutcome
}

extension DeviceConnecting {
    @discardableResult
    func send(_ message: ClientMessage) -> DeviceSendOutcome {
        send(message, requestId: nil)
    }
}

/// Discovers Button Heist services on the local network via Bonjour or direct address.
@ButtonHeistActor
protocol DeviceDiscovering: AnyObject {
    var discoveredDevices: [DiscoveredDevice] { get }
    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)? { get set }
    func start()
    func stop()
}
