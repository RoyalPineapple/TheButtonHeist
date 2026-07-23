#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum PredicateObservationBaselineSeed {
    case preserve
    case supplied(Observation.Moment)
    case currentObservation
}

/// Reduces settled observations against one immutable baseline. The semantic
/// observation log supplies the events for each reduction; this value does
/// not own or merge history.
internal struct PredicateObservationStreamState: Sendable, Equatable {
    private let baseline: Observation.Moment?

    internal init() {
        baseline = nil
    }

    private init(baseline: Observation.Moment?) {
        self.baseline = baseline
    }

    internal var observationBaseline: Observation.Moment? {
        baseline
    }

    internal func seedingBaseline(
        _ seed: PredicateObservationBaselineSeed,
        from event: Observation.SnapshotEvent,
        when required: Bool
    ) -> Self {
        guard required else { return PredicateObservationStreamState(baseline: nil) }
        return PredicateObservationStreamState(
            baseline: baseline ?? seed.baseline(for: event)
        )
    }

    internal func reducing(
        _ observation: SettledObservationEvidence,
        predicate: ResolvedAccessibilityPredicate,
        predicateExpression: AccessibilityPredicate,
        eventsSinceBaseline: Observation.EventsSince? = nil
    ) -> PredicateObservationStreamReduction {
        let evidence = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            eventsSinceBaseline: baseline == nil ? nil : eventsSinceBaseline
        )
        return PredicateObservationStreamReduction(
            state: self,
            reduction: PredicateObservationReduction(
                evidence: evidence,
                expectation: PredicateEvaluation.evaluate(
                    predicate,
                    expression: predicateExpression,
                    in: evidence
                )
            )
        )
    }
}

private extension PredicateObservationBaselineSeed {
    func baseline(for event: Observation.SnapshotEvent) -> Observation.Moment? {
        switch self {
        case .preserve:
            nil
        case .supplied(let baseline):
            baseline
        case .currentObservation:
            event.moment
        }
    }
}

internal struct PredicateObservationStreamReduction {
    internal let state: PredicateObservationStreamState
    internal let reduction: PredicateObservationReduction
}

internal struct PredicateObservationReduction {
    internal let evidence: PredicateObservationEvidence
    internal let expectation: ExpectationResult

    internal var observation: SettledObservationEvidence {
        evidence.observation
    }

    internal var trace: AccessibilityTrace? {
        evidence.changeTrace ?? observation.accessibilityTrace
    }

    internal var changeBaseline: Observation.Moment? {
        evidence.baseline
    }

    internal var eventsSinceBaseline: Observation.EventsSince? {
        evidence.eventsSinceBaseline
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
