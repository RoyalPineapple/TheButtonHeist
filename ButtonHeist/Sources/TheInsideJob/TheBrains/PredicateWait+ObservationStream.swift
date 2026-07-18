#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum PredicateObservationBaselineSeed {
    case preserve
    case supplied(SettledCapture)
    case currentObservation
}

/// Reduces settled observations against one immutable baseline. The semantic
/// observation log supplies the complete window for each reduction; this
/// value does not own or merge history.
internal struct PredicateObservationStreamState: Sendable, Equatable {
    private let baseline: SettledCapture?

    internal init() {
        baseline = nil
    }

    private init(baseline: SettledCapture?) {
        self.baseline = baseline
    }

    internal var observationBaseline: SettledCapture? {
        baseline
    }

    internal func seedingBaseline(
        _ seed: PredicateObservationBaselineSeed,
        from event: SettledObservationEvent,
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
        observationWindow: ObservationWindow? = nil
    ) -> PredicateObservationStreamReduction {
        let evidence = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: baseline == nil ? nil : observationWindow
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
    func baseline(for event: SettledObservationEvent) -> SettledCapture? {
        switch self {
        case .preserve:
            nil
        case .supplied(let baseline):
            baseline
        case .currentObservation:
            event.settledCapture
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
        evidence.window?.trace ?? observation.accessibilityTrace
    }

    internal var changeBaseline: SettledCapture? {
        evidence.baseline
    }

    internal var observationWindow: ObservationWindow? {
        evidence.window
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
