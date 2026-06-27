import Foundation

/// Structured reason for why a connection was closed.
///
/// Kept separate from FenceError because DisconnectReason is a value type
/// used by `ConnectionEvent.disconnected`, not a thrown error. It carries
/// transport-level detail (bufferOverflow, eventBacklogOverflow,
/// serverClosed, networkError, protocolMismatch, localDisconnect, missingToken,
/// and legacy certificate failures) that callers never need to catch. FenceError
/// is the single thrown error type for all of TheFence, TheHandoff, and
/// DeviceResolver.
enum DisconnectReason: Error, LocalizedError {
    case networkError(Error)
    case bufferOverflow
    case eventBacklogOverflow(maxEvents: Int)
    case serverClosed
    case authFailed(String, hint: String? = nil)
    case sessionLocked(String)
    case protocolMismatch(String)
    case localDisconnect
    // Legacy certificate-pinning failures are retained for old diagnostics only.
    // Current clients authenticate with token-derived TLS PSK.
    case certificateMismatch
    case missingFingerprint
    case missingToken

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
        diagnostic.cause
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
        case .networkError(let error):
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Network error: \(error.localizedDescription)",
                errorCode: "transport.network_error",
                phase: .transport,
                retryable: true,
                hint: "Check that the app is still running and reachable, then retry."
            )
        case .bufferOverflow:
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Server exceeded max buffer size",
                errorCode: "transport.buffer_overflow",
                phase: .transport,
                retryable: false,
                hint: "Request a smaller payload or narrow the interface query before retrying."
            )
        case .eventBacklogOverflow(let maxEvents):
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Connection event backlog exceeded \(maxEvents) buffered events",
                errorCode: "transport.event_backlog_overflow",
                phase: .transport,
                retryable: true,
                hint: "Reconnect and retry after reducing event volume or response size."
            )
        case .serverClosed:
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Connection closed by server",
                errorCode: "transport.server_closed",
                phase: .transport,
                retryable: true,
                hint: "Check that the app is still running and reachable, then retry."
            )
        case .authFailed(let reason, let hint):
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Auth failed: \(reason)",
                errorCode: "auth.failed",
                phase: .authentication,
                retryable: false,
                hint: hint
            )
        case .sessionLocked(let message):
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Session locked: \(message)",
                errorCode: "session.locked",
                phase: .session,
                retryable: true,
                hint: "Wait for the current driver to disconnect or for the session to time out. " +
                    "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
            )
        case .protocolMismatch(let message):
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Protocol mismatch: \(message)",
                errorCode: "protocol.mismatch",
                phase: .protocolNegotiation,
                retryable: false,
                hint: "Rebuild or reinstall so the CLI, MCP server, and iOS app use the same Button Heist version."
            )
        case .localDisconnect:
            return HandoffFailureDiagnostic(
                operation: .connection,
                target: nil,
                cause: "Disconnected by client",
                errorCode: "client.local_disconnect",
                phase: .client,
                retryable: false,
                hint: nil
            )
        case .certificateMismatch:
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Legacy TLS certificate fingerprint does not match expected value",
                errorCode: "tls.certificate_mismatch",
                phase: .tls,
                retryable: false,
                hint: "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
            )
        case .missingFingerprint:
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "Legacy TLS certificate fingerprint is unavailable for this device",
                errorCode: "tls.missing_fingerprint",
                phase: .tls,
                retryable: false,
                hint: "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
            )
        case .missingToken:
            return HandoffFailureDiagnostic(
                operation: .transport,
                target: nil,
                cause: "No token available for TLS pre-shared-key authentication",
                errorCode: "tls.missing_token",
                phase: .tls,
                retryable: false,
                hint: "Set BUTTONHEIST_TOKEN, pass --token, or configure a target token."
            )
        }
    }

    var connectionFailureMessage: String {
        HandoffFailureFormatter.connectionFailureMessage(for: diagnostic)
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
             (.missingFingerprint, .missingFingerprint),
             (.missingToken, .missingToken):
            return true
        case (.eventBacklogOverflow(let lhsMaxEvents), .eventBacklogOverflow(let rhsMaxEvents)):
            return lhsMaxEvents == rhsMaxEvents
        case (.authFailed(let lhsReason, let lhsHint), .authFailed(let rhsReason, let rhsHint)):
            return lhsReason == rhsReason && lhsHint == rhsHint
        case (.sessionLocked(let lhsMessage), .sessionLocked(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.protocolMismatch(let lhsMessage), .protocolMismatch(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// Captures the underlying TLS `DisconnectReason` observed off-actor on the
/// network callback, so a connection failure can be diagnosed after the fact.
///
/// **Ownership.** Single-slot index owned by `DeviceConnection` for the span of
/// one connection attempt. Key: none (one reason). Lifetime: per attempt.
/// Invalidation: overwritten by a newer reason; dropped when the attempt's
/// `DeviceConnection` is released. It cannot be derived from a receipt —
/// `NWConnection` discards the TLS failure cause once the connection tears down,
/// so this is the only place it survives. See `docs/ARCHITECTURE.md#state-has-one-owner`.
///
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
