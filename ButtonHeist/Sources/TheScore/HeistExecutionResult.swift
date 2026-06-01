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
    case waitForCases
    case forEach = "for_each"
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
    public let forEachResult: HeistForEachResult?
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
        forEachResult: HeistForEachResult? = nil,
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
        self.forEachResult = forEachResult
        self.childResults = childResults
    }

    public var isSkipped: Bool {
        skipped != nil
    }

    public var isFailure: Bool {
        guard skipped == nil else { return false }
        if stopsHeist { return true }
        if kind == .fail { return true }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if kind == .action, actionResult == nil { return true }
        if kind == .wait, actionResult?.success != true { return true }
        if kind == .waitForCases, caseSelection?.timedOut == true, caseSelection?.elseRan != true { return true }
        if kind == .forEach, forEachResult?.failureReason != nil { return true }
        if childResults?.contains(where: \.isFailure) == true { return true }
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

public struct HeistForEachResult: Codable, Sendable {
    public let matchedCount: Int
    public let limit: Int
    public let iterationCount: Int
    public let failureReason: String?

    public init(
        matchedCount: Int,
        limit: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.matchedCount = matchedCount
        self.limit = limit
        self.iterationCount = iterationCount
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
