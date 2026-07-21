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
        start: RuntimeElapsed.Instant,
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

        let result = await runtime.wait(.standalone(resolvedWait, startedAt: start))
        switch result.outcome {
        case .matched(let actionResult, let expectation):
            let evidence = HeistWaitEvidence.matched(
                .init(executed: actionResult, expectation: expectation),
                finalSummary: expectation.actual
            )
            return waitStepResult(
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
                return waitStepResult(
                    step: step,
                    completion: .failed(
                        evidence: .observed(.init(admitted: evidence)),
                        failure: standaloneWaitFailureDetail(wait: step, result: result)
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
            return waitStepResult(
                step: step,
                completion: completion,
                path: path,
                start: start
            )
        }
    }

    private func waitStepResult(
        step: WaitStep,
        completion: HeistWaitCompletion,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
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

struct HeistWaitResult {
    enum Outcome {
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

    let outcome: Outcome
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?
    let historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence?

    private init(
        outcome: Outcome,
        observedSequence: SettledObservationSequence?,
        observationSummary: String?,
        historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence?
    ) {
        self.outcome = outcome
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
        self.historicalWaitDiagnostics = historicalWaitDiagnostics
    }

    static func matched(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Met,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        announcement: ActionAnnouncementText? = nil,
        historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence? = nil
    ) -> HeistWaitResult {
        HeistWaitResult(
            outcome: .matched(
                makeActionResult(
                    failureKind: nil,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: announcement
                ),
                expectation
            ),
            observedSequence: observedSequence,
            observationSummary: observationSummary,
            historicalWaitDiagnostics: historicalWaitDiagnostics
        )
    }

    static func timedOut(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence? = nil
    ) -> HeistWaitResult {
        HeistWaitResult(
            outcome: .unmatched(
                makeActionResult(
                    failureKind: .timeout,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: nil
                ),
                expectation
            ),
            observedSequence: observedSequence,
            observationSummary: observationSummary,
            historicalWaitDiagnostics: historicalWaitDiagnostics
        )
    }

    static func failed(
        failureKind: ActionFailure.Kind,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        announcement: ActionAnnouncementText? = nil,
        historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence? = nil
    ) -> HeistWaitResult {
        HeistWaitResult(
            outcome: .unmatched(
                makeActionResult(
                    failureKind: failureKind,
                    message: message,
                    traceEvidence: traceEvidence,
                    announcement: announcement
                ),
                expectation
            ),
            observedSequence: nil,
            observationSummary: nil,
            historicalWaitDiagnostics: historicalWaitDiagnostics
        )
    }

    private static func makeActionResult(
        failureKind: ActionFailure.Kind?,
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
        if let failureKind {
            return ActionResult.failure(
                payload: .wait,
                failureKind: failureKind,
                message: message,
                observation: observation
            )
        }
        return ActionResult.success(
            payload: .wait,
            message: message,
            observation: observation
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
