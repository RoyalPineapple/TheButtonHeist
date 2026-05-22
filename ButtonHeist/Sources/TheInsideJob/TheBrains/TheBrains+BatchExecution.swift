#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct BatchExecutionRuntime {
        let execute: @MainActor (TheScore.Action) async -> ActionResult
        let waitForExpectation: @MainActor (ActionExpectation, TheScore.Deadline) async -> ActionResult
        let settleRefreshRecordBaseline: @MainActor () async -> Void

        static func live(_ brains: TheBrains) -> BatchExecutionRuntime {
            BatchExecutionRuntime(
                execute: { action in
                    await brains.executeBatchAction(action)
                },
                waitForExpectation: { expectation, deadline in
                    await brains.executeWaitForChange(
                        timeout: deadline.timeout ?? WaitForChangeTarget(expect: expectation).resolvedTimeout,
                        expectation: expectation
                    )
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

        var builder = ActionResultBuilder(
            method: .batchExecutionPlan,
            screenName: screenName,
            screenId: screenId
        )
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
        let actionResult = await runtime.execute(step.action)
        let expectationReceipt = await expectationReceipt(
            for: step,
            actionResult: actionResult,
            runtime: runtime
        )

        return BatchExecutionStepResult(
            index: index,
            actionName: step.action.canonicalName,
            expectationName: step.expectation.summaryDescription,
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
        let expectation = step.expectation
        let immediateExpectation = expectation.validate(against: actionResult)
        if immediateExpectation.met || expectation == .delivery {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }
        if step.action.fulfillsOwnExpectation {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: ExpectationResult(
                    met: true,
                    expectation: expectation,
                    actual: actionResult.message ?? actionResult.accessibilityDelta?.kindRawValue
                )
            )
        }

        let waitResult = await runtime.waitForExpectation(expectation, step.deadline)
        return BatchExpectationReceipt(
            actionResult: waitResult,
            expectation: ExpectationResult(
                met: waitResult.success,
                expectation: expectation,
                actual: waitResult.message ?? waitResult.accessibilityDelta?.kindRawValue
            )
        )
    }

    private func executeBatchAction(_ action: TheScore.Action) async -> ActionResult {
        let pendingRotorResultToken = stash.preparePendingRotorResult(
            targetedHeistId: action.pendingRotorResultTargetHeistId
        )
        defer {
            if let pendingRotorResultToken {
                stash.clearPendingRotorResult(consumedToken: pendingRotorResultToken)
            }
        }

        switch action {
        case .activate(let target):
            return await performInteraction(method: .activate) { recordedScreen in
                await self.actions.executeActivate(target.executableTarget, recordedScreen: recordedScreen)
            }
        case .increment(let target):
            return await performInteraction(method: .increment) { recordedScreen in
                await self.actions.executeIncrement(target.executableTarget, recordedScreen: recordedScreen)
            }
        case .decrement(let target):
            return await performInteraction(method: .decrement) { recordedScreen in
                await self.actions.executeDecrement(target.executableTarget, recordedScreen: recordedScreen)
            }
        case .performCustomAction(let target):
            return await performInteraction(method: .customAction) { recordedScreen in
                await self.actions.executeCustomAction(target, recordedScreen: recordedScreen)
            }
        case .rotor(let target):
            return await performInteraction(method: .rotor) { recordedScreen in
                await self.actions.executeRotor(target, recordedScreen: recordedScreen)
            }
        case .touchTap, .touchLongPress, .touchSwipe, .touchDrag,
             .touchPinch, .touchRotate, .touchTwoFingerTap,
             .touchDrawPath, .touchDrawBezier:
            return await executeBatchTouchAction(action)
        case .typeText(let target):
            return await performInteraction(method: .typeText) { recordedScreen in
                await self.actions.executeTypeText(target, recordedScreen: recordedScreen)
            }
        case .editAction(let target):
            return await performInteraction(method: .editAction) {
                await self.actions.executeEditAction(target)
            }
        case .setPasteboard(let target):
            return await performInteraction(method: .setPasteboard) {
                await self.actions.executeSetPasteboard(target)
            }
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return await executeBatchScrollAction(action)
        case .waitForIdle(let target):
            return await executeWaitForIdle(timeout: min(target.timeout ?? 5.0, 60.0))
        case .waitForElement(let target):
            return await performWaitFor(
                elementTarget: target.target.executableTarget,
                absent: target.absent,
                timeout: target.timeout
            )
        case .waitForChange(let target):
            return await executeWaitForChange(
                timeout: target.resolvedTimeout,
                expectation: target.expect
            )
        case .explore:
            return await performExplore()
        case .resignFirstResponder:
            return await performInteraction(method: .resignFirstResponder) {
                await self.actions.executeResignFirstResponder()
            }
        }
    }

    private func executeBatchTouchAction(_ action: TheScore.Action) async -> ActionResult {
        switch action {
        case .touchTap(let target):
            return await performInteraction(method: .syntheticTap) { recordedScreen in
                await self.actions.executeTap(target, recordedScreen: recordedScreen)
            }
        case .touchLongPress(let target):
            return await performInteraction(method: .syntheticLongPress) { recordedScreen in
                await self.actions.executeLongPress(target, recordedScreen: recordedScreen)
            }
        case .touchSwipe(let target):
            return await performInteraction(method: .syntheticSwipe) { recordedScreen in
                await self.actions.executeSwipe(target, recordedScreen: recordedScreen)
            }
        case .touchDrag(let target):
            return await performInteraction(method: .syntheticDrag) { recordedScreen in
                await self.actions.executeDrag(target, recordedScreen: recordedScreen)
            }
        case .touchPinch(let target):
            return await performInteraction(method: .syntheticPinch) { recordedScreen in
                await self.actions.executePinch(target, recordedScreen: recordedScreen)
            }
        case .touchRotate(let target):
            return await performInteraction(method: .syntheticRotate) { recordedScreen in
                await self.actions.executeRotate(target, recordedScreen: recordedScreen)
            }
        case .touchTwoFingerTap(let target):
            return await performInteraction(method: .syntheticTwoFingerTap) { recordedScreen in
                await self.actions.executeTwoFingerTap(target, recordedScreen: recordedScreen)
            }
        case .touchDrawPath(let target):
            return await performInteraction(method: .syntheticDrawPath) {
                await self.actions.executeDrawPath(target)
            }
        case .touchDrawBezier(let target):
            return await performInteraction(method: .syntheticDrawPath) {
                await self.actions.executeDrawBezier(target)
            }
        default:
            return unsupportedBatchActionResult(action, reason: "not a touch action")
        }
    }

    private func executeBatchScrollAction(_ action: TheScore.Action) async -> ActionResult {
        switch action {
        case .scroll(let target):
            return await performInteraction(method: .scroll) {
                await self.navigation.executeScroll(
                    elementTarget: target.target?.executableTarget,
                    direction: target.direction
                )
            }
        case .scrollToVisible(let target):
            return await performInteraction(method: .scrollToVisible) { recordedScreen in
                await self.navigation.executeScrollToVisible(
                    elementTarget: target.target?.executableTarget,
                    recordedScreen: recordedScreen
                )
            }
        case .elementSearch(let target):
            return await performElementSearch(
                elementTarget: target.target?.executableTarget,
                direction: target.direction,
                method: .elementSearch
            )
        case .scrollToEdge(let target):
            return await performInteraction(method: .scrollToEdge) {
                await self.navigation.executeScrollToEdge(
                    elementTarget: target.target?.executableTarget,
                    edge: target.edge
                )
            }
        default:
            return unsupportedBatchActionResult(action, reason: "not a scroll action")
        }
    }

    private func unsupportedBatchActionResult(
        _ action: TheScore.Action,
        reason: String
    ) -> ActionResult {
        var builder = ActionResultBuilder(
            method: .unsupportedCommand,
            screenName: screenName,
            screenId: screenId
        )
        builder.message = "Unsupported batch Action '\(action.canonicalName)': \(reason)"
        return builder.failure(errorKind: .unsupported)
    }

    private func appendSkippedBatchSteps(
        afterFailedIndex failedIndex: Int,
        remainingSteps: ArraySlice<TheScore.BatchStep>,
        into stepResults: inout [BatchExecutionStepResult]
    ) {
        for (offset, step) in remainingSteps.enumerated() {
            let index = failedIndex + 1 + offset
            let skipped = BatchExecutionSkippedStepResult(
                index: index,
                actionName: step.action.canonicalName,
                expectationName: step.expectation.summaryDescription,
                reason: "skipped: stop_on_error stopped batch after step \(failedIndex)",
                afterFailedIndex: failedIndex
            )
            stepResults.append(BatchExecutionStepResult(
                index: index,
                actionName: step.action.canonicalName,
                expectationName: step.expectation.summaryDescription,
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

extension TheScore.Action {
    var pendingRotorResultTargetHeistId: HeistId? {
        guard case .rotor(let target) = self else { return nil }
        return target.currentSourceHeistId
    }
}

private extension BatchExecutionStepResult {
    func markingStop() -> BatchExecutionStepResult {
        BatchExecutionStepResult(
            index: index,
            actionName: actionName,
            expectationName: expectationName,
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
