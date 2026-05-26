import Foundation

/// Structured reason for why a connection was closed.
///
/// Kept separate from FenceError because DisconnectReason is a value type
/// used by `ConnectionEvent.disconnected`, not a thrown error. It carries
/// transport-level detail (bufferOverflow, eventBacklogOverflow,
/// serverClosed, networkError, certificateMismatch, protocolMismatch,
/// localDisconnect) that callers never need to catch. FenceError is
/// the single thrown error type for all of TheFence, TheHandoff, and
/// DeviceResolver.
enum DisconnectReason: Error, LocalizedError {
    case networkError(Error)
    case bufferOverflow
    case eventBacklogOverflow(maxEvents: Int)
    case serverClosed
    case authFailed(String)
    case authApprovalPending(String)
    case sessionLocked(String)
    case protocolMismatch(String)
    case localDisconnect
    case certificateMismatch
    case missingFingerprint

    static func buttonHeistVersionMismatch(serverVersion: String, clientVersion: String) -> DisconnectReason {
        .protocolMismatch(buttonHeistVersionMismatchMessage(serverVersion: serverVersion, clientVersion: clientVersion))
    }

    static func buttonHeistVersionMismatchMessage(serverVersion: String, clientVersion: String) -> String {
        """
        Button Heist version mismatch: app/Inside Job is \(serverVersion), client/CLI/MCP is \(clientVersion). \
        Rebuild or reinstall the stale side so both use the same Button Heist version.
        """
    }

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .bufferOverflow:
            return "Server exceeded max buffer size"
        case .eventBacklogOverflow(let maxEvents):
            return "Connection event backlog exceeded \(maxEvents) buffered events"
        case .serverClosed:
            return "Connection closed by server"
        case .authFailed(let reason):
            return "Auth failed: \(reason)"
        case .authApprovalPending(let message):
            return "Auth approval pending: \(message)"
        case .sessionLocked(let message):
            return "Session locked: \(message)"
        case .protocolMismatch(let message):
            return "Protocol mismatch: \(message)"
        case .localDisconnect:
            return "Disconnected by client"
        case .certificateMismatch:
            return "Server certificate fingerprint does not match expected value"
        case .missingFingerprint:
            return "No TLS fingerprint available for non-loopback device — cannot establish secure connection"
        }
    }

    var failureCode: String {
        switch self {
        case .networkError:
            return "transport.network_error"
        case .bufferOverflow:
            return "transport.buffer_overflow"
        case .eventBacklogOverflow:
            return "transport.event_backlog_overflow"
        case .serverClosed:
            return "transport.server_closed"
        case .authFailed:
            return "auth.failed"
        case .authApprovalPending:
            return "auth.approval_pending"
        case .sessionLocked:
            return "session.locked"
        case .protocolMismatch:
            return "protocol.mismatch"
        case .localDisconnect:
            return "client.local_disconnect"
        case .certificateMismatch:
            return "tls.certificate_mismatch"
        case .missingFingerprint:
            return "tls.missing_fingerprint"
        }
    }

    var phase: FailurePhase {
        switch self {
        case .networkError, .bufferOverflow, .eventBacklogOverflow, .serverClosed:
            return .transport
        case .authFailed, .authApprovalPending:
            return .authentication
        case .sessionLocked:
            return .session
        case .protocolMismatch:
            return .protocolNegotiation
        case .localDisconnect:
            return .client
        case .certificateMismatch, .missingFingerprint:
            return .tls
        }
    }

    var retryable: Bool {
        switch self {
        case .networkError, .eventBacklogOverflow, .serverClosed, .sessionLocked, .authApprovalPending:
            return true
        case .bufferOverflow, .authFailed, .protocolMismatch, .localDisconnect,
             .certificateMismatch, .missingFingerprint:
            return false
        }
    }

    var hint: String? {
        switch self {
        case .networkError, .serverClosed:
            return "Check that the app is still running and reachable, then retry."
        case .bufferOverflow:
            return "Request a smaller payload or narrow the interface query before retrying."
        case .eventBacklogOverflow:
            return "Reconnect and retry after reducing event volume or response size."
        case .authFailed(let reason):
            if reason.localizedCaseInsensitiveContains("configured token") {
                return "Retry with the configured token."
            }
            if reason.localizedCaseInsensitiveContains("retry without") {
                return "Retry without a token to request a fresh session."
            }
            return nil
        case .authApprovalPending:
            return "Waiting for approval on the device. Tap Allow on the iOS device to continue."
        case .sessionLocked:
            return "Wait for the current driver to disconnect or for the session to time out. " +
                "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        case .protocolMismatch:
            return "Rebuild or reinstall so the CLI, MCP server, and iOS app use the same Button Heist version."
        case .localDisconnect:
            return nil
        case .certificateMismatch:
            return "Refresh the configured device fingerprint before reconnecting."
        case .missingFingerprint:
            return "Use a loopback simulator target or configure the device's TLS certificate fingerprint."
        }
    }

    var connectionFailureMessage: String {
        let base = "connection failed in \(phase.rawValue): observed \(observedCause)"
        guard let hint else { return base }
        return "\(base); \(hint)"
    }

    private var observedCause: String {
        errorDescription ?? localizedDescription
    }
}

extension DisconnectReason: Equatable {
    static func == (lhs: DisconnectReason, rhs: DisconnectReason) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let lhsError), .networkError(let rhsError)):
            let lhsNSError = lhsError as NSError
            let rhsNSError = rhsError as NSError
            return lhsNSError.domain == rhsNSError.domain &&
                lhsNSError.code == rhsNSError.code &&
                lhsNSError.localizedDescription == rhsNSError.localizedDescription
        case (.bufferOverflow, .bufferOverflow),
             (.serverClosed, .serverClosed),
             (.localDisconnect, .localDisconnect),
             (.certificateMismatch, .certificateMismatch),
             (.missingFingerprint, .missingFingerprint):
            return true
        case (.eventBacklogOverflow(let lhsMaxEvents), .eventBacklogOverflow(let rhsMaxEvents)):
            return lhsMaxEvents == rhsMaxEvents
        case (.authFailed(let lhsReason), .authFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.authApprovalPending(let lhsMessage), .authApprovalPending(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.sessionLocked(let lhsMessage), .sessionLocked(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.protocolMismatch(let lhsMessage), .protocolMismatch(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// `@unchecked Sendable` justification: all access to `reason` is serialized by `lock`.
final class TLSFailureTracker: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private var reason: DisconnectReason?

    func record(_ reason: DisconnectReason) {
        lock.withLock {
            self.reason = reason
        }
    }

    func currentReason() -> DisconnectReason? {
        lock.withLock {
            reason
        }
    }
}
