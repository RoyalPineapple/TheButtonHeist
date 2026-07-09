#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
import TheScore

internal struct PredicatePollingObservationEvaluation<Evaluation> {
    internal let observation: HeistSemanticObservation
    internal let evaluation: Evaluation
}

internal struct PredicatePollingResult<Evaluation> {
    internal let last: PredicatePollingObservationEvaluation<Evaluation>?
    internal let elapsedMs: Int
}

private struct PredicatePollingCursor<Evaluation> {
    fileprivate var observedSequence: SettledObservationSequence?
    fileprivate var changeBaseline: PredicatePollingChangeBaseline
    fileprivate var last: PredicatePollingObservationEvaluation<Evaluation>?

    fileprivate init(
        observedSequence: SettledObservationSequence?,
        changeBaselineSequence: SettledObservationSequence?,
        requiresChangeBaseline: Bool
    ) {
        self.observedSequence = observedSequence
        self.changeBaseline = PredicatePollingChangeBaseline(
            requiresChangeBaseline: requiresChangeBaseline,
            initialSequence: changeBaselineSequence
        )
    }
}

private enum PredicatePollingChangeBaseline {
    case notRequired
    case awaitingFirstObservation
    case observingSince(SettledObservationSequence)

    fileprivate init(requiresChangeBaseline: Bool, initialSequence: SettledObservationSequence?) {
        guard requiresChangeBaseline else {
            self = .notRequired
            return
        }
        if let initialSequence {
            self = .observingSince(initialSequence)
        } else {
            self = .awaitingFirstObservation
        }
    }

    fileprivate var sequence: SettledObservationSequence? {
        guard case .observingSince(let sequence) = self else { return nil }
        return sequence
    }

    fileprivate mutating func recordObservation(_ observation: HeistSemanticObservation) {
        guard case .awaitingFirstObservation = self else { return }
        self = .observingSince(observation.event.previous?.sequence ?? observation.event.sequence)
    }
}

internal struct PredicatePollingEngine<Evaluation> {
    internal typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        SettledObservationSequence?,
        Double?
    ) async -> HeistSemanticObservation?

    private let observeSemanticState: ObservationSource

    internal init(observeSemanticState: @escaping ObservationSource) {
        self.observeSemanticState = observeSemanticState
    }

    @MainActor
    internal func poll(
        scope: SemanticObservationScope,
        timeout rawTimeout: Double,
        start: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        after initialObservedSequence: SettledObservationSequence? = nil,
        changeBaselineSequence initialChangeBaselineSequence: SettledObservationSequence? = nil,
        requiresChangeBaseline: Bool,
        pollWhenTimeoutZero: Bool = true,
        initialVisibleFingerprint: PredicateVisibleFingerprint = .unknown,
        discoveryBootstrap: PredicateDiscoveryBootstrap = .ifNoObservation,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation,
        isMatched: (Evaluation) -> Bool
    ) async -> PredicatePollingResult<Evaluation> {
        let timeout = PredicateWait.clampedWaitTimeout(rawTimeout)
        let deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
        var cursor = PredicatePollingCursor<Evaluation>(
            observedSequence: initialObservedSequence,
            changeBaselineSequence: initialChangeBaselineSequence,
            requiresChangeBaseline: requiresChangeBaseline
        )
        let reducer = PredicatePollingReducer(
            timeout: timeout,
            pollWhenTimeoutZero: pollWhenTimeoutZero
        )
        var reduction = reducer.start(
            scope: scope,
            initialObservedSequence: initialObservedSequence,
            initialVisibleFingerprint: initialVisibleFingerprint,
            discoveryBootstrap: discoveryBootstrap
        )
        var tickStart = start

        while true {
            switch reduction.effect {
            case .observe(let request):
                if request.kind == .visibleImmediate {
                    tickStart = CFAbsoluteTimeGetCurrent()
                }

                let observed = await pollObservation(
                    request: request,
                    cursor: &cursor,
                    evaluate: evaluate
                )
                let now = CFAbsoluteTimeGetCurrent()
                let timing = PredicatePollingTickTiming(
                    remaining: deadline.remainingSeconds(at: now),
                    elapsed: max(0, now - tickStart)
                )
                let event = pollingEvent(
                    for: request,
                    observed: observed,
                    timing: timing,
                    isMatched: isMatched
                )
                reduction = reducer.reduce(reduction.state, event: event)

            case .sleep(let sleep):
                guard await Self.sleep(sleep) else {
                    reduction = reducer.reduce(reduction.state, event: .sleepCancelled)
                    continue
                }
                reduction = reducer.reduce(
                    reduction.state,
                    event: .sleepCompleted(remaining: deadline.remainingSeconds())
                )

            case .finish:
                return PredicatePollingResult(
                    last: cursor.last,
                    elapsedMs: deadline.elapsedMilliseconds()
                )
            }
        }
    }

    private func pollingEvent(
        for request: PredicatePollingObservationRequest,
        observed: PredicatePollingObservationEvaluation<Evaluation>?,
        timing: PredicatePollingTickTiming,
        isMatched: (Evaluation) -> Bool
    ) -> PredicatePollingEvent {
        switch request.scope {
        case .visible:
            guard let observed else {
                return .visibleUnavailable(timing: timing)
            }
            return .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: observed.observation.event.sequence,
                    fingerprint: PredicateVisibleFingerprint(observed.observation.visibleFingerprint),
                    matched: isMatched(observed.evaluation)
                ),
                timing: timing
            )
        case .discovery:
            guard let observed else {
                return .discoveryUnavailable(timing: timing)
            }
            return .discoveryObserved(
                PredicatePollingDiscoveryObservation(
                    sequence: observed.observation.event.sequence,
                    matched: isMatched(observed.evaluation)
                ),
                timing: timing
            )
        }
    }

    @MainActor
    private func pollObservation(
        request: PredicatePollingObservationRequest,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation
    ) async -> PredicatePollingObservationEvaluation<Evaluation>? {
        guard let observation = await observeSemanticState(
            request.scope,
            request.after,
            request.timeout
        ) else {
            return nil
        }

        cursor.observedSequence = observation.event.sequence
        cursor.changeBaseline.recordObservation(observation)

        let evaluation = evaluate(observation, cursor.changeBaseline.sequence)
        let observed = PredicatePollingObservationEvaluation(
            observation: observation,
            evaluation: evaluation
        )
        cursor.last = observed
        return observed
    }

    private static func sleep(_ sleep: PredicatePollingSleep) async -> Bool {
        guard sleep.duration > 0 else { return true }
        let nanoseconds = UInt64((sleep.duration * 1_000_000_000).rounded(.up))
        return await Task.cancellableSleep(for: .nanoseconds(nanoseconds))
    }
}

extension HeistSemanticObservation {
    internal var visibleFingerprint: String {
        state.screen.visibleOnly.semanticHash
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
