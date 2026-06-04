#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeActionStep(
        _ step: ActionStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        let command: ClientMessage
        do {
            command = try step.command.resolve(in: environment)
        } catch {
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .action,
                actionCommand: step.command,
                message: "could not resolve heist action command: \(error)",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true
            )
        }

        let actionResult = await runtime.execute(command)
        let expectationReceipt = await expectationReceipt(
            for: step,
            actionResult: actionResult,
            runtime: runtime,
            environment: environment
        )

        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .action,
            actionCommand: step.command,
            actionResult: actionResult,
            expectationActionResult: expectationReceipt?.actionResult,
            expectation: expectationReceipt?.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func expectationReceipt(
        for step: ActionStep,
        actionResult: ActionResult,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExpectationReceipt? {
        guard actionResult.success else { return nil }
        guard let expectation = step.expectation else { return nil }
        let resolvedExpectation: ResolvedWaitStep
        do {
            resolvedExpectation = try expectation.resolve(in: environment)
        } catch {
            let failed = ActionResultBuilder(method: .wait)
                .failure(errorKind: .actionFailed)
            return HeistExpectationReceipt(
                actionResult: failed,
                expectation: ExpectationResult(
                    met: false,
                    predicate: nil,
                    actual: "could not resolve heist expectation: \(error)"
                )
            )
        }

        let waitReceipt = await runtime.wait(resolvedExpectation, actionResult.accessibilityTrace)
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
