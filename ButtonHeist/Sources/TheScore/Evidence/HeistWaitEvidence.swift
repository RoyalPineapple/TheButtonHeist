import Foundation

public enum HeistPredicateEvidenceOutcome: String, Codable, Sendable, Equatable {
    case matched
    case continued
    case handledElse = "handled_else"
    case failed
}

public struct HeistWaitEvidence: Codable, Sendable, Equatable {
    private let storage: Storage
    public let baselineSummary: String?
    public let finalSummary: String?

    public struct MatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: ExpectationResult.Met

        public init?(
            actionResult: ActionResult,
            expectation: ExpectationResult.Met
        ) {
            guard actionResult.outcome.isSuccess else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }
    }

    public struct UnmatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: ExpectationResult

        public init?(
            actionResult: ActionResult,
            expectation: ExpectationResult
        ) {
            guard !actionResult.outcome.isSuccess || !expectation.met else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }
    }

    private enum Storage: Sendable, Equatable {
        case matched(MatchedCheck)
        case handledElse(UnmatchedCheck)
        case failed(UnmatchedCheck)
    }

    public var outcome: HeistPredicateEvidenceOutcome {
        switch storage {
        case .matched:
            return .matched
        case .handledElse:
            return .handledElse
        case .failed:
            return .failed
        }
    }

    public var actionResult: ActionResult {
        switch storage {
        case .matched(let check):
            return check.actionResult
        case .handledElse(let check),
             .failed(let check):
            return check.actionResult
        }
    }

    public var expectation: ExpectationResult {
        switch storage {
        case .matched(let check):
            return check.expectation.result
        case .handledElse(let check),
             .failed(let check):
            return check.expectation
        }
    }

    public static func matched(
        _ check: MatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .matched(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary
        )
    }

    public static func handledElse(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .handledElse(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary
        )
    }

    public static func failed(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .failed(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary
        )
    }

    private init(
        storage: Storage,
        baselineSummary: String?,
        finalSummary: String?
    ) {
        self.storage = storage
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case actionResult
        case expectation
        case baselineSummary
        case finalSummary
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(HeistPredicateEvidenceOutcome.self, forKey: .outcome)
        let actionResult = try container.decode(ActionResult.self, forKey: .actionResult)
        let expectation = try container.decode(ExpectationResult.self, forKey: .expectation)
        storage = try Self.storage(
            outcome: outcome,
            actionResult: actionResult,
            expectation: expectation,
            codingPath: container.codingPath
        )
        baselineSummary = try container.decodeIfPresent(String.self, forKey: .baselineSummary)
        finalSummary = try container.decodeIfPresent(String.self, forKey: .finalSummary)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(actionResult, forKey: .actionResult)
        try container.encode(expectation, forKey: .expectation)
        try container.encodeIfPresent(baselineSummary, forKey: .baselineSummary)
        try container.encodeIfPresent(finalSummary, forKey: .finalSummary)
    }

    private static func storage(
        outcome: HeistPredicateEvidenceOutcome,
        actionResult: ActionResult,
        expectation: ExpectationResult,
        codingPath: [CodingKey]
    ) throws -> Storage {
        switch (outcome, expectation) {
        case (.matched, .met(let expectation)):
            guard let check = MatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "matched wait evidence requires a successful action result and met expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .matched(check)
        case (.matched, .unmet):
            throw evidenceError(
                "matched wait evidence requires a successful action result and met expectation",
                codingPath: codingPath + [CodingKeys.outcome]
            )
        case (.handledElse, _):
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "handled_else wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .handledElse(check)
        case (.failed, _):
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "failed wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .failed(check)
        case (.continued, _):
            throw evidenceError(
                "continued outcome is only valid for repeat_until evidence",
                codingPath: codingPath + [CodingKeys.outcome]
            )
        }
    }

    private static func evidenceError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}
