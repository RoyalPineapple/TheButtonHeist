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
    ) -> PredicatePollingStep {
        let state = PredicatePollingState(
            observedSequence: initialObservedSequence,
            initialVisibleFingerprint: initialVisibleFingerprint,
            scope: scope,
            needsInitialProbe: discoveryBootstrap.needsInitialProbe(
                initialObservedSequence: initialObservedSequence
            ),
            timeout: timeout
        )

        guard timeout > 0 || pollWhenTimeoutZero else {
            return Self.finish(.notPolled)
        }
        return Self.beginVisibleTick(state)
    }

    static func observe(
        _ step: PredicatePollingImmediateVisibleStep,
        observation: PredicatePollingVisibleObservation?,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingStep {
        var state = step.state
        if let observation {
            state.recordObservedSequence(observation.sequence)
        }

        if let observation, observation.matched {
            return finishAfterVisibleTick(
                observation.visibleTick,
                state: state,
                timing: timing
            )
        }
        guard step.allowSettledWait, timing.remaining > 0 else {
            return finishAfterVisibleTick(
                observation.visibleTick,
                state: state,
                timing: timing
            )
        }
        return .observeSettledVisible(PredicatePollingSettledVisibleStep(
            state: state,
            immediateObservation: observation,
            timeout: visibleSettledTimeout(remaining: timing.remaining)
        ))
    }

    static func observe(
        _ step: PredicatePollingSettledVisibleStep,
        observation: PredicatePollingVisibleObservation?,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingStep {
        var state = step.state
        if let observation {
            state.recordObservedSequence(observation.sequence)
        }
        return finishAfterVisibleTick(
            observation?.visibleTick ?? step.immediateObservation.visibleTick,
            state: state,
            timing: timing
        )
    }

    static func observe(
        _ step: PredicatePollingDiscoveryStep,
        observation: PredicatePollingDiscoveryObservation?,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingStep {
        var state = step.state
        guard let observation else {
            return continueAfterTick(state, timing: timing)
        }
        state.recordObservedSequence(observation.sequence)
        state.recordDiscoveryProbe()

        guard !observation.matched else {
            return finish(.matched)
        }
        return continueAfterTick(state, timing: timing)
    }

    static func resume(
        _ step: PredicatePollingSleepStep,
        remaining: Double?
    ) -> PredicatePollingStep {
        guard let remaining else {
            return finish(.cancelled)
        }
        guard step.state.timeout > 0, remaining > 0 else {
            return finish(.timedOut)
        }
        return beginVisibleTick(step.state)
    }

    private static func beginVisibleTick(_ state: PredicatePollingState) -> PredicatePollingStep {
        .observeImmediateVisible(PredicatePollingImmediateVisibleStep(state: state))
    }

    private static func finishAfterVisibleTick(
        _ tick: PredicateVisibleTick,
        state: PredicatePollingState,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingStep {
        var nextState = state
        nextState.recordVisibleTick(tick)

        if case .observed(_, let matched) = tick, matched {
            return finish(.matched)
        }

        guard nextState.nextProbe == .discovery else {
            return continueAfterTick(nextState, timing: timing)
        }

        return .observeDiscovery(PredicatePollingDiscoveryStep(
            state: nextState,
            timeout: discoveryTimeout(remaining: timing.remaining)
        ))
    }

    private static func continueAfterTick(
        _ state: PredicatePollingState,
        timing: PredicatePollingTickTiming
    ) -> PredicatePollingStep {
        guard state.timeout > 0 else {
            return finish(.timedOut)
        }
        guard timing.remaining > 0 else {
            return finish(.timedOut)
        }

        let sleepSeconds = min(
            timing.remaining,
            max(0, SemanticObservationTiming.visibleTickIntervalSeconds - timing.elapsed)
        )
        guard sleepSeconds > 0 else {
            return beginVisibleTick(state)
        }

        return .sleep(PredicatePollingSleepStep(state: state, duration: sleepSeconds))
    }

    private static func finish(_ reason: PredicatePollingFinish) -> PredicatePollingStep {
        .finished(reason)
    }

    private static func visibleSettledTimeout(remaining: Double) -> Double {
        min(remaining, SemanticObservationTiming.visibleTickIntervalSeconds)
    }

    private static func discoveryTimeout(remaining: Double) -> Double {
        min(max(0, remaining), SemanticObservationTiming.defaultTimeout)
    }
}

enum PredicatePollingStep: Sendable, Equatable {
    case observeImmediateVisible(PredicatePollingImmediateVisibleStep)
    case observeSettledVisible(PredicatePollingSettledVisibleStep)
    case observeDiscovery(PredicatePollingDiscoveryStep)
    case sleep(PredicatePollingSleepStep)
    case finished(PredicatePollingFinish)
}

enum PredicatePollingFinish: Sendable, Equatable {
    case matched
    case timedOut
    case cancelled
    case notPolled
}

struct PredicatePollingImmediateVisibleStep: Sendable, Equatable {
    fileprivate let state: PredicatePollingState

    var after: SettledObservationSequence? {
        state.observedSequence
    }

    fileprivate var allowSettledWait: Bool {
        state.timeout > 0 && state.nextProbe != .discovery
    }

    fileprivate init(state: PredicatePollingState) {
        self.state = state
    }
}

struct PredicatePollingSettledVisibleStep: Sendable, Equatable {
    let timeout: Double
    fileprivate let state: PredicatePollingState
    fileprivate let immediateObservation: PredicatePollingVisibleObservation?

    var after: SettledObservationSequence? {
        state.observedSequence
    }

    fileprivate init(
        state: PredicatePollingState,
        immediateObservation: PredicatePollingVisibleObservation?,
        timeout: Double
    ) {
        self.state = state
        self.immediateObservation = immediateObservation
        self.timeout = timeout
    }
}

struct PredicatePollingDiscoveryStep: Sendable, Equatable {
    let timeout: Double
    fileprivate let state: PredicatePollingState

    var after: SettledObservationSequence? {
        state.observedSequence
    }

    fileprivate init(state: PredicatePollingState, timeout: Double) {
        self.state = state
        self.timeout = timeout
    }
}

struct PredicatePollingSleepStep: Sendable, Equatable {
    let duration: Double
    fileprivate let state: PredicatePollingState

    fileprivate init(state: PredicatePollingState, duration: Double) {
        self.state = state
        self.duration = duration
    }
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

private struct PredicatePollingState: Sendable, Equatable {
    fileprivate var observedSequence: SettledObservationSequence?
    fileprivate var probeState: PredicatePollingProbeState
    fileprivate let timeout: Double

    init(
        observedSequence: SettledObservationSequence?,
        initialVisibleFingerprint: PredicateVisibleFingerprint,
        scope: SemanticObservationScope,
        needsInitialProbe: Bool,
        timeout: Double
    ) {
        self.observedSequence = observedSequence
        self.timeout = timeout
        switch scope {
        case .visible:
            probeState = .viewportOnly
        case .discovery:
            probeState = .discovery(needsInitialProbe
                ? .probeDue(PredicateDiscoveryProbeDue(
                    fingerprint: initialVisibleFingerprint,
                    visibleTicksSinceProbe: .zero
                ))
                : .coolingDown(PredicateDiscoveryCooldown(
                    fingerprint: initialVisibleFingerprint,
                    visibleTicksSinceProbe: .zero
                )))
        }
    }

    var nextProbe: PredicateNextProbe {
        switch probeState {
        case .viewportOnly:
            return .visible
        case .discovery(let discovery):
            return discovery.nextProbe
        }
    }

    fileprivate mutating func recordObservedSequence(_ sequence: SettledObservationSequence) {
        observedSequence = sequence
    }

    fileprivate mutating func recordVisibleTick(_ tick: PredicateVisibleTick) {
        guard case .discovery(let discovery) = probeState else { return }
        probeState = .discovery(discovery.afterVisibleTick(tick))
    }

    fileprivate mutating func recordDiscoveryProbe() {
        guard case .discovery(.probeDue(let probe)) = probeState else {
            preconditionFailure("A discovery result requires a probe-due polling state")
        }
        probeState = .discovery(.coolingDown(probe.afterDiscoveryProbe()))
    }
}

private enum PredicatePollingProbeState: Sendable, Equatable {
    case viewportOnly
    case discovery(PredicateDiscoveryPollingState)
}

private extension Optional where Wrapped == PredicatePollingVisibleObservation {
    var visibleTick: PredicateVisibleTick {
        switch self {
        case .some(let observation):
            return observation.visibleTick
        case .none:
            return .unavailable
        }
    }
}

private extension PredicatePollingVisibleObservation {
    var visibleTick: PredicateVisibleTick {
        .observed(fingerprint: fingerprint, matched: matched)
    }
}

private enum PredicateDiscoveryPollingState: Sendable, Equatable {
    case probeDue(PredicateDiscoveryProbeDue)
    case coolingDown(PredicateDiscoveryCooldown)

    var nextProbe: PredicateNextProbe {
        switch self {
        case .probeDue:
            return .discovery
        case .coolingDown:
            return .visible
        }
    }

    fileprivate func afterVisibleTick(_ tick: PredicateVisibleTick) -> PredicateDiscoveryPollingState {
        switch tick {
        case .unavailable:
            return afterVisibleUnavailable()
        case .observed(let nextFingerprint, let matched):
            return afterVisibleObserved(nextFingerprint: nextFingerprint, matched: matched)
        }
    }

    private func afterVisibleUnavailable() -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let probe):
            return .probeDue(probe.recordingUnavailableVisibleTick())
        case .coolingDown(let cooldown):
            let nextTicks = cooldown.visibleTicksSinceProbe.incremented()
            return nextTicks.reachedDiscoveryProbeCadence
                ? .probeDue(PredicateDiscoveryProbeDue(
                    fingerprint: cooldown.fingerprint,
                    visibleTicksSinceProbe: nextTicks
                ))
                : .coolingDown(PredicateDiscoveryCooldown(
                    fingerprint: cooldown.fingerprint,
                    visibleTicksSinceProbe: nextTicks
                ))
        }
    }

    private func afterVisibleObserved(
        nextFingerprint observedFingerprint: PredicateVisibleFingerprint,
        matched: Bool
    ) -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let probe):
            let fingerprint = observedFingerprint.replacingUnknown(with: probe.fingerprint)
            return matched
                ? .coolingDown(PredicateDiscoveryCooldown(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: .zero
                ))
                : .probeDue(PredicateDiscoveryProbeDue(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: probe.visibleTicksSinceProbe.incremented()
                ))

        case .coolingDown(let cooldown):
            let fingerprint = observedFingerprint.replacingUnknown(with: cooldown.fingerprint)
            guard !matched else {
                return .coolingDown(PredicateDiscoveryCooldown(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: .zero
                ))
            }
            let nextTicks = cooldown.visibleTicksSinceProbe.incremented()
            if observedFingerprint != cooldown.fingerprint,
               case .known = observedFingerprint {
                return .probeDue(PredicateDiscoveryProbeDue(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: nextTicks
                ))
            }
            return nextTicks.reachedDiscoveryProbeCadence
                ? .probeDue(PredicateDiscoveryProbeDue(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: nextTicks
                ))
                : .coolingDown(PredicateDiscoveryCooldown(
                    fingerprint: fingerprint,
                    visibleTicksSinceProbe: nextTicks
                ))
        }
    }
}

private struct PredicateDiscoveryProbeDue: Sendable, Equatable {
    let fingerprint: PredicateVisibleFingerprint
    let visibleTicksSinceProbe: PredicateVisibleTickCount

    func recordingUnavailableVisibleTick() -> PredicateDiscoveryProbeDue {
        PredicateDiscoveryProbeDue(
            fingerprint: fingerprint,
            visibleTicksSinceProbe: visibleTicksSinceProbe.incremented()
        )
    }

    func afterDiscoveryProbe() -> PredicateDiscoveryCooldown {
        PredicateDiscoveryCooldown(
            fingerprint: fingerprint,
            visibleTicksSinceProbe: .zero
        )
    }
}

private struct PredicateDiscoveryCooldown: Sendable, Equatable {
    let fingerprint: PredicateVisibleFingerprint
    let visibleTicksSinceProbe: PredicateVisibleTickCount
}

private struct PredicateVisibleTickCount: Sendable, Equatable {
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
