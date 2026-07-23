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

        let settlement = await runtime.settle(Settlement.Command(
            observing: resolvedWait,
            baseline: .capture,
            startedAt: start
        ))
        let evidence = Settlement.ResultProjector.projectWait(settlement)
        switch evidence.outcome {
        case .matched:
            return waitStepResult(
                step: step,
                completion: .passed(evidence: .init(admitted: evidence)),
                path: path,
                start: start
            )

        case .failed:
            guard let elseBody = step.elseBody else {
                return waitStepResult(
                    step: step,
                    completion: .failed(
                        evidence: .observed(.init(admitted: evidence)),
                        failure: standaloneWaitFailureDetail(wait: step, evidence: evidence)
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
            let handledElse = HeistSettlementEvidence.handledElse(
                .init(executed: evidence.actionResult, expectation: evidence.expectation),
                baselineSummary: evidence.baselineSummary,
                finalSummary: evidence.finalSummary
            )
            let completion: HeistWaitCompletion
            switch children {
            case .passed(let children):
                completion = .passed(evidence: .init(admitted: handledElse), children: children)
            case .aborted(let children):
                completion = .childAborted(
                    evidence: .init(admitted: handledElse),
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
        case .handledElse, .continued:
            preconditionFailure("Settlement wait projection cannot produce \(evidence.outcome)")
        }
    }

    /// Executes a wait through the canonical settlement state machine.
    func executeSettlementWait(
        _ command: Settlement.Command
    ) async -> Settlement.Result {
        guard case .observation(let predicate, let deadline, _) = command else {
            preconditionFailure("Observation wait requires an observation settlement command")
        }
        let start = RuntimeElapsed.now
        let discoveryDeadline = SemanticObservationDeadline(
            start: start,
            timeoutSeconds: deadline.remainingDuration(at: start) / .seconds(1)
        )
        return await executeSettlement(
            command,
            observationEffects: { control in
                if case .announcement = predicate.resolved.core { return }
                await self.navigation.exploreForWait(
                    target: predicate.resolved.singularTarget,
                    deadline: discoveryDeadline,
                    stopWhen: { control.stopRequested }
                )
            },
            dispatch: { _ in
                preconditionFailure("Observation settlement cannot dispatch an action")
            }
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

#endif // DEBUG
#endif // canImport(UIKit)
