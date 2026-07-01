#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore
import ThePlans

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
        changeBaselineSequence: SettledObservationSequence? = nil
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

    static func evaluate(
        _ cases: [ResolvedPredicateCase],
        evidence: PredicateObservationEvidence
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            PredicateEvaluation.caseMatch($0, in: evidence)
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
        let requiresChangeBaseline = cases.contains { $0.predicate.requiresChangeBaseline }
        var stream = PredicateObservationStreamState()
        let pollResult = await PredicatePollingEngine<PredicateCaseSelection>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: rawTimeout,
            start: start,
            requiresChangeBaseline: requiresChangeBaseline,
            evaluate: { observation, _ in
                let baselineSeed: PredicateObservationBaselineSeed =
                    requiresChangeBaseline && stream.changeBaseline == nil
                        ? .previousObservationIfAvailable
                        : .preserve
                let reduced = stream.reducing(
                    observation,
                    predicate: cases.first?.predicate
                        ?? .state(.missing(ElementPredicate(identifier: "__empty_heist_cases__"))),
                    baselineSeed: baselineSeed
                )
                stream = reduced.state
                return PredicateCaseSelection.evaluate(
                    cases,
                    evidence: reduced.reduction.evidence
                )
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
