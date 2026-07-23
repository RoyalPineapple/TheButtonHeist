#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal enum ActionContextReduction {
        case matched(PredicateObservationReduction)
        case unmatched(LifecycleEvidence)
        case empty
        case unavailable(Observation.LogReadError)
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
    ) async -> ActionContextReduction? {
        guard step.predicate.requiresChangeBaseline, let context else { return nil }

        var evidence = LifecycleEvidence(
            predicate: step.predicateExpression,
            target: step.predicate.waitTarget
        )
        var lastReduction: PredicateObservationReduction?
        guard context.throughMoment.isSameOrAfter(context.preActionMoment) else {
            return .unavailable(.momentUnavailable(context.throughMoment))
        }
        let events: [Observation.Event]
        switch await vault.semanticObservationStream.storeOwner.readLog({
            $0.events(since: context.preActionMoment)
        }) {
        case .events(let retained):
            events = retained
        case .expired(let gap):
            return .unavailable(.historyEvicted(gap))
        case .unavailable(let error):
            return .unavailable(error)
        }
        for case .snapshot(let event) in events {
            guard context.throughMoment.isSameOrAfter(event.moment) else { break }
            let reduction = await reduceObservation(
                actionEvidenceProjector.projectSettledEvidence(from: event),
                predicate: step.predicate,
                predicateExpression: step.predicateExpression,
                baselineSeed: .supplied(context.preActionMoment),
                stream: evidence.stream
            )
            evidence = evidence.recording(reduction)
            lastReduction = reduction.reduction
            if case .changed = step.predicate.core,
               reduction.reduction.expectation.met {
                return .matched(reduction.reduction)
            }
        }
        guard let lastReduction else { return .empty }
        return lastReduction.expectation.met
            ? .matched(lastReduction)
            : .unmatched(evidence)
    }

}

internal struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    internal let baseline: Observation.Moment?
    internal let eventsSinceBaseline: Observation.EventsSince?

    internal init(
        observation: SettledObservationEvidence,
        baseline: Observation.Moment?,
        eventsSinceBaseline: Observation.EventsSince?
    ) {
        let snapshot = PredicateObservationSnapshot(observation)
        self.snapshot = snapshot
        self.baseline = baseline
        self.eventsSinceBaseline = eventsSinceBaseline
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
            guard let traceEvidence else {
                let actual = switch eventsSinceBaseline {
                case .expired:
                    "observation history incomplete"
                case .unavailable:
                    "observation history unavailable"
                case .events, .none:
                    PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                }
                return ExpectationResult(
                    met: false,
                    predicate: expression,
                    actual: actual
                )
            }
            return predicate.evaluate(in: traceEvidence).expectation(for: expression)
        }

        guard let evidence = AccessibilityTraceEvidence(
            trace: snapshot.trace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(met: false, predicate: expression, actual: "noTrace")
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }

    internal var changeTrace: AccessibilityTrace? {
        Self.changeTrace(
            baseline: baseline,
            eventsSinceBaseline: eventsSinceBaseline,
            through: observation.event
        )
    }

    internal var traceEvidence: AccessibilityTraceEvidence? {
        changeTrace.flatMap {
            AccessibilityTraceEvidence(trace: $0, completeness: .complete)
        }
    }

    internal static func traceEvidence(
        baseline: Observation.Moment?,
        eventsSinceBaseline: Observation.EventsSince?,
        through currentEvent: Observation.SnapshotEvent?
    ) -> AccessibilityTraceEvidence? {
        changeTrace(
            baseline: baseline,
            eventsSinceBaseline: eventsSinceBaseline,
            through: currentEvent
        ).flatMap {
            AccessibilityTraceEvidence(trace: $0, completeness: .complete)
        }
    }

    private static func changeTrace(
        baseline: Observation.Moment?,
        eventsSinceBaseline: Observation.EventsSince?,
        through currentEvent: Observation.SnapshotEvent?
    ) -> AccessibilityTrace? {
        guard let baseline,
              let currentEvent,
              case .events(let events) = eventsSinceBaseline else { return nil }
        let snapshots = events.compactMap { event -> Observation.SnapshotEvent? in
            guard case .snapshot(let snapshot) = event,
                  currentEvent.moment.isSameOrAfter(snapshot.moment) else { return nil }
            return snapshot
        }
        guard snapshots.last?.moment == currentEvent.moment else { return nil }
        return AccessibilityTrace(captures: [baseline.capture] + snapshots.map(\.moment.capture))
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
