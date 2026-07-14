import Foundation

extension ActionResultObservationEvidence {
    fileprivate var constructionViolation: String? {
        guard case .announcement(let text) = self, text.isEmpty else { return nil }
        return "action announcement must not be empty"
    }

    fileprivate func validateForConstruction() {
        precondition(constructionViolation == nil, constructionViolation ?? "")
    }
}

struct ActionResultEvidenceBody: Codable, Sendable, Equatable {
    let observation: ActionResultObservationEvidence
    let subjectEvidence: ActionSubjectEvidence?
    let activationTrace: ActivationTrace?
    let timing: ActionPerformanceTiming?

    init(
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) {
        observation.validateForConstruction()
        precondition(timing?.settleMs == nil, "settlement duration belongs to action observation")
        self.observation = observation
        self.subjectEvidence = subjectEvidence
        self.activationTrace = activationTrace
        self.timing = timing
    }

    private enum CodingKeys: String, CodingKey {
        case observation
        case subjectEvidence
        case activationTrace
        case timing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let observation = try container.decode(ActionResultObservationEvidence.self, forKey: .observation)
        if let violation = observation.constructionViolation {
            throw DecodingError.dataCorruptedError(
                forKey: .observation,
                in: container,
                debugDescription: violation
            )
        }
        let timing = try container.decodeIfPresent(ActionPerformanceTiming.self, forKey: .timing)
        guard timing?.settleMs == nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .timing,
                in: container,
                debugDescription: "settlement duration belongs to action observation"
            )
        }
        self.observation = observation
        subjectEvidence = try container.decodeIfPresent(ActionSubjectEvidence.self, forKey: .subjectEvidence)
        activationTrace = try container.decodeIfPresent(ActivationTrace.self, forKey: .activationTrace)
        self.timing = timing
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observation, forKey: .observation)
        try container.encodeIfPresent(subjectEvidence, forKey: .subjectEvidence)
        try container.encodeIfPresent(activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(timing, forKey: .timing)
    }
}

public struct ActionResultSuccessEvidence: Codable, Sendable, Equatable {
    let body: ActionResultEvidenceBody
    public let warning: HeistActionWarning?

    public var observation: ActionResultObservationEvidence { body.observation }
    public var subjectEvidence: ActionSubjectEvidence? { body.subjectEvidence }
    public var activationTrace: ActivationTrace? { body.activationTrace }
    public var timing: ActionPerformanceTiming? { body.timing }

    public static let none = ActionResultSuccessEvidence(observation: .none)

    public init(
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil,
        warning: HeistActionWarning? = nil
    ) {
        body = ActionResultEvidenceBody(
            observation: observation,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
        self.warning = warning
    }

    init(body: ActionResultEvidenceBody, warning: HeistActionWarning?) {
        self.body = body
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case observation
        case subjectEvidence
        case activationTrace
        case timing
        case warning
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultSuccessEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            body: try ActionResultEvidenceBody(from: decoder),
            warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(warning, forKey: .warning)
    }
}

public struct ActionResultFailureEvidence: Codable, Sendable, Equatable {
    let body: ActionResultEvidenceBody

    public var observation: ActionResultObservationEvidence { body.observation }
    public var subjectEvidence: ActionSubjectEvidence? { body.subjectEvidence }
    public var activationTrace: ActivationTrace? { body.activationTrace }
    public var timing: ActionPerformanceTiming? { body.timing }

    public static let none = ActionResultFailureEvidence(observation: .none)

    public init(
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil
    ) {
        body = ActionResultEvidenceBody(
            observation: observation,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    init(body: ActionResultEvidenceBody) {
        self.body = body
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case observation
        case subjectEvidence
        case activationTrace
        case timing
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultFailureEvidence")
        self.init(body: try ActionResultEvidenceBody(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
    }
}

/// Outcome-bound evidence attached to one action result. Failure has no warning-bearing state.
public enum ActionResultEvidence: Sendable, Equatable {
    case success(ActionResultSuccessEvidence)
    case failure(ErrorKind, ActionResultFailureEvidence)

    public var outcome: ActionResultOutcome {
        switch self {
        case .success:
            return .success
        case .failure(let errorKind, _):
            return .failure(errorKind)
        }
    }

    public var traceEvidence: AccessibilityTraceEvidence? { observation.traceEvidence }
    public var accessibilityTrace: AccessibilityTrace? { observation.accessibilityTrace }
    public var settlement: ActionSettlementEvidence? { observation.settlement }
    public var announcement: String? { observation.announcement }

    public var subjectEvidence: ActionSubjectEvidence? { body.subjectEvidence }
    public var activationTrace: ActivationTrace? { body.activationTrace }
    public var timing: ActionPerformanceTiming? { body.timing }

    public var warning: HeistActionWarning? {
        guard case .success(let evidence) = self else { return nil }
        return evidence.warning
    }

    var body: ActionResultEvidenceBody {
        switch self {
        case .success(let evidence):
            return evidence.body
        case .failure(_, let evidence):
            return evidence.body
        }
    }

    private var observation: ActionResultObservationEvidence { body.observation }
}
