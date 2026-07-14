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

extension ActionPerformanceTiming {
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

public struct ActionSettlementEvidence: Codable, Sendable, Equatable {
    private enum State: Sendable, Equatable {
        case settled
        case timedOut
    }

    private let state: State
    public let durationMs: Int

    private enum Kind: String, Codable {
        case settled
        case timedOut
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case durationMs
    }

    public static func settled(durationMs: Int) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .settled, durationMs: durationMs)
    }

    public static func timedOut(durationMs: Int) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .timedOut, durationMs: durationMs)
    }

    public var settled: Bool {
        if case .settled = state { return true }
        return false
    }

    fileprivate func replacingDurationMs(_ durationMs: Int?) -> ActionSettlementEvidence {
        guard let durationMs else { return self }
        switch state {
        case .settled:
            return .settled(durationMs: durationMs)
        case .timedOut:
            return .timedOut(durationMs: durationMs)
        }
    }

    private init(state: State, durationMs: Int) {
        precondition(durationMs >= 0, "action settlement duration must not be negative")
        self.state = state
        self.durationMs = durationMs
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
            self.init(state: .settled, durationMs: durationMs)
        case .timedOut:
            self.init(state: .timedOut, durationMs: durationMs)
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
        try container.encode(durationMs, forKey: .durationMs)
    }
}

extension ActionResultObservationEvidence {
    fileprivate func replacingSettlementDuration(_ durationMs: Int?) -> ActionResultObservationEvidence {
        guard let durationMs else { return self }
        guard case .settledTrace(let evidence, let settlement) = self else {
            preconditionFailure("settle timing requires trace settlement evidence")
        }
        return .settledTrace(evidence, settlement.replacingDurationMs(durationMs))
    }
}

extension ActionResultEvidenceBody {
    fileprivate func mergingTiming(_ timing: ActionPerformanceTiming) -> ActionResultEvidenceBody {
        ActionResultEvidenceBody(
            observation: observation.replacingSettlementDuration(timing.settleMs),
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: self.timing?.merging(timing).replacingSettleMs(nil)
                ?? timing.replacingSettleMs(nil)
        )
    }
}

extension ActionResultEvidence {
    fileprivate func mergingTiming(_ timing: ActionPerformanceTiming) -> ActionResultEvidence {
        switch self {
        case .success(let evidence):
            return .success(ActionResultSuccessEvidence(
                body: evidence.body.mergingTiming(timing),
                warning: evidence.warning
            ))
        case .failure(let errorKind, let evidence):
            return .failure(errorKind, ActionResultFailureEvidence(
                body: evidence.body.mergingTiming(timing)
            ))
        }
    }
}

/// The outcome of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable, Equatable {
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
    public var timing: ActionPerformanceTiming? {
        if let timing = evidence.timing {
            return timing.replacingSettleMs(settleTimeMs)
        }
        return settleTimeMs.map { ActionPerformanceTiming(settleMs: $0) }
    }

    public static func success(
        method: ActionMethod,
        message: String? = nil,
        evidence: ActionResultSuccessEvidence
    ) -> ActionResult {
        make(
            methodAndPayload: .methodOnly(method),
            message: message,
            evidence: .success(evidence)
        )
    }

    public static func success(
        payload: ActionResultPayload,
        message: String? = nil,
        evidence: ActionResultSuccessEvidence
    ) -> ActionResult {
        make(
            methodAndPayload: .payload(payload),
            message: message,
            evidence: .success(evidence)
        )
    }

    public static func failure(
        method: ActionMethod,
        errorKind: ErrorKind,
        message: String? = nil,
        evidence: ActionResultFailureEvidence
    ) -> ActionResult {
        make(
            methodAndPayload: .methodOnly(method),
            message: message,
            evidence: .failure(errorKind, evidence)
        )
    }

    public static func failure(
        payload: ActionResultPayload,
        errorKind: ErrorKind,
        message: String? = nil,
        evidence: ActionResultFailureEvidence
    ) -> ActionResult {
        make(
            methodAndPayload: .payload(payload),
            message: message,
            evidence: .failure(errorKind, evidence)
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

    private static func make(
        methodAndPayload: MethodAndPayload,
        message: String?,
        evidence: ActionResultEvidence
    ) -> ActionResult {
        if let validationMessage = evidenceValidationMessage(
            method: methodAndPayload.method,
            evidence: evidence
        ) {
            preconditionFailure(validationMessage)
        }
        return ActionResult(
            methodAndPayload: methodAndPayload,
            message: message,
            evidence: evidence
        )
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
        if let validationMessage = Self.evidenceValidationMessage(
            method: methodAndPayload.method,
            evidence: evidence
        ) {
            throw DecodingError.dataCorruptedError(
                forKey: .evidence,
                in: container,
                debugDescription: validationMessage
            )
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
            evidence: evidence.mergingTiming(timing)
        )
    }

    private static func evidenceValidationMessage(
        method: ActionMethod,
        evidence: ActionResultEvidence
    ) -> String? {
        if evidence.activationTrace != nil, method != .activate {
            return "activationTrace is only valid for activate ActionResult evidence"
        }
        guard let warning = evidence.warning else { return nil }
        switch warning {
        case .activationWeakAffordance where method != .activate:
            return "activation weak-affordance warning is only valid for activate ActionResult evidence"
        case .textEntryWeakAffordance where method != .typeText:
            return "text-entry weak-affordance warning is only valid for typeText ActionResult evidence"
        case .activationWeakAffordance, .textEntryWeakAffordance:
            return nil
        }
    }
}
