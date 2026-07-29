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

public struct ActionAnnouncementText: Codable, Sendable, Equatable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonEmpty(
            value,
            or: ReportAdmissionError(description: "action announcement must not be empty")
        )
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { value }
}

extension ActionAnnouncementText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum ActionResultObservationEvidence: Codable, Sendable, Equatable {
    case none
    case announcement(ActionAnnouncementText)
    case observed(Observation.Evidence)

    public var observationEvidence: Observation.Evidence? {
        switch self {
        case .observed(let evidence):
            return evidence
        case .none, .announcement:
            return nil
        }
    }

    public var announcement: String? {
        switch self {
        case .none:
            return nil
        case .announcement(let text):
            return text.description
        case .observed(let evidence):
            return evidence.notificationTexts.first
        }
    }

    private enum Kind: String, Codable {
        case none
        case announcement
        case observed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case announcement
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
        case .announcement:
            try container.rejectIncompatibleFields(
                allowing: [.kind, .announcement],
                typeName: "announcement action observation"
            )
            self = .announcement(try container.decode(ActionAnnouncementText.self, forKey: .announcement))
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
        case .announcement(let text):
            try container.encode(Kind.announcement, forKey: .kind)
            try container.encode(text, forKey: .announcement)
        case .observed(let evidence):
            try container.encode(Kind.observed, forKey: .kind)
            try container.encode(evidence, forKey: .observationEvidence)
        }
    }

}
