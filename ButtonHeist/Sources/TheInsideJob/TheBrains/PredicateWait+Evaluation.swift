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
        private let continuitySnapshot: Snapshot?
        internal let continuity: EvidenceContinuity.WaitEvidence?
        private let historicalDiagnostics: PredicateWaitHistoricalDiagnostics

        internal init(
            predicate: AccessibilityPredicate,
            continuity: EvidenceContinuity.WaitEvidence? = nil,
            historicalDiagnosticsRequest: HistoricalWaitDiagnostics.Request? = nil,
            target: ResolvedAccessibilityTarget? = nil
        ) {
            stream = PredicateObservationStreamState()
            initialExpectation = ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "no settled semantic observation available"
            )
            snapshot = nil
            continuitySnapshot = nil
            self.continuity = continuity
            historicalDiagnostics = PredicateWaitHistoricalDiagnostics(
                request: historicalDiagnosticsRequest,
                target: target
            )
        }

        private init(
            stream: PredicateObservationStreamState,
            initialExpectation: ExpectationResult,
            snapshot: Snapshot?,
            continuitySnapshot: Snapshot?,
            continuity: EvidenceContinuity.WaitEvidence?,
            historicalDiagnostics: PredicateWaitHistoricalDiagnostics
        ) {
            self.stream = stream
            self.initialExpectation = initialExpectation
            self.snapshot = snapshot
            self.continuitySnapshot = continuitySnapshot
            self.continuity = continuity
            self.historicalDiagnostics = historicalDiagnostics
        }

        internal var evaluation: ExpectationResult {
            continuitySnapshot?.expectation ?? currentEvaluation
        }

        internal var currentEvaluation: ExpectationResult {
            snapshot?.expectation ?? initialExpectation
        }

        internal var lastTrace: AccessibilityTrace? {
            (continuitySnapshot ?? snapshot)?.observation.trace
        }

        internal var lastObservationSummary: String? {
            (continuitySnapshot ?? snapshot)?.observation.summary
        }

        internal var observedSequence: SettledObservationSequence? {
            (continuitySnapshot ?? snapshot)?.observation.sequence
        }

        internal var changeBaseline: SettledCapture? {
            (continuitySnapshot ?? snapshot)?.baseline
        }

        internal var observationWindow: ObservationWindow? {
            (continuitySnapshot ?? snapshot)?.window
        }

        internal var continuityIsApplied: Bool {
            guard let continuity else { return false }
            if case .applied = continuity.status { return true }
            return false
        }

        internal var historicalWaitDiagnostics: HistoricalWaitDiagnostics.Evidence? {
            historicalDiagnostics.evidence
        }

        internal func recording(_ reduction: PredicateObservationStreamReduction) -> LifecycleEvidence {
            LifecycleEvidence(
                stream: reduction.state,
                initialExpectation: initialExpectation,
                snapshot: Snapshot(reduction.reduction),
                continuitySnapshot: nil,
                continuity: continuity,
                historicalDiagnostics: historicalDiagnostics.recording(reduction.reduction)
            )
        }

        internal func recordingCurrentContinuityMatch(
            observedThrough: EvidenceContinuity.Position?
        ) -> LifecycleEvidence {
            LifecycleEvidence(
                stream: stream,
                initialExpectation: initialExpectation,
                snapshot: snapshot,
                continuitySnapshot: nil,
                continuity: continuity?.recordingCurrentMatch(observedThrough: observedThrough),
                historicalDiagnostics: historicalDiagnostics
            )
        }

        internal func recording(
            _ evaluation: PredicateContinuityChangeEvaluation,
            fallbackReason: EvidenceContinuity.FallbackReason
        ) -> LifecycleEvidence {
            switch evaluation {
            case .matched(let observation, let expectation, let window, let match, let observedThrough):
                return LifecycleEvidence(
                    stream: stream,
                    initialExpectation: initialExpectation,
                    snapshot: snapshot,
                    continuitySnapshot: Snapshot(
                        observation: observation,
                        expectation: expectation,
                        baseline: window.baseline,
                        window: window
                    ),
                    continuity: continuity?.recordingApplied(
                        observedThrough: observedThrough,
                        match: match
                    ),
                    historicalDiagnostics: historicalDiagnostics
                )
            case .unmatched(let observedThrough):
                return LifecycleEvidence(
                    stream: stream,
                    initialExpectation: initialExpectation,
                    snapshot: snapshot,
                    continuitySnapshot: nil,
                    continuity: continuity?.recordingApplied(observedThrough: observedThrough),
                    historicalDiagnostics: historicalDiagnostics
                )
            case .fallback:
                return LifecycleEvidence(
                    stream: stream,
                    initialExpectation: initialExpectation,
                    snapshot: snapshot,
                    continuitySnapshot: nil,
                    continuity: EvidenceContinuity.WaitEvidence(
                        status: .fallback(reason: fallbackReason)
                    ),
                    historicalDiagnostics: historicalDiagnostics
                )
            }
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

        internal init(
            observation: SettledObservationEvidence,
            expectation: ExpectationResult,
            baseline: SettledCapture,
            window: ObservationWindow
        ) {
            self.observation = WaitObservation(
                trace: window.trace,
                summary: observation.summary,
                sequence: window.current.cursor.sequence
            )
            self.expectation = expectation
            self.baseline = baseline
            self.window = window
        }
    }

    internal struct WaitObservation: Sendable, Equatable {
        internal let trace: AccessibilityTrace?
        internal let summary: String
        internal let sequence: SettledObservationSequence
    }
}

private extension EvidenceContinuity.WaitEvidence {
    func recordingCurrentMatch(
        observedThrough: EvidenceContinuity.Position?
    ) -> EvidenceContinuity.WaitEvidence {
        switch status {
        case .applied:
            return EvidenceContinuity.WaitEvidence(
                status: status,
                match: .current,
                actionBoundary: actionBoundary,
                observedThrough: observedThrough ?? self.observedThrough
            )
        case .fallback, .ineligible, .notProvided:
            return EvidenceContinuity.WaitEvidence(status: status, match: .current)
        }
    }

    func recordingApplied(
        observedThrough: EvidenceContinuity.Position,
        match: EvidenceContinuity.MatchSource? = nil
    ) -> EvidenceContinuity.WaitEvidence {
        precondition(continuityStatusIsApplied)
        return EvidenceContinuity.WaitEvidence(
            status: status,
            match: match,
            actionBoundary: actionBoundary,
            observedThrough: observedThrough
        )
    }

    private var continuityStatusIsApplied: Bool {
        if case .applied = status { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
