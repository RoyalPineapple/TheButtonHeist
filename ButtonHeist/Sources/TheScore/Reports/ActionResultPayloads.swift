import ThePlans
import Foundation

// MARK: - Action Results

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

    fileprivate static func decoded(
        method: ActionMethod,
        resultPayload: ResultPayload,
        codingPath: [CodingKey]
    ) throws -> ActionResultPayload {
        switch (method, resultPayload) {
        case (.typeText, .value(let value)):
            return .typeText(value)
        case (.setPasteboard, .value(let value)):
            return .setPasteboard(value)
        case (.getPasteboard, .value(let value)):
            return .getPasteboard(value)
        case (.takeScreenshot, .screenshot(let screen)):
            return .screenshot(screen)
        case (.rotor, .rotor(let rotor)):
            return .rotor(rotor)
        case (.heistPlan, .heistExecution(let result)):
            return .heistExecution(result)
        case (.activate, _),
             (.increment, _),
             (.decrement, _),
             (.syntheticTap, _),
             (.syntheticLongPress, _),
             (.syntheticSwipe, _),
             (.syntheticDrag, _),
             (.typeText, _),
             (.customAction, _),
             (.editAction, _),
             (.resignFirstResponder, _),
             (.setPasteboard, _),
             (.getPasteboard, _),
             (.takeScreenshot, _),
             (.rotor, _),
             (.heistPlan, _),
             (.dismiss, _),
             (.magicTap, _),
             (.scroll, _),
             (.scrollToVisible, _),
             (.scrollToEdge, _),
             (.wait, _):
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: payloadValidationMessage(method: method, payload: resultPayload)
            ))
        }
    }

    private static func payloadValidationMessage(method: ActionMethod, payload: ResultPayload) -> String {
        switch (method, payload) {
        case (.takeScreenshot, _):
            return "takeScreenshot ActionResult payload must be screenshot"
        case (.heistPlan, _):
            return "heistPlan ActionResult payload must be heistExecution"
        case (.rotor, _):
            return "rotor ActionResult payload must be rotor"
        case (_, .value):
            return "value ActionResult payload is only valid for typeText, setPasteboard, or getPasteboard"
        case (_, .screenshot):
            return "screenshot ActionResult payload is only valid for takeScreenshot"
        case (_, .heistExecution):
            return "heistExecution ActionResult payload is only valid for heistPlan"
        case (_, .rotor):
            return "rotor ActionResult payload is only valid for rotor"
        }
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
    public let target: AccessibilityTarget
    public let element: HeistElement
    public let settledObservationSequence: SettledObservationSequence?

    public init(
        source: Source,
        phase: Phase = .resolvedBeforeDispatch,
        target: AccessibilityTarget,
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
            target: try container.decode(AccessibilityTarget.self, forKey: .target),
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
public enum ActivationTracePhase: Sendable, Equatable {
    case refreshFailed
    case accessibilityActivate
    case activationPointFallback(
        axActivateReturned: Bool?,
        tapActivationPoint: ScreenPoint,
        tapActivationSucceeded: Bool
    )
}

public struct ActivationTrace: Codable, Sendable, Equatable {
    private let phase: ActivationTracePhase

    public var axActivateReturned: Bool? {
        switch phase {
        case .refreshFailed:
            return nil
        case .accessibilityActivate:
            return true
        case .activationPointFallback(let axActivateReturned, _, _):
            return axActivateReturned
        }
    }

    public var tapActivationDispatched: Bool {
        if case .activationPointFallback = phase {
            return true
        }
        return false
    }

    public var tapActivationPoint: ScreenPoint? {
        guard case .activationPointFallback(_, let point, _) = phase else {
            return nil
        }
        return point
    }

    public var tapActivationSucceeded: Bool? {
        guard case .activationPointFallback(_, _, let succeeded) = phase else {
            return nil
        }
        return succeeded
    }

    public init(_ phase: ActivationTracePhase) {
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case axActivateReturned
        case tapActivationDispatched
        case tapActivationPoint
        case tapActivationSucceeded
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActivationTrace")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let axActivateReturned = try container.decodeIfPresent(Bool.self, forKey: .axActivateReturned)
        let tapActivationDispatched = try container.decode(Bool.self, forKey: .tapActivationDispatched)
        let tapActivationPoint = try container.decodeIfPresent(ScreenPoint.self, forKey: .tapActivationPoint)
        let tapActivationSucceeded = try container.decodeIfPresent(Bool.self, forKey: .tapActivationSucceeded)

        if tapActivationDispatched {
            guard let tapActivationPoint, let tapActivationSucceeded else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "tapActivationDispatched requires tapActivationPoint and tapActivationSucceeded"
                ))
            }
            self.init(.activationPointFallback(
                axActivateReturned: axActivateReturned,
                tapActivationPoint: tapActivationPoint,
                tapActivationSucceeded: tapActivationSucceeded
            ))
        } else {
            guard tapActivationPoint == nil, tapActivationSucceeded == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "tapActivationPoint and tapActivationSucceeded require tapActivationDispatched"
                ))
            }
            switch axActivateReturned {
            case .some(true):
                self.init(.accessibilityActivate)
            case .some(false):
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "axActivateReturned=false requires activation-point fallback fields"
                ))
            case nil:
                self.init(.refreshFailed)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(axActivateReturned, forKey: .axActivateReturned)
        try container.encode(tapActivationDispatched, forKey: .tapActivationDispatched)
        try container.encodeIfPresent(tapActivationPoint, forKey: .tapActivationPoint)
        try container.encodeIfPresent(tapActivationSucceeded, forKey: .tapActivationSucceeded)
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

    fileprivate func replacingSettleMs(_ settleMs: Int?) -> ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: beforeObservationMs,
            targetResolutionMs: targetResolutionMs,
            actionDispatchMs: actionDispatchMs,
            interactionMs: interactionMs,
            settleMs: settleMs,
            finalSemanticEvidenceMs: finalSemanticEvidenceMs,
            receiptGenerationMs: receiptGenerationMs,
            totalMs: totalMs
        )
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

public enum ActionSettlementEvidence: Codable, Sendable, Equatable {
    case settled(durationMs: Int)
    case timedOut(durationMs: Int)

    private enum Kind: String, Codable {
        case settled
        case timedOut
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case durationMs
    }

    public var durationMs: Int {
        switch self {
        case .settled(let durationMs), .timedOut(let durationMs):
            return durationMs
        }
    }

    public var settled: Bool {
        if case .settled = self { return true }
        return false
    }

    fileprivate func replacingDurationMs(_ durationMs: Int?) -> ActionSettlementEvidence {
        guard let durationMs else { return self }
        switch self {
        case .settled:
            return .settled(durationMs: durationMs)
        case .timedOut:
            return .timedOut(durationMs: durationMs)
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSettlementEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let durationMs = try container.decode(Int.self, forKey: .durationMs)
        guard durationMs >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .durationMs,
                in: container,
                debugDescription: "action settlement duration must not be negative"
            )
        }
        switch try container.decode(Kind.self, forKey: .kind) {
        case .settled:
            self = .settled(durationMs: durationMs)
        case .timedOut:
            self = .timedOut(durationMs: durationMs)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .settled:
            try container.encode(Kind.settled, forKey: .kind)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .kind)
        }
        try container.encode(durationMs, forKey: .durationMs)
    }
}

/// Independent evidence attached to one action result.
public struct ActionResultEvidence: Codable, Sendable, Equatable {
    public let accessibilityTrace: AccessibilityTrace?
    public let settlement: ActionSettlementEvidence?
    public let subjectEvidence: ActionSubjectEvidence?
    public let activationTrace: ActivationTrace?
    public let timing: ActionPerformanceTiming?
    public let announcement: String?

    public init(
        accessibilityTrace: AccessibilityTrace? = nil,
        settlement: ActionSettlementEvidence? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil,
        announcement: String? = nil
    ) {
        if let timingDurationMs = timing?.settleMs {
            precondition(
                timingDurationMs == settlement?.durationMs,
                "timing.settleMs must match ActionSettlementEvidence"
            )
        }
        let traceAnnouncement = accessibilityTrace?.capturedAnnouncements.first
        if let announcement, let traceAnnouncement {
            precondition(
                announcement == traceAnnouncement.text,
                "announcement must match accessibilityTrace captured announcement"
            )
        }
        self.accessibilityTrace = accessibilityTrace
        self.settlement = settlement
        self.subjectEvidence = subjectEvidence
        self.activationTrace = activationTrace
        self.timing = timing?.replacingSettleMs(nil)
        self.announcement = traceAnnouncement?.text ?? announcement
    }

    fileprivate func mergingTiming(_ timing: ActionPerformanceTiming) -> ActionResultEvidence {
        let settlement = settlement?.replacingDurationMs(timing.settleMs)
        precondition(timing.settleMs == nil || settlement != nil, "settle timing requires settlement evidence")
        return ActionResultEvidence(
            accessibilityTrace: accessibilityTrace,
            settlement: settlement,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: self.timing?.merging(timing).replacingSettleMs(nil)
                ?? timing.replacingSettleMs(nil),
            announcement: announcement
        )
    }
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable, Equatable {
    // MARK: - Nested Types

    private enum MethodAndPayload: Sendable, Equatable {
        case methodOnly(ActionMethod)
        case payload(ActionResultPayload)

        init(method: ActionMethod) {
            self = .methodOnly(method)
        }

        init(payload: ActionResultPayload) {
            self = .payload(payload)
        }

        init(
            decodedMethod method: ActionMethod,
            decodedPayload payload: ResultPayload?,
            codingPath: [CodingKey]
        ) throws {
            guard let payload else {
                self = .methodOnly(method)
                return
            }
            self = .payload(try ActionResultPayload.decoded(
                method: method,
                resultPayload: payload,
                codingPath: codingPath
            ))
        }

        var method: ActionMethod {
            switch self {
            case .methodOnly(let method):
                return method
            case .payload(let payload):
                return payload.method
            }
        }

        var resultPayload: ResultPayload? {
            guard case .payload(let payload) = self else { return nil }
            return payload.resultPayload
        }
    }

    // MARK: - Properties

    public let outcome: ActionResultOutcome
    private let methodAndPayload: MethodAndPayload

    /// Identifies the delivered action behavior. Activation-point delivery for
    /// `activate` still reports `.activate`.
    /// Explicit mechanical tap commands report the mechanical tap method.
    public var method: ActionMethod { methodAndPayload.method }
    public let message: String?
    public let evidence: ActionResultEvidence
    public var announcement: String? { evidence.announcement }
    public var capturedAnnouncement: CapturedAnnouncement? {
        evidence.accessibilityTrace?.capturedAnnouncements.first
    }
    /// Command-specific payload. At most one variant per result.
    public var payload: ResultPayload? { methodAndPayload.resultPayload }
    /// Source-of-truth accessibility capture receipt for this action.
    public var accessibilityTrace: AccessibilityTrace? { evidence.accessibilityTrace }
    /// True when the response represents a settled UI state — either the
    /// AX tree reached multi-cycle stability, or a screen transition
    /// preempted the settle loop and the new screen has been observed via
    /// the existing repopulation pipeline. False *only* when the hard
    /// settle timeout elapsed while the tree was still changing — the
    /// endpoint delta projection may not be a final state.
    public var settled: Bool? { evidence.settlement?.settled }
    /// Wall-clock milliseconds from action start to settle decision
    /// (settled, screen-changed, or timed out).
    public var settleTimeMs: Int? { evidence.settlement?.durationMs }
    /// Semantic subject the runtime resolved before dispatching the action.
    public var subjectEvidence: ActionSubjectEvidence? { evidence.subjectEvidence }
    /// Semantic activation dispatch-path diagnostics, present for `activate`.
    public var activationTrace: ActivationTrace? { evidence.activationTrace }
    /// Optional measured durations for the local observed action pipeline.
    public var timing: ActionPerformanceTiming? {
        if let timing = evidence.timing {
            return timing.replacingSettleMs(settleTimeMs)
        }
        return settleTimeMs.map { ActionPerformanceTiming(settleMs: $0) }
    }

    // MARK: - Init

    public static func success(
        method: ActionMethod,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) -> ActionResult {
        ActionResult(
            outcome: .success,
            method: method,
            message: message,
            evidence: evidence
        )
    }

    public static func success(
        payload: ActionResultPayload,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) -> ActionResult {
        ActionResult(
            outcome: .success,
            payload: payload,
            message: message,
            evidence: evidence
        )
    }

    public static func failure(
        method: ActionMethod,
        errorKind: ErrorKind,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) -> ActionResult {
        ActionResult(
            outcome: .failure(errorKind),
            method: method,
            message: message,
            evidence: evidence
        )
    }

    public static func failure(
        payload: ActionResultPayload,
        errorKind: ErrorKind,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) -> ActionResult {
        ActionResult(
            outcome: .failure(errorKind),
            payload: payload,
            message: message,
            evidence: evidence
        )
    }

    package init(
        outcome: ActionResultOutcome,
        method: ActionMethod,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) {
        self.init(
            outcome: outcome,
            methodAndPayload: .methodOnly(method),
            message: message,
            evidence: evidence
        )
    }

    package init(
        outcome: ActionResultOutcome,
        payload: ActionResultPayload,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) {
        self.init(
            outcome: outcome,
            methodAndPayload: .payload(payload),
            message: message,
            evidence: evidence
        )
    }

    private init(
        outcome: ActionResultOutcome,
        methodAndPayload: MethodAndPayload,
        message: String? = nil,
        evidence: ActionResultEvidence = ActionResultEvidence()
    ) {
        self.outcome = outcome
        self.methodAndPayload = methodAndPayload
        self.message = message
        self.evidence = evidence
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case method
        case message
        case payload
        case evidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(ActionResultOutcome.self, forKey: .outcome)
        let method = try container.decode(ActionMethod.self, forKey: .method)
        let payload = try container.decodeIfPresent(ResultPayload.self, forKey: .payload)
        let methodAndPayload = try MethodAndPayload(
            decodedMethod: method,
            decodedPayload: payload,
            codingPath: container.codingPath + [CodingKeys.payload]
        )

        self.init(
            outcome: outcome,
            methodAndPayload: methodAndPayload,
            message: try container.decodeIfPresent(String.self, forKey: .message),
            evidence: try container.decodeIfPresent(ActionResultEvidence.self, forKey: .evidence)
                ?? ActionResultEvidence()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encode(evidence, forKey: .evidence)
    }

    // MARK: - Timing

    public func withTiming(_ timing: ActionPerformanceTiming?) -> ActionResult {
        guard let timing else { return self }
        return ActionResult(
            outcome: outcome,
            methodAndPayload: methodAndPayload,
            message: message,
            evidence: evidence.mergingTiming(timing)
        )
    }
}
