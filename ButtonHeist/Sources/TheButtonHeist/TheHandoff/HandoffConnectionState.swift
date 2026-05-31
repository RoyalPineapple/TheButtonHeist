import Foundation
import os.log

private let driverIdentityLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "driver-identity")

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

struct HandoffReconnectAttempt {
    let target: HandoffReconnectTarget
}

enum HandoffConnectionPhase {
    case disconnected
    case reconnecting(HandoffReconnectAttempt)
    case connecting(HandoffConnectionAttempt)
    case connected(HandoffConnectedSession)
    case failed(HandoffConnectionError)
}

/// Concrete device identity auto-reconnect is allowed to recover.
struct HandoffReconnectTarget: Equatable {
    let filter: String?
    let device: DiscoveredDevice
}

enum HandoffDriverIdentity {
    static func effectiveDriverId(explicit driverId: String?) -> String {
        if let driverId, !driverId.isEmpty { return driverId }
        return persistentDriverId
    }

    private static let driverIdFile: URL = {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".buttonheist", isDirectory: true)
        return configDir.appendingPathComponent("driver-id")
    }()

    private static let persistentDriverId: String = {
        let fileURL = driverIdFile
        let existingValue: String?
        do {
            existingValue = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            existingValue = nil
        }
        if let existing = existingValue, !existing.isEmpty {
            repairDriverIdPermissions(fileURL)
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            driverIdentityLogger.warning("Failed to create driver-id directory: \(error.localizedDescription)")
        }
        if !FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(generated.utf8),
            attributes: [.posixPermissions: 0o600]
        ) {
            driverIdentityLogger.warning("Failed to persist driver-id to \(fileURL.path)")
        }
        return generated
    }()

    private static func repairDriverIdPermissions(_ fileURL: URL) {
        let fileManager = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch {
            driverIdentityLogger.warning("Failed to repair driver-id directory permissions: \(error.localizedDescription)")
        }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            driverIdentityLogger.warning("Failed to repair driver-id file permissions: \(error.localizedDescription)")
        }
    }
}
