#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeActionStep(
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

        let waitReceipt = await runtime.wait(expectation, actionResult.accessibilityTrace)
        return HeistExpectationReceipt(
            actionResult: waitReceipt.actionResult,
            expectation: waitReceipt.expectation
        )
    }
}

private struct HeistExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

#endif // DEBUG
#endif // canImport(UIKit)
