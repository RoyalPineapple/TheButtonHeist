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
    case ambiguousDeviceTarget(filter: String, matches: [String])

    var errorDescription: String? {
        HandoffFailureFormatter.message(for: diagnostic)
    }

    var failureCode: String {
        diagnostic.errorCode
    }

    var phase: FailurePhase {
        diagnostic.phase
    }

    var retryable: Bool {
        diagnostic.retryable
    }

    var hint: String? {
        diagnostic.hint
    }

    var diagnostic: HandoffFailureDiagnostic {
        switch self {
        case .connectionFailed(let message):
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: message,
                errorCode: "connection.failed",
                phase: .transport,
                retryable: true,
                hint: "Check that the app is running and reachable, then retry."
            )
        case .disconnected(let reason):
            return reason.diagnostic
        case .timeout:
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Connection timed out",
                errorCode: "setup.timeout",
                phase: .setup,
                retryable: true,
                hint: "Check that the app is running with Button Heist enabled; use 'buttonheist list_devices' to see available devices."
            )
        case .noDeviceFound:
            return HandoffFailureDiagnostic(
                operation: .discovery,
                target: nil,
                cause: "No device found",
                errorCode: "discovery.no_device_found",
                phase: .discovery,
                retryable: true,
                hint: "Start the app and confirm it advertises a Button Heist session."
            )
        case .noMatchingDevice(let filter, let available):
            return HandoffFailureDiagnostic(
                operation: .resolution,
                target: filter,
                cause: "No matching device",
                errorCode: "discovery.no_matching_device",
                phase: .discovery,
                retryable: false,
                hint: "Check the device filter or target name against 'buttonheist list_devices'.",
                candidates: available
            )
        case .ambiguousDeviceTarget(let filter, let matches):
            return HandoffFailureDiagnostic(
                operation: .resolution,
                target: filter,
                cause: "Ambiguous device target",
                errorCode: "discovery.ambiguous_device_target",
                phase: .discovery,
                retryable: false,
                hint: "Narrow the device target using a unique app name, device name, instance ID, installation ID, simulator UDID, or direct host:port.",
                candidates: matches
            )
        }
    }
}

enum HandoffFailureOperation: String, Equatable, Sendable {
    case discovery
    case resolution
    case connection
    case transport
}

struct HandoffFailureDiagnostic: Equatable, Sendable {
    let operation: HandoffFailureOperation
    let target: String?
    let cause: String
    let errorCode: String
    let phase: FailurePhase
    let retryable: Bool
    let hint: String?
    let candidates: [String]

    init(
        operation: HandoffFailureOperation,
        target: String?,
        cause: String,
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?,
        candidates: [String] = []
    ) {
        self.operation = operation
        self.target = target
        self.cause = cause
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
        self.candidates = candidates
    }
}

enum HandoffFailureFormatter {
    static func message(for diagnostic: HandoffFailureDiagnostic) -> String {
        switch diagnostic.errorCode {
        case "connection.failed":
            return diagnostic.cause
        case "setup.timeout":
            return "Connection timed out"
        case "discovery.no_device_found":
            return "No device found"
        case "discovery.no_matching_device":
            let available = diagnostic.candidates.joined(separator: ", ")
            return "No device matching '\(diagnostic.target ?? "(none)")' (available: \(available))"
        case "discovery.ambiguous_device_target":
            let matches = diagnostic.candidates.joined(separator: ", ")
            return "Ambiguous device target '\(diagnostic.target ?? "(none)")' (matches: \(matches))"
        case "auth.failed":
            return diagnostic.cause.replacingPrefix("Auth failed:", with: "Authentication failed:")
        case "session.locked":
            return diagnostic.cause
        default:
            return connectionFailureMessage(for: diagnostic)
        }
    }

    static func connectionFailureMessage(for diagnostic: HandoffFailureDiagnostic) -> String {
        let base = "connection failed in \(diagnostic.phase.rawValue): observed \(diagnostic.cause)"
        guard let hint = diagnostic.hint else { return base }
        return "\(base); \(hint)"
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return replacement + String(dropFirst(prefix.count))
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
