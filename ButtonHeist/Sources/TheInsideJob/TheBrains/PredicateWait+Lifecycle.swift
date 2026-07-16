#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
import ThePlans
import TheScore

internal enum PredicateWaitLifecyclePhase: Sendable, Equatable {
    case initialVisible
    case initialDiscovery
    case awaitingObservation
    case triggeredDiscovery
    case terminalVisible
    case terminalDiscovery
    case finished(PredicateWaitLifecycleOutcome)
}

internal struct PredicateWaitLifecycleEvaluation<Evidence>: Sendable, Equatable
where Evidence: Sendable & Equatable {
    internal let evidence: Evidence
    internal let matched: Bool
}

internal enum PredicateWaitLifecycleState<Evidence>: Sendable, Equatable
where Evidence: Sendable & Equatable {
    case initialVisible(Evidence)
    case initialDiscovery(Evidence)
    case awaitingObservation(Evidence)
    case triggeredDiscovery(Evidence)
    case terminalVisible(Evidence)
    case terminalDiscovery(Evidence)
    case finished(PredicateWaitLifecycleOutcome, Evidence)

    internal var phase: PredicateWaitLifecyclePhase {
        switch self {
        case .initialVisible:
            .initialVisible
        case .initialDiscovery:
            .initialDiscovery
        case .awaitingObservation:
            .awaitingObservation
        case .triggeredDiscovery:
            .triggeredDiscovery
        case .terminalVisible:
            .terminalVisible
        case .terminalDiscovery:
            .terminalDiscovery
        case .finished(let outcome, _):
            .finished(outcome)
        }
    }

    internal var evidence: Evidence {
        switch self {
        case .initialVisible(let evidence),
             .initialDiscovery(let evidence),
             .awaitingObservation(let evidence),
             .triggeredDiscovery(let evidence),
             .terminalVisible(let evidence),
             .terminalDiscovery(let evidence),
             .finished(_, let evidence):
            evidence
        }
    }
}

internal enum PredicateWaitLifecycleEvent<Evidence>: Sendable, Equatable
where Evidence: Sendable & Equatable {
    case evaluated(PredicateWaitLifecycleEvaluation<Evidence>)
    case observation(PredicateWaitLifecycleEvaluation<Evidence>)
    case deadlineReached
    case cancelled
}

internal enum PredicateWaitLifecycleEffect: Sendable, Equatable {
    case settleVisible(PredicateWaitVisibleBudget)
    case discover(PredicateWaitDiscoveryBudget)
    case awaitObservation
    case finish(PredicateWaitLifecycleOutcome)
}

internal enum PredicateWaitLifecycleOutcome: Sendable, Equatable {
    case matched
    case timedOut
    case cancelled
}

internal enum PredicateWaitVisibleBudget: Sendable, Equatable {
    case overall
    case viewportTransition

    @MainActor
    internal func deadline(
        overall: SemanticObservationDeadline
    ) -> SemanticObservationDeadline {
        switch self {
        case .overall:
            return overall
        case .viewportTransition:
            return SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutMs: SettleSession.viewportTransitionTimeoutMs
            )
        }
    }
}

internal enum PredicateWaitDiscoveryBudget: Sendable, Equatable {
    case overall
    case unbounded

    internal func deadline(
        overall: SemanticObservationDeadline
    ) -> SemanticObservationDeadline? {
        switch self {
        case .overall:
            return overall
        case .unbounded:
            return nil
        }
    }
}

internal enum PredicateWaitLifecycleSignal: Sendable, Equatable {
    case observation(ObservationEntry)
    case deadlineReached
}

internal enum PredicateWaitLifecycleRejection: Sendable, Equatable {
    case unexpectedEvent
    case alreadyFinished
}

extension PredicateWait {
    internal struct LifecycleEvidence: Sendable, Equatable {
        internal let stream: PredicateObservationStreamState
        private let initialExpectation: ExpectationResult
        private let snapshot: Snapshot?

        internal init(predicate: AccessibilityPredicate) {
            stream = PredicateObservationStreamState()
            initialExpectation = ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "no settled semantic observation available"
            )
            snapshot = nil
        }

        private init(
            stream: PredicateObservationStreamState,
            initialExpectation: ExpectationResult,
            snapshot: Snapshot
        ) {
            self.stream = stream
            self.initialExpectation = initialExpectation
            self.snapshot = snapshot
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

        internal func recording(_ reduction: PredicateObservationStreamReduction) -> LifecycleEvidence {
            LifecycleEvidence(
                stream: reduction.state,
                initialExpectation: initialExpectation,
                snapshot: Snapshot(reduction.reduction)
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

@MainActor
internal func predicateWaitLifecycleSignals(
    observations: ObservationEntrySequence,
    timeout: Double
) -> AsyncStream<PredicateWaitLifecycleSignal> {
    AsyncStream(bufferingPolicy: .unbounded) { continuation in
        let observationTask = Task { @MainActor in
            do {
                for try await observation in observations {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.observation(observation))
                }
            } catch {
                // A lost cursor forces the terminal visible/discovery checks.
                continuation.yield(.deadlineReached)
                continuation.finish()
            }
        }
        let deadlineTask = Task { @MainActor in
            let nanoseconds = UInt64((max(0, timeout) * 1_000_000_000).rounded(.up))
            guard await Task.cancellableSleep(for: .nanoseconds(nanoseconds)) else { return }
            continuation.yield(.deadlineReached)
            continuation.finish()
        }
        continuation.onTermination = { _ in
            observationTask.cancel()
            deadlineTask.cancel()
        }
    }
}

internal struct PredicateWaitLifecycleMachine<Evidence>: SimpleStateMachine, Sendable, Equatable
where Evidence: Sendable & Equatable {
    private let continuesAfterInitialMiss: Bool

    internal init(continuesAfterInitialMiss: Bool) {
        self.continuesAfterInitialMiss = continuesAfterInitialMiss
    }

    internal func advance(
        _ state: PredicateWaitLifecycleState<Evidence>,
        with event: PredicateWaitLifecycleEvent<Evidence>
    ) -> StateChange<
        PredicateWaitLifecycleState<Evidence>,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        switch (state, event) {
        case (.initialVisible, .evaluated(let evaluation)):
            if evaluation.matched {
                return finish(.matched, evidence: evaluation.evidence)
            }
            guard continuesAfterInitialMiss else {
                return finish(.timedOut, evidence: evaluation.evidence)
            }
            return change(
                to: .initialDiscovery(evaluation.evidence),
                effect: .discover(.overall)
            )

        case (.initialDiscovery, .evaluated(let evaluation)):
            return evaluation.matched
                ? finish(.matched, evidence: evaluation.evidence)
                : change(
                    to: .awaitingObservation(evaluation.evidence),
                    effect: .awaitObservation
                )

        case (.awaitingObservation, .observation(let evaluation)):
            return evaluation.matched
                ? finish(.matched, evidence: evaluation.evidence)
                : change(
                    to: .triggeredDiscovery(evaluation.evidence),
                    effect: .discover(.overall)
                )

        case (.awaitingObservation, .deadlineReached):
            return change(
                to: .terminalVisible(state.evidence),
                effect: .settleVisible(.viewportTransition)
            )

        case (.triggeredDiscovery, .evaluated(let evaluation)):
            return evaluation.matched
                ? finish(.matched, evidence: evaluation.evidence)
                : change(
                    to: .awaitingObservation(evaluation.evidence),
                    effect: .awaitObservation
                )

        case (.terminalVisible, .evaluated(let evaluation)):
            return evaluation.matched
                ? finish(.matched, evidence: evaluation.evidence)
                : change(
                    to: .terminalDiscovery(evaluation.evidence),
                    effect: .discover(.unbounded)
                )

        case (.terminalDiscovery, .evaluated(let evaluation)):
            return finish(
                evaluation.matched ? .matched : .timedOut,
                evidence: evaluation.evidence
            )

        case (.finished, _):
            return .rejected(.alreadyFinished, stayingIn: state)

        case (_, .cancelled):
            return finish(.cancelled, evidence: state.evidence)

        default:
            return .rejected(.unexpectedEvent, stayingIn: state)
        }
    }

    private func finish(
        _ outcome: PredicateWaitLifecycleOutcome,
        evidence: Evidence
    ) -> StateChange<
        PredicateWaitLifecycleState<Evidence>,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        change(to: .finished(outcome, evidence), effect: .finish(outcome))
    }

    private func change(
        to state: PredicateWaitLifecycleState<Evidence>,
        effect: PredicateWaitLifecycleEffect
    ) -> StateChange<
        PredicateWaitLifecycleState<Evidence>,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        .changed(to: state, effects: [effect])
    }
}

internal extension StateChange
where Effect == PredicateWaitLifecycleEffect,
      Rejection == PredicateWaitLifecycleRejection {
    var predicateWaitEffect: PredicateWaitLifecycleEffect {
        guard let effect = singleEffect else {
            preconditionFailure("PredicateWaitLifecycleMachine must emit exactly one effect")
        }
        return effect
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
