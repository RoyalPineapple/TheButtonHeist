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
            accumulatedDelta: initialTrace.accumulatedDelta(
                projection: predicate.deltaProjection
            )
        )
    }

    internal nonisolated static func suppliedChangeBaseline(
        from trace: AccessibilityTrace?,
        entry: SettledSemanticObservationEvent
    ) -> WaitChangeBaseline? {
        guard let capture = trace?.captures.first else { return nil }
        return WaitChangeBaseline(
            sequence: suppliedBaselineSequence(for: capture, entry: entry),
            capture: capture
        )
    }

    private nonisolated static func suppliedBaselineSequence(
        for capture: AccessibilityTrace.Capture,
        entry: SettledSemanticObservationEvent
    ) -> SettledObservationSequence {
        if entry.trace.captures.last?.hash == capture.hash {
            return entry.sequence
        }
        if entry.trace.captures.first?.hash == capture.hash,
           let previous = entry.previous {
            return previous.sequence
        }
        if let previous = entry.previous {
            return previous.sequence
        }
        return entry.sequence > 0 ? entry.sequence - 1 : 0
    }
}

private enum PredicateWaitAccumulatedTraceStorage {
    case unavailable
    case captures([AccessibilityTrace.Capture])
    case noChangeAfterBaseline(AccessibilityTrace.Capture)

    fileprivate static func noChangeDelta(for capture: AccessibilityTrace.Capture) -> AccessibilityTrace.AccumulatedDelta? {
        let trace = AccessibilityTrace(captures: [capture, capture])
        return trace.accumulatedDelta ?? AccessibilityTrace.AccumulatedDelta(
            elementCount: capture.interface.projectedElements.count,
            captureEdge: AccessibilityTrace.CaptureEdge(before: capture, after: capture),
            change: .noChange,
            interactionDigest: AccessibilityTrace.InteractionDigest(
                elementCountBefore: capture.interface.projectedElements.count,
                elementCountAfter: capture.interface.projectedElements.count,
                elementSetChanged: false,
                screenIdBefore: capture.context.screenId ?? InterfaceSummary.screenId(for: capture.interface),
                screenIdAfter: capture.context.screenId ?? InterfaceSummary.screenId(for: capture.interface),
                firstResponderChanged: false
            ),
            transient: []
        )
    }
}

extension PredicateWait {
    internal struct AccumulatedTrace {
        private var storage: PredicateWaitAccumulatedTraceStorage

        internal init(baseline: WaitChangeBaseline) {
            if let capture = baseline.capture {
                storage = .captures([capture])
            } else {
                storage = .unavailable
            }
        }

        internal var trace: AccessibilityTrace? {
            switch storage {
            case .unavailable:
                return nil
            case .captures(let captures):
                return AccessibilityTrace(captures: captures)
            case .noChangeAfterBaseline(let capture):
                return AccessibilityTrace(captures: [capture, capture])
            }
        }

        internal func delta(projection: AccessibilityTrace.DeltaProjection) -> AccessibilityTrace.AccumulatedDelta? {
            switch storage {
            case .unavailable:
                return nil
            case .captures(let captures):
                return AccessibilityTrace(captures: captures).accumulatedDelta(projection: projection)
            case .noChangeAfterBaseline(let capture):
                return PredicateWaitAccumulatedTraceStorage.noChangeDelta(for: capture)
            }
        }

        internal var isAvailable: Bool {
            switch storage {
            case .unavailable:
                return false
            case .captures, .noChangeAfterBaseline:
                return true
            }
        }

        internal mutating func append(_ observation: HeistSemanticObservation, projection: AccessibilityTrace.DeltaProjection) {
            guard let capture = observation.accessibilityTrace.captures.last else { return }
            switch storage {
            case .unavailable:
                return
            case .captures(var captures):
                guard let last = captures.last else {
                    captures.append(capture)
                    storage = .captures(captures)
                    return
                }
                if last.hash == capture.hash,
                   AccessibilityTrace.Delta.between(
                       last,
                       capture,
                       projection: projection
                   ).meaningfulWaitDelta == nil {
                    storage = .noChangeAfterBaseline(last)
                } else {
                    captures.append(capture)
                    storage = .captures(captures)
                }
            case .noChangeAfterBaseline(let baselineCapture):
                if baselineCapture.hash == capture.hash,
                   AccessibilityTrace.Delta.between(
                       baselineCapture,
                       capture,
                       projection: projection
                   ).meaningfulWaitDelta == nil {
                    return
                }
                storage = .captures([baselineCapture, capture])
            }
        }
    }
}

extension AccessibilityTrace.Delta {
    fileprivate var meaningfulWaitDelta: AccessibilityTrace.Delta? {
        switch self {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return self
        }
    }
}

internal struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    private let stateGraph: ElementMatchGraph
    internal let changeReadiness: PredicateChangeReadiness
    private let transition: PredicateWait.TransitionEvidence?

    internal init(
        observation: HeistSemanticObservation,
        changeReadiness: PredicateChangeReadiness,
        transition: PredicateWait.TransitionEvidence?
    ) {
        let snapshot = PredicateObservationSnapshot(observation)
        self.snapshot = snapshot
        self.stateGraph = ElementMatchGraph(interface: snapshot.interface)
        self.changeReadiness = changeReadiness
        self.transition = transition
    }

    internal var observation: HeistSemanticObservation {
        snapshot.observation
    }

    internal var trace: AccessibilityTrace? {
        transition?.trace ?? snapshot.trace
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
            switch changeReadiness {
            case .notRequired, .unavailableTrace:
                return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
            case .baselineOnly:
                return ExpectationResult(
                    met: false,
                    predicate: predicate,
                    actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                )
            case .observedTransition:
                guard let transition else {
                    return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
                }
                return PredicateChangeMatchSet(
                    currentElements: stateGraph.all.elements,
                    transition: transition
                ).evaluate(predicate)
            }
        }
    }
}

private struct PredicateObservationSnapshot {
    fileprivate let observation: HeistSemanticObservation
    fileprivate let sequence: SettledObservationSequence
    fileprivate let interface: Interface
    fileprivate let trace: AccessibilityTrace
    fileprivate let summary: String

    fileprivate init(_ observation: HeistSemanticObservation) {
        self.observation = observation
        self.sequence = observation.event.sequence
        self.interface = observation.state.interface
        self.trace = observation.accessibilityTrace
        self.summary = observation.summary
    }
}

private struct PredicateChangeMatchSet {
    private let currentElements: [HeistElement]
    private let transition: PredicateWait.TransitionEvidence

    fileprivate init(currentElements: [HeistElement], transition: PredicateWait.TransitionEvidence) {
        self.currentElements = currentElements
        self.transition = transition
    }

    fileprivate func evaluate(_ predicate: AccessibilityPredicate) -> ExpectationResult {
        predicate.evaluate(
            currentElements: currentElements,
            accumulatedDelta: transition.accumulatedDelta
        )
    }
}

extension PredicateWait {
    internal struct TransitionEvidence {
        internal let observedChange: ObservedChange
        private let accumulatedTrace: AccumulatedTrace
        private let projection: AccessibilityTrace.DeltaProjection

        internal init(
            observedChange: ObservedChange,
            accumulatedTrace: AccumulatedTrace,
            projection: AccessibilityTrace.DeltaProjection
        ) {
            self.observedChange = observedChange
            self.accumulatedTrace = accumulatedTrace
            self.projection = projection
        }

        internal var trace: AccessibilityTrace? {
            accumulatedTrace.trace
        }

        internal var accumulatedDelta: AccessibilityTrace.AccumulatedDelta? {
            accumulatedTrace.delta(projection: projection)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
