import Foundation

public struct HeistWaitEvidence: Codable, Sendable, Equatable {
    private let storage: Storage
    public let baselineSummary: String?
    public let finalSummary: String?
    public let warning: HeistPredicateWarning?

    public struct MatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: MetExpectationResult

        public init?(
            actionResult: ActionResult,
            expectation: MetExpectationResult
        ) {
            guard actionResult.outcome.isSuccess else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }
    }

    public struct UnmatchedCheck: Sendable, Equatable {
        public let actionResult: ActionResult
        public let expectation: PredicateExpectationCheck

        public init?(
            actionResult: ActionResult,
            expectation: PredicateExpectationCheck
        ) {
            guard !actionResult.outcome.isSuccess || !expectation.result.met else { return nil }
            self.actionResult = actionResult
            self.expectation = expectation
        }

        public init?(
            actionResult: ActionResult,
            expectation: ExpectationResult
        ) {
            self.init(
                actionResult: actionResult,
                expectation: PredicateExpectationCheck(expectation)
            )
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
            return check.expectation.result
        }
    }

    public static func matched(
        _ check: MatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .matched(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    public static func handledElse(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .handledElse(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    public static func failed(
        _ check: UnmatchedCheck,
        baselineSummary: String? = nil,
        finalSummary: String? = nil,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitEvidence {
        return HeistWaitEvidence(
            storage: .failed(check),
            baselineSummary: baselineSummary,
            finalSummary: finalSummary,
            warning: warning
        )
    }

    private init(
        storage: Storage,
        baselineSummary: String?,
        finalSummary: String?,
        warning: HeistPredicateWarning?
    ) {
        self.storage = storage
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case actionResult
        case expectation
        case baselineSummary
        case finalSummary
        case warning
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
        warning = try container.decodeIfPresent(HeistPredicateWarning.self, forKey: .warning)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(actionResult, forKey: .actionResult)
        try container.encode(expectation, forKey: .expectation)
        try container.encodeIfPresent(baselineSummary, forKey: .baselineSummary)
        try container.encodeIfPresent(finalSummary, forKey: .finalSummary)
        try container.encodeIfPresent(warning, forKey: .warning)
    }

    private static func storage(
        outcome: HeistPredicateEvidenceOutcome,
        actionResult: ActionResult,
        expectation: ExpectationResult,
        codingPath: [CodingKey]
    ) throws -> Storage {
        let expectation = PredicateExpectationCheck(expectation)
        switch outcome {
        case .matched:
            guard case .met(let expectation) = expectation,
                  let check = MatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "matched wait evidence requires a successful action result and met expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .matched(check)
        case .handledElse:
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "handled_else wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .handledElse(check)
        case .failed:
            guard let check = UnmatchedCheck(actionResult: actionResult, expectation: expectation) else {
                throw evidenceError(
                    "failed wait evidence requires a failed action result or unmet expectation",
                    codingPath: codingPath + [CodingKeys.outcome]
                )
            }
            return .failed(check)
        case .continued:
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

public struct HeistPredicateWarning: Codable, Sendable, Equatable {
    public let code: String
    public let predicate: String
    public let impliedPredicate: String?
    public let finalStateTiming: String?
    public let evidence: String?
    public let message: String

    public init(
        code: String,
        predicate: String,
        impliedPredicate: String? = nil,
        finalStateTiming: String? = nil,
        evidence: String? = nil,
        message: String
    ) {
        self.code = code
        self.predicate = predicate
        self.impliedPredicate = impliedPredicate
        self.finalStateTiming = finalStateTiming
        self.evidence = evidence
        self.message = message
    }
}
