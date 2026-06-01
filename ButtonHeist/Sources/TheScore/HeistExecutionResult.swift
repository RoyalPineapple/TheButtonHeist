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
    case warn
    case fail
    case skipped
}

/// One typed step result from a `HeistPlan`.
public struct HeistExecutionStepResult: Codable, Sendable {
    public let index: Int
    public let kind: HeistExecutionStepKind
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let message: String?
    public let durationMs: Int
    public let stopsHeist: Bool
    public let skipped: HeistExecutionSkippedStepResult?

    public init(
        index: Int,
        kind: HeistExecutionStepKind,
        actionResult: ActionResult? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        message: String? = nil,
        durationMs: Int,
        stopsHeist: Bool = false,
        skipped: HeistExecutionSkippedStepResult? = nil
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
    }

    public var isSkipped: Bool {
        skipped != nil
    }

    public var isFailure: Bool {
        guard skipped == nil else { return false }
        if kind == .fail { return true }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if kind == .action, actionResult == nil { return true }
        if kind == .wait, actionResult?.success != true { return true }
        return false
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
