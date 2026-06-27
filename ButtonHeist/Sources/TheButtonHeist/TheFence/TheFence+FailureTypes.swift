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

/// Stable public category for a command failure.
public enum PublicFailureKind: String, Sendable, Equatable {
    case request
    case discovery
    case connection
    case authentication = "auth"
    case session
    case configuration
    case server
    case client
    case unknown
}

/// Canonical diagnostic failure shape used by CLI and MCP responses.
public struct DiagnosticFailure: Sendable, Equatable {
    /// Stable machine-readable failure code.
    public let code: String
    /// Broad public category for the failure.
    public let kind: PublicFailureKind
    /// User-facing failure message.
    public let message: String
    /// Lifecycle metadata and recovery hint for the failure.
    public let details: FailureDetails

    /// Display-ready failure message.
    public var displayMessage: String { message }

    /// Lifecycle phase where the failure occurred.
    public var phase: FailurePhase { details.phase }

    /// Whether retrying the same operation can reasonably succeed.
    public var retryable: Bool { details.retryable }

    /// Short recovery hint that can be surfaced separately from the message.
    public var hint: String? { details.hint }

    private static let unknownDetails = FailureDetails(
        errorCode: "client.unknown",
        phase: .client,
        retryable: false,
        hint: nil
    )

    /// Creates a diagnostic failure from fully typed metadata.
    public init(message: String, details: FailureDetails, kind: PublicFailureKind? = nil) {
        self.code = details.errorCode
        self.kind = kind ?? PublicFailureKind(details: details)
        self.message = message
        self.details = details
    }

    /// Creates a diagnostic failure, falling back to the unknown client error
    /// shape when details are absent.
    public init(message: String, details: FailureDetails?, kind: PublicFailureKind? = nil) {
        let resolvedKind: PublicFailureKind?
        if let kind {
            resolvedKind = kind
        } else if details == nil {
            resolvedKind = .unknown
        } else {
            resolvedKind = nil
        }
        self.init(
            message: message,
            details: details ?? Self.unknownDetails,
            kind: resolvedKind
        )
    }
}

/// Source-compatible public failure name for response/rendering boundaries.
public typealias PublicFailure = DiagnosticFailure

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

private extension PublicFailureKind {
    init(details: FailureDetails) {
        if let prefix = details.errorCode.split(separator: ".").first.map(String.init) {
            switch prefix {
            case "request":
                self = .request
                return
            case "discovery":
                self = .discovery
                return
            case "setup", "connection", "protocol", "tls":
                self = .connection
                return
            case "auth":
                self = .authentication
                return
            case "session":
                self = .session
                return
            case "config":
                self = .configuration
                return
            case "server":
                self = .server
                return
            case "client", "formatting", "screen":
                self = .client
                return
            default:
                break
            }
        }

        switch details.phase {
        case .discovery:
            self = .discovery
        case .setup, .transport, .protocolNegotiation, .tls:
            self = .connection
        case .authentication:
            self = .authentication
        case .session:
            self = .session
        case .server:
            self = .server
        case .request:
            self = .request
        case .client:
            self = .client
        }
    }
}
