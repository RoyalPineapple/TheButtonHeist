import Foundation

/// Why a connection attempt failed. TheFence maps this domain error at the boundary.
///
/// Also used as the associated value in `HandoffConnectionPhase.failed`, which
/// is why this enum is `Equatable`. Not every case can appear in `.failed`: the
/// phase-producing cases are `connectionFailed` and `disconnected`; auth and
/// session-lock failures are disconnect causes. The resolver/timeout cases are
/// thrown directly from resolution/waiting paths and never become a phase value.
enum HandoffConnectionError: Error, LocalizedError, Equatable {
    case connectionFailed(String)
    case disconnected(DisconnectReason)
    case timeout
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message): return message
        case .disconnected(.authFailed(let reason)): return "Authentication failed: \(reason)"
        case .disconnected(.authApprovalPending(let message)): return "Authentication approval pending: \(message)"
        case .disconnected(.sessionLocked(let message)): return "Session locked: \(message)"
        case .disconnected(let reason): return reason.connectionFailureMessage
        case .timeout: return "Connection timed out"
        case .noDeviceFound: return "No device found"
        case .noMatchingDevice(let filter, let available):
            return "No device matching '\(filter)' (available: \(available.joined(separator: ", ")))"
        }
    }

    var failureCode: String {
        switch self {
        case .connectionFailed:
            return "connection.failed"
        case .disconnected(let reason):
            return reason.failureCode
        case .timeout:
            return "setup.timeout"
        case .noDeviceFound:
            return "discovery.no_device_found"
        case .noMatchingDevice:
            return "discovery.no_matching_device"
        }
    }

    var phase: FailurePhase {
        switch self {
        case .connectionFailed:
            return .transport
        case .disconnected(let reason):
            return reason.phase
        case .timeout:
            return .setup
        case .noDeviceFound, .noMatchingDevice:
            return .discovery
        }
    }

    var retryable: Bool {
        switch self {
        case .connectionFailed, .timeout, .noDeviceFound:
            return true
        case .disconnected(let reason):
            return reason.retryable
        case .noMatchingDevice:
            return false
        }
    }

    var hint: String? {
        switch self {
        case .connectionFailed:
            return "Check that the app is running and reachable, then retry."
        case .disconnected(let reason):
            return reason.hint
        case .timeout:
            return "Check that the app is running with Button Heist enabled; use 'buttonheist list_devices' to see available devices."
        case .noDeviceFound:
            return "Start the app and confirm it advertises a Button Heist session."
        case .noMatchingDevice:
            return "Check the device filter or target name against 'buttonheist list_devices'."
        }
    }
}

/// State carried while connected: device, keepalive task, and the lifecycle-scoped data
/// that only makes sense during a live connection.
struct HandoffConnectedSession {
    let attemptID: UUID
    let device: DiscoveredDevice
    let keepaliveTask: Task<Void, Never>
    var serverInfo: ServerInfo?
    var missedPongCount: Int

    init(
        attemptID: UUID,
        device: DiscoveredDevice,
        keepaliveTask: Task<Void, Never>,
        serverInfo: ServerInfo? = nil,
        missedPongCount: Int = 0
    ) {
        self.attemptID = attemptID
        self.device = device
        self.keepaliveTask = keepaliveTask
        self.serverInfo = serverInfo
        self.missedPongCount = missedPongCount
    }
}

/// Explicit connection lifecycle state machine. The device is carried in connecting and connected states.
struct HandoffConnectionAttempt {
    let id: UUID
    let device: DiscoveredDevice
}

enum HandoffConnectionPhase {
    case disconnected
    case connecting(HandoffConnectionAttempt)
    case connected(HandoffConnectedSession)
    case failed(HandoffConnectionError)
}

/// Concrete device identity auto-reconnect is allowed to recover.
struct HandoffReconnectTarget: Equatable {
    let filter: String?
    let device: DiscoveredDevice

    var displayName: String { device.name }

    func resolve(from discoveredDevices: [DiscoveredDevice]) -> DiscoveredDevice? {
        if device.reconnectsWithoutDiscovery {
            return device
        }

        return discoveredDevices.first { candidate in
            candidate.discoveryIdentity == device.discoveryIdentity && (
                filter.map { candidate.matches(filter: $0) } ?? true
            )
        }
    }
}

private extension DiscoveredDevice {
    var reconnectsWithoutDiscovery: Bool {
        if case .hostPort = endpoint {
            return true
        }
        return false
    }
}
