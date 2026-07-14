#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal func initialTraceChangeEvaluation(
        for step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace?
    ) -> ExpectationResult? {
        guard step.predicate.requiresChangeBaseline,
              let initialTrace,
              let evidence = AccessibilityTraceEvidence(
                  trace: initialTrace,
                  completeness: .incomplete
        )
        else { return nil }
        return step.predicate.evaluate(in: evidence).expectation(for: step.predicateExpression)
    }

}

internal struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    internal let baseline: SettledCapture?
    internal let window: ObservationWindow?

    internal init(
        observation: HeistSemanticObservation,
        baseline: SettledCapture?,
        window: ObservationWindow?
    ) {
        let snapshot = PredicateObservationSnapshot(observation)
        self.snapshot = snapshot
        self.baseline = baseline
        self.window = window
    }

    internal var observation: HeistSemanticObservation {
        snapshot.observation
    }

    internal func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate
    ) -> ExpectationResult {
        if predicate.requiresChangeBaseline {
            guard baseline != nil else {
                return ExpectationResult(met: false, predicate: expression, actual: "noTrace")
            }
            guard let window else {
                return ExpectationResult(
                    met: false,
                    predicate: expression,
                    actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                )
            }
            return predicate.evaluate(in: window.traceEvidence).expectation(for: expression)
        }

        guard let evidence = AccessibilityTraceEvidence(
            trace: snapshot.trace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(met: false, predicate: expression, actual: "noTrace")
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }
}

extension ObservationWindow {
    internal var traceEvidence: AccessibilityTraceEvidence {
        let evidenceCompleteness: AccessibilityTraceEvidence.Completeness = switch completeness {
        case .complete:
            .complete
        case .incomplete:
            .incomplete
        }
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: evidenceCompleteness
        ) else {
            preconditionFailure("observation window requires at least one capture")
        }
        return evidence
    }
}

private struct PredicateObservationSnapshot {
    fileprivate let observation: HeistSemanticObservation
    fileprivate let trace: AccessibilityTrace

    fileprivate init(_ observation: HeistSemanticObservation) {
        self.observation = observation
        self.trace = observation.accessibilityTrace
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
