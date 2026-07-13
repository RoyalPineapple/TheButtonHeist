#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

enum PredicateEvaluation {
    static func evaluate(
        _ predicate: AccessibilityPredicate<RootContext>,
        in evidence: PredicateObservationEvidence
    ) -> ExpectationResult {
        evidence.evaluate(predicate)
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate<RootContext>,
        in observation: HeistSemanticObservation
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: observation.accessibilityTrace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(met: false, predicate: predicate, actual: "no observed accessibility trace")
        }
        return predicate.evaluate(in: evidence)
    }

    static func evaluate(
        _ predicate: AccessibilityPredicate<RootContext>,
        in trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return ExpectationResult(met: false, predicate: predicate, actual: "no observed accessibility trace")
        }
        return predicate.evaluate(in: evidence)
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCase,
        in observation: HeistSemanticObservation
    ) -> HeistCaseMatchResult {
        let predicate = predicateCase.predicate.rootPredicate
        let result = evaluate(predicate, in: observation)
        return HeistCaseMatchResult(
            predicate: predicate,
            met: result.met,
            actual: result.actual
        )
    }

    static func caseMatch(
        _ predicateCase: ResolvedPredicateCase,
        in evidence: PredicateObservationEvidence
    ) -> HeistCaseMatchResult {
        let predicate = predicateCase.predicate.rootPredicate
        let result = evaluate(predicate, in: evidence)
        return HeistCaseMatchResult(
            predicate: predicate,
            met: result.met,
            actual: result.actual
        )
    }
}

extension AccessibilityPredicate where Context == RootContext {
    var requiresChangeBaseline: Bool {
        switch node {
        case .changed, .noChange:
            return true
        case .exists, .missing, .announcement:
            return false
        case .screen, .elements, .appeared, .disappeared, .updated:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
