#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

@MainActor
func evaluatePredicateCases(
    _ cases: [ResolvedPredicateCaseRuntimeInput],
    in event: Observation.SnapshotEvent?
) -> HeistCaseSelectionResult {
    let results = cases.map {
        if let event {
            PredicateEvaluation.caseMatch($0, in: event)
        } else {
            HeistCaseMatchResult(
                predicate: $0.predicateExpression.rootPredicate,
                met: false,
                actual: "no settled accessibility state observed"
            )
        }
    }
    return .selectingFirstMatch(
        cases: results,
        ifNone: .noMatch,
        elapsedMs: 0,
        lastObservedSummary: event?.summary
    )
}

#endif // DEBUG
#endif // canImport(UIKit)
