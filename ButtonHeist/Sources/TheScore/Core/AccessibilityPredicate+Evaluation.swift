import ThePlans

package extension ObservationPredicate {
    /// Answer this predicate from the exact evidence observed at runtime.
    func evaluate(
        in evidence: Observation.Evidence
    ) throws(Observation.Gap) -> PredicateEvaluationResult {
        let expectation = Expectation(
            [self],
            baseline: evidence.baseline,
            events: evidence.events
        )
        switch expectation.result {
        case .satisfied:
            return PredicateEvaluationResult(met: true, actual: nil)
        case .waiting(let outstandingDescription):
            if case .incomplete(let gap) = evidence.coverage {
                throw gap
            }
            return PredicateEvaluationResult(
                met: false,
                actual: outstandingDescription
            )
        }
    }
}
