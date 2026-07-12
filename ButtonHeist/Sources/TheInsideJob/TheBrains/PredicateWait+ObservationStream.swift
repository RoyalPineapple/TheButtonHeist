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

/// Reduces settled observations against one immutable baseline. Historical
/// edge collection belongs to `ObservationWindow`; this value only remembers
/// which baseline the predicate owns.
internal struct PredicateObservationStreamState {
    private let baseline: SettledCapture?

    internal init() {
        baseline = nil
    }

    private init(baseline: SettledCapture?) {
        self.baseline = baseline
    }

    internal var changeBaseline: SettledCapture? {
        baseline
    }

    internal func reducing(
        _ observation: HeistSemanticObservation,
        predicate: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed = .preserve,
        observationWindow suppliedWindow: ObservationWindow? = nil
    ) -> PredicateObservationStreamReduction {
        guard predicate.requiresChangeBaseline else {
            let evidence = PredicateObservationEvidence(
                observation: observation,
                baseline: nil,
                window: nil
            )
            return PredicateObservationStreamReduction(
                state: self,
                reduction: PredicateObservationReduction(
                    evidence: evidence,
                    expectation: PredicateEvaluation.evaluate(predicate, in: evidence)
                )
            )
        }

        let baseline = baseline ?? baselineSeed.baseline(for: observation.event)
        let window = baseline.flatMap { baseline in
            suppliedWindow ?? ObservationWindow.direct(
                from: baseline,
                through: observation.event,
                projection: predicate.deltaProjection
            )
        }
        let evidence = PredicateObservationEvidence(
            observation: observation,
            baseline: baseline,
            window: window
        )
        return PredicateObservationStreamReduction(
            state: PredicateObservationStreamState(baseline: baseline),
            reduction: PredicateObservationReduction(
                evidence: evidence,
                expectation: PredicateEvaluation.evaluate(predicate, in: evidence)
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

    internal var changeVerdict: ChangeVerdict? {
        evidence.window?.verdict
    }

    internal var observationWindow: ObservationWindow? {
        evidence.window
    }
}

extension PredicateWait.Snapshot {
    internal init(_ reduction: PredicateObservationReduction) {
        self.init(
            observation: PredicateWait.WaitObservation(
                trace: reduction.trace,
                summary: reduction.observation.summary,
                visibleFingerprint: .known(reduction.observation.visibleFingerprint),
                sequence: reduction.observation.event.sequence
            ),
            expectation: reduction.expectation,
            baseline: reduction.changeBaseline,
            window: reduction.observationWindow
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
