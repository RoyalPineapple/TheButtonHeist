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
    fileprivate var last: PredicatePollingObservationEvaluation<Evaluation>?

    fileprivate init(observedSequence: SettledObservationSequence?) {
        self.observedSequence = observedSequence
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
        pollWhenTimeoutZero: Bool = true,
        initialVisibleFingerprint: PredicateVisibleFingerprint = .unknown,
        discoveryBootstrap: PredicateDiscoveryBootstrap = .ifNoObservation,
        evaluate: (HeistSemanticObservation) -> Evaluation,
        isMatched: (Evaluation) -> Bool
    ) async -> PredicatePollingResult<Evaluation> {
        let timeout = PredicateWait.clampedWaitTimeout(rawTimeout)
        let deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
        var cursor = PredicatePollingCursor<Evaluation>(observedSequence: initialObservedSequence)
        let reducer = PredicatePollingReducer(
            timeout: timeout,
            pollWhenTimeoutZero: pollWhenTimeoutZero
        )
        var step = reducer.start(
            scope: scope,
            initialObservedSequence: initialObservedSequence,
            initialVisibleFingerprint: initialVisibleFingerprint,
            discoveryBootstrap: discoveryBootstrap
        )
        var tickStart = start

        while true {
            switch step {
            case .observeImmediateVisible(let immediate):
                tickStart = CFAbsoluteTimeGetCurrent()
                let observation = await pollVisibleObservation(
                    after: immediate.after,
                    timeout: 0,
                    cursor: &cursor,
                    evaluate: evaluate,
                    isMatched: isMatched
                )
                let now = CFAbsoluteTimeGetCurrent()
                let timing = PredicatePollingTickTiming(
                    remaining: deadline.remainingSeconds(at: now),
                    elapsed: max(0, now - tickStart)
                )
                step = PredicatePollingReducer.observe(
                    immediate,
                    observation: observation,
                    timing: timing
                )

            case .observeSettledVisible(let settled):
                let observation = await pollVisibleObservation(
                    after: settled.after,
                    timeout: settled.timeout,
                    cursor: &cursor,
                    evaluate: evaluate,
                    isMatched: isMatched
                )
                let now = CFAbsoluteTimeGetCurrent()
                let timing = PredicatePollingTickTiming(
                    remaining: deadline.remainingSeconds(at: now),
                    elapsed: max(0, now - tickStart)
                )
                step = PredicatePollingReducer.observe(
                    settled,
                    observation: observation,
                    timing: timing
                )

            case .observeDiscovery(let discovery):
                let observed = await pollObservation(
                    scope: .discovery,
                    after: discovery.after,
                    timeout: discovery.timeout,
                    cursor: &cursor,
                    evaluate: evaluate
                )
                let now = CFAbsoluteTimeGetCurrent()
                let timing = PredicatePollingTickTiming(
                    remaining: deadline.remainingSeconds(at: now),
                    elapsed: max(0, now - tickStart)
                )
                let observation = observed.map {
                    PredicatePollingDiscoveryObservation(
                        sequence: $0.observation.event.sequence,
                        matched: isMatched($0.evaluation)
                    )
                }
                step = PredicatePollingReducer.observe(
                    discovery,
                    observation: observation,
                    timing: timing
                )

            case .sleep(let sleep):
                guard await Self.sleep(for: sleep.duration) else {
                    step = PredicatePollingReducer.resume(sleep, remaining: nil)
                    continue
                }
                step = PredicatePollingReducer.resume(
                    sleep,
                    remaining: deadline.remainingSeconds()
                )

            case .finished:
                return PredicatePollingResult(
                    last: cursor.last,
                    elapsedMs: deadline.elapsedMilliseconds()
                )
            }
        }
    }

    @MainActor
    private func pollVisibleObservation(
        after sequence: SettledObservationSequence?,
        timeout: Double,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation) -> Evaluation,
        isMatched: (Evaluation) -> Bool
    ) async -> PredicatePollingVisibleObservation? {
        await pollObservation(
            scope: .visible,
            after: sequence,
            timeout: timeout,
            cursor: &cursor,
            evaluate: evaluate
        ).map {
            PredicatePollingVisibleObservation(
                sequence: $0.observation.event.sequence,
                fingerprint: PredicateVisibleFingerprint($0.observation.visibleFingerprint),
                matched: isMatched($0.evaluation)
            )
        }
    }

    @MainActor
    private func pollObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation) -> Evaluation
    ) async -> PredicatePollingObservationEvaluation<Evaluation>? {
        guard let observation = await observeSemanticState(
            scope,
            sequence,
            timeout
        ) else {
            return nil
        }

        cursor.observedSequence = observation.event.sequence
        let evaluation = evaluate(observation)
        let observed = PredicatePollingObservationEvaluation(
            observation: observation,
            evaluation: evaluation
        )
        cursor.last = observed
        return observed
    }

    private static func sleep(for duration: Double) async -> Bool {
        guard duration > 0 else { return true }
        let nanoseconds = UInt64((duration * 1_000_000_000).rounded(.up))
        return await Task.cancellableSleep(for: .nanoseconds(nanoseconds))
    }
}

extension HeistSemanticObservation {
    internal var visibleFingerprint: String {
        state.screen.viewportOnly.interfaceHash
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
