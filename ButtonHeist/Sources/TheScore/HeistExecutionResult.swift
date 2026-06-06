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
    case waitForCases
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case warn
    case fail
    case heist
    case invoke
}

public enum HeistExecutionStepStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
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
    case waitForCases(timeout: Double)
    case forEachString(parameter: String, count: Int)
    case forEachElement(parameter: String, matching: String, limit: Int)
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
    public let parameter: String
    public let count: Int
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let value: String?
    public let failureReason: String?

    public init(
        parameter: String,
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
    public let parameter: String
    public let matching: ElementPredicate
    public let limit: Int
    public let matchedCount: Int
    public let iterationCount: Int
    public let iterationOrdinal: Int?
    public let targetOrdinal: Int?
    public let targetSummary: String?
    public let failureReason: String?

    public init(
        parameter: String,
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

public struct HeistInvocationEvidence: Codable, Sendable, Equatable {
    public let invocation: HeistInvocationStep?
    public let name: String?
    public let argument: String?
    public let childFailedPath: String?

    public init(
        invocation: HeistInvocationStep? = nil,
        name: String? = nil,
        argument: String? = nil,
        childFailedPath: String? = nil
    ) {
        self.invocation = invocation
        self.name = name
        self.argument = argument
        self.childFailedPath = childFailedPath
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

public struct HeistCaseSelectionResult: Codable, Sendable, Equatable {
    public let cases: [HeistCaseMatchResult]
    public let selectedCaseIndex: Int?
    public let elapsedMs: Int
    public let timeout: Double?
    public let timedOut: Bool
    public let elseRan: Bool
    public let lastObservedSummary: String?

    public init(
        cases: [HeistCaseMatchResult],
        selectedCaseIndex: Int?,
        elapsedMs: Int,
        timeout: Double? = nil,
        timedOut: Bool = false,
        elseRan: Bool = false,
        lastObservedSummary: String? = nil
    ) {
        self.cases = cases
        self.selectedCaseIndex = selectedCaseIndex
        self.elapsedMs = elapsedMs
        self.timeout = timeout
        self.timedOut = timedOut
        self.elseRan = elseRan
        self.lastObservedSummary = lastObservedSummary
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
