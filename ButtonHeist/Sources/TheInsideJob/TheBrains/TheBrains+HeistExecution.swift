#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct HeistExecutionRuntime {
        let execute: @MainActor (ClientMessage) async -> ActionResult
        let wait: @MainActor (WaitStep) async -> ActionResult
        let settleRefreshRecordBaseline: @MainActor () async -> Void

        static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command in
                    await brains.executeCommand(command)
                },
                wait: { waitStep in
                    await brains.performWait(target: WaitTarget(
                        predicate: waitStep.predicate,
                        timeout: waitStep.timeout
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

    func executeHeistPlan(_ plan: HeistPlan) async -> ActionResult {
        await executeHeistPlan(plan, runtime: .live(self))
    }

    func executeHeistPlanForTest(
        _ plan: HeistPlan,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        await executeHeistPlan(plan, runtime: runtime)
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        let heistStart = CFAbsoluteTimeGetCurrent()
        var stepResults: [HeistExecutionStepResult] = []
        var failedIndex: Int?

        stepLoop: for (index, step) in plan.steps.enumerated() {
            var stepResult = await executeHeistStep(step, index: index, runtime: runtime)
            if stepResult.isFailure {
                stepResult = stepResult.markingStop()
                failedIndex = index
            }
            stepResults.append(stepResult)

            await runtime.settleRefreshRecordBaseline()

            if failedIndex != nil {
                appendSkippedHeistSteps(
                    afterFailedIndex: index,
                    remainingCount: plan.steps.count - index - 1,
                    into: &stepResults
                )
                break stepLoop
            }
        }

        let heistResult = HeistExecutionResult(
            steps: stepResults,
            totalTimingMs: Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000),
            failedIndex: failedIndex
        )

        var builder = ActionResultBuilder(method: .heistPlan)
        builder.message = heistExecutionMessage(
            completedCount: stepResults.count(where: { !$0.isSkipped }),
            failedCount: stepResults.count(where: \.isFailure),
            failedIndex: failedIndex
        )

        if failedIndex == nil {
            return builder.success(payload: .heistExecution(heistResult))
        }
        return builder.failure(errorKind: .actionFailed, payload: .heistExecution(heistResult))
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let start = CFAbsoluteTimeGetCurrent()
        switch step {
        case .action(let action):
            return await executeActionStep(action, index: index, start: start, runtime: runtime)
        case .wait(let waitStep):
            let result = await runtime.wait(waitStep)
            return HeistExecutionStepResult(
                index: index,
                kind: .wait,
                actionResult: result,
                expectation: waitStep.predicate.validate(against: result),
                durationMs: elapsedMilliseconds(since: start)
            )
        case .warn(let warn):
            return HeistExecutionStepResult(
                index: index,
                kind: .warn,
                message: warn.message,
                durationMs: elapsedMilliseconds(since: start)
            )
        case .fail(let fail):
            return HeistExecutionStepResult(
                index: index,
                kind: .fail,
                message: fail.message,
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true
            )
        }
    }

    private func executeActionStep(
        _ step: ActionStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let actionResult = await runtime.execute(step.command)
        let expectationReceipt = await expectationReceipt(
            for: step,
            actionResult: actionResult,
            runtime: runtime
        )

        return HeistExecutionStepResult(
            index: index,
            kind: .action,
            actionResult: actionResult,
            expectationActionResult: expectationReceipt?.actionResult,
            expectation: expectationReceipt?.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func expectationReceipt(
        for step: ActionStep,
        actionResult: ActionResult,
        runtime: HeistExecutionRuntime
    ) async -> HeistExpectationReceipt? {
        guard actionResult.success else { return nil }
        guard let expectation = step.expectation else { return nil }
        let immediateExpectation = expectation.predicate.validate(against: actionResult)
        if immediateExpectation.met || expectation.timeout == 0 {
            return HeistExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }

        let waitResult = await runtime.wait(expectation)
        return HeistExpectationReceipt(
            actionResult: waitResult,
            expectation: expectation.predicate.validate(against: waitResult)
        )
    }

    private func appendSkippedHeistSteps(
        afterFailedIndex failedIndex: Int,
        remainingCount: Int,
        into stepResults: inout [HeistExecutionStepResult]
    ) {
        guard remainingCount > 0 else { return }
        for index in (failedIndex + 1)..<(failedIndex + 1 + remainingCount) {
            let skipped = HeistExecutionSkippedStepResult(
                index: index,
                reason: "skipped: heist stopped after step \(failedIndex)",
                afterFailedIndex: failedIndex
            )
            stepResults.append(HeistExecutionStepResult(
                index: index,
                kind: .skipped,
                durationMs: 0,
                skipped: skipped
            ))
        }
    }

    private func heistExecutionMessage(
        completedCount: Int,
        failedCount: Int,
        failedIndex: Int?
    ) -> String {
        if let failedIndex {
            return "Heist execution stopped at step \(failedIndex) after \(completedCount) completed step(s)"
        }
        if failedCount > 0 {
            return "Heist execution completed \(completedCount) step(s) with \(failedCount) failed step(s)"
        }
        return "Heist execution completed \(completedCount) step(s)"
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private struct HeistExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

private extension HeistExecutionStepResult {
    func markingStop() -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            kind: kind,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            message: message,
            durationMs: durationMs,
            stopsHeist: true,
            skipped: skipped
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
