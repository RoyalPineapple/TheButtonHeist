import Foundation

// MARK: - Batch Execution Results

/// Typed result for an InsideJob-owned batch execution plan.
public struct BatchExecutionResult: Codable, Sendable {
    public let policy: BatchExecutionPolicy
    public let steps: [BatchExecutionStepResult]
    public let totalTimingMs: Int
    public let failedIndex: Int?

    public init(
        policy: BatchExecutionPolicy,
        steps: [BatchExecutionStepResult],
        totalTimingMs: Int,
        failedIndex: Int? = nil
    ) {
        self.policy = policy
        self.steps = steps
        self.totalTimingMs = totalTimingMs
        self.failedIndex = failedIndex
    }
}

/// One typed step result from a batch execution plan.
///
/// A step is normalized by InsideJob as `Action + AccessibilityPredicate? +
/// Deadline?`. Optional fields model the current result contract: skipped rows
/// do not have action output, and action-only rows do not have expectation data.
public struct BatchExecutionStepResult: Codable, Sendable {
    public let index: Int
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let durationMs: Int
    public let stopsBatch: Bool
    public let skipped: BatchExecutionSkippedStepResult?

    public init(
        index: Int,
        actionResult: ActionResult? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        durationMs: Int,
        stopsBatch: Bool = false,
        skipped: BatchExecutionSkippedStepResult? = nil
    ) {
        self.index = index
        self.actionResult = actionResult
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
        self.durationMs = durationMs
        self.stopsBatch = stopsBatch
        self.skipped = skipped
    }

    public var isSkipped: Bool {
        skipped != nil
    }

    public var isFailure: Bool {
        guard skipped == nil else { return false }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if actionResult == nil, expectationActionResult == nil, expectation == nil { return true }
        return false
    }
}

public struct BatchExecutionSkippedStepResult: Codable, Sendable {
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
