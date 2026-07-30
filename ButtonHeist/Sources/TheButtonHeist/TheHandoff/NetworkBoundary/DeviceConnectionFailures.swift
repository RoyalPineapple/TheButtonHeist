import Foundation
import ButtonHeistSupport
import TheScore

/// Structured reason for why a connection was closed.
///
/// Kept separate from FenceError because DisconnectReason is a value type
/// used by `ConnectionEvent.disconnected`, not a thrown error. It carries
/// transport-level detail (bufferOverflow, eventBacklogOverflow,
/// serverClosed, networkError, protocolMismatch, localDisconnect, missingToken)
/// that callers never need to catch. FenceError
/// is the single thrown error type for all of TheFence, TheHandoff, and
/// DeviceResolver.
enum DisconnectReason: Error, LocalizedError {
    case networkError(NetworkTransportFailure)
    case bufferOverflow
    case eventBacklogOverflow(maxEvents: Int)
    case serverClosed
    case authFailed(String, hint: String? = nil)
    case sessionLocked(String)
    case protocolMismatch(String)
    case localDisconnect
    case missingToken

    static func buttonHeistVersionMismatch(
        serverVersion: ButtonHeistVersion,
        clientVersion: ButtonHeistVersion
    ) -> DisconnectReason {
        .protocolMismatch(buttonHeistVersionMismatchMessage(serverVersion: serverVersion, clientVersion: clientVersion))
    }

    static func buttonHeistVersionMismatchMessage(
        serverVersion: ButtonHeistVersion,
        clientVersion: ButtonHeistVersion
    ) -> String {
        """
        Button Heist version mismatch: app/Inside Job is \(serverVersion), client/CLI/MCP is \(clientVersion). \
        Rebuild or reinstall the stale side so both use the same Button Heist version.
        """
    }

    var errorDescription: String? {
        cause
    }

    var failureCode: String {
        failureDetails.errorCode
    }

    var phase: FailurePhase {
        failureDetails.phase
    }

    var retryable: Bool {
        failureDetails.retryable
    }

    var hint: String? {
        failureDetails.hint
    }

    var cause: String {
        switch self {
        case .networkError(let failure):
            return "Network error: \(failure.description)"
        case .bufferOverflow:
            return "Server exceeded max buffer size"
        case .eventBacklogOverflow(let maxEvents):
            return "Connection event backlog exceeded \(maxEvents) buffered events"
        case .serverClosed:
            return "Connection closed by server"
        case .authFailed(let reason, _):
            return "Auth failed: \(reason)"
        case .sessionLocked(let message):
            return "Session locked: \(message)"
        case .protocolMismatch(let message):
            return "Protocol mismatch: \(message)"
        case .localDisconnect:
            return "Disconnected by client"
        case .missingToken:
            return "No token available for TLS pre-shared-key authentication"
        }
    }

    var failureDetails: FailureDetails {
        switch self {
        case .networkError:
            return FailureDetails(code: .transportNetworkError)
        case .bufferOverflow:
            return FailureDetails(code: .transportBufferOverflow)
        case .eventBacklogOverflow:
            return FailureDetails(code: .transportEventBacklogOverflow)
        case .serverClosed:
            return FailureDetails(code: .transportServerClosed)
        case .authFailed(_, let hint):
            return FailureDetails(code: .authFailed, hint: hint)
        case .sessionLocked:
            return FailureDetails(code: .sessionLocked)
        case .protocolMismatch:
            return FailureDetails(code: .protocolMismatch)
        case .localDisconnect:
            return FailureDetails(code: .clientLocalDisconnect)
        case .missingToken:
            return FailureDetails(code: .tlsMissingToken)
        }
    }

    var connectionFailureMessage: String {
        switch self {
        case .authFailed:
            return cause.replacingPrefix("Auth failed:", with: "Authentication failed:")
        case .sessionLocked:
            return cause
        default:
            let base = "connection failed in \(phase.rawValue): observed \(cause)"
            guard let hint else { return base }
            return "\(base); \(hint)"
        }
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return replacement + String(dropFirst(prefix.count))
    }
}

extension DisconnectReason: Equatable {
    static func == (lhs: DisconnectReason, rhs: DisconnectReason) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let lhsFailure), .networkError(let rhsFailure)):
            return lhsFailure == rhsFailure
        case (.bufferOverflow, .bufferOverflow),
             (.serverClosed, .serverClosed),
             (.localDisconnect, .localDisconnect),
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
