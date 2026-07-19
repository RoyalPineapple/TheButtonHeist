#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and delivery.
@MainActor
internal final class SemanticObservationStream {
    private static let passiveSettleTimeoutMs = 1_000
    private static let activeQuietWindowMs = 60

    internal typealias VisibleObservationSettler = @MainActor (
        TheVault,
        TheTripwire,
        SemanticObservationDemandState,
        TheTripwire.TripwireSignal,
        Int
    ) async -> SettleSession.Result

    @MainActor
    final class VisibleRefreshCompletion {
        let settlement: ObservationSettlement

        init(_ settlement: ObservationSettlement) {
            self.settlement = settlement
        }
    }

    @MainActor
    final class VisibleRefreshSession {
        let task: Task<VisibleRefreshCompletion, Never>

        init(task: Task<VisibleRefreshCompletion, Never>) {
            self.task = task
        }
    }

    weak var vault: TheVault?
    let tripwire: TheTripwire
    var visibleRefreshSession: VisibleRefreshSession?
    var settleVisibleObservation: VisibleObservationSettler
    var readTripwireSignal: @MainActor () -> TheTripwire.TripwireSignal
    // MARK: - Observation Bookkeeping

    var scopePressure = SemanticObservationScopePressure()
    var observationStore = SemanticObservationStore()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()

    // MARK: - Subscriber-Facing Settled Observation History

    var lifecycle = SemanticObservationLifecycle.stopped
    internal var latestEvent: SettledObservationEvent? {
        observationStore.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheVault` until the next explicit
    /// commit.
    internal var latestSettledObservationInvalidated: Bool {
        observationStore.latestSettledObservationInvalidated
    }
    internal var latestSettleFailureDiagnostic: String? {
        observationStore.settleFailureDiagnostic
    }

    internal var latestObservation: SettledObservation? {
        observationStore.latestObservation
    }

    internal var isActive: Bool {
        lifecycle.isRunning
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

    internal init(
        vault: TheVault,
        tripwire: TheTripwire,
        settleVisibleObservation: VisibleObservationSettler? = nil
    ) {
        self.vault = vault
        self.tripwire = tripwire
        self.readTripwireSignal = { tripwire.tripwireSignal() }
        self.settleVisibleObservation = settleVisibleObservation ?? { vault, tripwire, demand, baseline, timeoutMs in
            let policy: SettlePolicy = switch demand {
            case .active:
                .quietWindow(milliseconds: Self.activeQuietWindowMs)
            case .idle:
                .consecutiveCycles(required: SettleSession.defaultCyclesRequired)
            }
            return await SettleSession.live(
                vault: vault,
                tripwire: tripwire,
                timeoutMs: timeoutMs,
                policy: policy
            ).run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: baseline
            )
        }
    }

    internal func start(
        discovery: @escaping SemanticObservationLifecycle.DiscoveryObservation
    ) {
        guard !lifecycle.replaceDiscoveryIfRunning(discovery) else { return }
        if let vault {
            AccessibilityNotificationObserver.shared.subscribe(vault.accessibilityNotifications)
        }
        observationStore.invalidateCurrentObservation()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
        lifecycle.start(task: task, discovery: discovery)
    }

    internal func stop() {
        lifecycle.stop()?.cancel()
        visibleRefreshSession?.task.cancel()
        visibleRefreshSession = nil
        cancelObservationWaiters()
        if let vault {
            AccessibilityNotificationObserver.shared.unsubscribe(vault.accessibilityNotifications)
        }
    }

    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    internal func beginActiveObservationDemand() -> SemanticObservationDemand {
        let id = scopePressure.addActiveDemand()
        return SemanticObservationDemand(id: id, stream: self)
    }

    internal func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
    }

    internal func subscribedObservationScope() -> SemanticObservationScope {
        scopePressure.subscribedObservationScope()
    }

    internal func currentTripwireSignal() -> TheTripwire.TripwireSignal {
        readTripwireSignal()
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
        guard vault != nil else {
            stop()
            return false
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState()
        case .discovery:
            guard let discovery = lifecycle.discovery else {
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

    private func observeVisibleSemanticState() async -> Bool {
        if cleanObservation(scope: .visible, after: nil) != nil {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            observationStore.invalidateIfSignalChanged(to: currentTripwireSignal())
            return !Task.isCancelled
        }

        _ = await refreshVisibleObservation(
            timeoutMs: Self.passiveSettleTimeoutMs
        )
        return !Task.isCancelled
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
