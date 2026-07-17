#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in evidence: PredicateObservationEvidence
    ) -> ExpectationResult {
        evidence.evaluate(predicate, expression: expression)
    }

    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in observation: SettledObservationEvidence
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: observation.accessibilityTrace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(
                met: false,
                predicate: expression,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }

    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return ExpectationResult(
                met: false,
                predicate: expression,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCaseRuntimeInput,
        in observation: SettledObservationEvidence
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                predicateCase.predicate.rootPredicate,
                expression: predicateCase.predicateExpression.rootPredicate,
                in: observation
            )
        )
    }

    private static func caseMatchResult(
        _ predicateCase: ResolvedPredicateCaseRuntimeInput,
        result: ExpectationResult
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicateExpression.rootPredicate,
            met: result.met,
            actual: result.actual
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
