#if canImport(UIKit)
#if DEBUG
import TheScore

struct PredicatePollingReducer: Sendable, Equatable {
    let timeout: Double
    let pollWhenTimeoutZero: Bool

    func start(
        scope: SemanticObservationScope,
        initialObservedSequence: SettledObservationSequence?,
        initialVisibleFingerprint: PredicateVisibleFingerprint = .unknown,
        discoveryBootstrap: PredicateDiscoveryBootstrap = .ifNoObservation
    ) -> PredicatePollingReduction {
        let state = PredicatePollingState(
            observedSequence: initialObservedSequence,
            initialVisibleFingerprint: initialVisibleFingerprint,
            scope: scope,
            needsInitialProbe: discoveryBootstrap.needsInitialProbe(
                initialObservedSequence: initialObservedSequence
            )
        )

        guard timeout > 0 || pollWhenTimeoutZero else {
            return finish(state, reason: .notPolled)
        }
        return beginVisibleTick(state)
    }

    func reduce(
        _ state: PredicatePollingState,
        event: PredicatePollingEvent
    ) -> PredicatePollingReduction {
        switch event {
        case .visibleObserved(let observation, let timing):
            return reduceVisibleObserved(observation, timing: timing, state: state)
        case .visibleUnavailable(let timing):
            return reduceVisibleUnavailable(timing: timing, state: state)
        case .discoveryObserved(let observation, let timing):
            return reduceDiscoveryObserved(observation, timing: timing, state: state)
        case .discoveryUnavailable(let timing):
            return reduceDiscoveryUnavailable(timing: timing, state: state)
        case .sleepCompleted(let remaining):
            guard timeout > 0, remaining > 0 else {
                return finish(state, reason: .timedOut)
            }
            return beginVisibleTick(state)
        case .sleepCancelled:
            return finish(state, reason: .cancelled)
        }
    }

    private func beginVisibleTick(_ state: PredicatePollingState) -> PredicatePollingReduction {
        var nextState = state
        let context = PredicateVisibleTickContext(
            allowSettledWait: timeout > 0 && nextState.nextProbe != .discovery
        )
        nextState.beginImmediateVisibleTick(context)
        return reduction(
            to: nextState,
            effect: .observe(.visibleImmediate(after: nextState.observedSequence))
        )
    }

    private func reduceVisibleObserved(
        _ observation: PredicatePollingVisibleObservation,
        timing: PredicatePollingTickTiming,
        state: PredicatePollingState
    ) -> PredicatePollingReduction {
        var nextState = state
        nextState.recordObservedSequence(observation.sequence)

        switch nextState.phase {
        case .awaitingImmediateVisible(let context):
            if observation.matched {
                return finishAfterVisibleTick(
                    .observed(fingerprint: observation.fingerprint, matched: true),
                    state: nextState,
                    timing: timing
                )
            }
            guard context.allowSettledWait, timing.remaining > 0 else {
                return finishAfterVisibleTick(
                    .observed(fingerprint: observation.fingerprint, matched: false),
                    state: nextState,
                    timing: timing
                )
            }
            nextState.beginSettledVisibleTick(
                PredicatePendingVisibleTick(
                    immediateObservation: observation
                )
            )
            return reduction(
                to: nextState,
                effect: .observe(.visibleSettled(
                    after: nextState.observedSequence,
                    timeout: visibleSettledTimeout(remaining: timing.remaining)
                ))
            )

        case .awaitingSettledVisible:
            return finishAfterVisibleTick(
                .observed(fingerprint: observation.fingerprint, matched: observation.matched),
                state: nextState,
                timing: timing
            )

        case .idle, .awaitingDiscovery, .sleeping, .finished:
            return reduction(to: nextState, effect: .finish(.timedOut))
        }
    }

    private func reduceVisibleUnavailable(
        timing: PredicatePollingTickTiming,
        state: PredicatePollingState
    ) -> PredicatePollingReduction {
        var nextState = state
        switch nextState.phase {
        case .awaitingImmediateVisible(let context):
            guard context.allowSettledWait, timing.remaining > 0 else {
                return finishAfterVisibleTick(.unavailable, state: nextState, timing: timing)
            }
            nextState.beginSettledVisibleTick(
                PredicatePendingVisibleTick(
                    immediateObservation: nil
                )
            )
            return reduction(
                to: nextState,
                effect: .observe(.visibleSettled(
                    after: nextState.observedSequence,
                    timeout: visibleSettledTimeout(remaining: timing.remaining)
                ))
            )

        case .awaitingSettledVisible(let pending):
            if let immediate = pending.immediateObservation {
                return finishAfterVisibleTick(
                    .observed(fingerprint: immediate.fingerprint, matched: immediate.matched),
                    state: nextState,
                    timing: timing
                )
            }
            return finishAfterVisibleTick(.unavailable, state: nextState, timing: timing)

        case .idle, .awaitingDiscovery, .sleeping, .finished:
            return reduction(to: nextState, effect: .finish(.timedOut))
        }
    }

    private func finishAfterVisibleTick(
        _ tick: PredicateVisibleTick,
        state: PredicatePollingState,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingReduction {
        var nextState = state
        nextState.recordVisibleTick(tick)

        if case .observed(_, let matched) = tick, matched {
            return finish(nextState, reason: .matched)
        }

        guard nextState.nextProbe == .discovery else {
            return continueAfterTick(nextState, timing: timing)
        }

        nextState.beginDiscoveryProbe()
        return reduction(
            to: nextState,
            effect: .observe(.discovery(
                after: nextState.observedSequence,
                timeout: discoveryTimeout(remaining: timing.remaining)
            ))
        )
    }

    private func reduceDiscoveryObserved(
        _ observation: PredicatePollingDiscoveryObservation,
        timing: PredicatePollingTickTiming,
        state: PredicatePollingState
    ) -> PredicatePollingReduction {
        var nextState = state
        nextState.recordObservedSequence(observation.sequence)
        nextState.recordDiscoveryProbe()

        if observation.matched {
            return finish(nextState, reason: .matched)
        }
        return continueAfterTick(nextState, timing: timing)
    }

    private func reduceDiscoveryUnavailable(
        timing: PredicatePollingTickTiming,
        state: PredicatePollingState
    ) -> PredicatePollingReduction {
        continueAfterTick(state, timing: timing)
    }

    private func continueAfterTick(
        _ state: PredicatePollingState,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingReduction {
        guard timeout > 0 else {
            return finish(state, reason: .timedOut)
        }
        guard timing.remaining > 0 else {
            return finish(state, reason: .timedOut)
        }

        let sleepSeconds = min(
            timing.remaining,
            max(0, SemanticObservationTiming.visibleTickIntervalSeconds - timing.elapsed)
        )
        guard sleepSeconds > 0 else {
            return beginVisibleTick(state)
        }

        var nextState = state
        nextState.beginSleep()
        return reduction(
            to: nextState,
            effect: .sleep(PredicatePollingSleep(duration: sleepSeconds))
        )
    }

    private func finish(
        _ state: PredicatePollingState,
        reason: PredicatePollingFinish
    ) -> PredicatePollingReduction {
        var nextState = state
        nextState.finish()
        return reduction(to: nextState, effect: .finish(reason))
    }

    private func reduction(
        to state: PredicatePollingState,
        effect: PredicatePollingEffect
    ) -> PredicatePollingReduction {
        PredicatePollingReduction(state: state, effect: effect)
    }

    private func visibleSettledTimeout(remaining: Double) -> Double {
        min(remaining, SemanticObservationTiming.visibleTickIntervalSeconds)
    }

    private func discoveryTimeout(remaining: Double) -> Double {
        min(max(0, remaining), SemanticObservationTiming.defaultTimeout)
    }
}

struct PredicatePollingReduction: Sendable, Equatable {
    let state: PredicatePollingState
    let effect: PredicatePollingEffect
}

enum PredicatePollingEffect: Sendable, Equatable {
    case observe(PredicatePollingObservationRequest)
    case sleep(PredicatePollingSleep)
    case finish(PredicatePollingFinish)
}

enum PredicatePollingFinish: Sendable, Equatable {
    case matched
    case timedOut
    case cancelled
    case notPolled
}

struct PredicatePollingObservationRequest: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case visibleImmediate
        case visibleSettled
        case discovery
    }

    let kind: Kind
    let scope: SemanticObservationScope
    let after: SettledObservationSequence?
    let timeout: Double?

    static func visibleImmediate(after sequence: SettledObservationSequence?) -> PredicatePollingObservationRequest {
        PredicatePollingObservationRequest(
            kind: .visibleImmediate,
            scope: .visible,
            after: sequence,
            timeout: 0
        )
    }

    static func visibleSettled(
        after sequence: SettledObservationSequence?,
        timeout: Double
    ) -> PredicatePollingObservationRequest {
        PredicatePollingObservationRequest(
            kind: .visibleSettled,
            scope: .visible,
            after: sequence,
            timeout: timeout
        )
    }

    static func discovery(
        after sequence: SettledObservationSequence?,
        timeout: Double
    ) -> PredicatePollingObservationRequest {
        PredicatePollingObservationRequest(
            kind: .discovery,
            scope: .discovery,
            after: sequence,
            timeout: timeout
        )
    }
}

struct PredicatePollingSleep: Sendable, Equatable {
    let duration: Double
}

enum PredicatePollingEvent: Sendable, Equatable {
    case visibleObserved(PredicatePollingVisibleObservation, timing: PredicatePollingTickTiming)
    case visibleUnavailable(timing: PredicatePollingTickTiming)
    case discoveryObserved(PredicatePollingDiscoveryObservation, timing: PredicatePollingTickTiming)
    case discoveryUnavailable(timing: PredicatePollingTickTiming)
    case sleepCompleted(remaining: Double)
    case sleepCancelled
}

struct PredicatePollingTickTiming: Sendable, Equatable {
    let remaining: Double
    let elapsed: Double

    init(remaining: Double, elapsed: Double) {
        self.remaining = max(0, remaining)
        self.elapsed = max(0, elapsed)
    }
}

struct PredicatePollingVisibleObservation: Sendable, Equatable {
    let sequence: SettledObservationSequence
    let fingerprint: PredicateVisibleFingerprint
    let matched: Bool
}

struct PredicatePollingDiscoveryObservation: Sendable, Equatable {
    let sequence: SettledObservationSequence
    let matched: Bool
}

enum PredicatePollingCadence {
    static let discoveryProbeIntervalVisibleTicks = 5
}

enum PredicateDiscoveryBootstrap: Sendable, Equatable {
    case ifNoObservation
    case afterInitialDiscoveryAttempt

    func needsInitialProbe(
        initialObservedSequence: SettledObservationSequence?
    ) -> Bool {
        switch self {
        case .ifNoObservation:
            return initialObservedSequence == nil
        case .afterInitialDiscoveryAttempt:
            return false
        }
    }
}

enum PredicateNextProbe: Sendable, Equatable {
    case visible
    case discovery
}

enum PredicateVisibleTick: Sendable, Equatable {
    case unavailable
    case observed(fingerprint: PredicateVisibleFingerprint, matched: Bool)
}

struct PredicatePollingState: Sendable, Equatable {
    fileprivate var observedSequence: SettledObservationSequence?
    fileprivate var probeState: PredicatePollingProbeState
    fileprivate var phase: PredicatePollingPhase

    init(
        observedSequence: SettledObservationSequence?,
        initialVisibleFingerprint: PredicateVisibleFingerprint,
        scope: SemanticObservationScope,
        needsInitialProbe: Bool
    ) {
        self.observedSequence = observedSequence
        switch scope {
        case .visible:
            self.probeState = .viewportOnly
        case .discovery:
            self.probeState = .discovery(needsInitialProbe
                ? .probeDue(fingerprint: initialVisibleFingerprint, visibleTicksSinceProbe: .zero)
                : .coolingDown(fingerprint: initialVisibleFingerprint, visibleTicksSinceProbe: .zero))
        }
        self.phase = .idle
    }

    var nextProbe: PredicateNextProbe {
        switch probeState {
        case .viewportOnly:
            return .visible
        case .discovery(let discovery):
            return discovery.nextProbe
        }
    }

    fileprivate mutating func beginImmediateVisibleTick(_ context: PredicateVisibleTickContext) {
        phase = .awaitingImmediateVisible(context)
    }

    fileprivate mutating func beginSettledVisibleTick(_ pending: PredicatePendingVisibleTick) {
        phase = .awaitingSettledVisible(pending)
    }

    fileprivate mutating func beginDiscoveryProbe() {
        phase = .awaitingDiscovery
    }

    fileprivate mutating func beginSleep() {
        phase = .sleeping
    }

    fileprivate mutating func finish() {
        phase = .finished
    }

    fileprivate mutating func recordObservedSequence(_ sequence: SettledObservationSequence) {
        observedSequence = sequence
    }

    fileprivate mutating func recordVisibleTick(_ tick: PredicateVisibleTick) {
        guard case .discovery(let discovery) = probeState else { return }
        probeState = .discovery(discovery.afterVisibleTick(tick))
    }

    fileprivate mutating func recordDiscoveryProbe() {
        guard case .discovery(let discovery) = probeState else { return }
        probeState = .discovery(discovery.afterDiscoveryProbe())
    }
}

private enum PredicatePollingProbeState: Sendable, Equatable {
    case viewportOnly
    case discovery(PredicateDiscoveryPollingState)
}

private enum PredicatePollingPhase: Sendable, Equatable {
    case idle
    case awaitingImmediateVisible(PredicateVisibleTickContext)
    case awaitingSettledVisible(PredicatePendingVisibleTick)
    case awaitingDiscovery
    case sleeping
    case finished
}

private struct PredicateVisibleTickContext: Sendable, Equatable {
    let allowSettledWait: Bool
}

private struct PredicatePendingVisibleTick: Sendable, Equatable {
    let immediateObservation: PredicatePollingVisibleObservation?
}

enum PredicateDiscoveryPollingState: Sendable, Equatable {
    case probeDue(fingerprint: PredicateVisibleFingerprint, visibleTicksSinceProbe: PredicateVisibleTickCount)
    case coolingDown(fingerprint: PredicateVisibleFingerprint, visibleTicksSinceProbe: PredicateVisibleTickCount)

    var nextProbe: PredicateNextProbe {
        switch self {
        case .probeDue:
            return .discovery
        case .coolingDown:
            return .visible
        }
    }

    func afterVisibleTick(_ tick: PredicateVisibleTick) -> PredicateDiscoveryPollingState {
        switch tick {
        case .unavailable:
            return afterVisibleUnavailable()
        case .observed(let nextFingerprint, let matched):
            return afterVisibleObserved(nextFingerprint: nextFingerprint, matched: matched)
        }
    }

    func afterDiscoveryProbe() -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let fingerprint, _),
             .coolingDown(let fingerprint, _):
            return .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: .zero)
        }
    }

    private func afterVisibleUnavailable() -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let fingerprint, let ticks):
            return .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: ticks.incremented())
        case .coolingDown(let fingerprint, let ticks):
            let nextTicks = ticks.incremented()
            return nextTicks.reachedDiscoveryProbeCadence
                ? .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
                : .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
        }
    }

    private func afterVisibleObserved(
        nextFingerprint observedFingerprint: PredicateVisibleFingerprint,
        matched: Bool
    ) -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let previousFingerprint, let ticks):
            let fingerprint = observedFingerprint.replacingUnknown(with: previousFingerprint)
            return matched
                ? .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: .zero)
                : .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: ticks.incremented())

        case .coolingDown(let previousFingerprint, let ticks):
            let fingerprint = observedFingerprint.replacingUnknown(with: previousFingerprint)
            guard !matched else {
                return .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: .zero)
            }
            let nextTicks = ticks.incremented()
            if observedFingerprint != previousFingerprint,
               case .known = observedFingerprint {
                return .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
            }
            return nextTicks.reachedDiscoveryProbeCadence
                ? .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
                : .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
        }
    }
}

struct PredicateVisibleTickCount: Sendable, Equatable {
    static let zero = PredicateVisibleTickCount(rawValue: 0)

    private let rawValue: Int

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    func incremented() -> PredicateVisibleTickCount {
        PredicateVisibleTickCount(rawValue: rawValue + 1)
    }

    var reachedDiscoveryProbeCadence: Bool {
        rawValue >= PredicatePollingCadence.discoveryProbeIntervalVisibleTicks
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
