import Foundation

public struct HeistWaitMatchedEvidence: Codable, Sendable, Equatable {
    public let observation: Observation.Evidence
    public let expectation: ExpectationResult.Met

    public init(
        observation: Observation.Evidence,
        expectation: ExpectationResult.Met
    ) {
        self.observation = observation
        self.expectation = expectation
    }
}

public struct HeistWaitUnmatchedEvidence: Codable, Sendable, Equatable {
    public let observation: Observation.Evidence
    public let expectation: ExpectationResult.Unmet

    public init(
        observation: Observation.Evidence,
        expectation: ExpectationResult.Unmet
    ) {
        self.observation = observation
        self.expectation = expectation
    }
}

public enum HeistPassedWaitEvidence: Codable, Sendable, Equatable {
    case matched(HeistWaitMatchedEvidence)
    case handledElse(HeistWaitUnmatchedEvidence)

    private enum Kind: String, Codable {
        case matched
        case handledElse = "handled_else"
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case evidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "passed wait evidence"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .matched:
            self = .matched(
                try container.decode(HeistWaitMatchedEvidence.self, forKey: .evidence)
            )
        case .handledElse:
            self = .handledElse(
                try container.decode(HeistWaitUnmatchedEvidence.self, forKey: .evidence)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .matched(let evidence):
            try container.encode(Kind.matched, forKey: .type)
            try container.encode(evidence, forKey: .evidence)
        case .handledElse(let evidence):
            try container.encode(Kind.handledElse, forKey: .type)
            try container.encode(evidence, forKey: .evidence)
        }
    }

    public var observation: Observation.Evidence {
        switch self {
        case .matched(let evidence):
            evidence.observation
        case .handledElse(let evidence):
            evidence.observation
        }
    }

    public var expectation: ExpectationResult {
        switch self {
        case .matched(let evidence):
            evidence.expectation.result
        case .handledElse(let evidence):
            evidence.expectation.result
        }
    }
}
