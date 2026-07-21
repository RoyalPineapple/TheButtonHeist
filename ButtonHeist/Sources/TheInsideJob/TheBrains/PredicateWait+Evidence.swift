#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal enum ActionContextReduction {
        case matched(PredicateObservationReduction)
        case unmatched
        case unavailable(ObservationHistoryReadError)
    }

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

    internal func reduceActionContext(
        for step: ResolvedWaitRuntimeInput,
        context: ActionExpectationContext?
    ) -> ActionContextReduction? {
        guard case .changed = step.predicate.core, let context else { return nil }

        var stream = PredicateObservationStreamState()
        var cursor = context.preActionCapture.cursor
        let upperBound = context.throughObservationCursor
        guard upperBound.scope == cursor.scope,
              upperBound.sequence >= cursor.sequence else {
            return .unavailable(.cursorUnavailable(upperBound))
        }
        while cursor != upperBound {
            let entry: ObservationEntry
            switch vault.semanticObservationStream.readRetainedObservation(
                after: cursor,
                scope: cursor.scope
            ) {
            case .entry(let retained):
                guard retained.cursor.sequence <= upperBound.sequence else {
                    return .unavailable(.cursorUnavailable(upperBound))
                }
                entry = retained
            case .pending:
                return .unavailable(.cursorUnavailable(upperBound))
            case .failure(let error):
                return .unavailable(error)
            }
            let reduction = reduceObservation(
                actionEvidenceProjector.projectSettledEvidence(from: entry.event),
                predicate: step.predicate,
                predicateExpression: step.predicateExpression,
                baselineSeed: .supplied(context.preActionCapture),
                stream: stream
            )
            stream = reduction.state
            if reduction.reduction.expectation.met {
                return .matched(reduction.reduction)
            }
            cursor = entry.cursor
        }
        return .unmatched
    }

}

internal struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    internal let baseline: SettledCapture?
    internal let window: ObservationWindow?

    internal init(
        observation: SettledObservationEvidence,
        baseline: SettledCapture?,
        window: ObservationWindow?
    ) {
        let snapshot = PredicateObservationSnapshot(observation)
        self.snapshot = snapshot
        self.baseline = baseline
        self.window = window
    }

    internal var observation: SettledObservationEvidence {
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
    fileprivate let observation: SettledObservationEvidence
    fileprivate let trace: AccessibilityTrace

    fileprivate init(_ observation: SettledObservationEvidence) {
        self.observation = observation
        self.trace = observation.accessibilityTrace
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
