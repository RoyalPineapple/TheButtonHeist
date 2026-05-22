#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct BatchExecutionRuntime {
        let execute: @MainActor (Action) async -> ActionResult
        let waitForExpectation: @MainActor (ActionExpectation, Deadline) async -> ActionResult
        let settleRefreshRecordBaseline: @MainActor () async -> Void

        static func live(_ brains: TheBrains) -> BatchExecutionRuntime {
            BatchExecutionRuntime(
                execute: { action in
                    await brains.execute(action)
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

    struct BatchPlan {
        let steps: [BatchStep]
        let policy: BatchExecutionPolicy

        init(steps: [BatchStep], policy: BatchExecutionPolicy) {
            self.steps = steps
            self.policy = policy
        }

        init(_ wirePlan: TheScore.BatchPlan) {
            self.init(
                steps: wirePlan.steps.map(BatchStep.init),
                policy: wirePlan.policy
            )
        }
    }

    struct BatchStep {
        let action: Action
        let expectation: ActionExpectation
        let deadline: Deadline

        init(action: Action, expectation: ActionExpectation, deadline: Deadline) {
            self.action = action
            self.expectation = expectation
            self.deadline = deadline
        }

        init(_ wireStep: TheScore.BatchStep) {
            self.init(
                action: Action(wireStep.action),
                expectation: wireStep.expectation,
                deadline: Deadline(timeout: wireStep.deadline.timeout)
            )
        }
    }

    struct Deadline: Codable, Sendable, Equatable {
        let timeout: Double?
    }

    enum Action: Sendable {
        case clientMessage(ClientMessage)
        case waitForIdle(WaitForIdleTarget)
        case waitForElement(WaitForTarget)
        case waitForChange(WaitForChangeTarget, name: String? = nil)
        case checkpoint(name: String?)
        case unsupported(name: String, reason: String)

        init(_ batchAction: TheScore.Action) {
            switch batchAction {
            case .waitForIdle(let target):
                self = .waitForIdle(target)
            case .waitForElement(let target):
                self = .waitForElement(WaitForTarget(
                    elementTarget: target.target.executableTarget,
                    absent: target.absent,
                    timeout: target.timeout
                ))
            case .waitForChange(let target):
                self = .waitForChange(target)
            case .checkpoint(let target):
                self = .checkpoint(name: target.name)
            default:
                if let message = batchAction.bridgedClientMessage {
                    self = .clientMessage(message)
                } else {
                    self = .unsupported(
                        name: batchAction.description,
                        reason: "batch action has no client-message bridge"
                    )
                }
            }
        }

        var name: String {
            switch self {
            case .clientMessage(let message):
                return message.canonicalName
            case .waitForIdle:
                return "wait_for_idle"
            case .waitForElement:
                return "wait_for"
            case .waitForChange(_, let name):
                return name ?? "wait_for_change"
            case .checkpoint(let name):
                return name.map { "checkpoint:\($0)" } ?? "checkpoint"
            case .unsupported(let name, _):
                return name
            }
        }

        var fulfillsOwnExpectation: Bool {
            switch self {
            case .waitForElement, .waitForChange:
                return true
            case .clientMessage, .waitForIdle, .checkpoint, .unsupported:
                return false
            }
        }
    }

    func executeBatchExecutionPlan(_ plan: TheScore.BatchPlan) async -> ActionResult {
        await executeBatchPlan(BatchPlan(plan), runtime: .live(self))
    }

    func executeBatchExecutionPlanForTest(
        _ plan: TheScore.BatchPlan,
        runtime: BatchExecutionRuntime
    ) async -> ActionResult {
        await executeBatchPlan(BatchPlan(plan), runtime: runtime)
    }

    func executeBatchPlanForTest(
        _ plan: BatchPlan,
        runtime: BatchExecutionRuntime
    ) async -> ActionResult {
        await executeBatchPlan(plan, runtime: runtime)
    }

    private func executeBatchPlan(
        _ plan: BatchPlan,
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
        _ step: BatchStep,
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
            actionName: step.action.name,
            expectationName: step.expectation.summaryDescription,
            actionResult: actionResult,
            expectationActionResult: expectationReceipt?.actionResult,
            expectation: expectationReceipt?.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func expectationReceipt(
        for step: BatchStep,
        actionResult: ActionResult,
        runtime: BatchExecutionRuntime
    ) async -> BatchExpectationReceipt? {
        guard actionResult.success else { return nil }
        let expectation = step.expectation
        let immediateExpectation = expectation.validate(against: actionResult)
        if immediateExpectation.met {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }
        if expectation == .delivery {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }
        if step.action.fulfillsOwnExpectation {
            return BatchExpectationReceipt(
                actionResult: actionResult,
                expectation: ExpectationResult(
                    met: actionResult.success,
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

    private func execute(_ action: Action) async -> ActionResult {
        switch action {
        case .clientMessage(let message):
            return await executeCommand(message)
        case .waitForIdle(let target):
            return await executeWaitForIdle(timeout: min(target.timeout ?? 5.0, 60.0))
        case .waitForElement(let target):
            return await executeCommand(.waitFor(target))
        case .waitForChange(let target, _):
            return await executeWaitForChange(
                timeout: target.resolvedTimeout,
                expectation: target.expect
            )
        case .checkpoint(let name):
            return ActionResult(
                success: true,
                method: .waitForChange,
                message: name.map { "checkpoint:\($0)" } ?? "checkpoint"
            )
        case .unsupported(let name, let reason):
            var builder = ActionResultBuilder(
                method: .unsupportedCommand,
                screenName: screenName,
                screenId: screenId
            )
            builder.message = "Unsupported batch Action '\(name)': \(reason)"
            return builder.failure(errorKind: .unsupported)
        }
    }

    private func appendSkippedBatchSteps(
        afterFailedIndex failedIndex: Int,
        remainingSteps: ArraySlice<BatchStep>,
        into stepResults: inout [BatchExecutionStepResult]
    ) {
        for (offset, step) in remainingSteps.enumerated() {
            let index = failedIndex + 1 + offset
            let skipped = BatchExecutionSkippedStepResult(
                index: index,
                actionName: step.action.name,
                expectationName: step.expectation.summaryDescription,
                reason: "skipped: stop_on_error stopped batch after step \(failedIndex)",
                afterFailedIndex: failedIndex
            )
            stepResults.append(BatchExecutionStepResult(
                index: index,
                actionName: step.action.name,
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

private extension TheScore.Action {
    var bridgedClientMessage: ClientMessage? {
        switch self {
        case .activate(let target):
            return .activate(target.executableTarget)
        case .increment(let target):
            return .increment(target.executableTarget)
        case .decrement(let target):
            return .decrement(target.executableTarget)
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.target.executableTarget,
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.target.executableTarget,
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: target.direction,
                currentHeistId: target.currentSourceHeistId,
                currentTextRange: target.currentTextRange
            ))
        case .touchTap(let target):
            return .touchTap(TouchTapTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY
            ))
        case .touchLongPress(let target):
            return .touchLongPress(LongPressTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY,
                duration: target.duration
            ))
        case .touchSwipe(let target):
            return .touchSwipe(SwipeTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                direction: target.direction,
                duration: target.duration,
                start: target.start,
                end: target.end
            ))
        case .touchDrag(let target):
            return .touchDrag(DragTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                duration: target.duration
            ))
        case .touchPinch(let target):
            return .touchPinch(PinchTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                scale: target.scale,
                spread: target.spread,
                duration: target.duration
            ))
        case .touchRotate(let target):
            return .touchRotate(RotateTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                angle: target.angle,
                radius: target.radius,
                duration: target.duration
            ))
        case .touchTwoFingerTap(let target):
            return .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                spread: target.spread
            ))
        case .touchDrawPath(let target):
            return .touchDrawPath(target)
        case .touchDrawBezier(let target):
            return .touchDrawBezier(target)
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.target?.executableTarget
            ))
        case .editAction(let target):
            return .editAction(target)
        case .setPasteboard(let target):
            return .setPasteboard(target)
        case .scroll(let target):
            return .scroll(ScrollTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.target?.executableTarget
            ))
        case .elementSearch(let target):
            return .elementSearch(ElementSearchTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                elementTarget: target.target?.executableTarget,
                edge: target.edge
            ))
        case .waitForIdle, .waitForElement, .waitForChange, .checkpoint:
            return nil
        case .explore:
            return .explore
        case .resignFirstResponder:
            return .resignFirstResponder
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
