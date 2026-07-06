import ThePlans
import Foundation

// MARK: - Action Results

/// Typed error classification used by both `ActionResult.errorKind` and the
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

/// Semantic subject the runtime resolved immediately before dispatching an action.
///
/// This is result evidence, not a replay selector. Offline suggestion tooling can
/// combine it with settled before/after traces to choose a minimum matcher later.
public struct ActionSubjectEvidence: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case resolvedSemanticTarget
        case textInputTarget
        case elementGestureTarget
    }

    public enum Phase: String, Codable, Sendable {
        case resolvedBeforeDispatch
    }

    public let source: Source
    public let phase: Phase
    public let target: ElementTarget
    public let element: HeistElement
    public let settledObservationSequence: SettledObservationSequence?

    public init(
        source: Source,
        phase: Phase = .resolvedBeforeDispatch,
        target: ElementTarget,
        element: HeistElement,
        settledObservationSequence: SettledObservationSequence? = nil
    ) {
        self.source = source
        self.phase = phase
        self.target = target
        self.element = element
        self.settledObservationSequence = settledObservationSequence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case phase
        case target
        case element
        case settledObservationSequence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSubjectEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try container.decode(Source.self, forKey: .source),
            phase: try container.decode(Phase.self, forKey: .phase),
            target: try container.decode(ElementTarget.self, forKey: .target),
            element: try container.decode(HeistElement.self, forKey: .element),
            settledObservationSequence: try container.decodeIfPresent(SettledObservationSequence.self, forKey: .settledObservationSequence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(phase, forKey: .phase)
        try container.encode(target, forKey: .target)
        try container.encode(element, forKey: .element)
        try container.encodeIfPresent(settledObservationSequence, forKey: .settledObservationSequence)
    }
}

/// Dispatch-path diagnostics for semantic `activate`.
///
/// `Activate` refreshes semantic and live geometry first, then calls
/// `accessibilityActivate()` once. A `true` result is treated as the semantic
/// action completing, so activation-point tap dispatch is not sent. When the
/// accessibility action declines, the runtime dispatches at the fresh activation
/// point if needed.
public struct ActivationTrace: Codable, Sendable, Equatable {
    public let axActivateReturned: Bool?
    public let tapActivationDispatched: Bool
    public let tapActivationPoint: ScreenPoint?
    public let tapActivationSucceeded: Bool?

    public init(
        axActivateReturned: Bool?,
        tapActivationDispatched: Bool = false,
        tapActivationPoint: ScreenPoint? = nil,
        tapActivationSucceeded: Bool? = nil
    ) {
        self.axActivateReturned = axActivateReturned
        self.tapActivationDispatched = tapActivationDispatched
        self.tapActivationPoint = tapActivationPoint
        self.tapActivationSucceeded = tapActivationSucceeded
    }
}

/// Optional local timing breakdown for one observed action pipeline.
public struct ActionPerformanceTiming: Codable, Sendable, Equatable {
    public let beforeObservationMs: Int?
    public let targetResolutionMs: Int?
    public let actionDispatchMs: Int?
    public let interactionMs: Int?
    public let settleMs: Int?
    public let finalSemanticEvidenceMs: Int?
    public let receiptGenerationMs: Int?
    public let totalMs: Int?

    public init(
        beforeObservationMs: Int? = nil,
        targetResolutionMs: Int? = nil,
        actionDispatchMs: Int? = nil,
        interactionMs: Int? = nil,
        settleMs: Int? = nil,
        finalSemanticEvidenceMs: Int? = nil,
        receiptGenerationMs: Int? = nil,
        totalMs: Int? = nil
    ) {
        self.beforeObservationMs = beforeObservationMs
        self.targetResolutionMs = targetResolutionMs
        self.actionDispatchMs = actionDispatchMs
        self.interactionMs = interactionMs
        self.settleMs = settleMs
        self.finalSemanticEvidenceMs = finalSemanticEvidenceMs
        self.receiptGenerationMs = receiptGenerationMs
        self.totalMs = totalMs
    }

    public func merging(_ other: ActionPerformanceTiming?) -> ActionPerformanceTiming {
        guard let other else { return self }
        return ActionPerformanceTiming(
            beforeObservationMs: other.beforeObservationMs ?? beforeObservationMs,
            targetResolutionMs: other.targetResolutionMs ?? targetResolutionMs,
            actionDispatchMs: other.actionDispatchMs ?? actionDispatchMs,
            interactionMs: other.interactionMs ?? interactionMs,
            settleMs: other.settleMs ?? settleMs,
            finalSemanticEvidenceMs: other.finalSemanticEvidenceMs ?? finalSemanticEvidenceMs,
            receiptGenerationMs: other.receiptGenerationMs ?? receiptGenerationMs,
            totalMs: other.totalMs ?? totalMs
        )
    }
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable, Equatable {
    // MARK: - Nested Types

    package enum Outcome: Sendable, Equatable {
        case success
        case failure(ErrorKind)

        private init?(decodedSuccess success: Bool, errorKind: ErrorKind?) {
            switch (success, errorKind) {
            case (true, nil):
                self = .success
            case (false, .some(let kind)):
                self = .failure(kind)
            case (true, .some), (false, nil):
                return nil
            }
        }

        /// Boundary-only adapter for external JSON where success/errorKind
        /// arrive as separate wire fields.
        fileprivate static func decoded(success: Bool, errorKind: ErrorKind?) -> Outcome? {
            Outcome(decodedSuccess: success, errorKind: errorKind)
        }

        var success: Bool {
            if case .success = self { return true }
            return false
        }

        var errorKind: ErrorKind? {
            if case .failure(let kind) = self { return kind }
            return nil
        }
    }

    // MARK: - Properties

    private let outcome: Outcome

    /// Whether the action was delivered and completed normally. `false` means
    /// the action reached the server but the handler reported failure — it is
    /// not a transport-level error (those surface as thrown errors).
    public var success: Bool { outcome.success }
    /// Identifies the delivered action behavior. Activation-point delivery for
    /// `activate` still reports `.activate`.
    /// Explicit mechanical tap commands report the mechanical tap method.
    public let method: ActionMethod
    public let message: String?
    /// First spoken accessibility text observed during this action, sourced
    /// from string payloads on announcement, layoutChanged, or screenChanged.
    public let announcement: String?
    /// Typed error classification (nil on success)
    public var errorKind: ErrorKind? { outcome.errorKind }
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
    /// Semantic subject the runtime resolved before dispatching the action.
    public let subjectEvidence: ActionSubjectEvidence?
    /// Semantic activation dispatch-path diagnostics, present for `activate`.
    public let activationTrace: ActivationTrace?
    /// Optional measured durations for the local observed action pipeline.
    public let timing: ActionPerformanceTiming?

    // MARK: - Init

    public static func success(
        method: ActionMethod,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        ActionResult(
            outcome: .success,
            method: method,
            message: message,
            announcement: announcement,
            payload: nil,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    public static func success(
        payload: ActionResultPayload,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        ActionResult(
            outcome: .success,
            method: payload.method,
            message: message,
            announcement: announcement,
            payload: payload.resultPayload,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    public static func failure(
        method: ActionMethod,
        errorKind: ErrorKind,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        ActionResult(
            outcome: .failure(errorKind),
            method: method,
            message: message,
            announcement: announcement,
            payload: nil,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    public static func failure(
        payload: ActionResultPayload,
        errorKind: ErrorKind,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        ActionResult(
            outcome: .failure(errorKind),
            method: payload.method,
            message: message,
            announcement: announcement,
            payload: payload.resultPayload,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    package init(
        outcome: Outcome,
        method: ActionMethod,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) {
        self.init(
            outcome: outcome,
            method: method,
            message: message,
            announcement: announcement,
            payload: nil,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    package init(
        outcome: Outcome,
        payload: ActionResultPayload,
        message: String? = nil,
        announcement: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) {
        self.init(
            outcome: outcome,
            method: payload.method,
            message: message,
            announcement: announcement,
            payload: payload.resultPayload,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    private init(
        outcome: Outcome,
        method: ActionMethod,
        message: String? = nil,
        announcement: String? = nil,
        payload: ResultPayload? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) {
        self.outcome = outcome
        self.method = method
        self.message = message
        self.announcement = announcement ?? accessibilityTrace?.capturedAnnouncements.first?.text
        self.payload = payload
        self.accessibilityTrace = accessibilityTrace
        self.settled = settled
        self.settleTimeMs = settleTimeMs
        self.subjectEvidence = subjectEvidence
        self.activationTrace = activationTrace
        self.timing = timing
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case success
        case method
        case message
        case announcement
        case errorKind
        case payload
        case accessibilityTrace
        case settled
        case settleTimeMs
        case subjectEvidence
        case activationTrace
        case timing
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let success = try container.decode(Bool.self, forKey: .success)
        let method = try container.decode(ActionMethod.self, forKey: .method)
        let errorKind = try container.decodeIfPresent(ErrorKind.self, forKey: .errorKind)
        let payload = try container.decodeIfPresent(ResultPayload.self, forKey: .payload)

        guard let outcome = Outcome.decoded(success: success, errorKind: errorKind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .errorKind,
                in: container,
                debugDescription: Self.outcomeValidationMessage(success: success, errorKind: errorKind)
            )
        }
        guard Self.payload(payload, isCompatibleWith: method) else {
            throw DecodingError.dataCorruptedError(
                forKey: .payload,
                in: container,
                debugDescription: Self.payloadValidationMessage(method: method, payload: payload)
            )
        }

        self.init(
            outcome: outcome,
            method: method,
            message: try container.decodeIfPresent(String.self, forKey: .message),
            announcement: try container.decodeIfPresent(String.self, forKey: .announcement),
            payload: payload,
            accessibilityTrace: try container.decodeIfPresent(AccessibilityTrace.self, forKey: .accessibilityTrace),
            settled: try container.decodeIfPresent(Bool.self, forKey: .settled),
            settleTimeMs: try container.decodeIfPresent(Int.self, forKey: .settleTimeMs),
            subjectEvidence: try container.decodeIfPresent(ActionSubjectEvidence.self, forKey: .subjectEvidence),
            activationTrace: try container.decodeIfPresent(ActivationTrace.self, forKey: .activationTrace),
            timing: try container.decodeIfPresent(ActionPerformanceTiming.self, forKey: .timing)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(announcement, forKey: .announcement)
        try container.encodeIfPresent(errorKind, forKey: .errorKind)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(accessibilityTrace, forKey: .accessibilityTrace)
        try container.encodeIfPresent(settled, forKey: .settled)
        try container.encodeIfPresent(settleTimeMs, forKey: .settleTimeMs)
        try container.encodeIfPresent(subjectEvidence, forKey: .subjectEvidence)
        try container.encodeIfPresent(activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(timing, forKey: .timing)
    }

    // MARK: - Timing

    public func withTiming(_ timing: ActionPerformanceTiming?) -> ActionResult {
        guard let timing else { return self }
        return ActionResult(
            outcome: outcome,
            method: method,
            message: message,
            announcement: announcement,
            payload: payload,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: self.timing?.merging(timing) ?? timing
        )
    }

    // MARK: - Private Helpers

    private static func payload(_ payload: ResultPayload?, isCompatibleWith method: ActionMethod) -> Bool {
        switch payload {
        case nil:
            return true
        case .value:
            return method == .typeText || method == .setPasteboard || method == .getPasteboard
        case .rotor:
            return method == .rotor
        case .screenshot:
            return method == .takeScreenshot
        case .heistExecution:
            return method == .heistPlan
        }
    }

    private static func outcomeValidationMessage(success: Bool, errorKind: ErrorKind?) -> String {
        if success, let errorKind {
            return "successful ActionResult must not include errorKind \(errorKind.rawValue)"
        }
        return "failed ActionResult requires errorKind"
    }

    private static func payloadValidationMessage(method: ActionMethod, payload: ResultPayload?) -> String {
        switch (method, payload) {
        case (.takeScreenshot, .some(_)):
            return "takeScreenshot ActionResult payload must be screenshot"
        case (.heistPlan, .some(_)):
            return "heistPlan ActionResult payload must be heistExecution"
        case (.rotor, .some(_)):
            return "rotor ActionResult payload must be rotor"
        case (_, .value):
            return "value ActionResult payload is only valid for typeText, setPasteboard, or getPasteboard"
        case (_, .screenshot):
            return "screenshot ActionResult payload is only valid for takeScreenshot"
        case (_, .heistExecution):
            return "heistExecution ActionResult payload is only valid for heistPlan"
        case (_, .rotor):
            return "rotor ActionResult payload is only valid for rotor"
        case (_, nil):
            return "ActionResult payload is compatible"
        }
    }
}
