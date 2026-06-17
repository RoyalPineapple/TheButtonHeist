#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct SettledSemanticObservation {
    let sequence: UInt64
    let scope: SemanticObservationScope
    let screen: Screen
    let tripwireSignal: TheTripwire.TripwireSignal
}

struct SettledSemanticObservationEvent {
    let sequence: UInt64
    let scope: SemanticObservationScope
    let observation: SettledSemanticObservation
    let previous: SettledSemanticObservation?
    let trace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?

    var latestCaptureRef: AccessibilityTrace.CaptureRef? {
        trace.captures.last.map(AccessibilityTrace.CaptureRef.init(capture:))
    }
}

struct VisibleSemanticObservationEvidence {
    let screen: Screen
    let tripwireSignal: TheTripwire.TripwireSignal
    let settledObservationSequence: UInt64?
    let settleOutcome: SettleOutcome
}

@MainActor
final class SemanticObservationStream {
    /// An active stream is an observation lease. Baseline cycles observe the
    /// visible world; subscribers can widen demand to discovery.
    typealias DiscoveryObservation = @MainActor () async -> Screen?

    private weak var stash: TheStash?
    private let tripwire: TheTripwire

    // MARK: - Observation Bookkeeping

    private var scopePressure = SemanticObservationScopePressure()
    private let settledWaiters = SemanticObservationSettledWaiters()
    private let cycles = SemanticObservationCycles()

    // MARK: - Subscriber-Facing Settled Observation History

    private var settledSequence: UInt64 = 0
    private(set) var latestEvent: SettledSemanticObservationEvent?
    /// Invalidates only `latestEvent` as a clean waiter result. Settled
    /// semantic truth remains in `TheStash` until the next explicit commit.
    private(set) var latestSettledObservationInvalidated = true
    private(set) var latestSettleFailureDiagnostic: String?

    // MARK: - Passive Observation Scheduling

    private(set) var passiveObservationTask: Task<Void, Never>?
    private var discoveryObservation: DiscoveryObservation?
    private var passiveObservationSettledReading: TheTripwire.PulseReading?

    var latestObservation: SettledSemanticObservation? {
        latestEvent?.observation
    }

    var isActive: Bool {
        passiveObservationTask != nil
    }

    var settledWaiterCount: Int {
        settledWaiters.count
    }

    var activeObservationDemandCount: Int {
        scopePressure.activeDemandCount
    }

    var hasActiveObservationDemand: Bool {
        scopePressure.hasActiveDemand
    }

    init(stash: TheStash, tripwire: TheTripwire) {
        self.stash = stash
        self.tripwire = tripwire
    }

    func start(discovery: @escaping DiscoveryObservation) {
        discoveryObservation = discovery
        guard passiveObservationTask == nil else { return }
        latestSettledObservationInvalidated = true
        passiveObservationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
    }

    func stop() {
        passiveObservationTask?.cancel()
        passiveObservationTask = nil
        discoveryObservation = nil
        passiveObservationSettledReading = nil
        settledWaiters.completeAll(returning: nil)
        cycles.completeAllWaiters()
    }

    func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    func beginActiveObservationDemand(scope: SemanticObservationScope) -> SemanticObservationDemand {
        let id = scopePressure.addActiveDemand(scope: scope)
        return SemanticObservationDemand(id: id, scope: scope, stream: self)
    }

    func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
    }

    func subscribedObservationScope() -> SemanticObservationScope {
        scopePressure.subscribedObservationScope()
    }

    func settledEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard isActive else { return nil }
            await cycles.waitForNextCycle(scope: scope, after: cycles.baselineCycle())
            return cleanEvent(scope: scope, after: requiredSequence)
        }

        if sequence == nil, scope == .visible {
            if isActive {
                await cycles.waitForNextCycle(scope: scope, after: cycles.baselineCycle())
            } else {
                return await waitForNextSettledEvent(
                    scope: scope,
                    after: latestObservation?.sequence,
                    timeout: timeout
                )
            }
        }

        if let latest = cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        if isActive {
            await cycles.waitForNextCycle(scope: scope, after: cycles.baselineCycle())
            if let latest = cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
        }

        return await waitForNextSettledEvent(scope: scope, after: requiredSequence, timeout: timeout)
    }

    func visibleEvidence(timeout: Double?) async -> VisibleSemanticObservationEvidence? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        guard let stash else { return nil }

        let outcome = await SemanticObservationSettleCadence.settleVisibleObservationForCurrentDemand(
            hasActiveDemand: hasActiveObservationDemand,
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: latestEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal(),
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )

        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            stash.recordFailedSettleDiagnosticEvidence(outcome.finalScreen)
            return nil
        }

        guard let screen = outcome.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            stash.recordFailedSettleDiagnosticEvidence(nil)
            return nil
        }

        if outcome.outcome.didSettleCleanly {
            let event = commitSettledVisibleObservation(screen)
            return VisibleSemanticObservationEvidence(
                screen: event.observation.screen,
                tripwireSignal: event.observation.tripwireSignal,
                settledObservationSequence: event.sequence,
                settleOutcome: outcome.outcome
            )
        }

        latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
        stash.recordFailedSettleDiagnosticEvidence(screen)
        return nil
    }

    @discardableResult
    func commitSettledVisibleObservation(_ screen: Screen) -> SettledSemanticObservationEvent {
        publishCommittedObservation(screen, scope: .visible)
    }

    @discardableResult
    func commitSettledDiscoveryObservation(_ screen: Screen) -> SettledSemanticObservationEvent {
        publishCommittedObservation(screen, scope: .discovery)
    }

    @discardableResult
    private func publishCommittedObservation(
        _ screen: Screen,
        scope: SemanticObservationScope
    ) -> SettledSemanticObservationEvent {
        guard let stash else {
            preconditionFailure("SemanticObservationStream cannot commit after TheStash is released")
        }
        switch scope {
        case .visible:
            stash.commitSettledVisibleWorld(screen)
        case .discovery:
            stash.commitSettledDiscoveryWorld(screen)
        }
        return publishCurrentSettledObservation(scope: scope, stash: stash)
    }

    func settlePostActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        settleOutcome providedOutcome: SettleSession.Outcome? = nil
    ) async -> (settle: SettleSession.Outcome, event: SettledSemanticObservationEvent?, diagnosticScreen: Screen?) {
        guard let stash else {
            return (
                SettleSession.Outcome(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalScreen: nil,
                    elementsByKey: [:]
                ),
                nil,
                nil
            )
        }
        let outcome: SettleSession.Outcome
        if let providedOutcome {
            outcome = providedOutcome
        } else {
            outcome = await SemanticObservationSettleCadence.settleVisibleObservationForCurrentDemand(
                hasActiveDemand: hasActiveObservationDemand,
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: SettleSession.defaultTimeoutMs
            )
        }

        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            stash.recordFailedSettleDiagnosticEvidence(outcome.finalScreen)
            return (outcome, nil, nil)
        }

        guard let finalScreen = outcome.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            stash.recordFailedSettleDiagnosticEvidence(nil)
            return (outcome, nil, nil)
        }
        if outcome.outcome.didSettleCleanly {
            return (outcome, commitSettledVisibleObservation(finalScreen), nil)
        }

        latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
        stash.recordFailedSettleDiagnosticEvidence(finalScreen)
        return (outcome, nil, stash.latestFailedSettleDiagnosticEvidence)
    }

    func clearSettledObservationHistory() {
        latestEvent = nil
        latestSettledObservationInvalidated = true
        passiveObservationSettledReading = nil
        latestSettleFailureDiagnostic = nil
    }

    func invalidateLatestSettledObservation() {
        latestSettledObservationInvalidated = true
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        stash: TheStash
    ) -> SettledSemanticObservationEvent {
        settledSequence += 1
        let observation = SettledSemanticObservation(
            sequence: settledSequence,
            scope: scope,
            screen: stash.settledSemanticScreen,
            tripwireSignal: tripwire.tripwireSignal()
        )
        let event = SemanticObservationEventFactory.makeEvent(
            observation: observation,
            previous: latestEvent,
            stash: stash
        )
        latestEvent = event
        latestSettledObservationInvalidated = false
        latestSettleFailureDiagnostic = nil
        passiveObservationSettledReading = tripwire.latestReading
        settledWaiters.completeWaiters(with: event)
        return event
    }

    private func waitForNextSettledEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if let latest = cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        return await settledWaiters.wait(
            scope: scope,
            afterSequence: requiredSequence,
            timeout: timeout
        )
    }

    private static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        return max(1, Int((timeout * 1_000).rounded(.up)))
    }

    private func baselineSequence(
        for scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> UInt64? {
        let currentSequence = latestEvent?.sequence
        if scope == .discovery {
            let baseline = sequence ?? currentSequence
            return max(baseline ?? 0, currentSequence ?? 0)
        }
        if sequence == nil, !isActive {
            return currentSequence
        }
        return sequence
    }

    private func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> SettledSemanticObservationEvent? {
        guard !latestSettledObservationInvalidated,
              let latest = latestEvent,
              latest.scope >= scope,
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }

    private func runPassiveObservationCycle() async {
        let scope = subscribedObservationScope()
        cycles.beginCycle()
        let didObserve = await performObservationCycle(scope: scope)
        cycles.finishCycle(didObserve: didObserve, scope: scope)
        guard didObserve else { return }
        await Task.yield()
    }

    private func performObservationCycle(scope: SemanticObservationScope) async -> Bool {
        guard let stash else {
            stop()
            return false
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState(stash: stash)
        case .discovery:
            guard let discoveryObservation else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            guard let exploredScreen = await discoveryObservation() else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            _ = commitSettledDiscoveryObservation(exploredScreen)
            await Task.yield()
            return true
        }
    }

    private func observeVisibleSemanticState(stash: TheStash) async -> Bool {
        if hasActiveObservationDemand {
            return await observeVisibleSemanticStateAtActiveCadence(stash: stash)
        }

        if let reading = tripwire.latestReading,
           !latestSettledObservationInvalidated,
           passiveObservationSettledReading?.tick == reading.tick {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            return true
        }

        // Layer quiet is only advisory for passive semantic observation. Complex
        // apps can have unrelated CALayer motion forever; the AX-tree settle
        // loop below is the correctness signal for accessibility actions.
        let layerGateWasClear = tripwire.latestReading?.isSettled ?? tripwire.allClear()

        let baselineSignal = latestEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire, timeoutMs: 1_000)
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineSignal
        )

        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(
                for: settle,
                layerGateWasClear: layerGateWasClear
            )
            stash.recordFailedSettleDiagnosticEvidence(settle.finalScreen)
            await Task.yield()
            return true
        }

        _ = commitSettledVisibleObservation(screen)
        await Task.yield()
        return true
    }

    private func observeVisibleSemanticStateAtActiveCadence(stash: TheStash) async -> Bool {
        let baselineSignal = latestEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal()
        let settle = await SemanticObservationSettleCadence.settleVisibleObservationAtActiveCadence(
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: baselineSignal,
            timeoutMs: SemanticObservationSettleCadence.activePassiveSettleTimeoutMs
        )

        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: settle)
            stash.recordFailedSettleDiagnosticEvidence(settle.finalScreen)
            await Task.yield()
            return true
        }

        _ = commitSettledVisibleObservation(screen)
        await Task.yield()
        return true
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
