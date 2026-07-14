#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeConditionalStep(
        _ step: ConditionalStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
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
            return caseResolutionFailure(index: index, path: path, kind: .conditional, start: start, error: error)
        }

        let selection = await runtime.selectPredicateCase(resolvedCases, 0)
        return await dispatchPredicateCases(
            PredicateCaseDispatch(
                selection: selection,
                cases: resolvedCases,
                elseBody: step.elseBody ?? [],
                path: path,
                kind: .conditional,
                intent: .conditional,
                pathSegment: "conditional",
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
        case .matchedCase(let selectedCaseIndex):
            let children = await executeHeistSteps(
                dispatch.cases[selectedCaseIndex].body,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(dispatch.path).\(dispatch.pathSegment).cases[\(selectedCaseIndex)].body"
            )
            return caseNode(dispatch, selection: dispatch.selection, children: children)

        case .elseBranch, .timedOut, .noMatch:
            guard let elseBody = dispatch.elseBody else {
                return heistReceipt(.init(
                    path: dispatch.path,
                    kind: dispatch.kind,
                    durationMs: elapsedMilliseconds(since: dispatch.start),
                    intent: dispatch.intent,
                    evidence: .caseSelection(HeistCaseSelectionEvidence(selection: dispatch.selection)),
                    childFailure: { childPath in
                        self.childFailureDetail(category: .invocation, childPath: childPath)
                    }
                ))
            }

            let selection = dispatch.selection.selectingElseBranch()
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(dispatch.path).\(dispatch.pathSegment).else_body"
            )
            return caseNode(dispatch, selection: selection, children: children)
        }
    }

    private func caseNode(
        _ dispatch: PredicateCaseDispatch,
        selection: HeistCaseSelectionResult,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        heistReceipt(.init(
            path: dispatch.path,
            kind: dispatch.kind,
            durationMs: elapsedMilliseconds(since: dispatch.start),
            intent: dispatch.intent,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: selection)),
            children: children,
            childFailure: { childPath in
                self.childFailureDetail(category: .invocation, childPath: childPath)
            }
        ))
    }

    private func caseResolutionFailure(
        index _: Int,
        path: String,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        heistReceipt(.init(
            path: path,
            kind: kind,
            durationMs: elapsedMilliseconds(since: start),
            intent: .conditional,
            completion: .failed(HeistFailureDetail(
                category: .validation,
                contract: "case predicates resolve before evaluation",
                observed: "could not resolve heist case predicate: \(error)"
            ))
        ))
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
    let path: String
    let kind: HeistExecutionStepKind
    let intent: HeistStepIntent
    let pathSegment: String
    let start: CFAbsoluteTime
}

private extension HeistCaseSelectionResult {
    func selectingElseBranch() -> HeistCaseSelectionResult {
        HeistCaseSelectionResult(
            cases: cases,
            outcome: .elseBranch(reason: elseBranchReason),
            elapsedMs: elapsedMs,
            timeout: timeout,
            lastObservedSummary: lastObservedSummary
        )
    }

    var elseBranchReason: HeistCaseSelectionMissReason {
        switch outcome {
        case .timedOut, .elseBranch(reason: .timedOut):
            return .timedOut
        case .matchedCase, .elseBranch(reason: .noMatch), .noMatch:
            return .noMatch
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
