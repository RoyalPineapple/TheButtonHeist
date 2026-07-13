import ThePlans
import Foundation

/// Typed error classification used by action-result outcomes and the
/// server-broadcast `ServerError` payload.
public enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case accessibilityTreeUnavailable
    case elementNotFound
    case timeout
    case validationError
    case actionFailed
    /// Authentication failed (rejected token or rate-limited).
    case authFailure
    /// General server error not tied to a specific action.
    case general
}

/// Structured payload for server-broadcast error messages.
public struct ServerError: Codable, Sendable, Equatable {
    public let kind: ErrorKind
    public let message: String
    public let recoveryHint: String?

    public init(kind: ErrorKind, message: String, recoveryHint: String? = nil) {
        precondition(!message.isEmpty, "ServerError message must not be empty")
        precondition(recoveryHint?.isEmpty != true, "ServerError recoveryHint must not be empty")
        self.kind = kind
        self.message = message
        self.recoveryHint = recoveryHint
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case recoveryHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ErrorKind.self, forKey: .kind)
        let message = try container.decode(String.self, forKey: .message)
        let recoveryHint = try container.decodeIfPresent(String.self, forKey: .recoveryHint)
        guard !message.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: container,
                debugDescription: "server error message must not be empty"
            )
        }
        if recoveryHint?.isEmpty == true {
            throw DecodingError.dataCorruptedError(
                forKey: .recoveryHint,
                in: container,
                debugDescription: "server error recoveryHint must not be empty"
            )
        }
        self.kind = kind
        self.message = message
        self.recoveryHint = recoveryHint
    }
}

/// Wire payload carried by an `ActionResult`.
///
/// `ResultPayload` is intentionally the decoded/encoded representation. Source
/// construction should use `ActionResultPayload` so the method is bound to the
/// payload before an `ActionResult` is built.
public enum ResultPayload: Codable, Sendable, Equatable {
    case value(String)
    case rotor(RotorResult)
    case screenshot(ScreenPayload)
    case heistExecution(HeistExecutionResult)

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
            self = .heistExecution(try container.decode(HeistExecutionResult.self, forKey: .data))
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
        case .heistExecution(let result):
            try container.encode(Kind.heistExecution, forKey: .kind)
            try container.encode(result, forKey: .data)
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
    package let resultPayload: ResultPayload

    private init(method: ActionMethod, resultPayload: ResultPayload) {
        self.method = method
        self.resultPayload = resultPayload
    }

    public static func typeText(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .typeText, resultPayload: .value(value))
    }

    public static func setPasteboard(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .setPasteboard, resultPayload: .value(value))
    }

    public static func getPasteboard(_ value: String) -> ActionResultPayload {
        ActionResultPayload(method: .getPasteboard, resultPayload: .value(value))
    }

    public static func screenshot(_ screen: ScreenPayload) -> ActionResultPayload {
        ActionResultPayload(method: .takeScreenshot, resultPayload: .screenshot(screen))
    }

    public static func rotor(_ rotor: RotorResult) -> ActionResultPayload {
        ActionResultPayload(method: .rotor, resultPayload: .rotor(rotor))
    }

    public static func heistExecution(_ result: HeistExecutionResult) -> ActionResultPayload {
        ActionResultPayload(method: .heistPlan, resultPayload: .heistExecution(result))
    }
}

/// The delivered outcome of an action command.
public enum ActionResultOutcome: Codable, Sendable, Equatable {
    case success
    case failure(ErrorKind)

    private enum Kind: String, Codable {
        case success
        case failure
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case errorKind
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var errorKind: ErrorKind? {
        if case .failure(let kind) = self { return kind }
        return nil
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultOutcome")
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .success:
            if let errorKind = try container.decodeIfPresent(ErrorKind.self, forKey: .errorKind) {
                throw DecodingError.dataCorruptedError(
                    forKey: .errorKind,
                    in: container,
                    debugDescription: "successful ActionResult outcome must not include errorKind \(errorKind.rawValue)"
                )
            }
            self = .success
        case .failure:
            guard let errorKind = try container.decodeIfPresent(ErrorKind.self, forKey: .errorKind) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .errorKind,
                    in: container,
                    debugDescription: "failed ActionResult outcome requires errorKind"
                )
            }
            self = .failure(errorKind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success:
            try container.encode(Kind.success, forKey: .kind)
        case .failure(let errorKind):
            try container.encode(Kind.failure, forKey: .kind)
            try container.encode(errorKind, forKey: .errorKind)
        }
    }
}
