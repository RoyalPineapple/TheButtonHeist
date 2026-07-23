#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

@MainActor
func evaluatePredicateCases(
    _ cases: [ResolvedPredicateCaseRuntimeInput],
    in settlement: Settlement.Result
) -> HeistCaseSelectionResult {
    let results = cases.map {
        Settlement.PredicateEvaluation.caseMatch($0, in: settlement)
    }
    return .selectingFirstMatch(
        cases: results,
        ifNone: .noMatch,
        elapsedMs: 0,
        lastObservedSummary: settlement.evidence.handoff.event?.summary
    )
}

#endif // DEBUG
#endif // canImport(UIKit)
