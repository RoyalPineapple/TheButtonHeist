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

        guard let observation = await runtime.observeSemanticState(resolvedCases.observationScope, nil, nil) else {
            return caseObservationFailure(index: index, path: path, kind: .conditional, start: start)
        }

        let evaluated = PredicateCaseSelection.evaluate(resolvedCases, observation: observation)
        // `if` is the immediate (timeout 0) selection; `wait_for` is the waited
        // one. Both produce a `HeistCaseSelectionResult` and then run the chosen
        // body through the one shared dispatcher below.
        let selection = HeistCaseSelectionResult(
            cases: evaluated.cases,
            selectedCaseIndex: evaluated.selectedCaseIndex,
            elapsedMs: elapsedMilliseconds(since: start),
            lastObservedSummary: observation.summary
        )
        return await dispatchPredicateCases(
            PredicateCaseDispatch(
                selection: selection,
                cases: resolvedCases,
                elseBody: step.elseBody,
                index: index,
                path: path,
                kind: .conditional,
                pathSegment: "conditional",
                start: start,
                elseMessage: "no case matched; else ran",
                noMatchMessage: "no case matched"
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
                index: index,
                path: path,
                kind: .waitForCases,
                pathSegment: "wait_for_cases",
                start: start,
                elseMessage: "timed out after \(heistTimeoutDescription(step.timeout))s; else ran",
                noMatchMessage: waitForCasesTimeoutMessage(step: step, lastObservedSummary: selection.lastObservedSummary)
            ),
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }

    /// Run a resolved case selection: matched case body, else body, or a
    /// terminal no-match node. Shared by `if` and `wait_for` — they differ only
    /// in how the `selection` was produced (immediate vs waited) and in the
    /// node `kind`/messages; the failure of an unmatched `wait_for` rides on the
    /// selection's `timedOut`, so no policy flag is needed here.
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
            return HeistExecutionStepResult(
                index: dispatch.index,
                path: dispatch.path,
                kind: dispatch.kind,
                message: "matched case \(selectedCaseIndex)",
                durationMs: elapsedMilliseconds(since: dispatch.start),
                caseSelection: dispatch.selection,
                children: children
            )
        }

        if let elseBody = dispatch.elseBody {
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(dispatch.path).\(dispatch.pathSegment).else_body"
            )
            return HeistExecutionStepResult(
                index: dispatch.index,
                path: dispatch.path,
                kind: dispatch.kind,
                message: dispatch.elseMessage,
                durationMs: elapsedMilliseconds(since: dispatch.start),
                caseSelection: dispatch.selection.markingElseRan(),
                children: children
            )
        }

        return HeistExecutionStepResult(
            index: dispatch.index,
            path: dispatch.path,
            kind: dispatch.kind,
            message: dispatch.noMatchMessage,
            durationMs: elapsedMilliseconds(since: dispatch.start),
            caseSelection: dispatch.selection
        )
    }

    private func caseObservationFailure(
        index: Int,
        path: String,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: kind,
            message: "Could not observe settled accessibility state before evaluating heist cases",
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: true
        )
    }

    private func caseResolutionFailure(
        index: Int,
        path: String,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: kind,
            message: "Could not resolve heist case predicate: \(error)",
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: true
        )
    }

    private func waitForCasesTimeoutMessage(
        step: WaitForCasesStep,
        lastObservedSummary: String?
    ) -> String {
        [
            "timed out after \(heistTimeoutDescription(step.timeout))s waiting for heist case",
            "cases: \(step.cases.map(\.predicate.description).joined(separator: "; "))",
            "last observed: \(lastObservedSummary ?? "no settled accessibility state")",
            "Next: add Else, widen predicate, or increase timeout.",
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

/// The resolved inputs for running a predicate-case selection — the matched
/// selection plus the cases/else body and the node identity/labels. Bundled so
/// `if` and `wait_for` share one dispatcher without parameter sprawl.
private struct PredicateCaseDispatch {
    let selection: HeistCaseSelectionResult
    let cases: [ResolvedPredicateCase]
    let elseBody: [HeistStep]?
    let index: Int
    let path: String
    let kind: HeistExecutionStepKind
    let pathSegment: String
    let start: CFAbsoluteTime
    let elseMessage: String
    let noMatchMessage: String
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
