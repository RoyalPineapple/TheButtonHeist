import Foundation

// MARK: - Action Results

/// Typed error classification used by both `ActionResult.errorKind` and the
/// server-broadcast `ServerError` payload.
public enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case elementNotFound
    case timeout
    case unsupported
    case inputError
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
///   - `.explore`      → the explicit `explore` command
public enum ResultPayload: Codable, Sendable {
    case value(String)
    case scrollSearch(ScrollSearchResult)
    case explore(ExploreResult)
    case rotor(RotorResult)
    case batchExecution(BatchExecutionResult)

    private enum Kind: String, Codable {
        case value
        case scrollSearch
        case explore
        case rotor
        case batchExecution
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
        case .explore:
            self = .explore(try container.decode(ExploreResult.self, forKey: .data))
        case .rotor:
            self = .rotor(try container.decode(RotorResult.self, forKey: .data))
        case .batchExecution:
            self = .batchExecution(try container.decode(BatchExecutionResult.self, forKey: .data))
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
        case .explore(let explore):
            try container.encode(Kind.explore, forKey: .kind)
            try container.encode(explore, forKey: .data)
        case .rotor(let rotor):
            try container.encode(Kind.rotor, forKey: .kind)
            try container.encode(rotor, forKey: .data)
        case .batchExecution(let result):
            try container.encode(Kind.batchExecution, forKey: .kind)
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
    /// Compact projection describing what changed in the hierarchy after the
    /// action. This is always derived from `accessibilityTrace`; action results
    /// store captures as truth, not stale compact deltas.
    public var accessibilityDelta: AccessibilityTrace.Delta? {
        accessibilityTrace?.endpointDeltaProjection
    }
    /// Whether the UI was still animating when this result was produced.
    /// nil means idle (no animations detected).
    public let animating: Bool?
    /// Screen name projection derived from the final trace capture.
    public var screenName: String? {
        accessibilityTrace?.endpointScreenNameProjection
    }
    /// Screen id projection derived from the final trace capture.
    public var screenId: String? {
        accessibilityTrace?.endpointScreenIdProjection
    }
    /// True when the response represents a settled UI state — either the
    /// AX tree reached multi-cycle stability, or a screen transition
    /// preempted the settle loop and the new screen has been observed via
    /// the existing repopulation pipeline. False *only* when the hard
    /// settle timeout elapsed while the tree was still changing — the
    /// snapshot in `accessibilityDelta` may not be a final state.
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
        animating: Bool? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) {
        self.success = success
        self.method = method
        self.message = message
        self.errorKind = errorKind
        self.payload = payload
        self.accessibilityTrace = accessibilityTrace
        self.animating = animating
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
        case animating
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
            animating: try container.decodeIfPresent(Bool.self, forKey: .animating),
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
        try container.encodeIfPresent(animating, forKey: .animating)
        try container.encodeIfPresent(settled, forKey: .settled)
        try container.encodeIfPresent(settleTimeMs, forKey: .settleTimeMs)
    }
}

/// Diagnostics from a scroll_to_visible search operation.
public struct ScrollSearchResult: Codable, Sendable {
    /// Number of scroll operations performed
    public let scrollCount: Int
    /// Number of unique elements seen across all scroll positions
    public let uniqueElementsSeen: Int
    /// Total items in the data source (UITableView/UICollectionView only)
    public let totalItems: Int?
    /// Whether every item in the data source was checked
    public let exhaustive: Bool
    /// The matched element id, if found. The action trace owns the element snapshot.
    public let foundHeistId: HeistId?

    public init(
        scrollCount: Int,
        uniqueElementsSeen: Int,
        totalItems: Int? = nil,
        exhaustive: Bool,
        foundHeistId: HeistId? = nil
    ) {
        self.scrollCount = scrollCount
        self.uniqueElementsSeen = uniqueElementsSeen
        self.totalItems = totalItems
        self.exhaustive = exhaustive
        self.foundHeistId = foundHeistId
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scrollCount
        case uniqueElementsSeen
        case totalItems
        case exhaustive
        case foundHeistId
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ScrollSearchResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scrollCount: try container.decode(Int.self, forKey: .scrollCount),
            uniqueElementsSeen: try container.decode(Int.self, forKey: .uniqueElementsSeen),
            totalItems: try container.decodeIfPresent(Int.self, forKey: .totalItems),
            exhaustive: try container.decode(Bool.self, forKey: .exhaustive),
            foundHeistId: try container.decodeIfPresent(HeistId.self, forKey: .foundHeistId)
        )
    }

}

// MARK: - Explore Result

/// Result from an explore (full screen census) operation.
public struct ExploreResult: Codable, Sendable {
    /// Number of elements discovered across all scroll positions.
    public let elementCount: Int
    /// Total scrollByPage calls during exploration
    public let scrollCount: Int
    /// Number of scrollable containers explored
    public let containersExplored: Int
    /// Wall-clock time spent exploring, in seconds
    public let explorationTime: Double

    public init(
        elementCount: Int,
        scrollCount: Int,
        containersExplored: Int,
        explorationTime: Double
    ) {
        self.elementCount = elementCount
        self.scrollCount = scrollCount
        self.containersExplored = containersExplored
        self.explorationTime = explorationTime
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case elementCount
        case scrollCount
        case containersExplored
        case explorationTime
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ExploreResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            elementCount: try container.decode(Int.self, forKey: .elementCount),
            scrollCount: try container.decode(Int.self, forKey: .scrollCount),
            containersExplored: try container.decode(Int.self, forKey: .containersExplored),
            explorationTime: try container.decode(Double.self, forKey: .explorationTime)
        )
    }

}

// MARK: - Custom Rotor Result

/// Result from a live rotor step operation.
public struct RotorResult: Codable, Sendable {
    public let rotor: String
    public let direction: RotorDirection
    /// The selected element id, if the rotor resolved to an element. The action trace owns the element snapshot.
    public let foundHeistId: HeistId?
    public let textRange: RotorTextRange?

    public init(
        rotor: String,
        direction: RotorDirection,
        foundHeistId: HeistId? = nil,
        textRange: RotorTextRange? = nil
    ) {
        self.rotor = rotor
        self.direction = direction
        self.foundHeistId = foundHeistId
        self.textRange = textRange
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rotor
        case direction
        case foundHeistId
        case textRange
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "RotorResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rotor: try container.decode(String.self, forKey: .rotor),
            direction: try container.decode(RotorDirection.self, forKey: .direction),
            foundHeistId: try container.decodeIfPresent(HeistId.self, forKey: .foundHeistId),
            textRange: try container.decodeIfPresent(RotorTextRange.self, forKey: .textRange)
        )
    }

}

/// Text range returned by a rotor result.
public struct RotorTextRange: Codable, Equatable, Sendable {
    public let text: String?
    public let startOffset: Int?
    public let endOffset: Int?
    public let rangeDescription: String

    public init(
        text: String? = nil,
        startOffset: Int? = nil,
        endOffset: Int? = nil,
        rangeDescription: String
    ) {
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.rangeDescription = rangeDescription
    }
}

/// Identifies which action handler produced an ActionResult.
public enum ActionMethod: String, Codable, Sendable {
    case activate
    case increment
    case decrement
    case syntheticTap
    case syntheticLongPress
    case syntheticSwipe
    case syntheticDrag
    case syntheticPinch
    case syntheticRotate
    case syntheticTwoFingerTap
    case syntheticDrawPath
    case typeText
    case customAction
    case editAction
    case resignFirstResponder
    case setPasteboard
    case getPasteboard
    case rotor
    case waitForIdle
    case waitForChange
    case batchExecutionPlan
    case scroll
    case scrollToVisible
    case elementSearch
    case scrollToEdge
    case waitFor
    case explore
    case elementNotFound
    case elementDeallocated
}
