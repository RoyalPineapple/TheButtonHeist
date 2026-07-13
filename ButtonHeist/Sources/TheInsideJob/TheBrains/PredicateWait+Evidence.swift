#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal func initialTraceChangeEvaluation(
        for predicate: AccessibilityPredicate<RootContext>,
        initialTrace: AccessibilityTrace?
    ) -> ExpectationResult? {
        guard predicate.requiresChangeBaseline,
              let initialTrace,
              let evidence = AccessibilityTraceEvidence(
                  trace: initialTrace,
                  completeness: .incomplete
              )
        else { return nil }
        return predicate.evaluate(in: evidence)
    }

    internal nonisolated static func suppliedChangeBaseline(
        from trace: AccessibilityTrace?,
        sequence: SettledObservationSequence?,
        entry: SettledSemanticObservationEvent
    ) -> SettledCapture? {
        guard let capture = trace?.captures.first else { return nil }
        if let sequence {
            let cursor = entry.previousCursor?.sequence == sequence
                ? entry.previousCursor
                : ObservationCursor(
                    generation: entry.generation,
                    scope: entry.scope,
                    sequence: sequence,
                    captureHash: capture.hash,
                    notificationSequence: 0
                )
            return cursor.map { SettledCapture(cursor: $0, capture: capture) }
        }
        if entry.cursor?.captureHash == capture.hash,
           let cursor = entry.cursor {
            return SettledCapture(cursor: cursor, capture: capture)
        }
        if entry.previousCursor?.captureHash == capture.hash,
           let cursor = entry.previousCursor {
            return SettledCapture(cursor: cursor, capture: capture)
        }
        let cursor = entry.previousCursor.map {
            ObservationCursor(
                generation: $0.generation,
                scope: $0.scope,
                sequence: $0.sequence,
                captureHash: capture.hash,
                notificationSequence: $0.notificationSequence
            )
        } ?? entry.cursor.map {
            ObservationCursor(
                generation: $0.generation,
                scope: $0.scope,
                sequence: $0.sequence,
                captureHash: capture.hash,
                notificationSequence: $0.notificationSequence
            )
        }
        return cursor.map { SettledCapture(cursor: $0, capture: capture) }
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

    internal func evaluate(_ predicate: AccessibilityPredicate<RootContext>) -> ExpectationResult {
        if predicate.requiresChangeBaseline {
            guard baseline != nil else {
                return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
            }
            guard let window else {
                return ExpectationResult(
                    met: false,
                    predicate: predicate,
                    actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                )
            }
            return predicate.evaluate(in: window.traceEvidence)
        }

        guard let evidence = AccessibilityTraceEvidence(
            trace: snapshot.trace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
        }
        return predicate.evaluate(in: evidence)
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
