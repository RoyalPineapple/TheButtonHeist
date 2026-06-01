import Foundation

// MARK: - Heist Execution Results

/// Typed result for executing a `HeistPlan`.
public struct HeistExecutionResult: Codable, Sendable {
    public let steps: [HeistExecutionStepResult]
    public let totalTimingMs: Int
    public let failedIndex: Int?

    public init(
        steps: [HeistExecutionStepResult],
        totalTimingMs: Int,
        failedIndex: Int? = nil
    ) {
        self.steps = steps
        self.totalTimingMs = totalTimingMs
        self.failedIndex = failedIndex
    }
}

public enum HeistExecutionStepKind: String, Codable, Sendable {
    case action
    case wait
    case conditional
    case waitForCases = "wait_for_cases"
    case repeatCount = "repeat_count"
    case repeatUntil = "repeat_until"
    case warn
    case fail
    case skipped
}

/// One typed step result from a `HeistPlan`.
public struct HeistExecutionStepResult: Codable, Sendable {
    /// Sibling-local step index inside the containing `steps` or `childResults` array.
    public let index: Int
    public let kind: HeistExecutionStepKind
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let message: String?
    public let durationMs: Int
    public let stopsHeist: Bool
    public let skipped: HeistExecutionSkippedStepResult?
    public let caseSelection: HeistCaseSelectionResult?
    public let repeatResult: HeistRepeatResult?
    public let childResults: [HeistExecutionStepResult]?

    public init(
        index: Int,
        kind: HeistExecutionStepKind,
        actionResult: ActionResult? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        message: String? = nil,
        durationMs: Int,
        stopsHeist: Bool = false,
        skipped: HeistExecutionSkippedStepResult? = nil,
        caseSelection: HeistCaseSelectionResult? = nil,
        repeatResult: HeistRepeatResult? = nil,
        childResults: [HeistExecutionStepResult]? = nil
    ) {
        self.index = index
        self.kind = kind
        self.actionResult = actionResult
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
        self.message = message
        self.durationMs = durationMs
        self.stopsHeist = stopsHeist
        self.skipped = skipped
        self.caseSelection = caseSelection
        self.repeatResult = repeatResult
        self.childResults = childResults
    }

    public var isSkipped: Bool {
        skipped != nil
    }

    public var isFailure: Bool {
        guard skipped == nil else { return false }
        if childResults?.contains(where: \.isFailure) == true { return true }
        if stopsHeist { return true }
        if kind == .fail { return true }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if kind == .action, actionResult == nil { return true }
        if kind == .wait, actionResult?.success != true { return true }
        if kind == .waitForCases, caseSelection?.timedOut == true, caseSelection?.elseRan != true { return true }
        if repeatResult?.failureReason != nil { return true }
        return false
    }
}

public struct HeistCaseSelectionResult: Codable, Sendable {
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

public struct HeistCaseMatchResult: Codable, Sendable {
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

public struct HeistRepeatResult: Codable, Sendable {
    public let iterationCount: Int
    public let elapsedMs: Int
    public let timeout: Double?
    public let maxIterations: Int?
    public let finalPredicate: AccessibilityPredicate?
    public let finalPredicateResult: ExpectationResult?
    public let failureReason: String?

    public init(
        iterationCount: Int,
        elapsedMs: Int,
        timeout: Double? = nil,
        maxIterations: Int? = nil,
        finalPredicate: AccessibilityPredicate? = nil,
        finalPredicateResult: ExpectationResult? = nil,
        failureReason: String? = nil
    ) {
        self.iterationCount = iterationCount
        self.elapsedMs = elapsedMs
        self.timeout = timeout
        self.maxIterations = maxIterations
        self.finalPredicate = finalPredicate
        self.finalPredicateResult = finalPredicateResult
        self.failureReason = failureReason
    }
}

public struct HeistExecutionSkippedStepResult: Codable, Sendable {
    public let index: Int
    public let reason: String
    public let afterFailedIndex: Int

    public init(
        index: Int,
        reason: String,
        afterFailedIndex: Int
    ) {
        self.index = index
        self.reason = reason
        self.afterFailedIndex = afterFailedIndex
    }
}
