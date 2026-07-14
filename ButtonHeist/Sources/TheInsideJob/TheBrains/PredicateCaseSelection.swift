#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore
import ThePlans

struct PredicateCaseSelection {
    typealias ObservationSource = PredicatePollingEngine<PredicateCaseSelection>.ObservationSource

    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [ResolvedPredicateCaseRuntimeInput]) -> PredicateCaseSelection {
        PredicateCaseSelection(
            cases: cases.map {
                let predicate = $0.predicateExpression.rootPredicate
                return HeistCaseMatchResult(
                    predicate: predicate,
                    met: false,
                    actual: "no settled accessibility state observed"
                )
            },
            selectedCaseIndex: nil
        )
    }

    static func evaluate(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        observation: HeistSemanticObservation
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            PredicateEvaluation.caseMatch(
                $0,
                in: observation
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.met)
        )
    }

    @MainActor static func waitFor(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        timeout rawTimeout: Double,
        observeSemanticState: @escaping ObservationSource
    ) async -> HeistCaseSelectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let scope = cases.observationScope
        guard !cases.isEmpty else {
            return HeistCaseSelectionResult(
                cases: [],
                outcome: .noMatch,
                elapsedMs: 0,
                timeout: rawTimeout,
                lastObservedSummary: nil
            )
        }
        let pollResult = await PredicatePollingEngine<PredicateCaseSelection>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: rawTimeout,
            start: start,
            evaluate: { observation in
                PredicateCaseSelection.evaluate(cases, observation: observation)
            },
            isMatched: { $0.selectedCaseIndex != nil }
        )

        let lastSelection = pollResult.last?.evaluation ?? PredicateCaseSelection.unevaluated(cases)
        if let selectedCaseIndex = lastSelection.selectedCaseIndex {
            return HeistCaseSelectionResult(
                cases: lastSelection.cases,
                outcome: .matchedCase(index: selectedCaseIndex),
                elapsedMs: pollResult.elapsedMs,
                timeout: rawTimeout,
                lastObservedSummary: pollResult.last?.observation.summary
            )
        }

        return HeistCaseSelectionResult(
            cases: lastSelection.cases,
            outcome: PredicateWait.clampedWaitTimeout(rawTimeout) > 0 ? .timedOut : .noMatch,
            elapsedMs: pollResult.elapsedMs,
            timeout: rawTimeout,
            lastObservedSummary: pollResult.last?.observation.summary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
