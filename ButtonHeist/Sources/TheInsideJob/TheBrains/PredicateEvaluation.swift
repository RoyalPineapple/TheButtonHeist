#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: AccessibilityPredicate,
        currentElements: [HeistElement],
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
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
        in observation: HeistSemanticObservation
    ) -> ExpectationResult {
        if case .state = predicate {
            return PredicateObservationEvidence(
                observation: observation,
                baseline: nil,
                window: nil
            ).evaluate(predicate)
        }

        return evaluate(
            predicate,
            currentElements: observation.accessibilityTrace.captures.last?.interface.projectedElements
                ?? observation.state.interface.projectedElements,
            delta: observation.delta
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in trace: AccessibilityTrace
    ) -> ExpectationResult {
        predicate.evaluate(in: PredicateEvaluationEvidence(trace: trace))
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCase,
        in observation: HeistSemanticObservation
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicate,
            result: evaluate(
                predicateCase.predicate,
                in: observation
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
        case .state, .announcement:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
