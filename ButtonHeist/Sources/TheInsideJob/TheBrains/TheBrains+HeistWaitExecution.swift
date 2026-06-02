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
        let receipt = await runtime.wait(step)
        return HeistExecutionStepResult(
            index: index,
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
