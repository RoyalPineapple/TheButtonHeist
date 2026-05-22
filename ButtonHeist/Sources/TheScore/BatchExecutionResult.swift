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
/// A step is normalized by InsideJob as `Action + ActionExpectation? +
/// Deadline?`. Optional fields here preserve wire compatibility for skipped
/// rows and for current adapter syntax that cannot express an expectation.
public struct BatchExecutionStepResult: Codable, Sendable {
    public let index: Int
    public let actionName: String?
    public let expectationName: String?
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let durationMs: Int
    public let stopsBatch: Bool
    public let skipped: BatchExecutionSkippedStepResult?

    public init(
        index: Int,
        actionName: String? = nil,
        expectationName: String? = nil,
        actionResult: ActionResult? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        durationMs: Int,
        stopsBatch: Bool = false,
        skipped: BatchExecutionSkippedStepResult? = nil
    ) {
        self.index = index
        self.actionName = actionName
        self.expectationName = expectationName
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
        if actionName == nil, expectationName == nil { return true }
        return false
    }

    public var displayName: String {
        if let actionName, let expectationName {
            return "\(actionName)+\(expectationName)"
        }
        return actionName ?? expectationName ?? "invalid"
    }
}

public struct BatchExecutionSkippedStepResult: Codable, Sendable {
    public let index: Int
    public let actionName: String?
    public let expectationName: String?
    public let reason: String
    public let afterFailedIndex: Int

    public init(
        index: Int,
        actionName: String? = nil,
        expectationName: String? = nil,
        reason: String,
        afterFailedIndex: Int
    ) {
        self.index = index
        self.actionName = actionName
        self.expectationName = expectationName
        self.reason = reason
        self.afterFailedIndex = afterFailedIndex
    }
}
