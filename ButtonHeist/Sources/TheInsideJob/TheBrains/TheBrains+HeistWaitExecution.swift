#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeWaitStep(
        _ step: WaitStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let receipt = await waitReceipt(for: step, runtime: runtime)
        return HeistExecutionStepResult(
            index: index,
            kind: .wait,
            actionResult: receipt.actionResult,
            expectation: receipt.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    func waitReceipt(
        for step: WaitStep,
        runtime: HeistExecutionRuntime
    ) async -> HeistWaitReceipt {
        let waitResult = await runtime.wait(step)
        let expectation = heistWaitExpectation(for: step, result: waitResult)
        return HeistWaitReceipt(actionResult: waitResult, expectation: expectation)
    }

    private func heistWaitExpectation(
        for step: WaitStep,
        result: ActionResult
    ) -> ExpectationResult {
        guard result.success else {
            return ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: result.message ?? "failed"
            )
        }
        return step.predicate.validate(against: result)
    }
}

struct HeistWaitReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

#endif // DEBUG
#endif // canImport(UIKit)
