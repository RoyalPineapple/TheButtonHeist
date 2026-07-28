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
        host: HeistExecution.Host,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedWait: ResolvedWaitStep
        do {
            resolvedWait = try step.resolve(in: environment)
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

        let settlement = await host.execute(HeistExecution.Command(
            observing: step.predicate,
            resolved: resolvedWait.predicate,
            timeout: resolvedWait.timeout
        ))
        let evidence = HeistExecution.ResultProjector.projectWait(settlement)
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
                host: host,
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
            preconditionFailure("HeistExecution wait projection cannot produce \(evidence.outcome)")
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

#endif // DEBUG
#endif // canImport(UIKit)
