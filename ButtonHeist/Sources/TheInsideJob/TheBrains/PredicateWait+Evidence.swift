#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal func initialTraceChangeEvaluation(
        for predicate: AccessibilityPredicate,
        initialTrace: AccessibilityTrace?
    ) -> ExpectationResult? {
        guard predicate.requiresChangeBaseline,
              let initialTrace,
              let lastCapture = initialTrace.captures.last
        else { return nil }
        return PredicateEvaluation.evaluate(
            predicate,
            currentElements: lastCapture.interface.projectedElements,
            accumulatedDelta: initialTrace.accumulatedDelta(projection: predicate.deltaProjection)
        )
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
        return SettledCapture(previousOf: entry)
    }
}

internal struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    private let stateGraph: ElementMatchGraph
    internal let baseline: SettledCapture?
    internal let window: ObservationWindow?

    internal init(
        observation: HeistSemanticObservation,
        baseline: SettledCapture?,
        window: ObservationWindow?
    ) {
        let snapshot = PredicateObservationSnapshot(observation)
        self.snapshot = snapshot
        self.stateGraph = ElementMatchGraph(interface: snapshot.interface)
        self.baseline = baseline
        self.window = window
    }

    internal var observation: HeistSemanticObservation {
        snapshot.observation
    }

    internal var trace: AccessibilityTrace? {
        window?.trace ?? snapshot.trace
    }

    internal func evaluate(_ predicate: AccessibilityPredicate) -> ExpectationResult {
        switch predicate {
        case .state(let state):
            return state.evaluate(in: stateGraph).expectation(for: predicate)
        case .announcement:
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "announcement predicates require spoken accessibility text evidence"
            )
        case .changePredicate, .noChangePredicate:
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
            guard let verdict = window.verdict else {
                let actual = switch window.completeness {
                case .incomplete(let gap) where gap.reason == .noObservationAfterBaseline:
                    PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                case .complete, .incomplete:
                    "observation history incomplete"
                }
                return ExpectationResult(met: false, predicate: predicate, actual: actual)
            }
            let accumulatedDelta: AccessibilityTrace.AccumulatedDelta? = switch verdict {
            case .changed(let facts):
                facts.accumulatedDelta
            case .unchanged:
                window.accumulatedDelta
            }
            return predicate.evaluate(
                currentElements: window.current.capture.interface.projectedElements,
                accumulatedDelta: accumulatedDelta
            )
        }
    }
}

private struct PredicateObservationSnapshot {
    fileprivate let observation: HeistSemanticObservation
    fileprivate let interface: Interface
    fileprivate let trace: AccessibilityTrace

    fileprivate init(_ observation: HeistSemanticObservation) {
        self.observation = observation
        self.interface = observation.state.interface
        self.trace = observation.accessibilityTrace
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
