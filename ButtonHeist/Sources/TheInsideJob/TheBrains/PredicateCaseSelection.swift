#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct PredicateCaseSelection {
    typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        UInt64?,
        Double?
    ) async -> HeistSemanticObservation?

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

    static func waitFor(
        _ cases: [ResolvedPredicateCase],
        timeout rawTimeout: Double,
        observeSemanticState: ObservationSource
    ) async -> HeistCaseSelectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = PredicateWait.clampedWaitTimeout(rawTimeout)
        let scope = cases.observationScope
        let requiresChangeBaseline = cases.contains { $0.predicate.requiresFutureSettledBaseline }
        var observedSequence: UInt64?
        var changeBaselineSequence: UInt64?
        var lastSelection = PredicateCaseSelection.unevaluated(cases)
        var lastSummary: String?

        repeat {
            let remaining = max(0, start + timeout - CFAbsoluteTimeGetCurrent())
            guard let observation = await observeSemanticState(
                scope,
                observedSequence,
                min(remaining, SemanticObservationTiming.defaultTimeout)
            ) else {
                if timeout == 0 { break }
                continue
            }

            observedSequence = observation.event.sequence
            lastSummary = observation.summary
            if requiresChangeBaseline, changeBaselineSequence == nil {
                changeBaselineSequence = observation.event.sequence
            }

            lastSelection = PredicateCaseSelection.evaluate(
                cases,
                observation: observation,
                changeBaselineSequence: changeBaselineSequence
            )

            if lastSelection.selectedCaseIndex != nil {
                return HeistCaseSelectionResult(
                    cases: lastSelection.cases,
                    selectedCaseIndex: lastSelection.selectedCaseIndex,
                    elapsedMs: elapsedMilliseconds(since: start),
                    timeout: rawTimeout,
                    lastObservedSummary: observation.summary
                )
            }

            if timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < start + timeout

        return HeistCaseSelectionResult(
            cases: lastSelection.cases,
            selectedCaseIndex: nil,
            elapsedMs: elapsedMilliseconds(since: start),
            timeout: rawTimeout,
            timedOut: true,
            lastObservedSummary: lastSummary
        )
    }

    private static func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
