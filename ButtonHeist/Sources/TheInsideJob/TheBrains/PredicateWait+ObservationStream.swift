#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum PredicateObservationBaselineSeed {
    case preserve
    case supplied(WaitChangeBaseline)
    case currentObservation
    case previousObservationIfAvailable
}

/// Reduces a settled observation stream into current-state match evidence and
/// baseline-to-current transition evidence without reading mutable runtime state.
internal struct PredicateObservationStreamState {
    private let changeState: PredicateChangeObservationState

    internal init() {
        self.init(changeState: .awaitingBaseline)
    }

    private init(changeState: PredicateChangeObservationState) {
        self.changeState = changeState
    }

    internal var changeBaseline: WaitChangeBaseline? {
        changeState.baseline
    }

    internal func reducing(
        _ observation: HeistSemanticObservation,
        predicate: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed = .preserve
    ) -> PredicateObservationStreamReduction {
        let projection = predicate.deltaProjection
        let advance = changeState.advancing(
            observation,
            baselineSeed: baselineSeed,
            projection: projection
        )

        let evidence = PredicateObservationEvidence(
            observation: observation,
            changeReadiness: advance.readiness,
            transition: advance.transition
        )
        let reduction = PredicateObservationReduction(
            evidence: evidence,
            expectation: PredicateEvaluation.evaluate(predicate, in: evidence)
        )
        return PredicateObservationStreamReduction(
            state: PredicateObservationStreamState(changeState: advance.state),
            reduction: reduction
        )
    }
}

private enum PredicateChangeObservationState {
    case awaitingBaseline
    case observing(PredicateChangeObservationCursor)

    fileprivate var baseline: WaitChangeBaseline? {
        guard case .observing(let cursor) = self else { return nil }
        return cursor.baseline
    }

    fileprivate func advancing(
        _ observation: HeistSemanticObservation,
        baselineSeed: PredicateObservationBaselineSeed,
        projection: AccessibilityTrace.DeltaProjection
    ) -> PredicateChangeObservationAdvance {
        switch self {
        case .observing(var cursor):
            cursor.append(observation)
            return cursor.advance(observedSequence: observation.event.sequence)
        case .awaitingBaseline:
            switch baselineSeed {
            case .preserve:
                return PredicateChangeObservationAdvance(
                    state: .awaitingBaseline,
                    readiness: .notRequired,
                    transition: nil
                )
            case .supplied(let suppliedBaseline):
                var cursor = PredicateChangeObservationCursor(
                    baseline: suppliedBaseline,
                    projection: projection
                )
                cursor.append(observation)
                return cursor.advance(observedSequence: observation.event.sequence)
            case .currentObservation:
                let cursor = PredicateChangeObservationCursor(
                    baseline: WaitChangeBaseline(event: observation.event),
                    projection: projection
                )
                return cursor.advance(observedSequence: observation.event.sequence)
            case .previousObservationIfAvailable:
                let inferredBaseline = WaitChangeBaseline(previousOf: observation.event)
                    ?? WaitChangeBaseline(event: observation.event)
                var cursor = PredicateChangeObservationCursor(
                    baseline: inferredBaseline,
                    projection: projection
                )
                cursor.append(observation)
                return cursor.advance(observedSequence: observation.event.sequence)
            }
        }
    }
}

private struct PredicateChangeObservationCursor {
    fileprivate let baseline: WaitChangeBaseline
    private let projection: AccessibilityTrace.DeltaProjection
    private var accumulatedTrace: PredicateWait.AccumulatedTrace

    fileprivate init(baseline: WaitChangeBaseline, projection: AccessibilityTrace.DeltaProjection) {
        self.baseline = baseline
        self.projection = projection
        self.accumulatedTrace = PredicateWait.AccumulatedTrace(baseline: baseline)
    }

    fileprivate mutating func append(_ observation: HeistSemanticObservation) {
        accumulatedTrace.append(observation, projection: projection)
    }

    fileprivate func advance(observedSequence: SettledObservationSequence) -> PredicateChangeObservationAdvance {
        guard let observedChange = PredicateWait.ObservedChange(
            baseline: baseline,
            observedSequence: observedSequence
        ) else {
            return PredicateChangeObservationAdvance(
                state: .observing(self),
                readiness: .baselineOnly(baseline),
                transition: nil
            )
        }

        guard accumulatedTrace.isAvailable else {
            return PredicateChangeObservationAdvance(
                state: .observing(self),
                readiness: .unavailableTrace(observedChange),
                transition: nil
            )
        }

        return PredicateChangeObservationAdvance(
            state: .observing(self),
            readiness: .observedTransition(observedChange),
            transition: PredicateWait.TransitionEvidence(
                observedChange: observedChange,
                accumulatedTrace: accumulatedTrace,
                projection: projection
            )
        )
    }
}

private struct PredicateChangeObservationAdvance {
    fileprivate let state: PredicateChangeObservationState
    fileprivate let readiness: PredicateChangeReadiness
    fileprivate let transition: PredicateWait.TransitionEvidence?
}

internal struct PredicateObservationStreamReduction {
    internal let state: PredicateObservationStreamState
    internal let reduction: PredicateObservationReduction
}

internal struct PredicateObservationReduction {
    internal let evidence: PredicateObservationEvidence
    internal let expectation: ExpectationResult

    internal init(
        evidence: PredicateObservationEvidence,
        expectation: ExpectationResult
    ) {
        self.evidence = evidence
        self.expectation = expectation
    }

    internal var observation: HeistSemanticObservation {
        evidence.observation
    }

    internal var trace: AccessibilityTrace? {
        evidence.trace
    }

    internal var changeBaseline: WaitChangeBaseline? {
        evidence.changeReadiness.baseline
    }

    internal var changeReadiness: PredicateChangeReadiness {
        evidence.changeReadiness
    }
}

extension PredicateWait.Snapshot {
    internal init(_ reduction: PredicateObservationReduction) {
        self.init(
            observation: PredicateWait.WaitObservation(
                trace: reduction.trace ?? reduction.observation.accessibilityTrace,
                summary: reduction.observation.summary,
                visibleFingerprint: .known(reduction.observation.visibleFingerprint),
                sequence: reduction.observation.event.sequence
            ),
            expectation: reduction.expectation,
            changeReadiness: reduction.changeReadiness
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
