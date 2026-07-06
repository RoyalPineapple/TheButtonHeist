import Foundation
import os.log
import TheScore

private let driverIdentityLogger = ButtonHeistLog.logger(.handoff(.driverIdentity))

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
                code: .connectionFailed
            )
        case .disconnected(let reason):
            return reason.diagnostic
        case .timeout:
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Connection timed out",
                code: .setupTimeout,
                hint: "Check that the app is running with Button Heist enabled; use 'buttonheist list_devices' to see available devices."
            )
        case .noDeviceFound:
            return HandoffFailureDiagnostic(
                operation: .discovery,
                target: nil,
                cause: "No device found",
                code: .discoveryNoDeviceFound,
                hint: "Start the app and confirm it advertises a Button Heist session."
            )
        case .noMatchingDevice(let filter, let available):
            return HandoffFailureDiagnostic(
                operation: .resolution,
                target: filter,
                cause: "No matching device",
                code: .discoveryNoMatchingDevice,
                candidates: available
            )
        case .ambiguousDeviceTarget(let filter, let matches):
            return HandoffFailureDiagnostic(
                operation: .resolution,
                target: filter,
                cause: "Ambiguous device target",
                code: .discoveryAmbiguousDeviceTarget,
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
    let details: FailureDetails
    let candidates: [String]

    var errorCode: String { details.errorCode }
    var phase: FailurePhase { details.phase }
    var retryable: Bool { details.retryable }
    var hint: String? { details.hint }

    init(
        operation: HandoffFailureOperation,
        target: String?,
        cause: String,
        code: KnownFailureCode,
        hint: String?,
        candidates: [String] = []
    ) {
        self.operation = operation
        self.target = target
        self.cause = cause
        self.details = FailureDetails(code: code, hint: hint)
        self.candidates = candidates
    }

    init(
        operation: HandoffFailureOperation,
        target: String?,
        cause: String,
        code: KnownFailureCode,
        candidates: [String] = []
    ) {
        self.init(
            operation: operation,
            target: target,
            cause: cause,
            code: code,
            hint: nil,
            candidates: candidates
        )
    }
}

enum HandoffFailureFormatter {
    static func message(for diagnostic: HandoffFailureDiagnostic) -> String {
        switch diagnostic.details.code.knownCode {
        case .connectionFailed:
            return diagnostic.cause
        case .setupTimeout:
            return "Connection timed out"
        case .discoveryNoDeviceFound:
            return "No device found"
        case .discoveryNoMatchingDevice:
            let available = diagnostic.candidates.joined(separator: ", ")
            return "No device matching '\(diagnostic.target ?? "(none)")' (available: \(available))"
        case .discoveryAmbiguousDeviceTarget:
            let matches = diagnostic.candidates.joined(separator: ", ")
            return "Ambiguous device target '\(diagnostic.target ?? "(none)")' (matches: \(matches))"
        case .authFailed:
            return diagnostic.cause.replacingPrefix("Auth failed:", with: "Authentication failed:")
        case .sessionLocked:
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
    let runID: UUID
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
struct HandoffReconnectTarget: Equatable, Sendable {
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
