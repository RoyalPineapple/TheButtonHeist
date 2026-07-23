import ThePlans
import Foundation

public struct ElapsedMilliseconds: Codable, Sendable, Equatable, CustomStringConvertible {
    public let milliseconds: Int

    public init(validatingMilliseconds milliseconds: Int) throws {
        guard milliseconds >= 0 else {
            throw ReportAdmissionError(description: "elapsed milliseconds must not be negative")
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

extension ElapsedMilliseconds: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload { try Self(validatingMilliseconds: value) }
    }
}

/// The signal that proved an action's final accessibility observation settled.
public enum ActionSettlementPath: String, Codable, Sendable, Equatable {
    case semanticStability
    case uikitIdle
    case accessibilityQuietWindow
}

public struct ActionSettlementEvidence: Codable, Sendable, Equatable {
    private enum State: Sendable, Equatable {
        case settled
        case timedOut
        case observationHandoffTimedOut
    }

    private let state: State
    public let durationMs: ElapsedMilliseconds
    public let path: ActionSettlementPath?

    private enum Kind: String, Codable {
        case settled
        case timedOut
        case observationHandoffTimedOut
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case durationMs
        case path
    }

    public static func settled(
        duration: ElapsedMilliseconds,
        path: ActionSettlementPath? = nil
    ) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .settled, duration: duration, path: path)
    }

    public static func timedOut(duration: ElapsedMilliseconds) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .timedOut, duration: duration, path: nil)
    }

    public static func observationHandoffTimedOut(
        duration: ElapsedMilliseconds,
        path: ActionSettlementPath
    ) -> ActionSettlementEvidence {
        ActionSettlementEvidence(state: .observationHandoffTimedOut, duration: duration, path: path)
    }

    public var settled: Bool {
        if case .settled = state { return true }
        return false
    }

    public var readinessEstablished: Bool {
        switch state {
        case .settled, .observationHandoffTimedOut:
            true
        case .timedOut:
            false
        }
    }

    public var observationHandoffCompleted: Bool {
        if case .settled = state { return true }
        return false
    }

    private init(state: State, duration: ElapsedMilliseconds, path: ActionSettlementPath?) {
        self.state = state
        durationMs = duration
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSettlementEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try container.decode(ElapsedMilliseconds.self, forKey: .durationMs)
        let path = try container.decodeIfPresent(ActionSettlementPath.self, forKey: .path)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .settled:
            self.init(state: .settled, duration: duration, path: path)
        case .timedOut:
            guard path == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "timed-out settlement cannot carry a settlement path"
                )
            }
            self.init(state: .timedOut, duration: duration, path: nil)
        case .observationHandoffTimedOut:
            guard let path else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "observation handoff timeout requires an established readiness path"
                )
            }
            self.init(state: .observationHandoffTimedOut, duration: duration, path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch state {
        case .settled:
            try container.encode(Kind.settled, forKey: .kind)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .kind)
        case .observationHandoffTimedOut:
            try container.encode(Kind.observationHandoffTimedOut, forKey: .kind)
        }
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(path, forKey: .path)
    }
}

/// The result of executing an action command, including post-action diagnostics.
public struct ActionResult: Codable, Sendable, Equatable {
    public enum Payload: Sendable, Equatable {
        case activate
        case increment
        case decrement
        case dismiss
        case magicTap
        case oneFingerTap
        case longPress
        case swipe
        case drag
        case typeText(String?)
        case customAction
        case editAction
        case dismissKeyboard
        case setPasteboard(String?)
        case getPasteboard(String?)
        case screenshot(ScreenPayload?)
        case rotor(RotorResult?)
        case heist(HeistResult?)
        case scroll
        case scrollToVisible
        case scrollToEdge
        case wait

        package var method: ActionMethod {
            switch self {
            case .activate: .activate
            case .increment: .increment
            case .decrement: .decrement
            case .dismiss: .dismiss
            case .magicTap: .magicTap
            case .oneFingerTap: .oneFingerTap
            case .longPress: .longPress
            case .swipe: .swipe
            case .drag: .drag
            case .typeText: .typeText
            case .customAction: .customAction
            case .editAction: .editAction
            case .dismissKeyboard: .dismissKeyboard
            case .setPasteboard: .setPasteboard
            case .getPasteboard: .getPasteboard
            case .screenshot: .takeScreenshot
            case .rotor: .rotor
            case .heist: .heistPlan
            case .scroll: .scroll
            case .scrollToVisible: .scrollToVisible
            case .scrollToEdge: .scrollToEdge
            case .wait: .wait
            }
        }
    }

    public let payload: Payload
    public var outcome: ActionResultOutcome { evidence.outcome }

    /// Identifies the delivered action behavior. Activation-point delivery for
    /// `activate` still reports `.activate`.
    /// Explicit mechanical tap commands report the mechanical tap method.
    public var method: ActionMethod { payload.method }
    public let message: String?
    public let evidence: ActionResultEvidence
    public var warning: HeistActionWarning? { evidence.warning }
    public var announcement: String? { evidence.announcement }
    public var capturedAnnouncement: CapturedAnnouncement? {
        evidence.accessibilityTrace?.capturedAnnouncements.first
    }
    /// Source-of-truth accessibility capture evidence for this action.
    public var accessibilityTrace: AccessibilityTrace? { evidence.accessibilityTrace }
    /// Source-of-truth trace and observation-completeness evidence for this action.
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
    public var settleTimeMs: ElapsedMilliseconds? { evidence.settlement?.durationMs }
    /// Semantic subject the runtime resolved before dispatching the action.
    public var subjectEvidence: ActionSubjectEvidence? { evidence.subjectEvidence }
    /// Semantic activation dispatch-path diagnostics, present for `activate`.
    public var activationTrace: ActivationTrace? { evidence.activationTrace }
    public var screenActionHandler: ScreenActionHandlerName? { evidence.screenActionHandler }
    /// Optional measured durations for the local observed action pipeline.
    public var timing: ActionPerformanceTiming? { evidence.timing }

    public static func success(
        payload: Payload,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            payload, .success, message, observation, subjectEvidence, timing: timing
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
            .activate,
            .success,
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            screenActionHandler: nil,
            timing: timing
        )
    }

    public static func failure(
        payload: Payload,
        failureKind: ActionFailure.Kind,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            payload, .failure(failureKind), message, observation, subjectEvidence, timing: timing
        )
    }

    public static func activationFailure(
        failureKind: ActionFailure.Kind,
        message: String? = nil,
        observation: ActionResultObservationEvidence = .none,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace,
        timing: ActionPerformanceTiming? = nil
    ) -> ActionResult {
        construct(
            .activate,
            .failure(failureKind),
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    private static func construct(
        _ payload: Payload,
        _ outcome: ActionResultOutcome,
        _ message: String?,
        _ observation: ActionResultObservationEvidence,
        _ subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace? = nil,
        screenActionHandler: ScreenActionHandlerName? = nil,
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
                warning: warning(
                    method: payload.method,
                    subjectEvidence: subjectEvidence,
                    activationTrace: activationTrace
                ),
                screenActionHandler: screenActionHandler
            ))
        case .failure(let failureKind):
            ActionResultEvidence.failure(failureKind, ActionResultFailureEvidence(body: body))
        }
        return ActionResult(payload: payload, message: message, evidence: evidence)
    }

    package init(
        outcome: ActionResultOutcome,
        payload: Payload,
        message: String?,
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace?,
        screenActionHandler: ScreenActionHandlerName? = nil,
        timing: ActionPerformanceTiming?
    ) {
        precondition(activationTrace == nil || payload.method == .activate)
        precondition(screenActionHandler == nil || payload.method.isScreenAction)
        self = Self.construct(
            payload,
            outcome,
            message,
            observation,
            subjectEvidence,
            activationTrace: activationTrace,
            screenActionHandler: screenActionHandler,
            timing: timing
        )
    }

    private init(
        payload: Payload,
        message: String?,
        evidence: ActionResultEvidence
    ) {
        self.payload = payload
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
        let payload = try Self.decodePayload(method: method, from: container)

        let evidence: ActionResultEvidence
        switch outcome {
        case .success:
            evidence = .success(
                try container.decode(ActionResultSuccessEvidence.self, forKey: .evidence)
            )
        case .failure(let failureKind):
            evidence = .failure(
                failureKind,
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
        if evidence.screenActionHandler != nil, !method.isScreenAction {
            throw DecodingError.dataCorruptedError(
                forKey: .evidence,
                in: container,
                debugDescription: "screenActionHandler is only valid for dismiss and magicTap ActionResult evidence"
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
            payload: payload,
            message: try container.decodeIfPresent(String.self, forKey: .message),
            evidence: evidence
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try encodePayload(to: &container)
        switch evidence {
        case .success(let evidence):
            try container.encode(evidence, forKey: .evidence)
        case .failure(_, let evidence):
            try container.encode(evidence, forKey: .evidence)
        }
    }

    private static func decodePayload(
        method: ActionMethod,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Payload {
        switch method {
        case .activate:
            return try decodePayloadWithoutData(.activate, method: method, from: container)
        case .increment:
            return try decodePayloadWithoutData(.increment, method: method, from: container)
        case .decrement:
            return try decodePayloadWithoutData(.decrement, method: method, from: container)
        case .dismiss:
            return try decodePayloadWithoutData(.dismiss, method: method, from: container)
        case .magicTap:
            return try decodePayloadWithoutData(.magicTap, method: method, from: container)
        case .oneFingerTap:
            return try decodePayloadWithoutData(.oneFingerTap, method: method, from: container)
        case .longPress:
            return try decodePayloadWithoutData(.longPress, method: method, from: container)
        case .swipe:
            return try decodePayloadWithoutData(.swipe, method: method, from: container)
        case .drag:
            return try decodePayloadWithoutData(.drag, method: method, from: container)
        case .typeText:
            return .typeText(try container.decodeIfPresent(String.self, forKey: .payload))
        case .customAction:
            return try decodePayloadWithoutData(.customAction, method: method, from: container)
        case .editAction:
            return try decodePayloadWithoutData(.editAction, method: method, from: container)
        case .dismissKeyboard:
            return try decodePayloadWithoutData(.dismissKeyboard, method: method, from: container)
        case .setPasteboard:
            return .setPasteboard(try container.decodeIfPresent(String.self, forKey: .payload))
        case .getPasteboard:
            return .getPasteboard(try container.decodeIfPresent(String.self, forKey: .payload))
        case .takeScreenshot:
            return .screenshot(try container.decodeIfPresent(ScreenPayload.self, forKey: .payload))
        case .rotor:
            return .rotor(try container.decodeIfPresent(RotorResult.self, forKey: .payload))
        case .heistPlan:
            return .heist(try container.decodeIfPresent(HeistResult.self, forKey: .payload))
        case .scroll:
            return try decodePayloadWithoutData(.scroll, method: method, from: container)
        case .scrollToVisible:
            return try decodePayloadWithoutData(.scrollToVisible, method: method, from: container)
        case .scrollToEdge:
            return try decodePayloadWithoutData(.scrollToEdge, method: method, from: container)
        case .wait:
            return try decodePayloadWithoutData(.wait, method: method, from: container)
        }
    }

    private static func decodePayloadWithoutData(
        _ payload: Payload,
        method: ActionMethod,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Payload {
        guard !container.contains(.payload) else {
            throw DecodingError.dataCorruptedError(
                forKey: .payload,
                in: container,
                debugDescription: "\(method.rawValue) ActionResult does not carry payload data"
            )
        }
        return payload
    }

    private func encodePayload(
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch payload {
        case .typeText(let value), .setPasteboard(let value), .getPasteboard(let value):
            try container.encodeIfPresent(value, forKey: .payload)
        case .screenshot(let screen):
            try container.encodeIfPresent(screen, forKey: .payload)
        case .rotor(let rotor):
            try container.encodeIfPresent(rotor, forKey: .payload)
        case .heist(let result):
            try container.encodeIfPresent(result, forKey: .payload)
        case .activate,
             .increment,
             .decrement,
             .dismiss,
             .magicTap,
             .oneFingerTap,
             .longPress,
             .swipe,
             .drag,
             .customAction,
             .editAction,
             .dismissKeyboard,
             .scroll,
             .scrollToVisible,
             .scrollToEdge,
             .wait:
            break
        }
    }

    private static func warning(
        method: ActionMethod,
        subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace?
    ) -> HeistActionWarning? {
        guard let element = subjectEvidence?.element else { return nil }
        let evidence = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            traits: AccessibilityPolicy.orderedMatcherTraits(element.traits),
            actions: element.actions.sorted { $0.description < $1.description }
        ).rendered(using: .activationAffordanceEvidence)

        switch method {
        case .activate where !element.actions.contains(.activate)
            && activationTrace?.implementsAccessibilityActivation == false:
            return .activationWeakAffordance(evidence: evidence)
        case .typeText where !AccessibilityPolicy.supportsTextEntry(element.traits):
            return .textEntryWeakAffordance(evidence: evidence)
        default:
            return nil
        }
    }
}
