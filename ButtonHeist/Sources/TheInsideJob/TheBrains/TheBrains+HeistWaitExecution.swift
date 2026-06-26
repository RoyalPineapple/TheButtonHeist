#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeWaitStep(
        _ step: WaitStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        // A wait is a step with no command: just the predicate wait.
        await executeStep(
            command: nil,
            wait: step,
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }
}

struct HeistWaitReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
    let observedSequence: UInt64?
    let observationSummary: String?

    init(
        actionResult: ActionResult,
        expectation: ExpectationResult,
        observedSequence: UInt64? = nil,
        observationSummary: String? = nil
    ) {
        self.actionResult = actionResult
        self.expectation = expectation
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
