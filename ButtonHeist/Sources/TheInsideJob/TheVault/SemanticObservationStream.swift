#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and publication.
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
    ) async -> SettleSession.Outcome

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
    let observationLog = SemanticObservationLog()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()

    // MARK: - Subscriber-Facing Settled Observation History

    var runtimeState = SemanticObservationRuntimeState()
    internal var latestEvent: SettledObservationEvent? {
        observationLog.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheVault` until the next explicit
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
        discovery: @escaping SemanticObservationRuntimeState.DiscoveryObservation
    ) {
        guard !runtimeState.replaceDiscoveryIfRunning(discovery) else { return }
        if let vault {
            AccessibilityNotificationObserver.shared.subscribe(vault.accessibilityNotifications)
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

    private func observeVisibleSemanticState() async -> Bool {
        if hasActiveObservationDemand {
            _ = await Task.cancellableSleep(for: .milliseconds(10))
            return !Task.isCancelled
        }

        if cleanObservation(scope: .visible, after: nil) != nil {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            observationLog.invalidateIfSignalChanged(to: currentTripwireSignal())
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
