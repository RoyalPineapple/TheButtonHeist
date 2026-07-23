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

    /// Executes one public standalone wait through observation-only settlement.
    func executeStandaloneWait(
        _ step: ResolvedWaitRuntimeInput,
        startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
    ) async -> HeistWaitResult {
        await executeSettlementWait(step, startedAt: startedAt)
    }

    /// Executes a wait through the canonical settlement state machine.
    func executeSettlementWait(
        _ step: ResolvedWaitRuntimeInput,
        startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now,
        baseline: Settlement.Baseline = .capture
    ) async -> HeistWaitResult {
        let command = Settlement.Command(
            trigger: .observation,
            predicate: Settlement.Predicate(
                authored: step.predicateExpression,
                resolved: step.predicate
            ),
            deadline: Settlement.Deadline(
                instant: startedAt.advanced(by: .seconds(step.timeout.seconds))
            ),
            baseline: baseline
        )
        let discoveryDeadline = SemanticObservationDeadline(
            start: startedAt,
            timeoutSeconds: step.timeout.seconds
        )
        let settlement = await executeSettlement(
            command,
            observationEffects: { control in
                if case .announcement = step.predicate.core { return }
                await self.interactionCoordinator.publishStandaloneWaitDiscovery(
                    target: step.predicate.waitTarget,
                    deadline: discoveryDeadline,
                    control: control
                )
            },
            dispatch: { _ in
                preconditionFailure("Observation settlement cannot dispatch an action")
            }
        )
        let evidence = Settlement.ResultProjector.projectWait(settlement)
        return HeistWaitResult.projected(
            evidence,
            observationMoment: settlement.evidence.handoff.event?.moment
        )
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
    let observationMoment: Observation.Moment?
    let observationSummary: String?

    var observedSequence: SettledObservationSequence? {
        observationMoment?.sequence
    }

    private init(
        outcome: Outcome,
        observationMoment: Observation.Moment?,
        observationSummary: String?
    ) {
        self.outcome = outcome
        self.observationMoment = observationMoment
        self.observationSummary = observationSummary
    }

    static func matched(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Met,
        observationMoment: Observation.Moment? = nil,
        observationSummary: String? = nil,
        announcement: ActionAnnouncementText? = nil
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
            observationMoment: observationMoment,
            observationSummary: observationSummary
        )
    }

    static func timedOut(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        observationMoment: Observation.Moment? = nil,
        observationSummary: String? = nil
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
            observationMoment: observationMoment,
            observationSummary: observationSummary
        )
    }

    static func failed(
        failureKind: ActionFailure.Kind,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        announcement: ActionAnnouncementText? = nil
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
            observationMoment: nil,
            observationSummary: nil
        )
    }

    static func projected(
        _ evidence: HeistWaitEvidence,
        observationMoment: Observation.Moment?
    ) -> HeistWaitResult {
        let outcome: Outcome = switch evidence.expectation {
        case .met(let expectation):
            .matched(evidence.actionResult, expectation)
        case .unmet(let expectation):
            .unmatched(evidence.actionResult, expectation)
        }
        return HeistWaitResult(
            outcome: outcome,
            observationMoment: observationMoment,
            observationSummary: evidence.finalSummary
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
