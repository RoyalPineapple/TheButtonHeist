#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum PredicateObservationBaselineSeed {
    case preserve
    case supplied(SettledCapture)
    case currentObservation
    case previousObservationIfAvailable
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

    internal func reducing(
        _ observation: HeistSemanticObservation,
        predicate: ResolvedAccessibilityPredicate,
        predicateExpression: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed = .preserve,
        observationWindow: ObservationWindow? = nil
    ) -> PredicateObservationStreamReduction {
        let baseline = predicate.requiresChangeBaseline
            ? baseline ?? baselineSeed.baseline(for: observation.event)
            : nil
        let evidence = PredicateObservationEvidence(
            observation: observation,
            baseline: predicate.requiresChangeBaseline ? baseline : nil,
            window: observationWindow
        )
        return PredicateObservationStreamReduction(
            state: PredicateObservationStreamState(baseline: baseline),
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
    func baseline(for event: SettledSemanticObservationEvent) -> SettledCapture? {
        switch self {
        case .preserve:
            nil
        case .supplied(let baseline):
            baseline
        case .currentObservation:
            event.settledCapture
        case .previousObservationIfAvailable:
            SettledCapture(previousOf: event) ?? event.settledCapture
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

    internal var observation: HeistSemanticObservation {
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
