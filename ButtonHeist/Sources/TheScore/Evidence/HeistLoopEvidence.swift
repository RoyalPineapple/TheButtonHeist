import Foundation
import ThePlans

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
    public let lastObservedSummary: String?
    private let storage: Storage

    private enum Storage: Sendable, Equatable {
        case matched(
            iterationOrdinal: Int?,
            expectation: ExpectationResult.Met,
            actionResult: ActionResult?
        )
        case continued(
            iterationOrdinal: Int,
            expectation: ExpectationResult.Unmet,
            actionResult: ActionResult?
        )
        case failed(
            iterationOrdinal: Int?,
            expectation: ExpectationResult.Unmet,
            failureReason: String
        )
    }

    public var outcome: HeistPredicateEvidenceOutcome {
        switch storage {
        case .matched:
            return .matched
        case .continued:
            return .continued
        case .failed:
            return .failed
        }
    }

    public var iterationOrdinal: Int? {
        switch storage {
        case .matched(let iterationOrdinal, _, _),
             .failed(let iterationOrdinal, _, _):
            return iterationOrdinal
        case .continued(let iterationOrdinal, _, _):
            return iterationOrdinal
        }
    }

    public var expectation: ExpectationResult {
        switch storage {
        case .matched(_, let expectation, _):
            return expectation.result
        case .continued(_, let expectation, _),
             .failed(_, let expectation, _):
            return expectation.result
        }
    }

    public var actionResult: ActionResult? {
        switch storage {
        case .matched(_, _, let actionResult),
             .continued(_, _, let actionResult):
            return actionResult
        case .failed:
            return nil
        }
    }

    public var failureReason: String? {
        switch storage {
        case .failed(_, _, let failureReason):
            return failureReason
        case .matched, .continued:
            return nil
        }
    }

    private init?(
        iterationCount: Int = 0,
        lastObservedSummary: String?,
        storage: Storage
    ) {
        guard iterationCount >= 0 else { return nil }
        let ordinal: Int?
        switch storage {
        case .matched(let value, _, _), .failed(let value, _, _): ordinal = value
        case .continued(let value, _, _): ordinal = value
        }
        guard ordinal.map({ $0 >= 0 && $0 < iterationCount }) ?? true else { return nil }
        self.iterationCount = iterationCount
        self.lastObservedSummary = lastObservedSummary
        self.storage = storage
    }

    private init(
        executedIterationCount iterationCount: Int,
        lastObservedSummary: String?,
        storage: Storage
    ) {
        precondition(iterationCount >= 0)
        let ordinal: Int?
        switch storage {
        case .matched(let value, _, _), .failed(let value, _, _): ordinal = value
        case .continued(let value, _, _): ordinal = value
        }
        precondition(ordinal.map { $0 >= 0 && $0 < iterationCount } ?? true)
        self.iterationCount = iterationCount
        self.lastObservedSummary = lastObservedSummary
        self.storage = storage
    }

    package static func executedMatched(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Met,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .matched(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    package static func executedContinued(
        iterationCount: Int,
        iterationOrdinal: Int,
        expectation: ExpectationResult.Unmet,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    package static func executedFailed(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Unmet,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            executedIterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func matched(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Met,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .matched(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    public static func continued(
        iterationCount: Int,
        iterationOrdinal: Int,
        expectation: ExpectationResult.Unmet,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    public static func failed(
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Unmet,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence? {
        HeistRepeatUntilEvidence(
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .failed(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case iterationCount
        case iterationOrdinal
        case expectation
        case actionResult
        case lastObservedSummary
        case failureReason
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "repeat_until evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(HeistPredicateEvidenceOutcome.self, forKey: .outcome)
        let iterationCount = try container.decode(Int.self, forKey: .iterationCount)
        let iterationOrdinal = try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal)
        let expectation = try container.decode(ExpectationResult.self, forKey: .expectation)
        let actionResult = try container.decodeIfPresent(ActionResult.self, forKey: .actionResult)
        let lastObservedSummary = try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
        let failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let storage = try Self.storage(
            outcome: outcome,
            iterationOrdinal: iterationOrdinal,
            expectation: expectation,
            actionResult: actionResult,
            failureReason: failureReason,
            codingPath: container.codingPath
        )
        guard let admitted = Self(
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: storage
        ) else {
            let key = iterationCount < 0 ? CodingKeys.iterationCount : CodingKeys.iterationOrdinal
            let description = iterationCount < 0
                ? "repeat_until iterationCount must be nonnegative"
                : "repeat_until iterationOrdinal must be nonnegative and less than iterationCount"
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: description)
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encode(expectation, forKey: .expectation)
        try container.encodeIfPresent(actionResult, forKey: .actionResult)
        try container.encodeIfPresent(lastObservedSummary, forKey: .lastObservedSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }

    private static func storage(
        outcome: HeistPredicateEvidenceOutcome,
        iterationOrdinal: Int?,
        expectation: ExpectationResult,
        actionResult: ActionResult?,
        failureReason: String?,
        codingPath: [CodingKey]
    ) throws -> Storage {
        switch (outcome, expectation) {
        case (.matched, .met(let expectation)) where failureReason == nil:
            return .matched(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        case (.continued, .unmet(let expectation)) where failureReason == nil:
            guard let iterationOrdinal else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath + [CodingKeys.iterationOrdinal],
                    debugDescription: "continued repeat_until evidence requires iterationOrdinal"
                ))
            }
            return .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        case (.failed, .unmet(let expectation)) where actionResult == nil:
            guard let failureReason else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath + [CodingKeys.failureReason],
                    debugDescription: "failed repeat_until evidence requires failureReason"
                ))
            }
            return .failed(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                failureReason: failureReason
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [CodingKeys.outcome],
                debugDescription: "repeat_until evidence outcome does not match its required fields"
            ))
        }
    }
}
