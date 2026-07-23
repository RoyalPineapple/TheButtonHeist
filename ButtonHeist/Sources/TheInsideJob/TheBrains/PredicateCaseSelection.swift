#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension PredicateWait {
    func selectPredicateCase(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        timeout _: Double
    ) async -> HeistCaseSelectionResult {
        let event = await vault.semanticObservationStream.settledEvent(
            scope: cases.observationScope,
            after: nil,
            timeout: 0
        )
        return evaluatePredicateCases(
            cases,
            in: event.map { actionEvidenceProjector.projectSettledEvidence(from: $0) }
        )
    }
}

@MainActor
func evaluatePredicateCases(
    _ cases: [ResolvedPredicateCaseRuntimeInput],
    in observation: SettledObservationEvidence?
) -> HeistCaseSelectionResult {
    let results = cases.map {
        if let observation {
            PredicateEvaluation.caseMatch($0, in: observation)
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
        lastObservedSummary: observation?.summary
    )
}

#endif // DEBUG
#endif // canImport(UIKit)
