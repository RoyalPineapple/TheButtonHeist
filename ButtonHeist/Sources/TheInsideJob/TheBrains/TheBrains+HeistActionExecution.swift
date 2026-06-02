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

        if let immediateReceipt = immediateExpectationReceipt(for: expectation, actionResult: actionResult) {
            return immediateReceipt
        }

        let waitReceipt = await runtime.wait(expectation)
        return HeistExpectationReceipt(
            actionResult: waitReceipt.actionResult,
            expectation: waitReceipt.expectation
        )
    }

    private func immediateExpectationReceipt(
        for expectation: WaitStep,
        actionResult: ActionResult
    ) -> HeistExpectationReceipt? {
        guard expectation.timeout == 0,
              let trace = actionResult.accessibilityTrace
        else { return nil }

        let evaluation = expectation.predicate.validate(against: actionResult)
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = trace
        builder.message = evaluation.met
            ? "predicate met after 0.0s"
            : [
                "timed out after 0.0s waiting for heist predicate",
                "expected: \(expectation.predicate.description)",
                "last result: \(evaluation.actual ?? "not met")",
                "last observed: action result trace",
            ].joined(separator: "; ")

        return HeistExpectationReceipt(
            actionResult: evaluation.met
                ? builder.success()
                : builder.failure(errorKind: .timeout),
            expectation: evaluation
        )
    }
}

private struct HeistExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

#endif // DEBUG
#endif // canImport(UIKit)
