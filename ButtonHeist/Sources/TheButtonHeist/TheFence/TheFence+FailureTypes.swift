import Foundation

import TheScore

/// Stable client-side phase for connection and request failures.
///
/// This is not part of the wire protocol. It classifies existing local errors
/// so CLI/MCP surfaces and tests can reason about failures without parsing
/// human messages.
public enum FailurePhase: String, Sendable, Equatable, CaseIterable {
    case discovery
    case setup
    case transport
    case authentication = "auth"
    case session
    case request
    case protocolNegotiation = "protocol"
    case tls
    case client
    case server
}

/// Typed connection-attempt failure preserved from the lower-level disconnect cause.
public struct ConnectionFailure: Equatable, Sendable {
    public let message: String
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let hint: String?

    public init(
        message: String,
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.message = message
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }
}

extension ConnectionFailure {
    init(disconnectReason reason: DisconnectReason) {
        self.init(
            message: reason.connectionFailureMessage,
            errorCode: reason.failureCode,
            phase: reason.phase,
            retryable: reason.retryable,
            hint: reason.hint
        )
    }
}
