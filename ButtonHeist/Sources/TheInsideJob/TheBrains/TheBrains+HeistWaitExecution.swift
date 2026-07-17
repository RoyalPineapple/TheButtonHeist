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

        let receipt = await runtime.wait(.standalone(resolvedWait))
        switch receipt.result {
        case .matched(let actionResult, let expectation):
            let completion = HeistWaitEvidence.MatchedCheck(
                actionResult: actionResult,
                expectation: expectation
            ).flatMap {
                HeistPassedWaitEvidence(.matched($0, finalSummary: expectation.actual))
            }.map {
                HeistWaitCompletion.passed(evidence: $0)
            }
            return waitReceipt(
                step: step,
                completion: completion,
                path: path,
                start: start
            )

        case .unmatched(let actionResult, let expectation):
            guard let elseBody = step.elseBody else {
                let completion = HeistWaitEvidence.UnmatchedCheck(
                    actionResult: actionResult,
                    expectation: expectation.result
                ).flatMap {
                    HeistFailedWaitEvidence(.failed($0, finalSummary: expectation.actual))
                }.map {
                    HeistWaitCompletion.failed(
                        evidence: .observed($0),
                        failure: standaloneWaitFailureDetail(wait: step, receipt: receipt)
                    )
                }
                return waitReceipt(
                    step: step,
                    completion: completion,
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
            let evidence = HeistWaitEvidence.UnmatchedCheck(
                actionResult: actionResult,
                expectation: expectation.result
            ).flatMap {
                HeistPassedWaitEvidence(.handledElse($0, finalSummary: expectation.actual))
            }
            let completion: HeistWaitCompletion?
            switch HeistExecutedChildren(children) {
            case .passed(let children):
                completion = evidence.map {
                    .passed(evidence: $0, children: children)
                }
            case .aborted(let children):
                completion = evidence.map {
                    .childAborted(
                        evidence: $0,
                        failure: childFailureDetail(category: .wait, childPath: children.abortedAtPath),
                        children: children
                    )
                }
            }
            return waitReceipt(
                step: step,
                completion: completion,
                path: path,
                start: start,
                children: children
            )
        }
    }

    private func waitReceipt(
        step: WaitStep,
        completion: HeistWaitCompletion?,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let construction = completion.map {
            HeistExecutionStepResult.construct(
                path: path,
                durationMs: durationMs,
                node: .wait(predicate: step.predicate, timeout: step.timeout, completion: $0)
            )
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs,
            children: children
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
        announcement: String? = nil
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
        announcement: String? = nil
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
        announcement: String?
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
                evidence: ActionResultFailureEvidence(observation: observation)
            )
        }
        return ActionResult.success(
            method: .wait,
            message: message,
            evidence: ActionResultSuccessEvidence(observation: observation)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
