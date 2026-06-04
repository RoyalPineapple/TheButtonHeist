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

        let selection = PredicateCaseSelection.evaluate(resolvedCases, observation: observation)
        if let selectedCaseIndex = selection.selectedCaseIndex {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let children = await executeHeistSteps(
                resolvedCases[selectedCaseIndex].body,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(path).conditional.cases[\(selectedCaseIndex)].body"
            )
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .conditional,
                message: "matched case \(selectedCaseIndex)",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: selectedCaseIndex,
                    elapsedMs: selectionElapsedMs,
                    lastObservedSummary: observation.summary
                ),
                children: children
            )
        }

        if let elseBody = step.elseBody {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(path).conditional.else_body"
            )
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .conditional,
                message: "no case matched; else ran",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: nil,
                    elapsedMs: selectionElapsedMs,
                    elseRan: true,
                    lastObservedSummary: observation.summary
                ),
                children: children
            )
        }

        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .conditional,
            message: "no case matched",
            durationMs: elapsedMilliseconds(since: start),
            caseSelection: HeistCaseSelectionResult(
                cases: selection.cases,
                selectedCaseIndex: nil,
                elapsedMs: elapsedMilliseconds(since: start),
                lastObservedSummary: observation.summary
            )
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
        if let selectedCaseIndex = selection.selectedCaseIndex {
            let children = await executeHeistSteps(
                resolvedCases[selectedCaseIndex].body,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(path).wait_for_cases.cases[\(selectedCaseIndex)].body"
            )
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .waitForCases,
                message: "matched case \(selectedCaseIndex)",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: selection,
                children: children
            )
        }

        if let elseBody = step.elseBody {
            let children = await executeHeistSteps(
                elseBody,
                runtime: runtime,
                environment: environment,
                scope: scope,
                path: "\(path).wait_for_cases.else_body"
            )
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .waitForCases,
                message: "timed out after \(heistTimeoutDescription(step.timeout))s; else ran",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: nil,
                    elapsedMs: selection.elapsedMs,
                    timeout: step.timeout,
                    timedOut: true,
                    elseRan: true,
                    lastObservedSummary: selection.lastObservedSummary
                ),
                children: children
            )
        }

        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .waitForCases,
            message: waitForCasesTimeoutMessage(step: step, lastObservedSummary: selection.lastObservedSummary),
            durationMs: elapsedMilliseconds(since: start),
            caseSelection: HeistCaseSelectionResult(
                cases: selection.cases,
                selectedCaseIndex: nil,
                elapsedMs: selection.elapsedMs,
                timeout: step.timeout,
                timedOut: true,
                lastObservedSummary: selection.lastObservedSummary
            )
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

#endif // DEBUG
#endif // canImport(UIKit)
