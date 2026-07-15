#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

internal enum PredicateWaitLifecycleState: Sendable, Equatable {
    case initialVisible
    case initialDiscovery
    case awaitingObservation
    case triggeredDiscovery
    case terminalVisible
    case terminalDiscovery
    case finished(PredicateWaitLifecycleOutcome)
}

internal enum PredicateWaitLifecycleEvent: Sendable, Equatable {
    case evaluated(matched: Bool)
    case observation(matched: Bool)
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

internal struct PredicateWaitLifecycleMachine: SimpleStateMachine, Sendable, Equatable {
    internal func advance(
        _ state: PredicateWaitLifecycleState,
        with event: PredicateWaitLifecycleEvent
    ) -> StateChange<
        PredicateWaitLifecycleState,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        switch (state, event) {
        case (.initialVisible, .evaluated(let matched)):
            return matched
                ? finish(.matched)
                : change(to: .initialDiscovery, effect: .discover(.overall))

        case (.initialDiscovery, .evaluated(let matched)):
            return matched
                ? finish(.matched)
                : change(to: .awaitingObservation, effect: .awaitObservation)

        case (.awaitingObservation, .observation(let matched)):
            return matched
                ? finish(.matched)
                : change(to: .triggeredDiscovery, effect: .discover(.overall))

        case (.awaitingObservation, .deadlineReached):
            return change(to: .terminalVisible, effect: .settleVisible(.viewportTransition))

        case (.triggeredDiscovery, .evaluated(let matched)):
            return matched
                ? finish(.matched)
                : change(to: .awaitingObservation, effect: .awaitObservation)

        case (.terminalVisible, .evaluated(let matched)):
            return matched
                ? finish(.matched)
                : change(to: .terminalDiscovery, effect: .discover(.unbounded))

        case (.terminalDiscovery, .evaluated(let matched)):
            return finish(matched ? .matched : .timedOut)

        case (.finished, _):
            return .rejected(.alreadyFinished, stayingIn: state)

        case (_, .cancelled):
            return finish(.cancelled)

        default:
            return .rejected(.unexpectedEvent, stayingIn: state)
        }
    }

    private func finish(
        _ outcome: PredicateWaitLifecycleOutcome
    ) -> StateChange<
        PredicateWaitLifecycleState,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        change(to: .finished(outcome), effect: .finish(outcome))
    }

    private func change(
        to state: PredicateWaitLifecycleState,
        effect: PredicateWaitLifecycleEffect
    ) -> StateChange<
        PredicateWaitLifecycleState,
        PredicateWaitLifecycleEffect,
        PredicateWaitLifecycleRejection
    > {
        .changed(to: state, effects: [effect])
    }
}

internal extension StateChange
where State == PredicateWaitLifecycleState,
      Effect == PredicateWaitLifecycleEffect,
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
