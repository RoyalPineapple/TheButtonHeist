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
        runtime: any HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedCases: [ResolvedPredicateCase]
        do {
            resolvedCases = try step.cases.map { try $0.resolve(in: environment) }
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
        runtime: any HeistExecutionRuntime,
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
                return HeistExecutionStepResult(
                    path: dispatch.path,
                    kind: dispatch.kind,
                    status: .passed,
                    durationMs: elapsedMilliseconds(since: dispatch.start),
                    intent: dispatch.intent,
                    evidence: .caseSelection(HeistCaseSelectionEvidence(selection: dispatch.selection)),
                    failure: nil
                )
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
        let abortedAtChildPath = children.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: dispatch.path,
            kind: dispatch.kind,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: dispatch.start),
            intent: dispatch.intent,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: selection)),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .invocation, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func caseResolutionFailure(
        index _: Int,
        path: String,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: kind,
            status: .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .conditional,
            failure: HeistFailureDetail(
                category: .validation,
                contract: "case predicates resolve before evaluation",
                observed: "could not resolve heist case predicate: \(error)"
            )
        )
    }

}

extension Array where Element == ResolvedPredicateCase {
    var observationScope: SemanticObservationScope {
        map(\.predicate.observationScope).max() ?? .visible
    }
}

private struct PredicateCaseDispatch {
    let selection: HeistCaseSelectionResult
    let cases: [ResolvedPredicateCase]
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
