#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct BatchExecutionRuntime {
        let execute: @MainActor (ClientMessage) async -> ActionResult
        let waitForExpectation: @MainActor (AccessibilityPredicate, TheScore.Deadline) async -> ActionResult
        let settleRefreshRecordBaseline: @MainActor () async -> Void

        static func live(_ brains: TheBrains) -> BatchExecutionRuntime {
            BatchExecutionRuntime(
                execute: { command in
                    await brains.executeCommand(command)
                },
                waitForExpectation: { expectation, deadline in
                    await brains.performWait(target: WaitTarget(
                        predicate: expectation,
                        timeout: deadline.timeout
                    ))
                },
                settleRefreshRecordBaseline: {
                    _ = await brains.tripwire.waitForAllClear(timeout: 0.5)
                    if brains.refresh() != nil {
                        brains.recordSentState()
                    }
                }
            )
        }
    }

    func executeBatchExecutionPlan(_ plan: TheScore.BatchPlan) async -> ActionResult {
        await executeBatchPlan(plan, runtime: .live(self))
    }

    func executeBatchExecutionPlanForTest(
        _ plan: TheScore.BatchPlan,
        runtime: BatchExecutionRuntime
    ) async -> ActionResult {
        await executeBatchPlan(plan, runtime: runtime)
    }

    private func executeBatchPlan(
        _ plan: TheScore.BatchPlan,
        runtime: BatchExecutionRuntime
    ) async -> ActionResult {
        let batchStart = CFAbsoluteTimeGetCurrent()
        var stepResults: [BatchExecutionStepResult] = []
        var failedIndex: Int?

        stepLoop: for (index, step) in plan.steps.enumerated() {
            var stepResult = await executeBatchStep(step, index: index, runtime: runtime)
            if stepResult.isFailure, plan.policy == .stopOnError {
                stepResult = stepResult.markingStop()
                failedIndex = index
            }
            stepResults.append(stepResult)

            await runtime.settleRefreshRecordBaseline()

            if failedIndex != nil {
                appendSkippedBatchSteps(
                    afterFailedIndex: index,
                    remainingSteps: plan.steps.dropFirst(index + 1),
                    into: &stepResults
                )
                break stepLoop
            }
        }

        let batchResult = BatchExecutionResult(
            policy: plan.policy,
            steps: stepResults,
            totalTimingMs: Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000),
            failedIndex: failedIndex
        )

        var builder = ActionResultBuilder(method: .batchExecutionPlan)
        builder.message = batchExecutionMessage(
            completedCount: stepResults.count(where: { !$0.isSkipped }),
            failedCount: stepResults.count(where: \.isFailure),
            failedIndex: failedIndex
        )

        if failedIndex == nil {
            return builder.success(payload: .batchExecution(batchResult))
        }
        return builder.failure(errorKind: .actionFailed, payload: .batchExecution(batchResult))
    }

    private func executeBatchStep(
        _ step: TheScore.BatchStep,
        index: Int,
        runtime: BatchExecutionRuntime
    ) async -> BatchExecutionStepResult {
        let start = CFAbsoluteTimeGetCurrent()
        let actionResult = await runtime.execute(step.command)
        let expectationReceipt = await expectationReceipt(
            for: step,
            actionResult: actionResult,
            runtime: runtime
        )

        return BatchExecutionStepResult(
            index: index,
            actionResult: actionResult,
            expectationActionResult: expectationReceipt?.actionResult,
            expectation: expectationReceipt?.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func expectationReceipt(
        for step: TheScore.BatchStep,
        actionResult: ActionResult,
        runtime: BatchExecutionRuntime
    ) async -> BatchExpectationReceipt? {
        guard actionResult.success else { return nil }
        guard let expectation = step.predicate else { return nil }
        let immediateExpectation = expectation.validate(against: actionResult)
        if immediateExpectation.met {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }

        let waitResult = await runtime.waitForExpectation(expectation, step.deadline)
        return BatchExpectationReceipt(
            actionResult: waitResult,
            expectation: expectation.validate(against: waitResult)
        )
    }

    private func appendSkippedBatchSteps(
        afterFailedIndex failedIndex: Int,
        remainingSteps: ArraySlice<TheScore.BatchStep>,
        into stepResults: inout [BatchExecutionStepResult]
    ) {
        for index in (failedIndex + 1)..<(failedIndex + 1 + remainingSteps.count) {
            let skipped = BatchExecutionSkippedStepResult(
                index: index,
                reason: "skipped: stop_on_error stopped batch after step \(failedIndex)",
                afterFailedIndex: failedIndex
            )
            stepResults.append(BatchExecutionStepResult(
                index: index,
                durationMs: 0,
                skipped: skipped
            ))
        }
    }

    private func batchExecutionMessage(
        completedCount: Int,
        failedCount: Int,
        failedIndex: Int?
    ) -> String {
        if let failedIndex {
            return "Batch execution stopped at step \(failedIndex) after \(completedCount) completed step(s)"
        }
        if failedCount > 0 {
            return "Batch execution completed \(completedCount) step(s) with \(failedCount) failed step(s)"
        }
        return "Batch execution completed \(completedCount) step(s)"
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private struct BatchExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

private extension BatchExecutionStepResult {
    func markingStop() -> BatchExecutionStepResult {
        BatchExecutionStepResult(
            index: index,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            durationMs: durationMs,
            stopsBatch: true,
            skipped: skipped
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
