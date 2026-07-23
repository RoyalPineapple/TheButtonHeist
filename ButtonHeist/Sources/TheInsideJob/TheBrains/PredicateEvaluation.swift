#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in event: Observation.SnapshotEvent
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: event.trace,
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
        in event: Observation.SnapshotEvent
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                predicateCase.predicate.rootPredicate,
                expression: predicateCase.predicateExpression.rootPredicate,
                in: event
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
