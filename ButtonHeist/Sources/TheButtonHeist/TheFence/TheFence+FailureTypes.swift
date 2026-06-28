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

/// Compiler-visible set of public failure codes known to Button Heist.
///
/// The raw values are the stable strings emitted in public JSON. Keep metadata
/// switches exhaustive so adding a known code requires explicit classification.
public enum KnownFailureCode: String, Codable, Sendable, CaseIterable {
    case requestInvalid = "request.invalid"
    case requestMissingTarget = "request.missing_target"
    case requestAccessibilityTreeUnavailable = "request.accessibility_tree_unavailable"
    case requestElementNotFound = "request.element_not_found"
    case requestTimeout = "request.timeout"
    case requestValidationError = "request.validation_error"
    case requestActionFailed = "request.action_failed"
    case discoveryNoDeviceFound = "discovery.no_device_found"
    case discoveryNoMatchingDevice = "discovery.no_matching_device"
    case discoveryAmbiguousDeviceTarget = "discovery.ambiguous_device_target"
    case setupTimeout = "setup.timeout"
    case connectionFailed = "connection.failed"
    case connectionNotConnected = "connection.not_connected"
    case connectionEndpointUnreachable = "connection.endpoint_unreachable"
    case transportNetworkError = "transport.network_error"
    case transportBufferOverflow = "transport.buffer_overflow"
    case transportEventBacklogOverflow = "transport.event_backlog_overflow"
    case transportServerClosed = "transport.server_closed"
    case authFailed = "auth.failed"
    case sessionLocked = "session.locked"
    case protocolMismatch = "protocol.mismatch"
    case tlsCertificateMismatch = "tls.certificate_mismatch"
    case tlsMissingFingerprint = "tls.missing_fingerprint"
    case tlsMissingToken = "tls.missing_token"
    case clientLocalDisconnect = "client.local_disconnect"
    case clientUnknown = "client.unknown"
    case serverGeneral = "server.general"
    case configReadFailed = "config.read_failed"
    case configDecodeFailed = "config.decode_failed"
    case formattingJSONEncodingFailed = "formatting.json_encoding_failed"
    case screenInlinePayloadTooLarge = "screen.inline_payload_too_large"

    public var kind: PublicFailureKind {
        switch self {
        case .requestInvalid,
             .requestMissingTarget,
             .requestAccessibilityTreeUnavailable,
             .requestElementNotFound,
             .requestTimeout,
             .requestValidationError,
             .requestActionFailed:
            return .request
        case .discoveryNoDeviceFound,
             .discoveryNoMatchingDevice,
             .discoveryAmbiguousDeviceTarget:
            return .discovery
        case .setupTimeout,
             .connectionFailed,
             .connectionNotConnected,
             .connectionEndpointUnreachable,
             .transportNetworkError,
             .transportBufferOverflow,
             .transportEventBacklogOverflow,
             .transportServerClosed,
             .protocolMismatch,
             .tlsCertificateMismatch,
             .tlsMissingFingerprint,
             .tlsMissingToken:
            return .connection
        case .authFailed:
            return .authentication
        case .sessionLocked:
            return .session
        case .configReadFailed,
             .configDecodeFailed:
            return .configuration
        case .serverGeneral:
            return .server
        case .clientLocalDisconnect,
             .formattingJSONEncodingFailed,
             .screenInlinePayloadTooLarge:
            return .client
        case .clientUnknown:
            return .unknown
        }
    }

    public var phase: FailurePhase {
        switch self {
        case .requestInvalid,
             .requestMissingTarget,
             .requestAccessibilityTreeUnavailable,
             .requestElementNotFound,
             .requestTimeout,
             .requestValidationError,
             .requestActionFailed,
             .connectionNotConnected:
            return .request
        case .discoveryNoDeviceFound,
             .discoveryNoMatchingDevice,
             .discoveryAmbiguousDeviceTarget:
            return .discovery
        case .setupTimeout,
             .configReadFailed,
             .configDecodeFailed:
            return .setup
        case .connectionFailed,
             .connectionEndpointUnreachable,
             .transportNetworkError,
             .transportBufferOverflow,
             .transportEventBacklogOverflow,
             .transportServerClosed:
            return .transport
        case .authFailed:
            return .authentication
        case .sessionLocked:
            return .session
        case .protocolMismatch:
            return .protocolNegotiation
        case .tlsCertificateMismatch,
             .tlsMissingFingerprint,
             .tlsMissingToken:
            return .tls
        case .clientLocalDisconnect,
             .clientUnknown,
             .formattingJSONEncodingFailed,
             .screenInlinePayloadTooLarge:
            return .client
        case .serverGeneral:
            return .server
        }
    }

    public var retryable: Bool {
        switch self {
        case .requestAccessibilityTreeUnavailable,
             .requestTimeout,
             .discoveryNoDeviceFound,
             .setupTimeout,
             .connectionFailed,
             .connectionNotConnected,
             .connectionEndpointUnreachable,
             .transportNetworkError,
             .transportEventBacklogOverflow,
             .transportServerClosed,
             .sessionLocked:
            return true
        case .requestInvalid,
             .requestMissingTarget,
             .requestElementNotFound,
             .requestValidationError,
             .requestActionFailed,
             .discoveryNoMatchingDevice,
             .discoveryAmbiguousDeviceTarget,
             .transportBufferOverflow,
             .authFailed,
             .protocolMismatch,
             .tlsCertificateMismatch,
             .tlsMissingFingerprint,
             .tlsMissingToken,
             .clientLocalDisconnect,
             .clientUnknown,
             .serverGeneral,
             .configReadFailed,
             .configDecodeFailed,
             .formattingJSONEncodingFailed,
             .screenInlinePayloadTooLarge:
            return false
        }
    }

    public var defaultHint: String? {
        switch self {
        case .requestInvalid:
            return "Fix the request shape or arguments before retrying."
        case .requestMissingTarget:
            return "get_interface()"
        case .requestAccessibilityTreeUnavailable:
            return "Wait for a traversable app window, then refresh the interface or retry the command."
        case .requestElementNotFound:
            return "Refresh the interface and verify the target's accessibility properties."
        case .requestTimeout:
            return FenceError.actionTimeoutRecoveryHint
        case .requestValidationError:
            return "Fix the request so it satisfies the server-side validation rules."
        case .requestActionFailed:
            return nil
        case .discoveryNoDeviceFound:
            return "Start the app and confirm it advertises a session for The Button Heist."
        case .discoveryNoMatchingDevice:
            return "Check the device filter or target name against 'buttonheist list_devices'."
        case .discoveryAmbiguousDeviceTarget:
            return "Narrow the device target using a unique app name, device name, instance ID, installation ID, simulator UDID, or direct host:port."
        case .setupTimeout:
            return "Is the app running? Check 'buttonheist list_devices' to see available devices."
        case .connectionFailed:
            return "Check that the app is running and reachable, then retry."
        case .connectionNotConnected:
            return "Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices."
        case .connectionEndpointUnreachable:
            return "Check that the app is running at the configured endpoint, then retry the command."
        case .transportNetworkError,
             .transportServerClosed:
            return "Check that the app is still running and reachable, then retry."
        case .transportBufferOverflow:
            return "Request a smaller payload or narrow the interface query before retrying."
        case .transportEventBacklogOverflow:
            return "Reconnect and retry after reducing event volume or response size."
        case .authFailed:
            return nil
        case .sessionLocked:
            return "Wait for the current driver to disconnect or for the session to time out. " +
                "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        case .protocolMismatch:
            return "Rebuild or reinstall so the CLI, MCP server, and iOS app use the same Button Heist version."
        case .tlsCertificateMismatch,
             .tlsMissingFingerprint:
            return "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
        case .tlsMissingToken:
            return "Set BUTTONHEIST_TOKEN, pass --token, or configure a target token."
        case .clientLocalDisconnect,
             .clientUnknown,
             .serverGeneral:
            return nil
        case .configReadFailed,
             .configDecodeFailed:
            return "Verify the config path points to a readable JSON file matching the Button Heist config schema."
        case .formattingJSONEncodingFailed:
            return "Report this diagnostic with the command that produced it."
        case .screenInlinePayloadTooLarge:
            return "Omit inlineData or pass output to receive a screenshot artifact path."
        }
    }
}

/// Public failure code value that preserves raw JSON strings at boundaries while
/// exposing typed metadata for codes known to this client.
public struct FailureCode: RawRepresentable, Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public var knownCode: KnownFailureCode? {
        KnownFailureCode(rawValue: rawValue)
    }

    public var kind: PublicFailureKind? {
        knownCode?.kind
    }

    public var phase: FailurePhase? {
        knownCode?.phase
    }

    public var retryable: Bool? {
        knownCode?.retryable
    }

    public var defaultHint: String? {
        knownCode?.defaultHint
    }

    public var description: String {
        rawValue
    }

    public init(_ knownCode: KnownFailureCode) {
        self.rawValue = knownCode.rawValue
    }

    /// Boundary initializer for raw public JSON/API values.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension FailureDetails {
    /// Typed failure code. `errorCode` remains the raw JSON/API boundary value.
    var code: FailureCode {
        FailureCode(rawValue: errorCode)
    }

    init(code: FailureCode, phase: FailurePhase, retryable: Bool, hint: String?) {
        self.init(errorCode: code.rawValue, phase: phase, retryable: retryable, hint: hint)
    }

    init(code knownCode: KnownFailureCode, hint: String? = nil) {
        self.init(
            code: FailureCode(knownCode),
            phase: knownCode.phase,
            retryable: knownCode.retryable,
            hint: hint ?? knownCode.defaultHint
        )
    }
}

/// Canonical diagnostic failure shape used by CLI and MCP responses.
public struct DiagnosticFailure: Sendable, Equatable {
    /// Typed machine-readable failure code.
    public let failureCode: FailureCode
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
        code: .clientUnknown,
        hint: nil
    )

    /// Creates a diagnostic failure from fully typed metadata.
    public init(message: String, details: FailureDetails, kind: PublicFailureKind? = nil) {
        self.failureCode = details.code
        self.code = details.code.rawValue
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
    public let failureCode: FailureCode
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let hint: String?

    public init(
        message: String,
        failureCode: FailureCode,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.message = message
        self.failureCode = failureCode
        self.errorCode = failureCode.rawValue
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }

    public init(
        message: String,
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.init(
            message: message,
            failureCode: FailureCode(rawValue: errorCode),
            phase: phase,
            retryable: retryable,
            hint: hint
        )
    }
}

extension ConnectionFailure {
    init(disconnectReason reason: DisconnectReason) {
        self.init(
            message: reason.connectionFailureMessage,
            failureCode: FailureCode(rawValue: reason.failureCode),
            phase: reason.phase,
            retryable: reason.retryable,
            hint: reason.hint
        )
    }
}

private extension PublicFailureKind {
    init(details: FailureDetails) {
        if let typedKind = details.code.kind {
            self = typedKind
            return
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
