import ThePlans
import Foundation

// MARK: - Heist Execution Receipt

/// Durable receipt for executing a `HeistPlan`.
public struct HeistExecutionResult: Codable, Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let durationMs: Int
    public let abortedAtPath: String?

    public init(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String? = nil
    ) {
        self.steps = steps
        self.durationMs = durationMs
        self.abortedAtPath = abortedAtPath
    }
}

public enum HeistExecutionStepKind: String, Codable, Sendable, Equatable {
    case action
    case wait
    case conditional
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case repeatUntil = "repeat_until"
    case repeatUntilIteration = "repeat_until_iteration"
    case warn
    case fail
    case heist
    case invoke
}

public enum HeistExecutionStepStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case skipped
}

/// One node in a heist execution receipt tree.
public struct HeistExecutionStepResult: Codable, Sendable, Equatable {
    /// JSON-style path to this execution node in the heist program tree.
    public let path: String
    public let kind: HeistExecutionStepKind
    public let status: HeistExecutionStepStatus
    public let durationMs: Int

    public let intent: HeistStepIntent?
    public let evidence: HeistStepEvidence?
    public let failure: HeistFailureDetail?
    public let abortedAtChildPath: String?
    public let children: [HeistExecutionStepResult]

    public init(
        path: String,
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus,
        durationMs: Int,
        intent: HeistStepIntent? = nil,
        evidence: HeistStepEvidence? = nil,
        failure: HeistFailureDetail? = nil,
        abortedAtChildPath: String? = nil,
        children: [HeistExecutionStepResult] = []
    ) {
        self.path = path
        self.kind = kind
        self.status = status
        self.durationMs = durationMs
        self.intent = intent
        self.evidence = evidence
        self.failure = failure
        self.abortedAtChildPath = abortedAtChildPath
        self.children = children
    }
}

public enum HeistStepIntent: Codable, Sendable, Equatable {
    case action(command: String, target: String?)
    case wait(predicate: String, timeout: Double)
    case conditional
    case forEachString(parameter: HeistReferenceName, count: Int)
    case forEachElement(parameter: HeistReferenceName, matching: String, limit: Int)
    case repeatUntil(predicate: String, timeout: Double)
    case invoke(path: String, argument: String?)
    case heist(name: String?)
    case warn(message: String)
    case fail(message: String)
}

public enum HeistStepEvidence: Codable, Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case caseSelection(HeistCaseSelectionEvidence)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case warning(HeistExecutionWarning)
}

public struct HeistActionEvidence: Codable, Sendable, Equatable {
    public let command: HeistActionCommand?
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?

    public init(
        command: HeistActionCommand?,
        actionResult: ActionResult?,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.command = command
        self.actionResult = actionResult
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
    }
}

public struct HeistWaitEvidence: Codable, Sendable, Equatable {
    public let actionResult: ActionResult
    public let expectation: ExpectationResult
    public let baselineSummary: String?
    public let finalSummary: String?

    public init(
        actionResult: ActionResult,
        expectation: ExpectationResult,
        baselineSummary: String? = nil,
        finalSummary: String? = nil
    ) {
        self.actionResult = actionResult
        self.expectation = expectation
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
    }
}

public struct HeistCaseSelectionEvidence: Codable, Sendable, Equatable {
    public let selection: HeistCaseSelectionResult

    public init(selection: HeistCaseSelectionResult) {
        self.selection = selection
    }
}

public struct HeistForEachStringEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let count: Int
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let value: String?
    public let failureReason: String?

    public init(
        parameter: HeistReferenceName,
        count: Int,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        value: String? = nil,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.count = count
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.value = value
        self.failureReason = failureReason
    }
}

public struct HeistForEachElementEvidence: Codable, Sendable, Equatable {
    public let parameter: HeistReferenceName
    public let matching: ElementPredicate
    public let limit: Int
    public let matchedCount: Int
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let targetOrdinal: Int?
    public let targetSummary: String?
    public let failureReason: String?

    public init(
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        limit: Int,
        matchedCount: Int,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        targetOrdinal: Int? = nil,
        targetSummary: String? = nil,
        failureReason: String? = nil
    ) {
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
        self.matchedCount = matchedCount
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.targetOrdinal = targetOrdinal
        self.targetSummary = targetSummary
        self.failureReason = failureReason
    }
}

public struct HeistRepeatUntilEvidence: Codable, Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let timeout: Double
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let expectation: ExpectationResult
    public let actionResult: ActionResult?
    public let lastObservedSummary: String?
    public let failureReason: String?

    public init(
        predicate: AccessibilityPredicate,
        timeout: Double,
        iterationCount: Int,
        iterationOrdinal: Int? = nil,
        expectation: ExpectationResult,
        actionResult: ActionResult? = nil,
        lastObservedSummary: String? = nil,
        failureReason: String? = nil
    ) {
        self.predicate = predicate
        self.timeout = timeout
        self.iterationCount = iterationCount
        self.iterationOrdinal = iterationOrdinal
        self.expectation = expectation
        self.actionResult = actionResult
        self.lastObservedSummary = lastObservedSummary
        self.failureReason = failureReason
    }
}

public struct HeistInvocationEvidence: Codable, Sendable, Equatable {
    public let invocation: HeistInvocationStep?
    public let name: String?
    public let argument: String?
    public let childFailedPath: String?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?

    public init(
        invocation: HeistInvocationStep? = nil,
        name: String? = nil,
        argument: String? = nil,
        childFailedPath: String? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.invocation = invocation
        self.name = name
        self.argument = argument
        self.childFailedPath = childFailedPath
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
    }
}

/// One warning emitted by a `Warn(...)` heist step.
public struct HeistExecutionWarning: Codable, Sendable, Equatable {
    public let path: String
    public let message: String

    public init(
        path: String,
        message: String
    ) {
        self.path = path
        self.message = message
    }
}

public struct HeistFailureDetail: Codable, Sendable, Equatable {
    public let category: HeistFailureCategory
    public let contract: String
    public let observed: String
    public let expected: String?

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil
    ) {
        self.category = category
        self.contract = contract
        self.observed = observed
        self.expected = expected
    }
}

public enum HeistFailureCategory: String, Codable, Sendable, Equatable {
    case validation
    case runtimeUnavailable
    case targetResolution
    case action
    case expectation
    case wait
    case invocation
    case loop
    case explicitFailure
}

public enum HeistCaseSelectionMissReason: String, Codable, Sendable, Equatable {
    case noMatch = "no_match"
    case timedOut = "timed_out"
}

public enum HeistCaseSelectionOutcome: Codable, Sendable, Equatable {
    case matchedCase(index: Int)
    case elseBranch(reason: HeistCaseSelectionMissReason)
    case timedOut
    case noMatch

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case index
        case reason
    }

    private enum Kind: String, Codable {
        case matchedCase = "matched_case"
        case elseBranch = "else_branch"
        case timedOut = "timed_out"
        case noMatch = "no_match"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case selection outcome")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .matchedCase:
            try Self.rejectIfPresent(.reason, in: container, kind: .matchedCase)
            let index = try container.decode(Int.self, forKey: .index)
            guard index >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .index,
                    in: container,
                    debugDescription: "matched_case index must be non-negative"
                )
            }
            self = .matchedCase(index: index)
        case .elseBranch:
            try Self.rejectIfPresent(.index, in: container, kind: .elseBranch)
            self = .elseBranch(
                reason: try container.decode(HeistCaseSelectionMissReason.self, forKey: .reason)
            )
        case .timedOut:
            try Self.rejectIfPresent(.index, in: container, kind: .timedOut)
            try Self.rejectIfPresent(.reason, in: container, kind: .timedOut)
            self = .timedOut
        case .noMatch:
            try Self.rejectIfPresent(.index, in: container, kind: .noMatch)
            try Self.rejectIfPresent(.reason, in: container, kind: .noMatch)
            self = .noMatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .matchedCase(let index):
            try container.encode(Kind.matchedCase, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .elseBranch(let reason):
            try container.encode(Kind.elseBranch, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .kind)
        case .noMatch:
            try container.encode(Kind.noMatch, forKey: .kind)
        }
    }

    private static func rejectIfPresent(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        kind: Kind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(kind.rawValue) outcome must not include \(key.stringValue)"
        )
    }
}

public struct HeistCaseSelectionResult: Codable, Sendable, Equatable {
    public let cases: [HeistCaseMatchResult]
    public let outcome: HeistCaseSelectionOutcome
    public let elapsedMs: Int
    public let timeout: Double?
    public let lastObservedSummary: String?

    public init(
        cases: [HeistCaseMatchResult],
        outcome: HeistCaseSelectionOutcome,
        elapsedMs: Int,
        timeout: Double? = nil,
        lastObservedSummary: String? = nil
    ) {
        self.cases = cases
        self.outcome = Self.normalized(outcome: outcome, cases: cases)
        self.elapsedMs = elapsedMs
        self.timeout = timeout
        self.lastObservedSummary = lastObservedSummary
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case outcome
        case elapsedMs
        case timeout
        case lastObservedSummary
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist case selection result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cases = try container.decode([HeistCaseMatchResult].self, forKey: .cases)

        self.init(
            cases: cases,
            outcome: try container.decode(HeistCaseSelectionOutcome.self, forKey: .outcome),
            elapsedMs: try container.decode(Int.self, forKey: .elapsedMs),
            timeout: try container.decodeIfPresent(Double.self, forKey: .timeout),
            lastObservedSummary: try container.decodeIfPresent(String.self, forKey: .lastObservedSummary)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cases, forKey: .cases)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(lastObservedSummary, forKey: .lastObservedSummary)
    }

    private static func normalized(
        outcome: HeistCaseSelectionOutcome,
        cases: [HeistCaseMatchResult]
    ) -> HeistCaseSelectionOutcome {
        switch outcome {
        case .matchedCase(let index):
            return cases.indices.contains(index) ? .matchedCase(index: index) : .noMatch
        case .elseBranch, .timedOut, .noMatch:
            return outcome
        }
    }
}

public struct HeistCaseMatchResult: Codable, Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let result: ExpectationResult

    public init(
        predicate: AccessibilityPredicate,
        result: ExpectationResult
    ) {
        self.predicate = predicate
        self.result = result
    }
}
