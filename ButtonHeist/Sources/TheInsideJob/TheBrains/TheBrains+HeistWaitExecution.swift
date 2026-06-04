#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeWaitStep(
        _ step: WaitStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        let resolvedStep: ResolvedWaitStep
        do {
            resolvedStep = try step.resolve(in: environment)
        } catch {
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .wait,
                message: "could not resolve heist wait predicate: \(error)",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true
            )
        }
        let receipt = await runtime.wait(resolvedStep, nil)
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .wait,
            actionResult: receipt.actionResult,
            expectation: receipt.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }
}

struct HeistWaitReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

#endif // DEBUG
#endif // canImport(UIKit)
