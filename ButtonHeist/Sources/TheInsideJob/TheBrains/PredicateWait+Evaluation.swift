#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal struct PredicateWaitEvaluation<Evidence>: Sendable, Equatable
where Evidence: Sendable & Equatable {
    internal let evidence: Evidence
    internal let matched: Bool
}

internal enum PredicateWaitOutcome: Sendable, Equatable {
    case matched
    case timedOut
    case cancelled
}

extension PredicateWait {
    internal struct LifecycleEvidence: Sendable, Equatable {
        internal let stream: PredicateObservationStreamState
        private let initialExpectation: ExpectationResult
        private let snapshot: Snapshot?
        private let historicalDiagnostics: PredicateWaitHistoricalDiagnostics

        internal init(
            predicate: AccessibilityPredicate,
            target: ResolvedAccessibilityTarget? = nil
        ) {
            stream = PredicateObservationStreamState()
            initialExpectation = ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "no settled semantic observation available"
            )
            snapshot = nil
            historicalDiagnostics = PredicateWaitHistoricalDiagnostics(
                target: target,
                predicate: predicate
            )
        }

        private init(
            stream: PredicateObservationStreamState,
            initialExpectation: ExpectationResult,
            snapshot: Snapshot?,
            historicalDiagnostics: PredicateWaitHistoricalDiagnostics
        ) {
            self.stream = stream
            self.initialExpectation = initialExpectation
            self.snapshot = snapshot
            self.historicalDiagnostics = historicalDiagnostics
        }

        internal var evaluation: ExpectationResult {
            snapshot?.expectation ?? initialExpectation
        }

        internal var lastTrace: AccessibilityTrace? {
            snapshot?.observation.trace
        }

        internal var lastObservationSummary: String? {
            snapshot?.observation.summary
        }

        internal var observedSequence: SettledObservationSequence? {
            snapshot?.observation.sequence
        }

        internal var changeBaseline: SettledCapture? {
            snapshot?.baseline
        }

        internal var observationWindow: ObservationWindow? {
            snapshot?.window
        }

        internal var timeoutMismatchMessage: String? {
            historicalDiagnostics.timeoutMismatchMessage
        }

        internal func recording(_ reduction: PredicateObservationStreamReduction) -> LifecycleEvidence {
            LifecycleEvidence(
                stream: reduction.state,
                initialExpectation: initialExpectation,
                snapshot: Snapshot(reduction.reduction),
                historicalDiagnostics: historicalDiagnostics.recording(reduction.reduction)
            )
        }
    }

    internal struct Snapshot: Sendable, Equatable {
        internal let observation: WaitObservation
        internal let expectation: ExpectationResult
        internal let baseline: SettledCapture?
        internal let window: ObservationWindow?

        internal init(_ reduction: PredicateObservationReduction) {
            observation = WaitObservation(
                trace: reduction.trace,
                summary: reduction.observation.summary,
                sequence: reduction.observation.event.sequence
            )
            expectation = reduction.expectation
            baseline = reduction.changeBaseline
            window = reduction.observationWindow
        }
    }

    internal struct WaitObservation: Sendable, Equatable {
        internal let trace: AccessibilityTrace?
        internal let summary: String
        internal let sequence: SettledObservationSequence
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
