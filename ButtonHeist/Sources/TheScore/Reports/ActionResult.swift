import ThePlans
import Foundation

extension ActionResultPayload {
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
}

public struct ActionSettlementDuration: Codable, Sendable, Equatable, CustomStringConvertible {
    public let milliseconds: Int

    public init(validatingMilliseconds milliseconds: Int) throws {
        guard milliseconds >= 0 else {
            throw ReportAdmissionError(description: "action settlement duration must not be negative")
        }
        self.milliseconds = milliseconds
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validatingMilliseconds:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(milliseconds, to: encoder)
    }

    public var description: String { milliseconds.description }
}

extension ActionSettlementDuration: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload { try Self(validatingMilliseconds: value) }
    }
}

public struct ActionSettlementEvidence: Codable, Sendable, Equatable {
    private enum State: Sendable, Equatable {
        case settled
        case timedOut
    }

    private let state: State
    public let duration: ActionSettlementDuration
    public var durationMs: Int { duration.milliseconds }

    private enum Kind: String, Codable {
        case settled
        case timedOut
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case durationMs
    }

    public static func settled(duration: ActionSettlementDuration) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .settled, duration: duration)
    }

    public static func timedOut(duration: ActionSettlementDuration) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .timedOut, duration: duration)
    }

    public var settled: Bool {
        if case .settled = state { return true }
        return false
    }

    private init(state: State, duration: ActionSettlementDuration) {
        self.state = state
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSettlementEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try container.decode(ActionSettlementDuration.self, forKey: .durationMs)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .settled:
            self.init(state: .settled, duration: duration)
        case .timedOut:
            self.init(state: .timedOut, duration: duration)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch state {
        case .settled:
            try container.encode(Kind.settled, forKey: .kind)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .kind)
        }
        try container.encode(duration, forKey: .durationMs)
    }
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable, Equatable {
    package enum MethodAndPayload: Sendable, Equatable {
        case methodOnly(ActionMethod)
        case payload(ActionResultPayload)

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

    private let methodAndPayload: MethodAndPayload
    public var outcome: ActionResultOutcome { evidence.outcome }

    /// Identifies the delivered action behavior. Activation-point delivery for
    /// `activate` still reports `.activate`.
    /// Explicit mechanical tap commands report the mechanical tap method.
    public var method: ActionMethod { methodAndPayload.method }
    public let message: String?
    public let evidence: ActionResultEvidence
    public var warning: HeistActionWarning? { evidence.warning }
    public var announcement: String? { evidence.announcement }
    public var capturedAnnouncement: CapturedAnnouncement? {
        evidence.accessibilityTrace?.capturedAnnouncements.first
    }
    /// Command-specific payload. At most one variant per result.
    public var payload: ResultPayload? { methodAndPayload.resultPayload }
    /// Source-of-truth accessibility capture receipt for this action.
    public var accessibilityTrace: AccessibilityTrace? { evidence.accessibilityTrace }
    /// Source-of-truth trace and observation-completeness proof for this action.
    public var traceEvidence: AccessibilityTraceEvidence? { evidence.traceEvidence }
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
    public var timing: ActionPerformanceTiming? { evidence.timing }

    public static func success(
        method: ActionMethod,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .methodOnly(method), .success, message, observation, subjectEvidence, timing: timing
        )
    }

    public static func success(
        payload: ActionResultPayload,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .payload(payload), .success, message, observation, subjectEvidence, timing: timing
        )
    }

    public static func activationSuccess(
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .methodOnly(.activate),
            .success,
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    public static func failure(
        method: ActionMethod,
        errorKind: ErrorKind,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .methodOnly(method), .failure(errorKind), message, observation, subjectEvidence, timing: timing
        )
    }

    public static func failure(
        payload: ActionResultPayload,
        errorKind: ErrorKind,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .payload(payload), .failure(errorKind), message, observation, subjectEvidence, timing: timing
        )
    }

    public static func activationFailure(
        errorKind: ErrorKind,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .methodOnly(.activate),
            .failure(errorKind),
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    private static func construct(
        _ methodAndPayload: MethodAndPayload,
        _ outcome: ActionResultOutcome,
        _ message: String?,
        _ observation: ActionResultObservationEvidence,
        _ subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming?
    ) -> ActionResult {
        let body = ActionResultEvidenceBody(
            observation: observation,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
        let evidence = switch outcome {
        case .success:
            ActionResultEvidence.success(ActionResultSuccessEvidence(
                body: body,
                warning: warning(method: methodAndPayload.method, subjectEvidence: subjectEvidence)
            ))
        case .failure(let errorKind):
            ActionResultEvidence.failure(errorKind, ActionResultFailureEvidence(body: body))
        }
        return ActionResult(methodAndPayload: methodAndPayload, message: message, evidence: evidence)
    }

    package init(
        outcome: ActionResultOutcome,
        methodAndPayload: MethodAndPayload,
        message: String?,
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace?
    ) {
        precondition(activationTrace == nil || methodAndPayload.method == .activate)
        self = Self.construct(
            methodAndPayload,
            outcome,
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            timing: nil
        )
    }

    private init(
        methodAndPayload: MethodAndPayload,
        message: String?,
        evidence: ActionResultEvidence
    ) {
        self.methodAndPayload = methodAndPayload
        self.message = message
        self.evidence = evidence
    }

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

        let evidence: ActionResultEvidence
        switch outcome {
        case .success:
            evidence = .success(
                try container.decode(ActionResultSuccessEvidence.self, forKey: .evidence)
            )
        case .failure(let errorKind):
            evidence = .failure(
                errorKind,
                try container.decode(ActionResultFailureEvidence.self, forKey: .evidence)
            )
        }
        if evidence.activationTrace != nil, method != .activate {
            throw DecodingError.dataCorruptedError(
                forKey: .evidence,
                in: container,
                debugDescription: "activationTrace is only valid for activate ActionResult evidence"
            )
        }
        if case .success(let successEvidence) = evidence, let warning = successEvidence.warning {
            let validMethod = switch warning {
            case .activationWeakAffordance: method == .activate
            case .textEntryWeakAffordance: method == .typeText
            }
            guard validMethod else {
                throw DecodingError.dataCorruptedError(
                    forKey: .evidence,
                    in: container,
                    debugDescription: "action warning does not belong to \(method.rawValue) ActionResult evidence"
                )
            }
        }

        self.init(
            methodAndPayload: methodAndPayload,
            message: try container.decodeIfPresent(String.self, forKey: .message),
            evidence: evidence
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(payload, forKey: .payload)
        switch evidence {
        case .success(let evidence):
            try container.encode(evidence, forKey: .evidence)
        case .failure(_, let evidence):
            try container.encode(evidence, forKey: .evidence)
        }
    }

    public func withTiming(_ timing: ActionPerformanceTiming?) -> ActionResult {
        guard let timing else { return self }
        return ActionResult(
            methodAndPayload: methodAndPayload,
            message: message,
            evidence: evidence.withTiming(timing)
        )
    }

    private static func warning(
        method: ActionMethod,
        subjectEvidence: ActionSubjectEvidence?
    ) -> HeistActionWarning? {
        guard let element = subjectEvidence?.element else { return nil }
        let evidence = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            traits: AccessibilityPolicy.orderedMatcherTraits(element.traits),
            actions: element.actions.sorted { $0.description < $1.description }
        ).rendered(using: .activationAffordanceEvidence)

        switch method {
        case .activate where !AccessibilityPolicy.advertisesActivationAffordance(element.traits):
            return .activationWeakAffordance(evidence: evidence)
        case .typeText where !AccessibilityPolicy.supportsTextEntry(element.traits):
            return .textEntryWeakAffordance(evidence: evidence)
        default:
            return nil
        }
    }
}
