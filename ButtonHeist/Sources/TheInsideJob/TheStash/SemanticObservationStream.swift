#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and publication.
@MainActor
internal final class SemanticObservationStream {
    /// An active stream is an observation lease. Baseline cycles observe the
    /// visible world; subscribers can widen demand to discovery.
    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.ExploredScreen?

    weak var stash: TheStash?
    let tripwire: TheTripwire
    // MARK: - Observation Bookkeeping

    var scopePressure = SemanticObservationScopePressure()
    let cycles = SemanticObservationCycles()
    let observationLog = SemanticObservationLog()

    // MARK: - Subscriber-Facing Settled Observation History

    var runtimeState = SemanticObservationRuntimeState()
    internal var latestEvent: SettledSemanticObservationEvent? {
        observationLog.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheStash` until the next explicit
    /// commit.
    internal var latestSettledObservationInvalidated: Bool {
        observationLog.latestSettledObservationInvalidated
    }
    internal var latestSettleFailureDiagnostic: String? {
        runtimeState.settleFailureDiagnostic
    }

    internal var latestObservation: SettledSemanticObservation? {
        observationLog.latestObservation
    }

    internal var isActive: Bool {
        runtimeState.isRunning
    }

    internal var observationReplayWaiterCount: Int {
        observationLog.waiterCount
    }

    internal var cycleWaiterCount: Int {
        cycles.waiterCount
    }

    internal var activeObservationDemandCount: Int {
        scopePressure.activeDemandCount
    }

    internal var activeObservationDemandState: SemanticObservationDemandState {
        scopePressure.demandState
    }

    internal var hasActiveObservationDemand: Bool {
        scopePressure.hasActiveDemand
    }

    internal init(stash: TheStash, tripwire: TheTripwire) {
        self.stash = stash
        self.tripwire = tripwire
    }

    internal func start(discovery: @escaping DiscoveryObservation) {
        guard !runtimeState.replaceDiscoveryIfRunning(discovery) else { return }
        if let stash {
            AccessibilityNotificationObserver.shared.subscribe(stash.accessibilityNotifications)
        }
        observationLog.invalidateCurrentPublication()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
        runtimeState.start(task: task, discovery: discovery)
    }

    internal func stop() {
        runtimeState.stop()?.cancel()
        cycles.cancelRunningCycle()
        cycles.completeAllWaiters()
        observationLog.cancelAllWaiters()
        if let stash {
            AccessibilityNotificationObserver.shared.unsubscribe(stash.accessibilityNotifications)
        }
    }

    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    internal func beginActiveObservationDemand(scope: SemanticObservationScope) -> SemanticObservationDemand {
        let id = scopePressure.addActiveDemand(scope: scope)
        return SemanticObservationDemand(id: id, scope: scope, stream: self)
    }

    internal func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
    }

    internal func subscribedObservationScope() -> SemanticObservationScope {
        scopePressure.subscribedObservationScope()
    }

    private func runPassiveObservationCycle() async {
        let scope = subscribedObservationScope()
        guard case .started(let cycle) = cycles.beginCycle(scope: scope) else {
            _ = await Task.cancellableSleep(for: .milliseconds(10))
            return
        }
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, result: .interrupted)
            return
        }
        let result = await performObservationCycle(scope: scope)
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, result: .interrupted)
            return
        }
        cycles.finishCycle(token: cycle, result: result)
        guard case .completed = result else { return }
        await Task.yield()
    }

    private func performObservationCycle(
        scope: SemanticObservationScope
    ) async -> SemanticObservationCycles.CycleResult {
        guard let stash else {
            stop()
            return .interrupted
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState(stash: stash)
        case .discovery:
            guard let discovery = runtimeState.discovery else {
                invalidateLatestSettledObservation()
                return .completed(settledSequence: nil)
            }
            guard let exploration = await discovery() else {
                invalidateLatestSettledObservation()
                return .completed(settledSequence: nil)
            }
            guard !Task.isCancelled else { return .interrupted }
            return .completed(settledSequence: exploration.event.sequence)
        }
    }

    private func observeVisibleSemanticState(
        stash: TheStash
    ) async -> SemanticObservationCycles.CycleResult {
        let baselineSignal = tripwire.tripwireSignal()
        let settle: SettleSession.Outcome
        let layerGateWasClear: Bool?
        switch activeObservationDemandState {
        case .active:
            settle = await SemanticObservationSettleCadence.settleVisibleObservationAtActiveCadence(
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineSignal,
                timeoutMs: SemanticObservationSettleCadence.activePassiveSettleTimeoutMs
            )
            layerGateWasClear = nil
        case .idle:
            if let reading = tripwire.latestReading,
               !latestSettledObservationInvalidated,
               runtimeState.settledReading?.tick == reading.tick {
                _ = await Task.cancellableSleep(for: .milliseconds(100))
                return .completed(settledSequence: nil)
            }
            // Layer quiet is advisory. AX-tree stability is the commit proof.
            layerGateWasClear = tripwire.latestReading?.isSettled ?? tripwire.allClear()
            settle = await SettleSession.live(stash: stash, tripwire: tripwire, timeoutMs: 1_000).run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: baselineSignal
            )
        }

        guard !Task.isCancelled else { return .interrupted }
        guard let proof = admitSettledProof(
            settle,
            stash: stash,
            layerGateWasClear: layerGateWasClear
        ) else { return .completed(settledSequence: nil) }
        guard !Task.isCancelled else { return .interrupted }
        let event = commitSettledVisibleObservation(proof)
        return .completed(settledSequence: event.sequence)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
