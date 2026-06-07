#if canImport(UIKit)
#if DEBUG
import Foundation

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
        let resolvedCases: [ResolvedPredicateCase]
        do {
            resolvedCases = try step.cases.map { try $0.resolve(in: environment) }
        } catch {
            return caseResolutionFailure(index: index, path: path, kind: .conditional, start: start, error: error)
        }

        let selection = await runtime.waitForCases(resolvedCases, 0)
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

    func executeWaitForCasesStep(
        _ step: WaitForCasesStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedCases: [ResolvedPredicateCase]
        do {
            resolvedCases = try step.cases.map { try $0.resolve(in: environment) }
        } catch {
            return caseResolutionFailure(index: index, path: path, kind: .waitForCases, start: start, error: error)
        }

        let selection = await runtime.waitForCases(resolvedCases, step.timeout)
        return await dispatchPredicateCases(
            PredicateCaseDispatch(
                selection: selection,
                cases: resolvedCases,
                elseBody: step.elseBody,
                path: path,
                kind: .waitForCases,
                intent: .waitForCases(timeout: step.timeout),
                pathSegment: "wait_for_cases",
                start: start
            ),
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }

    /// Run a resolved case selection: matched case body, else body, or a
    /// terminal no-match node. Shared by `if` and `wait_for`.
    private func dispatchPredicateCases(
        _ dispatch: PredicateCaseDispatch,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        if let selectedCaseIndex = dispatch.selection.selectedCaseIndex {
            let children = await executeHeistSteps(
                dispatch.cases[selectedCaseIndex].body,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(dispatch.path).\(dispatch.pathSegment).cases[\(selectedCaseIndex)].body"
            )
            return caseNode(dispatch, selection: dispatch.selection, children: children)
        }

        if let elseBody = dispatch.elseBody {
            let selection = dispatch.selection.markingElseRan()
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(dispatch.path).\(dispatch.pathSegment).else_body"
            )
            return caseNode(dispatch, selection: selection, children: children)
        }

        let failure: HeistFailureDetail?
        if dispatch.kind == .waitForCases, dispatch.selection.timedOut {
            failure = HeistFailureDetail(
                category: .wait,
                contract: "wait_for_cases selects a case before timeout or runs else",
                observed: waitForCasesTimeoutObserved(selection: dispatch.selection),
                expected: dispatch.selection.cases.map(\.predicate.description).joined(separator: "; ")
            )
        } else {
            failure = nil
        }
        return HeistExecutionStepResult(
            path: dispatch.path,
            kind: dispatch.kind,
            status: failure == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: dispatch.start),
            intent: dispatch.intent,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: dispatch.selection)),
            failure: failure
        )
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
                childFailureDetail(category: dispatch.kind == .waitForCases ? .wait : .invocation, childPath: $0)
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
            intent: kind == .waitForCases ? .waitForCases(timeout: 0) : .conditional,
            failure: HeistFailureDetail(
                category: .validation,
                contract: "case predicates resolve before evaluation",
                observed: "could not resolve heist case predicate: \(error)"
            )
        )
    }

    private func waitForCasesTimeoutObserved(selection: HeistCaseSelectionResult) -> String {
        [
            selection.timeout.map { "timed out after \(heistTimeoutDescription($0))s" }
                ?? "timed out",
            "last observed: \(selection.lastObservedSummary ?? "no settled accessibility state")",
        ].joined(separator: "; ")
    }

    private func heistTimeoutDescription(_ timeout: Double) -> String {
        guard timeout.isFinite else { return "\(timeout)" }
        let rounded = timeout.rounded()
        if abs(timeout - rounded) < 0.000_001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.3f", timeout)
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
    func markingElseRan() -> HeistCaseSelectionResult {
        HeistCaseSelectionResult(
            cases: cases,
            selectedCaseIndex: selectedCaseIndex,
            elapsedMs: elapsedMs,
            timeout: timeout,
            timedOut: timedOut,
            elseRan: true,
            lastObservedSummary: lastObservedSummary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
