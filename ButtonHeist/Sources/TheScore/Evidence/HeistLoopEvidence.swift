import Foundation
import ThePlans

public struct HeistForEachStringEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let count: Int
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

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.shape = .summary(failureReason: failureReason)
    }

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        value: String,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.shape = .iteration(
            iterationOrdinal: iterationOrdinal,
            value: value,
            failureReason: failureReason
        )
    }

    private enum Shape: Sendable, Equatable {
        case summary(failureReason: String?)
        case iteration(iterationOrdinal: Int, value: String, failureReason: String?)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case parameter
        case count
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

        switch (iterationOrdinal, value) {
        case (.some(let iterationOrdinal), .some(let value)):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                iterationOrdinal: iterationOrdinal,
                value: value,
                failureReason: failureReason
            )
        case (nil, nil):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                failureReason: failureReason
            )
        case (.some, nil), (nil, .some):
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_string iteration evidence requires iterationOrdinal and value together"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(count, forKey: .count)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct HeistForEachElementEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let matching: ElementPredicateTemplate
    public let limit: Int
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

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = .summary(failureReason: failureReason)
    }

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int,
        targetOrdinal: Int,
        targetSummary: String,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.shape = .iteration(
            iterationOrdinal: iterationOrdinal,
            targetOrdinal: targetOrdinal,
            targetSummary: targetSummary,
            failureReason: failureReason
        )
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
        case parameter
        case matching
        case limit
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

        switch (iterationOrdinal, targetOrdinal, targetSummary) {
        case (.some(let iterationOrdinal), .some(let targetOrdinal), .some(let targetSummary)):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicateTemplate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit),
                matchedCount: try container.decode(Int.self, forKey: .matchedCount),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                iterationOrdinal: iterationOrdinal,
                targetOrdinal: targetOrdinal,
                targetSummary: targetSummary,
                failureReason: failureReason
            )
        case (nil, nil, nil):
            self.init(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicateTemplate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit),
                matchedCount: try container.decode(Int.self, forKey: .matchedCount),
                iterationCount: try container.decode(Int.self, forKey: .iterationCount),
                failureReason: failureReason
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "for_each_element iteration evidence requires iterationOrdinal, targetOrdinal, and targetSummary together"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(matching, forKey: .matching)
        try container.encode(limit, forKey: .limit)
        try container.encode(matchedCount, forKey: .matchedCount)
        try container.encode(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(targetOrdinal, forKey: .targetOrdinal)
        try container.encodeIfPresent(targetSummary, forKey: .targetSummary)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct HeistRepeatUntilEvidence: Codable, Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let timeout: Double
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
        case handledElse(
            expectation: ExpectationResult.Unmet,
            failureReason: String?
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
        case .handledElse:
            return .handledElse
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
        case .handledElse:
            return nil
        }
    }

    public var expectation: ExpectationResult {
        switch storage {
        case .matched(_, let expectation, _):
            return expectation.result
        case .continued(_, let expectation, _),
             .handledElse(let expectation, _),
             .failed(_, let expectation, _):
            return expectation.result
        }
    }

    public var actionResult: ActionResult? {
        switch storage {
        case .matched(_, _, let actionResult),
             .continued(_, _, let actionResult):
            return actionResult
        case .handledElse, .failed:
            return nil
        }
    }

    public var failureReason: String? {
        switch storage {
        case .handledElse(_, let failureReason):
            return failureReason
        case .failed(_, _, let failureReason):
            return failureReason
        case .matched, .continued:
            return nil
        }
    }

    private init(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int = 0,
        lastObservedSummary: String?,
        storage: Storage
    ) {
        self.predicate = predicate
        self.timeout = timeout
        self.iterationCount = iterationCount
        self.lastObservedSummary = lastObservedSummary
        self.storage = storage
    }

    public static func matched(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Met,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
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
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int,
        expectation: ExpectationResult.Unmet,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .continued(
                iterationOrdinal: iterationOrdinal,
                expectation: expectation,
                actionResult: actionResult
            )
        )
    }

    public static func handledElse(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        expectation: ExpectationResult.Unmet,
        lastObservedSummary: String?,
        failureReason: String? = nil
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: .handledElse(
                expectation: expectation,
                failureReason: failureReason
            )
        )
    }

    public static func failed(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult.Unmet,
        lastObservedSummary: String?,
        failureReason: String
    ) -> HeistRepeatUntilEvidence {
        HeistRepeatUntilEvidence(
            predicate: predicate,
            timeout: timeout,
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
        case predicate
        case timeout
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
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let timeout = try container.decode(Double.self, forKey: .timeout)
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
        self.init(
            predicate: predicate,
            timeout: timeout,
            iterationCount: iterationCount,
            lastObservedSummary: lastObservedSummary,
            storage: storage
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
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
        case (.handledElse, .unmet(let expectation)) where iterationOrdinal == nil && actionResult == nil:
            return .handledElse(expectation: expectation, failureReason: failureReason)
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
