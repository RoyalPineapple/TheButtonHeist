import Foundation
import Network

// MARK: - Event Enums

/// Synchronous outcome for handing a client message to the transport.
enum DeviceSendOutcome: Equatable, Sendable {
    case enqueued
    case failed(DeviceSendFailure)
}

struct DeviceEncodingFailure: Error, LocalizedError, Equatable, Sendable, CustomStringConvertible {
    let underlyingDescription: String

    init(_ error: any Error) {
        self.underlyingDescription = String(describing: error)
    }

    var description: String {
        underlyingDescription
    }

    var errorDescription: String? {
        underlyingDescription
    }
}

struct DeviceTransportFailure: Error, LocalizedError, Equatable, Sendable, CustomStringConvertible {
    enum Reason: Equatable, Sendable {
        case posix(code: Int)
        case dns(code: Int)
        case tls(status: Int)
        case wifiAware(code: Int)
        case unknown(String)
    }

    let reason: Reason
    let underlyingDescription: String

    init(_ error: NWError) {
        let reason = Self.reason(for: error)
        self.reason = reason
        self.underlyingDescription = "\(reason.description): \(error.localizedDescription)"
    }

    var description: String {
        underlyingDescription
    }

    var errorDescription: String? {
        underlyingDescription
    }

    var isEmpty: Bool {
        underlyingDescription.isEmpty
    }

    private static func reason(for error: NWError) -> Reason {
        switch error {
        case .posix(let code):
            return .posix(code: Int(code.rawValue))
        case .dns(let code):
            return .dns(code: Int(code))
        case .tls(let status):
            return .tls(status: Int(status))
        case .wifiAware(let code):
            return .wifiAware(code: Int(code))
        @unknown default:
            return .unknown(String(describing: error))
        }
    }
}

extension DeviceTransportFailure.Reason: CustomStringConvertible {
    var description: String {
        switch self {
        case .posix(let code):
            return "posix(\(code))"
        case .dns(let code):
            return "dns(\(code))"
        case .tls(let status):
            return "tls(\(status))"
        case .wifiAware(let code):
            return "wifiAware(\(code))"
        case .unknown(let description):
            return "unknown(\(description))"
        }
    }
}

enum DeviceSendFailure: Error, LocalizedError, Equatable, Sendable {
    case notConnected
    case encodingFailed(DeviceEncodingFailure)
    case transportFailed(DeviceTransportFailure)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connection is closed"
        case .encodingFailed(let failure):
            return "Failed to encode request: \(failure.description)"
        case .transportFailed(let failure):
            return "Transport send failed: \(failure.description)"
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
