#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and publication.
@MainActor
internal final class SemanticObservationStream {
    weak var stash: TheStash?
    let tripwire: TheTripwire
    // MARK: - Observation Bookkeeping

    var scopePressure = SemanticObservationScopePressure()
    let observationLog = SemanticObservationLog()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()

    // MARK: - Subscriber-Facing Settled Observation History

    var runtimeState = SemanticObservationRuntimeState()
    internal var latestEvent: SettledObservationEvent? {
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

    internal var latestObservation: SettledObservation? {
        observationLog.latestObservation
    }

    internal var isActive: Bool {
        runtimeState.isRunning
    }

    internal var observationWaiterCount: Int {
        observationWaiters.count
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

    internal func start(
        discovery: @escaping SemanticObservationRuntimeState.DiscoveryObservation
    ) {
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
        cancelObservationWaiters()
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
        guard !Task.isCancelled,
              await performObservationCycle(scope: scope),
              !Task.isCancelled else { return }
        completeObservationWaiters(completedScope: scope)
        await Task.yield()
    }

    private func performObservationCycle(
        scope: SemanticObservationScope
    ) async -> Bool {
        guard let stash else {
            stop()
            return false
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState(stash: stash)
        case .discovery:
            guard let discovery = runtimeState.discovery else {
                invalidateLatestSettledObservation()
                return true
            }
            guard let exploration = await discovery() else {
                invalidateLatestSettledObservation()
                return true
            }
            _ = exploration
            return !Task.isCancelled
        }
    }

    private func observeVisibleSemanticState(
        stash: TheStash
    ) async -> Bool {
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
                return !Task.isCancelled
            }
            // Layer quiet is advisory. AX-tree stability is the commit proof.
            layerGateWasClear = tripwire.latestReading?.isSettled ?? tripwire.allClear()
            settle = await SettleSession.live(stash: stash, tripwire: tripwire, timeoutMs: 1_000).run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: baselineSignal
            )
        }

        guard !Task.isCancelled else { return false }
        guard let proof = admitSettledProof(
            settle,
            stash: stash,
            layerGateWasClear: layerGateWasClear
        ) else { return true }
        guard !Task.isCancelled else { return false }
        _ = commitSettledVisibleObservation(proof)
        return true
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
