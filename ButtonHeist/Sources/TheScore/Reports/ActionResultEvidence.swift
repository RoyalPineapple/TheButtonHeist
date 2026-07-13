import Foundation

extension ActionResultObservationEvidence {
    fileprivate func validateForConstruction() {
        guard case .announcement(let text) = self else { return }
        precondition(!text.isEmpty, "action announcement must not be empty")
    }
}

public struct ActionResultSuccessEvidence: Codable, Sendable, Equatable {
    public let observation: ActionResultObservationEvidence
    public let subjectEvidence: ActionSubjectEvidence?
    public let activationTrace: ActivationTrace?
    public let timing: ActionPerformanceTiming?
    public let warning: HeistActionWarning?

    public static let none = ActionResultSuccessEvidence(observation: .none)

    public init(
        observation: ActionResultObservationEvidence,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        timing: ActionPerformanceTiming? = nil,
        warning: HeistActionWarning? = nil
    ) {
        observation.validateForConstruction()
        precondition(timing?.settleMs == nil, "settlement duration belongs to action observation")
        self.observation = observation
        self.subjectEvidence = subjectEvidence
        self.activationTrace = activationTrace
        self.timing = timing
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
        let timing = try container.decodeIfPresent(ActionPerformanceTiming.self, forKey: .timing)
        try Self.rejectSettlementTiming(timing, in: container)
        self.init(
            observation: try container.decode(ActionResultObservationEvidence.self, forKey: .observation),
            subjectEvidence: try container.decodeIfPresent(
                ActionSubjectEvidence.self,
                forKey: .subjectEvidence
            ),
            activationTrace: try container.decodeIfPresent(ActivationTrace.self, forKey: .activationTrace),
            timing: timing,
            warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observation, forKey: .observation)
        try container.encodeIfPresent(subjectEvidence, forKey: .subjectEvidence)
        try container.encodeIfPresent(activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encodeIfPresent(warning, forKey: .warning)
    }

    private static func rejectSettlementTiming(
        _ timing: ActionPerformanceTiming?,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        guard timing?.settleMs != nil else { return }
        throw DecodingError.dataCorruptedError(
            forKey: .timing,
            in: container,
            debugDescription: "settlement duration belongs to action observation"
        )
    }
}

public struct ActionResultFailureEvidence: Codable, Sendable, Equatable {
    public let observation: ActionResultObservationEvidence
    public let subjectEvidence: ActionSubjectEvidence?
    public let activationTrace: ActivationTrace?
    public let timing: ActionPerformanceTiming?

    public static let none = ActionResultFailureEvidence(observation: .none)

    public init(
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case observation
        case subjectEvidence
        case activationTrace
        case timing
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultFailureEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timing = try container.decodeIfPresent(ActionPerformanceTiming.self, forKey: .timing)
        guard timing?.settleMs == nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .timing,
                in: container,
                debugDescription: "settlement duration belongs to action observation"
            )
        }
        self.init(
            observation: try container.decode(ActionResultObservationEvidence.self, forKey: .observation),
            subjectEvidence: try container.decodeIfPresent(
                ActionSubjectEvidence.self,
                forKey: .subjectEvidence
            ),
            activationTrace: try container.decodeIfPresent(ActivationTrace.self, forKey: .activationTrace),
            timing: timing
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observation, forKey: .observation)
        try container.encodeIfPresent(subjectEvidence, forKey: .subjectEvidence)
        try container.encodeIfPresent(activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(timing, forKey: .timing)
    }

}

/// Outcome-bound evidence attached to one action result.
public enum ActionResultEvidence: Sendable, Equatable {
    case success(ActionResultSuccessEvidence)
    case failure(ActionResultFailureEvidence)

    public var accessibilityTrace: AccessibilityTrace? { observation.accessibilityTrace }
    public var settlement: ActionSettlementEvidence? { observation.settlement }
    public var announcement: String? { observation.announcement }

    public var subjectEvidence: ActionSubjectEvidence? {
        switch self {
        case .success(let evidence):
            return evidence.subjectEvidence
        case .failure(let evidence):
            return evidence.subjectEvidence
        }
    }

    public var activationTrace: ActivationTrace? {
        switch self {
        case .success(let evidence):
            return evidence.activationTrace
        case .failure(let evidence):
            return evidence.activationTrace
        }
    }

    public var timing: ActionPerformanceTiming? {
        switch self {
        case .success(let evidence):
            return evidence.timing
        case .failure(let evidence):
            return evidence.timing
        }
    }

    public var warning: HeistActionWarning? {
        guard case .success(let evidence) = self else { return nil }
        return evidence.warning
    }

    private var observation: ActionResultObservationEvidence {
        switch self {
        case .success(let evidence):
            return evidence.observation
        case .failure(let evidence):
            return evidence.observation
        }
    }
}
