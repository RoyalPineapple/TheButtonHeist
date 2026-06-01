import Foundation

// MARK: - Action Results

/// Typed error classification used by both `ActionResult.errorKind` and the
/// server-broadcast `ServerError` payload.
public enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case elementNotFound
    case timeout
    case validationError
    case actionFailed
    /// Authentication failed (rejected token, denied UI prompt, rate-limited).
    case authFailure
    /// Authentication is blocked on the on-device approval prompt.
    case authApprovalPending
    /// General server error not tied to a specific action.
    case general
}

/// Structured payload for server-broadcast error messages.
public struct ServerError: Codable, Sendable, Equatable {
    public let kind: ErrorKind
    public let message: String

    public init(kind: ErrorKind, message: String) {
        precondition(!message.isEmpty, "ServerError message must not be empty")
        self.kind = kind
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ErrorKind.self, forKey: .kind)
        let message = try container.decode(String.self, forKey: .message)
        guard !message.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: container,
                debugDescription: "server error message must not be empty"
            )
        }
        self.kind = kind
        self.message = message
    }
}

/// Non-terminal auth status sent while InsideJob waits for user approval.
public struct AuthApprovalPendingPayload: Codable, Sendable, Equatable {
    public let message: String
    public let hint: String

    public init(
        message: String = "Waiting for approval on the device.",
        hint: String = "Tap Allow on the iOS device to continue."
    ) {
        self.message = message
        self.hint = hint
    }
}

/// Command-specific payload carried by an `ActionResult`.
///
/// Modeled as an enum so the "at most one" invariant is structural rather than
/// documented. Encodes natively as a tagged union under the `payload` key on
/// `ActionResult`: `{"kind": "value", "data": "..."}`,
/// `{"kind": "scrollSearch", "data": {...}}`, etc.
///   - `.value`        → typeText / setPasteboard / getPasteboard
///   - `.scrollSearch` → element_search / scroll_to_visible
public enum ResultPayload: Codable, Sendable {
    case value(String)
    case scrollSearch(ScrollSearchResult)
    case rotor(RotorResult)
    case heistExecution(HeistExecutionResult)

    private enum Kind: String, Codable {
        case value
        case scrollSearch
        case rotor
        case heistExecution
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .value:
            self = .value(try container.decode(String.self, forKey: .data))
        case .scrollSearch:
            self = .scrollSearch(try container.decode(ScrollSearchResult.self, forKey: .data))
        case .rotor:
            self = .rotor(try container.decode(RotorResult.self, forKey: .data))
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
        case .scrollSearch(let search):
            try container.encode(Kind.scrollSearch, forKey: .kind)
            try container.encode(search, forKey: .data)
        case .rotor(let rotor):
            try container.encode(Kind.rotor, forKey: .kind)
            try container.encode(rotor, forKey: .data)
        case .heistExecution(let result):
            try container.encode(Kind.heistExecution, forKey: .kind)
            try container.encode(result, forKey: .data)
        }
    }
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable {
    /// Whether the action was delivered and completed normally. `false` means
    /// the action reached the server but the handler reported failure — it is
    /// not a transport-level error (those surface as thrown errors).
    public let success: Bool
    /// Identifies which server-side handler produced this result (e.g.
    /// `.syntheticTap`, `.accessibilityActivate`). Useful when diagnosing
    /// why an action succeeded but had no visible effect.
    public let method: ActionMethod
    public let message: String?
    /// Typed error classification (nil on success)
    public let errorKind: ErrorKind?
    /// Command-specific payload. At most one variant per result.
    public let payload: ResultPayload?
    /// Source-of-truth accessibility capture receipt for this action.
    public let accessibilityTrace: AccessibilityTrace?
    /// True when the response represents a settled UI state — either the
    /// AX tree reached multi-cycle stability, or a screen transition
    /// preempted the settle loop and the new screen has been observed via
    /// the existing repopulation pipeline. False *only* when the hard
    /// settle timeout elapsed while the tree was still changing — the
    /// endpoint delta projection may not be a final state.
    public let settled: Bool?
    /// Wall-clock milliseconds from action start to settle decision
    /// (settled, screen-changed, or timed out).
    public let settleTimeMs: Int?

    public init(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        errorKind: ErrorKind? = nil,
        payload: ResultPayload? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) {
        self.success = success
        self.method = method
        self.message = message
        self.errorKind = errorKind
        self.payload = payload
        self.accessibilityTrace = accessibilityTrace
        self.settled = settled
        self.settleTimeMs = settleTimeMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case success
        case method
        case message
        case errorKind
        case payload
        case accessibilityTrace
        case settled
        case settleTimeMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            success: try container.decode(Bool.self, forKey: .success),
            method: try container.decode(ActionMethod.self, forKey: .method),
            message: try container.decodeIfPresent(String.self, forKey: .message),
            errorKind: try container.decodeIfPresent(ErrorKind.self, forKey: .errorKind),
            payload: try container.decodeIfPresent(ResultPayload.self, forKey: .payload),
            accessibilityTrace: try container.decodeIfPresent(AccessibilityTrace.self, forKey: .accessibilityTrace),
            settled: try container.decodeIfPresent(Bool.self, forKey: .settled),
            settleTimeMs: try container.decodeIfPresent(Int.self, forKey: .settleTimeMs)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(errorKind, forKey: .errorKind)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(accessibilityTrace, forKey: .accessibilityTrace)
        try container.encodeIfPresent(settled, forKey: .settled)
        try container.encodeIfPresent(settleTimeMs, forKey: .settleTimeMs)
    }
}
