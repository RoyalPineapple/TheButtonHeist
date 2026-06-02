#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct HeistExecutionRuntime {
        let execute: @MainActor (ClientMessage) async -> ActionResult
        let wait: @MainActor (WaitStep, AccessibilityTrace?) async -> HeistWaitReceipt
        let observeSemanticState: @MainActor (SemanticObservationScope, PostActionObservation.BeforeState?, Double?) async -> HeistSemanticObservation?
        let recordDeliveredObservationAfterStep: @MainActor () async -> Void

        @MainActor
        static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            return HeistExecutionRuntime(
                execute: { command in
                    await brains.executeCommand(command)
                },
                wait: { waitStep, initialTrace in
                    await brains.interactionObservation.waitForPredicate(waitStep, initialTrace: initialTrace)
                },
                observeSemanticState: { scope, baseline, timeout in
                    await brains.interactionObservation.observeSemanticState(scope: scope, baseline: baseline, timeout: timeout)
                },
                recordDeliveredObservationAfterStep: {
                    if let state = await brains.interactionObservation.recordDeliveredBaselineAfterStep() {
                        brains.waitForChangeState.recordDeliveredBaseline(state)
                    }
                }
            )
        }
    }

    func executeHeistPlan(_ plan: HeistPlan) async -> ActionResult {
        startSemanticObservation()
        return await executeHeistPlan(plan, runtime: .live(self))
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
        let stepResults = await executeHeistSteps(plan.steps, runtime: runtime)
        let failedIndex = stepResults.firstIndex(where: \.isFailure)

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

    func executeHeistSteps(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime
    ) async -> [HeistExecutionStepResult] {
        var stepResults: [HeistExecutionStepResult] = []
        var failedIndex: Int?

        stepLoop: for (index, step) in steps.enumerated() {
            var stepResult = await executeHeistStep(step, index: index, runtime: runtime)
            if stepResult.isFailure {
                stepResult = stepResult.markingStop()
                failedIndex = index
            }
            stepResults.append(stepResult)

            await runtime.recordDeliveredObservationAfterStep()

            if failedIndex != nil {
                appendSkippedHeistSteps(
                    afterFailedIndex: index,
                    remainingCount: steps.count - index - 1,
                    into: &stepResults
                )
                break stepLoop
            }
        }

        return stepResults
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
            return await executeWaitStep(waitStep, index: index, start: start, runtime: runtime)
        case .conditional(let conditional):
            return await executeConditionalStep(conditional, index: index, start: start, runtime: runtime)
        case .waitForCases(let waitForCases):
            return await executeWaitForCasesStep(waitForCases, index: index, start: start, runtime: runtime)
        case .forEach(let forEach):
            return await executeForEachStep(forEach, index: index, start: start, runtime: runtime)
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

    func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
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
            skipped: skipped,
            caseSelection: caseSelection,
            forEachResult: forEachResult,
            childResults: childResults
        )
    }
}

extension HeistExecutionStepResult {
    func reindexed(_ newIndex: Int) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: newIndex,
            kind: kind,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            message: message,
            durationMs: durationMs,
            stopsHeist: stopsHeist,
            skipped: skipped,
            caseSelection: caseSelection,
            forEachResult: forEachResult,
            childResults: childResults
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
