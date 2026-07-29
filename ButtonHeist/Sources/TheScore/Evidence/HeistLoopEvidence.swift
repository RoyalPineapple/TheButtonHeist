import Foundation
import ThePlans

public enum HeistPredicateEvidenceOutcome: String, Codable, Sendable, Equatable {
    case matched
    case continued
    case handledElse = "handled_else"
    case failed
}

public struct HeistForEachStringEvidence: Codable, Sendable, Equatable {
    public let iterationCount: Int
    private let shape: Shape

    public var iterationOrdinal: Int? {
        guard case .iteration(let iterationOrdinal, _, _) = shape else {
            return nil
        }
        return iterationOrdinal
    }

    public var value: String? {
        guard case .iteration(_, let value, _) = shape else {
            return nil
        }
        return value
    }

    public var failureReason: String? {
        switch shape {
        case .summary(let failureReason), .iteration(_, _, let failureReason):
            return failureReason
        }
    }

    public init?(
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.init(
            iterationCount: iterationCount,
            shape: .summary(failureReason: failureReason)
        )
    }

    public init?(
        iterationCount: Int,
        iterationOrdinal: Int,
        value: String,
        failureReason: String? = nil
    ) {
        self.init(
            iterationCount: iterationCount,
            shape: .iteration(
                iterationOrdinal: iterationOrdinal,
                value: value,
                failureReason: failureReason
            )
        )
    }

    private init?(iterationCount: Int, shape: Shape) {
        guard iterationCount >= 0 else { return nil }
        if case .iteration(let ordinal, _, _) = shape {
            guard ordinal >= 0, ordinal < iterationCount else { return nil }
        }
        self.iterationCount = iterationCount
        self.shape = shape
    }

    package static func executedSummary(
        iterationCount: Int,
        failureReason: String? = nil
    ) -> Self {
        Self(
            admittedIterationCount: iterationCount,
            shape: .summary(failureReason: failureReason)
        )
    }

    package static func executedIteration(
        iterationCount: Int,
        iterationOrdinal: Int,
        value: String,
        failureReason: String? = nil
    ) -> Self {
        Self(
            admittedIterationCount: iterationCount,
            shape: .iteration(
                iterationOrdinal: iterationOrdinal,
                value: value,
                failureReason: failureReason
            )
        )
    }

    private init(admittedIterationCount iterationCount: Int, shape: Shape) {
        precondition(iterationCount >= 0)
        if case .iteration(let ordinal, _, _) = shape {
            precondition(ordinal >= 0 && ordinal < iterationCount)
        }
        self.iterationCount = iterationCount
        self.shape = shape
    }

    private enum Shape: Sendable, Equatable {
        case summary(failureReason: String?)
        case iteration(iterationOrdinal: Int, value: String, failureReason: String?)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case iterationCount
        case iterationOrdinal
        case value
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistForEachStringEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let iterationCount = try container.decode(Int.self, forKey: .iterationCount)
        let shape: Shape
        switch (iterationOrdinal, value) {
        case (.some(let iterationOrdinal), .some(let value)):
            shape = .iteration(
                iterationOrdinal: iterationOrdinal,
                value: value,
                failureReason: failureReason
            )
        case (nil, nil):
            shape = .summary(failureReason: failureReason)
        case (.some, nil), (nil, .some):
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_string iteration evidence requires iterationOrdinal and value together"
            ))
        }
        guard let admitted = Self(iterationCount: iterationCount, shape: shape) else {
            let invalid: (CodingKeys, String)
            if iterationCount < 0 {
                invalid = (.iterationCount, "for_each_string iterationCount must be nonnegative")
            } else if let iterationOrdinal, iterationOrdinal < 0 {
                invalid = (.iterationOrdinal, "for_each_string iterationOrdinal must be nonnegative")
            } else {
                invalid = (.iterationOrdinal, "for_each_string iterationOrdinal must be less than iterationCount")
            }
            throw DecodingError.dataCorruptedError(
                forKey: invalid.0,
                in: container,
                debugDescription: invalid.1
            )
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

}

public struct HeistForEachElementEvidence: Codable, Sendable, Equatable {
    public let matchedCount: Int
    public let iterationCount: Int
    private let shape: Shape

    public var iterationOrdinal: Int? {
        guard case .iteration(let iterationOrdinal, _, _, _) = shape else {
            return nil
        }
        return iterationOrdinal
    }

    public var targetOrdinal: Int? {
        guard case .iteration(_, let targetOrdinal, _, _) = shape else {
            return nil
        }
        return targetOrdinal
    }

    public var targetSummary: String? {
        guard case .iteration(_, _, let targetSummary, _) = shape else {
            return nil
        }
        return targetSummary
    }

    public var failureReason: String? {
        switch shape {
        case .summary(let failureReason), .iteration(_, _, _, let failureReason):
            return failureReason
        }
    }

    public init?(
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.init(
            matchedCount: matchedCount,
            iterationCount: iterationCount,
            shape: .summary(failureReason: failureReason)
        )
    }

    public init?(
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        targetOrdinal: Int,
        targetSummary: String,
        failureReason: String? = nil
    ) {
        self.init(
            matchedCount: matchedCount,
            iterationCount: iterationCount,
            shape: .iteration(
                iterationOrdinal: iterationOrdinal,
                targetOrdinal: targetOrdinal,
                targetSummary: targetSummary,
                failureReason: failureReason
            )
        )
    }

    private init?(matchedCount: Int, iterationCount: Int, shape: Shape) {
        guard matchedCount >= 0,
              iterationCount >= 0,
              iterationCount <= matchedCount else { return nil }
        if case .iteration(let iterationOrdinal, let targetOrdinal, _, _) = shape {
            guard iterationOrdinal >= 0,
                  iterationOrdinal < iterationCount,
                  targetOrdinal >= 0,
                  targetOrdinal < matchedCount else { return nil }
        }
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = shape
    }

    package static func executedSummary(
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) -> Self {
        Self(
            admittedMatchedCount: matchedCount,
            iterationCount: iterationCount,
            shape: .summary(failureReason: failureReason)
        )
    }

    package static func executedIteration(
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        targetOrdinal: Int,
        targetSummary: String,
        failureReason: String? = nil
    ) -> Self {
        Self(
            admittedMatchedCount: matchedCount,
            iterationCount: iterationCount,
            shape: .iteration(
                iterationOrdinal: iterationOrdinal,
                targetOrdinal: targetOrdinal,
                targetSummary: targetSummary,
                failureReason: failureReason
            )
        )
    }

    private init(admittedMatchedCount matchedCount: Int, iterationCount: Int, shape: Shape) {
        precondition(matchedCount >= 0 && iterationCount >= 0 && iterationCount <= matchedCount)
        if case .iteration(let iterationOrdinal, let targetOrdinal, _, _) = shape {
            precondition(iterationOrdinal >= 0 && iterationOrdinal < iterationCount)
            precondition(targetOrdinal >= 0 && targetOrdinal < matchedCount)
        }
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = shape
    }

    private enum Shape: Sendable, Equatable {
        case summary(failureReason: String?)
        case iteration(
            iterationOrdinal: Int,
            targetOrdinal: Int,
            targetSummary: String,
            failureReason: String?
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matchedCount
        case iterationCount
        case iterationOrdinal
        case targetOrdinal
        case targetSummary
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistForEachElementEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let targetOrdinal = try container.decodeIfPresent(Int.self, forKey: .targetOrdinal)
        let targetSummary = try container.decodeIfPresent(String.self, forKey: .targetSummary)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let matchedCount = try container.decode(Int.self, forKey: .matchedCount)
        let iterationCount = try container.decode(Int.self, forKey: .iterationCount)
        let shape: Shape
        switch (iterationOrdinal, targetOrdinal, targetSummary) {
        case (.some(let iterationOrdinal), .some(let targetOrdinal), .some(let targetSummary)):
            shape = .iteration(
                iterationOrdinal: iterationOrdinal,
                targetOrdinal: targetOrdinal,
                targetSummary: targetSummary,
                failureReason: failureReason
            )
        case (nil, nil, nil):
            shape = .summary(failureReason: failureReason)
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_element iteration evidence requires iterationOrdinal, targetOrdinal, and targetSummary together"
            ))
        }
        guard let admitted = Self(matchedCount: matchedCount, iterationCount: iterationCount, shape: shape) else {
            let invalid: (CodingKeys, String)
            if matchedCount < 0 {
                invalid = (.matchedCount, "for_each_element matchedCount must be nonnegative")
            } else if iterationCount < 0 {
                invalid = (.iterationCount, "for_each_element iterationCount must be nonnegative")
            } else if iterationCount > matchedCount {
                invalid = (.iterationCount, "for_each_element iterationCount must not exceed matchedCount")
            } else if let iterationOrdinal, iterationOrdinal < 0 {
                invalid = (.iterationOrdinal, "for_each_element iterationOrdinal must be nonnegative")
            } else if let iterationOrdinal, iterationOrdinal >= iterationCount {
                invalid = (.iterationOrdinal, "for_each_element iterationOrdinal must be less than iterationCount")
            } else if let targetOrdinal, targetOrdinal < 0 {
                invalid = (.targetOrdinal, "for_each_element targetOrdinal must be nonnegative")
            } else {
                invalid = (.targetOrdinal, "for_each_element targetOrdinal must be less than matchedCount")
            }
            throw DecodingError.dataCorruptedError(
                forKey: invalid.0,
                in: container,
                debugDescription: invalid.1
            )
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchedCount, forKey: .matchedCount)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(targetOrdinal, forKey: .targetOrdinal)
        try container.encodeIfPresent(targetSummary, forKey: .targetSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

}

public struct HeistRepeatUntilEvidence: Codable, Sendable, Equatable {
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let lastObservedSummary: String?
    public let outcome: HeistPredicateEvidenceOutcome
    public let failureReason: String?

    private init?(
        iterationCount: Int = 0,
        iterationOrdinal: Int?,
        lastObservedSummary: String?,
        outcome: HeistPredicateEvidenceOutcome,
        failureReason: String?
    ) {
        guard iterationCount >= 0 else { return nil }
        guard iterationOrdinal.map({ $0 >= 0 && $0 < iterationCount }) ?? true else { return nil }
        guard Self.fieldsMatch(
            outcome: outcome,
            iterationOrdinal: iterationOrdinal,
            failureReason: failureReason
        ) else { return nil }
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.lastObservedSummary = lastObservedSummary
        self.outcome = outcome
        self.failureReason = failureReason
    }

    private init(
        executedIterationCount iterationCount: Int,
        iterationOrdinal: Int?,
        lastObservedSummary: String?,
        outcome: HeistPredicateEvidenceOutcome,
        failureReason: String?
    ) {
        self = requireValidLiteralPayload {
            guard let evidence = Self(
                iterationCount: iterationCount,
                iterationOrdinal: iterationOrdinal,
                lastObservedSummary: lastObservedSummary,
                outcome: outcome,
                failureReason: failureReason
            ) else {
                throw ReportAdmissionError(description: "invalid executed repeat_until evidence")
            }
            return evidence
        }
    }

    package static func executedMatched(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .matched,
            failureReason: nil
        )
    }

    package static func executedContinued(
        iterationCount: Int,
        iterationOrdinal: Int,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .continued,
            failureReason: nil
        )
    }

    package static func executedFailed(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .failed,
            failureReason: failureReason
        )
    }

    public static func matched(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .matched,
            failureReason: nil
        )
    }

    public static func continued(
        iterationCount: Int,
        iterationOrdinal: Int,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .continued,
            failureReason: nil
        )
    }

    public static func failed(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: .failed,
            failureReason: failureReason
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case iterationCount
        case iterationOrdinal
        case lastObservedSummary
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "repeat_until evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(HeistPredicateEvidenceOutcome.self, forKey: .outcome)
        let iterationCount = try container.decode(Int.self, forKey: .iterationCount)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let lastObservedSummary = try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        guard let admitted = Self(
            iterationCount: iterationCount,
            iterationOrdinal: iterationOrdinal,
            lastObservedSummary: lastObservedSummary,
            outcome: outcome,
            failureReason: failureReason
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "repeat_until outcome does not match its iteration and failure fields"
            ))
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(lastObservedSummary, forKey: .lastObservedSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

    private static func fieldsMatch(
        outcome: HeistPredicateEvidenceOutcome,
        iterationOrdinal: Int?,
        failureReason: String?
    ) -> Bool {
        switch outcome {
        case .matched:
            failureReason == nil
        case .continued:
            iterationOrdinal != nil && failureReason == nil
        case .failed:
            failureReason != nil
        case .handledElse:
            false
        }
    }
}
