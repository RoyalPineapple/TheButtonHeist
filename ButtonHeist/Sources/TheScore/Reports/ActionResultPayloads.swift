import ThePlans
import Foundation

/// Failure classification for action dispatch and observation.
public enum ActionFailure {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case accessibilityTreeUnavailable
        case elementNotFound
        case timeout
        case validationError
        case actionFailed
    }
}

struct ReportAdmissionError: Error, Sendable, CustomStringConvertible {
    let description: String
}

/// Structured payload for server-broadcast error messages.
public struct ServerErrorMessage: Codable, Sendable, Equatable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonEmpty(
            value,
            or: ReportAdmissionError(description: "server error message must not be empty")
        )
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { value }
}

extension ServerErrorMessage: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public struct ServerErrorRecoveryHint: Codable, Sendable, Equatable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonEmpty(
            value,
            or: ReportAdmissionError(description: "server error recoveryHint must not be empty")
        )
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { value }
}

extension ServerErrorRecoveryHint: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public struct ServerError: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Authentication failed (rejected token or rate-limited).
        case authFailure
        /// General server error not tied to a specific action.
        case general
    }

    public let kind: Kind
    public let message: ServerErrorMessage
    public let recoveryHint: ServerErrorRecoveryHint?

    public init(
        kind: Kind,
        message: ServerErrorMessage,
        recoveryHint: ServerErrorRecoveryHint? = nil
    ) {
        self.kind = kind
        self.message = message
        self.recoveryHint = recoveryHint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case message
        case recoveryHint
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "server error")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(Kind.self, forKey: .kind),
            message: try container.decode(ServerErrorMessage.self, forKey: .message),
            recoveryHint: try container.decodeIfPresent(ServerErrorRecoveryHint.self, forKey: .recoveryHint)
        )
    }
}

/// Wire payload carried by an `ActionResult`.
///
/// `ActionResultWirePayload` is intentionally the decoded/encoded
/// representation. Source construction should use `ActionResultPayload` so the
/// method is bound to the payload before an `ActionResult` is built.
public enum ActionResultWirePayload: Codable, Sendable, Equatable {
    case value(String)
    case rotor(RotorResult)
    case screenshot(ScreenPayload)
    case heistExecution(HeistExecutionReceipt)

    private enum Kind: String, Codable {
        case value
        case rotor
        case screenshot
        case heistExecution
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case data
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResult payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .value:
            self = .value(try container.decode(String.self, forKey: .data))
        case .rotor:
            self = .rotor(try container.decode(RotorResult.self, forKey: .data))
        case .screenshot:
            self = .screenshot(try container.decode(ScreenPayload.self, forKey: .data))
        case .heistExecution:
            self = .heistExecution(try container.decode(HeistExecutionReceipt.self, forKey: .data))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let string):
            try container.encode(Kind.value, forKey: .kind)
            try container.encode(string, forKey: .data)
        case .rotor(let rotor):
            try container.encode(Kind.rotor, forKey: .kind)
            try container.encode(rotor, forKey: .data)
        case .screenshot(let screen):
            try container.encode(Kind.screenshot, forKey: .kind)
            try container.encode(screen, forKey: .data)
        case .heistExecution(let receipt):
            try container.encode(Kind.heistExecution, forKey: .kind)
            try container.encode(receipt, forKey: .data)
        }
    }
}

/// Method-bound payload for source construction of an `ActionResult`.
///
/// The wire payload enum remains available for decoding and projection, but
/// production result factories take this typed wrapper so value/screenshot/
/// rotor/heist payloads carry their only valid `ActionMethod`.
public struct ActionResultPayload: Sendable, Equatable {
    package let method: ActionMethod
    package let wirePayload: ActionResultWirePayload

    private init(method: ActionMethod, wirePayload: ActionResultWirePayload) {
        self.method = method
        self.wirePayload = wirePayload
    }

    public static func typeText(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .typeText, wirePayload: .value(value))
    }

    public static func setPasteboard(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .setPasteboard, wirePayload: .value(value))
    }

    public static func getPasteboard(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .getPasteboard, wirePayload: .value(value))
    }

    public static func screenshot(_ screen: ScreenPayload) -> ActionResultPayload {
        ActionResultPayload(method: .takeScreenshot, wirePayload: .screenshot(screen))
    }

    public static func rotor(_ rotor: RotorResult) -> ActionResultPayload {
        ActionResultPayload(method: .rotor, wirePayload: .rotor(rotor))
    }

    public static func heistExecution(_ receipt: HeistExecutionReceipt) -> ActionResultPayload {
        ActionResultPayload(method: .heistPlan, wirePayload: .heistExecution(receipt))
    }
}

/// The delivered outcome of an action command.
public enum ActionResultOutcome: Codable, Sendable, Equatable {
    case success
    case failure(ActionFailure.Kind)

    private enum Kind: String, Codable {
        case success
        case failure
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case failureKind
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var failureKind: ActionFailure.Kind? {
        if case .failure(let kind) = self { return kind }
        return nil
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultOutcome")
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .success:
            try container.rejectIncompatibleFields(
                allowing: [.kind],
                typeName: "successful ActionResult outcome"
            )
            self = .success
        case .failure:
            guard let failureKind = try container.decodeIfPresent(
                ActionFailure.Kind.self,
                forKey: .failureKind
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .failureKind,
                    in: container,
                    debugDescription: "failed ActionResult outcome requires failureKind"
                )
            }
            self = .failure(failureKind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success:
            try container.encode(Kind.success, forKey: .kind)
        case .failure(let failureKind):
            try container.encode(Kind.failure, forKey: .kind)
            try container.encode(failureKind, forKey: .failureKind)
        }
    }
}
