#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeConditionalStep(
        _ step: ConditionalStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        guard let observation = await runtime.observeSemanticState(step.observationScope, nil, nil) else {
            return caseObservationFailure(index: index, kind: .conditional, start: start)
        }

        let selection = evaluatePredicateCases(step.cases, observation: observation)
        if let selectedCaseIndex = selection.selectedCaseIndex {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(step.cases[selectedCaseIndex].steps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
                kind: .conditional,
                message: "matched case \(selectedCaseIndex)",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: selectedCaseIndex,
                    elapsedMs: selectionElapsedMs,
                    lastObservedSummary: observation.summary
                ),
                childResults: childResults
            )
        }

        if let elseSteps = step.elseSteps {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(elseSteps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
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
                childResults: childResults
            )
        }

        return HeistExecutionStepResult(
            index: index,
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
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let deadline = start + step.timeout
        var baseline: PostActionObservation.BeforeState?
        var lastSelection = PredicateCaseSelection.unevaluated(step.cases)
        var lastSummary: String?

        repeat {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            let observation = await runtime.observeSemanticState(
                step.observationScope,
                baseline,
                min(remaining, 1.0)
            )

            guard let observation else {
                if step.timeout == 0 { break }
                continue
            }
            baseline = observation.state
            lastSummary = observation.summary
            lastSelection = evaluatePredicateCases(step.cases, observation: observation)

            if let selectedCaseIndex = lastSelection.selectedCaseIndex {
                let selectionElapsedMs = elapsedMilliseconds(since: start)
                let childResults = await executeHeistSteps(step.cases[selectedCaseIndex].steps, runtime: runtime)
                return HeistExecutionStepResult(
                    index: index,
                    kind: .waitForCases,
                    message: "matched case \(selectedCaseIndex)",
                    durationMs: elapsedMilliseconds(since: start),
                    caseSelection: HeistCaseSelectionResult(
                        cases: lastSelection.cases,
                        selectedCaseIndex: selectedCaseIndex,
                        elapsedMs: selectionElapsedMs,
                        timeout: step.timeout,
                        lastObservedSummary: observation.summary
                    ),
                    childResults: childResults
                )
            }

            if step.timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < deadline

        if let elseSteps = step.elseSteps {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(elseSteps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
                kind: .waitForCases,
                message: "timed out after \(heistTimeoutDescription(step.timeout))s; else ran",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: lastSelection.cases,
                    selectedCaseIndex: nil,
                    elapsedMs: selectionElapsedMs,
                    timeout: step.timeout,
                    timedOut: true,
                    elseRan: true,
                    lastObservedSummary: lastSummary
                ),
                childResults: childResults
            )
        }

        return HeistExecutionStepResult(
            index: index,
            kind: .waitForCases,
            message: waitForCasesTimeoutMessage(step: step, lastObservedSummary: lastSummary),
            durationMs: elapsedMilliseconds(since: start),
            caseSelection: HeistCaseSelectionResult(
                cases: lastSelection.cases,
                selectedCaseIndex: nil,
                elapsedMs: elapsedMilliseconds(since: start),
                timeout: step.timeout,
                timedOut: true,
                lastObservedSummary: lastSummary
            )
        )
    }

    private func evaluatePredicateCases(
        _ cases: [PredicateCase],
        observation: HeistSemanticObservation
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            HeistCaseMatchResult(
                predicate: $0.predicate,
                result: $0.predicate.evaluate(
                    currentElements: observation.state.interface.projectedElements,
                    delta: observation.delta
                )
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.result.met)
        )
    }

    private func caseObservationFailure(
        index: Int,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            kind: kind,
            message: "Could not observe settled accessibility state before evaluating heist cases",
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

private struct PredicateCaseSelection {
    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [PredicateCase]) -> PredicateCaseSelection {
        PredicateCaseSelection(
            cases: cases.map {
                HeistCaseMatchResult(
                    predicate: $0.predicate,
                    result: ExpectationResult(
                        met: false,
                        predicate: $0.predicate,
                        actual: "no settled accessibility state observed"
                    )
                )
            },
            selectedCaseIndex: nil
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
