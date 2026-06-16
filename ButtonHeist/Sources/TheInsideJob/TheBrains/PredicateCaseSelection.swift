#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct PredicateCaseSelection {
    typealias ObservationSource = PredicatePollingEngine<PredicateCaseSelection>.ObservationSource

    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [ResolvedPredicateCase]) -> PredicateCaseSelection {
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

    static func evaluate(
        _ cases: [ResolvedPredicateCase],
        observation: HeistSemanticObservation,
        changeBaselineSequence: UInt64? = nil
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            PredicateEvaluation.caseMatch(
                $0,
                in: observation,
                changeBaselineSequence: changeBaselineSequence
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.result.met)
        )
    }

    @MainActor static func waitFor(
        _ cases: [ResolvedPredicateCase],
        timeout rawTimeout: Double,
        observeSemanticState: @escaping ObservationSource
    ) async -> HeistCaseSelectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let scope = cases.observationScope
        let requiresChangeBaseline = cases.contains { $0.predicate.requiresFutureSettledBaseline }
        let pollResult = await PredicatePollingEngine<PredicateCaseSelection>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: rawTimeout,
            start: start,
            requiresChangeBaseline: requiresChangeBaseline,
            evaluate: { observation, changeBaselineSequence in
                PredicateCaseSelection.evaluate(
                    cases,
                    observation: observation,
                    changeBaselineSequence: changeBaselineSequence
                )
            },
            isMatched: { $0.selectedCaseIndex != nil }
        )

        let lastSelection = pollResult.lastEvaluation ?? PredicateCaseSelection.unevaluated(cases)
        if let selectedCaseIndex = lastSelection.selectedCaseIndex {
            return HeistCaseSelectionResult(
                cases: lastSelection.cases,
                selectedCaseIndex: selectedCaseIndex,
                elapsedMs: pollResult.elapsedMs,
                timeout: rawTimeout,
                lastObservedSummary: pollResult.lastObservation?.summary
            )
        }

        return HeistCaseSelectionResult(
            cases: lastSelection.cases,
            selectedCaseIndex: nil,
            elapsedMs: pollResult.elapsedMs,
            timeout: rawTimeout,
            timedOut: true,
            lastObservedSummary: pollResult.lastObservation?.summary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
