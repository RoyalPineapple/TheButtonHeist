#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: AccessibilityPredicate,
        currentElements: [HeistElement],
        delta: AccessibilityTrace.Delta?,
        observedSequence: SettledObservationSequence? = nil,
        changeBaselineSequence: SettledObservationSequence? = nil
    ) -> ExpectationResult {
        if predicate.requiresChangeBaseline,
           let observedSequence,
           let changeBaselineSequence,
           observedSequence <= changeBaselineSequence {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
            )
        }
        return predicate.evaluate(
            currentElements: currentElements,
            delta: delta
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        currentElements: [HeistElement],
        accumulatedDelta: AccessibilityTrace.AccumulatedDelta?
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: currentElements,
            accumulatedDelta: accumulatedDelta
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in evidence: PredicateObservationEvidence
    ) -> ExpectationResult {
        evidence.evaluate(predicate)
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in observation: HeistSemanticObservation,
        changeBaselineSequence: SettledObservationSequence? = nil
    ) -> ExpectationResult {
        evaluate(
            predicate,
            currentElements: observation.state.interface.projectedElements,
            delta: observation.delta,
            observedSequence: observation.event.sequence,
            changeBaselineSequence: changeBaselineSequence
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in trace: AccessibilityTrace
    ) -> ExpectationResult {
        evaluate(
            predicate,
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            delta: trace.endpointDelta
        )
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCase,
        in observation: HeistSemanticObservation,
        changeBaselineSequence: SettledObservationSequence? = nil
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicate,
            result: evaluate(
                predicateCase.predicate,
                in: observation,
                changeBaselineSequence: changeBaselineSequence
            )
        )
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCase,
        in evidence: PredicateObservationEvidence
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicate,
            result: evaluate(predicateCase.predicate, in: evidence)
        )
    }
}

extension AccessibilityPredicate {
    var requiresChangeBaseline: Bool {
        switch self {
        case .changePredicate, .noChangePredicate:
            return true
        case .state:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
