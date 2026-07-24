#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

@MainActor
func evaluatePredicateCases(
    _ cases: [PredicateCase],
    resolved: [ResolvedScreenAssertion],
    in settlement: Settlement.Result
) -> HeistCaseSelectionResult {
    precondition(cases.count == resolved.count, "resolved predicate case count must match authored cases")
    let results = cases.indices.map {
        Settlement.PredicateEvaluation.caseMatch(
            cases[$0],
            resolved: resolved[$0],
            in: settlement
        )
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
