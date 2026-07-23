#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeConditionalStep(
        _ step: ConditionalStep,
        index: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedCases: [ResolvedPredicateCaseRuntimeInput]
        do {
            resolvedCases = try step.cases.map {
                try ResolvedPredicateCaseRuntimeInput(resolving: $0, in: environment)
            }
        } catch {
            return caseResolutionFailure(index: index, path: path, start: start, error: error)
        }

        let event = await runtime.settledEvent(
            resolvedCases.observationScope,
            nil,
            0
        )
        let selection = evaluatePredicateCases(resolvedCases, in: event)
        return await dispatchPredicateCases(
            PredicateCaseDispatch(
                selection: selection,
                cases: resolvedCases,
                elseBody: step.elseBody,
                path: path,
                start: start
            ),
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }

    /// Run a resolved case selection: matched case body, else body, or a
    /// terminal no-match node.
    private func dispatchPredicateCases(
        _ dispatch: PredicateCaseDispatch,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        switch dispatch.selection.outcome {
        case .matchedCase(let selectedCaseOrdinal):
            let selectedCaseIndex = Int(selectedCaseOrdinal)
            let children = await executeHeistSteps(
                dispatch.cases[selectedCaseIndex].body,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: dispatch.path.conditionalCaseBody(at: selectedCaseIndex)
            )
            return caseNode(dispatch, selection: dispatch.selection, children: children)

        case .elseBranch, .timedOut, .noMatch:
            guard let elseBody = dispatch.elseBody else {
                return .conditional(
                    path: dispatch.path,
                    durationMs: elapsedMilliseconds(since: dispatch.start),
                    completion: .passed(
                        evidence: HeistCaseSelectionEvidence(selection: dispatch.selection)
                    )
                )
            }

            let selection = dispatch.selection.selectingElseBranch()
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: dispatch.path.conditionalElseBody()
            )
            return caseNode(dispatch, selection: selection, children: children)
        }
    }

    private func caseNode(
        _ dispatch: PredicateCaseDispatch,
        selection: HeistCaseSelectionResult,
        children: HeistExecutedChildren
    ) -> HeistExecutionStepResult {
        let evidence = HeistCaseSelectionEvidence(selection: selection)
        switch children {
        case .passed(let children):
            return .conditional(
                path: dispatch.path,
                durationMs: elapsedMilliseconds(since: dispatch.start),
                completion: .passed(evidence: evidence, children: children)
            )
        case .aborted(let children):
            return .conditional(
                path: dispatch.path,
                durationMs: elapsedMilliseconds(since: dispatch.start),
                completion: .childAborted(
                    evidence: evidence,
                    failure: childFailureDetail(
                        category: .invocation,
                        childPath: children.abortedAtPath
                    ),
                    children: children
                )
            )
        }
    }

    private func caseResolutionFailure(
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        error: Error
    ) -> HeistExecutionStepResult {
        .conditional(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .validation,
                contract: "case predicates resolve before evaluation",
                observed: "could not resolve heist case predicate: \(error)"
            ))
        )
    }

}

extension Array where Element == ResolvedPredicateCaseRuntimeInput {
    var observationScope: SemanticObservationScope {
        map(\.predicate.observationScope).max() ?? .visible
    }
}

private struct PredicateCaseDispatch {
    let selection: HeistCaseSelectionResult
    let cases: [ResolvedPredicateCaseRuntimeInput]
    let elseBody: [HeistStep]?
    let path: HeistExecutionPath
    let start: RuntimeElapsed.Instant
}

#endif // DEBUG
#endif // canImport(UIKit)
