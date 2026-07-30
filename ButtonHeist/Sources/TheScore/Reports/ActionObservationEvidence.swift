import Foundation
import ThePlans

/// Optional local timing breakdown for one observed action pipeline.
public struct ActionPerformanceTiming: Codable, Sendable, Equatable {
    public let targetResolutionMs: ElapsedMilliseconds?
    public let actionDispatchMs: ElapsedMilliseconds?
    public let interactionMs: ElapsedMilliseconds?
    public let totalMs: ElapsedMilliseconds?

    public init(
        targetResolutionMs: ElapsedMilliseconds? = nil,
        actionDispatchMs: ElapsedMilliseconds? = nil,
        interactionMs: ElapsedMilliseconds? = nil,
        totalMs: ElapsedMilliseconds? = nil
    ) {
        self.targetResolutionMs = targetResolutionMs
        self.actionDispatchMs = actionDispatchMs
        self.interactionMs = interactionMs
        self.totalMs = totalMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case targetResolutionMs
        case actionDispatchMs
        case interactionMs
        case totalMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionPerformanceTiming")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targetResolutionMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .targetResolutionMs),
            actionDispatchMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .actionDispatchMs),
            interactionMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .interactionMs),
            totalMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .totalMs)
        )
    }
}

public enum ActionResultObservationEvidence: Codable, Sendable, Equatable {
    case none
    case observed(Observation.Evidence)

    public var observationEvidence: Observation.Evidence? {
        switch self {
        case .observed(let evidence):
            return evidence
        case .none:
            return nil
        }
    }

    public var announcement: String? { observationEvidence?.notificationTexts.first }

    private enum Kind: String, Codable {
        case none
        case observed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case observationEvidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultObservationEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .none:
            try container.rejectIncompatibleFields(
                allowing: [.kind],
                typeName: "none action observation"
            )
            self = .none
        case .observed:
            try container.rejectIncompatibleFields(
                allowing: [.kind, .observationEvidence],
                typeName: "observed action observation"
            )
            self = .observed(
                try container.decode(Observation.Evidence.self, forKey: .observationEvidence)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .observed(let evidence):
            try container.encode(Kind.observed, forKey: .kind)
            try container.encode(evidence, forKey: .observationEvidence)
        }
    }

}
