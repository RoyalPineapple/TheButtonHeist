#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension Settlement {
    internal enum PredicateEvaluation {}
}

extension Settlement.PredicateEvaluation {
    static func evaluate(
        _ predicate: Settlement.Predicate,
        in result: Settlement.Result
    ) -> PredicateEvaluationResult {
        guard let event = result.currentObservation else {
            return PredicateEvaluationResult(
                met: false,
                actual: "settlement did not produce a current observation"
            )
        }
        let completeness: AccessibilityTraceEvidence.Completeness = switch result {
        case .currentState:
            .incomplete
        case .observation, .action:
            .complete
        }
        return evaluate(predicate, trace: event.trace, completeness: completeness)
    }

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
        in result: Settlement.Result
    ) -> ExpectationResult {
        evaluate(
            Settlement.Predicate(authored: expression, resolved: predicate),
            in: result
        ).expectation(for: expression)
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
        _ predicateCase: PredicateCase,
        resolved: ResolvedPresenceCondition,
        in event: Observation.SnapshotEvent
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                resolved.rootPredicate,
                expression: predicateCase.predicate.rootPredicate,
                in: event
            )
        )
    }

    static func caseMatch(
        _ predicateCase: PredicateCase,
        resolved: ResolvedPresenceCondition,
        in result: Settlement.Result
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                resolved.rootPredicate,
                expression: predicateCase.predicate.rootPredicate,
                in: result
            )
        )
    }

    private static func caseMatchResult(
        _ predicateCase: PredicateCase,
        result: ExpectationResult
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicate.rootPredicate,
            met: result.met,
            actual: result.actual
        )
    }

    private static func evaluate(
        _ predicate: Settlement.Predicate,
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> PredicateEvaluationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return PredicateEvaluationResult(
                met: false,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.resolved.evaluate(in: evidence)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
