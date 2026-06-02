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

        let waitResult = await runtime.wait(expectation)
        guard waitResult.success else {
            return HeistExpectationReceipt(
                actionResult: waitResult,
                expectation: ExpectationResult(
                    met: false,
                    predicate: expectation.predicate,
                    actual: waitResult.message ?? "failed"
                )
            )
        }
        return HeistExpectationReceipt(
            actionResult: waitResult,
            expectation: expectation.predicate.validate(against: waitResult)
        )
    }
}

private struct HeistExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

#endif // DEBUG
#endif // canImport(UIKit)
