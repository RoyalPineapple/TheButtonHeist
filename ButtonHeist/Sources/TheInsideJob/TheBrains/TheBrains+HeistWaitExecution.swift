#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension TheBrains {
    internal struct HeistStandaloneWaitResolutionFailure {
        let wait: WaitStep
        let errorDescription: String
    }

    func executeWaitStep(
        _ step: WaitStep,
        index _: Int,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedWait: ResolvedWaitRuntimeInput
        do {
            resolvedWait = try ResolvedWaitRuntimeInput(resolving: step, in: environment)
        } catch {
            return standaloneWaitResolutionFailureResult(
                HeistStandaloneWaitResolutionFailure(
                    wait: step,
                    errorDescription: String(describing: error)
                ),
                path: path,
                start: start
            )
        }

        let receipt = await runtime.wait(.standalone(resolvedWait, startedAt: start))
        switch receipt.result {
        case .matched(let actionResult, let expectation):
            let evidence = HeistWaitEvidence.matched(
                .init(executed: actionResult, expectation: expectation),
                finalSummary: expectation.actual
            )
            return waitReceipt(
                step: step,
                completion: .passed(evidence: .init(admitted: evidence)),
                path: path,
                start: start
            )

        case .unmatched(let actionResult, let expectation):
            guard let elseBody = step.elseBody else {
                let evidence = HeistWaitEvidence.failed(
                    .init(executed: actionResult, expectation: expectation.result),
                    finalSummary: expectation.actual
                )
                return waitReceipt(
                    step: step,
                    completion: .failed(
                        evidence: .observed(.init(admitted: evidence)),
                        failure: standaloneWaitFailureDetail(wait: step, receipt: receipt)
                    ),
                    path: path,
                    start: start
                )
            }

            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: path.waitElseBody()
            )
            let evidence = HeistPassedWaitEvidence(admitted: .handledElse(
                .init(executed: actionResult, expectation: expectation.result),
                finalSummary: expectation.actual
            ))
            let completion: HeistWaitCompletion
            switch children {
            case .passed(let children):
                completion = .passed(evidence: evidence, children: children)
            case .aborted(let children):
                completion = .childAborted(
                    evidence: evidence,
                    failure: childFailureDetail(category: .wait, childPath: children.abortedAtPath),
                    children: children
                )
            }
            return waitReceipt(
                step: step,
                completion: completion,
                path: path,
                start: start
            )
        }
    }

    private func waitReceipt(
        step: WaitStep,
        completion: HeistWaitCompletion,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        return .wait(
            path: path,
            durationMs: durationMs,
            predicate: step.predicate,
            timeout: step.timeout,
            completion: completion
        )
    }
}

struct HeistWaitReceipt {
    enum Result {
        case matched(ActionResult, ExpectationResult.Met)
        case unmatched(ActionResult, ExpectationResult.Unmet)

        var actionResult: ActionResult {
            switch self {
            case .matched(let actionResult, _), .unmatched(let actionResult, _):
                return actionResult
            }
        }

        var expectation: ExpectationResult {
            switch self {
            case .matched(_, let expectation):
                return expectation.result
            case .unmatched(_, let expectation):
                return expectation.result
            }
        }
    }

    let result: Result
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?

    private init(
        result: Result,
        observedSequence: SettledObservationSequence?,
        observationSummary: String?
    ) {
        self.result = result
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
    }

    static func matched(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Met,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        announcement: ActionAnnouncementText? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            result: .matched(
                makeActionResult(
                    errorKind: nil,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: announcement
                ),
                expectation
            ),
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    static func timedOut(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            result: .unmatched(
                makeActionResult(
                    errorKind: .timeout,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: nil
                ),
                expectation
            ),
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    static func failed(
        errorKind: ErrorKind,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        announcement: ActionAnnouncementText? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            result: .unmatched(
                makeActionResult(
                    errorKind: errorKind,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: announcement
                ),
                expectation
            ),
            observedSequence: nil,
            observationSummary: nil
        )
    }

    private static func makeActionResult(
        errorKind: ErrorKind?,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        announcement: ActionAnnouncementText?
    ) -> ActionResult {
        let observation: ActionResultObservationEvidence
        switch (traceEvidence, announcement) {
        case (nil, nil):
            observation = .none
        case (nil, let announcement?):
            observation = .announcement(announcement)
        case (let evidence?, _):
            observation = .trace(evidence)
        }
        if let errorKind {
            return ActionResult.failure(
                method: .wait,
                errorKind: errorKind,
                message: message,
                observation: observation
            )
        }
        return ActionResult.success(
            method: .wait,
            message: message,
            observation: observation
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
