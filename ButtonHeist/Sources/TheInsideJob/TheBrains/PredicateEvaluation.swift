#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: AccessibilityPredicate,
        currentElements: [HeistElement],
        delta: AccessibilityTrace.Delta?,
        observedSequence: UInt64? = nil,
        changeBaselineSequence: UInt64? = nil
    ) -> ExpectationResult {
        if predicate.requiresFutureSettledBaseline,
           let observedSequence,
           let changeBaselineSequence,
           observedSequence <= changeBaselineSequence {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "change predicate requires future settled observation after baseline"
            )
        }
        return predicate.evaluate(
            currentElements: currentElements,
            delta: delta
        )
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate,
        in observation: HeistSemanticObservation,
        changeBaselineSequence: UInt64? = nil
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
        changeBaselineSequence: UInt64? = nil
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
}

extension AccessibilityPredicate {
    var requiresFutureSettledBaseline: Bool {
        if case .changed = self { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
