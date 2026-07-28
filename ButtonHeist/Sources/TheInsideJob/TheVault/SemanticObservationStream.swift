#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and delivery.
extension Observation {
@MainActor
internal final class Stream {
    private static let passiveDiscoveryCadence: Duration = .seconds(1)

    weak var vault: TheVault?
    let tripwire: TheTripwire
    var visibleRefreshPhase = VisibleRefreshPhase.idle
    var nextVisibleRefreshToken: UInt64 = 0
    var readTripwireSignal: @MainActor () -> TheTripwire.TripwireSignal
    private var lastPassiveDiscoveryStartedAt: RuntimeElapsed.Instant?
    // MARK: - Observation Bookkeeping

    var scopePressure = SemanticObservationScopePressure()
    /// Whether Button Heist is the one moving the viewport right now.
    ///
    /// Screen identity is compared over the viewport, so a reading taken part
    /// way through a scroll can share no elements with the reading before it.
    /// A viewport transition holds this for as long as it drives the scroll,
    /// which is what lets an ambient reading state `.viewportMovement`.
    private(set) var isMovingViewport = false
    let storeOwner = StoreOwner()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()
    private var receive: @MainActor (Event) -> Void = { _ in }
    /// Runs at the top of every visible reading, before the tree is read.
    var beforeVisibleReading: @MainActor () async -> Void = {}
    /// What the vault holds, readable without awaiting the store.
    ///
    /// The store is the record and lives behind an actor; callers on the main
    /// actor that need the current tree synchronously read it here, written as
    /// each tick goes out.
    private(set) var latestReadSnapshotEvent: SnapshotEvent?
    private(set) var latestReadInterfaceTree: InterfaceTree = .empty

    // MARK: - Subscriber-Facing Settled Observation History

    var lifecycle = SemanticObservationLifecycle.stopped
    internal func latestReadEvent() async -> SnapshotEvent? {
        await storeOwner.latestReadEvent()
    }
    internal func latestSettleFailureDiagnostic() async -> String? {
        await storeOwner.latestSettleFailureDiagnostic()
    }

    internal func readScopedScreenChangedSequence() async -> UInt64 {
        await storeOwner.scopedScreenChangedSequence()
    }

    internal func latestReadSnapshot() async -> Snapshot? {
        await storeOwner.latestReadSnapshot()
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
        tripwire: TheTripwire
    ) {
        self.vault = vault
        self.tripwire = tripwire
        self.readTripwireSignal = { tripwire.tripwireSignal() }
    }

    internal func start(
        discovery: @escaping SemanticObservationLifecycle.DiscoveryObservation
    ) async {
        guard !lifecycle.replaceDiscoveryIfRunning(discovery) else { return }
        await storeOwner.discardCurrentObservation()
        forgetReadState()
        lastPassiveDiscoveryStartedAt = nil
        if let vault {
            AccessibilityNotificationObserver.shared.subscribe(vault.accessibilityNotifications)
        }
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
        lastPassiveDiscoveryStartedAt = nil
        visibleRefreshPhase.cancel()
        cancelObservationWaiters()
        if let vault {
            AccessibilityNotificationObserver.shared.unsubscribe(vault.accessibilityNotifications)
        }
    }

    /// Raises the scope the vault reads at, without listening.
    ///
    /// Holding a scope is how a caller says how hard to look; the vault reads at
    /// the widest scope anyone holds. Ticks are a separate question, and only the
    /// running heist step asks it.
    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    /// Raises the scope and takes the ticks.
    ///
    /// There is one receiver because there is one of everything downstream: one
    /// brains running one heist step. Nothing routes, because there is nowhere
    /// else a tick could go.
    internal func subscribe(
        scope: SemanticObservationScope,
        receive: @escaping @MainActor (Event) -> Void
    ) -> SemanticObservationSubscription {
        self.receive = receive
        return subscribe(scope: scope)
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    func publishImmediately(_ event: Event) {
        if let snapshotEvent = event.snapshotEvent {
            latestReadSnapshotEvent = snapshotEvent
            latestReadInterfaceTree = snapshotEvent.snapshot.observation.tree
        }
        receive(event)
    }

    /// Forgets what the vault held.
    ///
    /// Paired with the store throwing its tree away: the mirror describes what
    /// the store holds, so it goes when that does.
    func forgetReadState() {
        latestReadSnapshotEvent = nil
        latestReadInterfaceTree = .empty
    }

    /// Runs `movement` with every reading taken during it attributed to the
    /// viewport movement it drives. A movement reached from inside another one
    /// is already covered, and the claim ends where the outermost one does.
    internal func movingViewport<Value>(_ movement: () async -> Value) async -> Value {
        let wasMovingViewport = isMovingViewport
        isMovingViewport = true
        defer { isMovingViewport = wasMovingViewport }
        return await movement()
    }

    internal func beginActiveObservationDemand() -> SemanticObservationDemand {
        SemanticObservationDemand(id: scopePressure.addActiveDemand(), stream: self)
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
              await admitPassiveObservationCycle(scope: scope),
              await performObservationCycle(scope: scope),
              !Task.isCancelled else { return }
        await completeObservationWaiters(completedScope: scope)
        await Task.yield()
    }

    private func admitPassiveObservationCycle(
        scope: SemanticObservationScope
    ) async -> Bool {
        guard scope == .discovery else { return true }
        if let lastPassiveDiscoveryStartedAt {
            let elapsed = lastPassiveDiscoveryStartedAt.duration(to: RuntimeElapsed.now)
            let remaining = Self.passiveDiscoveryCadence - elapsed
            if remaining > .zero {
                guard await Task.cancellableSleep(for: remaining) else { return false }
            }
        }
        lastPassiveDiscoveryStartedAt = RuntimeElapsed.now
        return !Task.isCancelled
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
                await discardCurrentObservation()
                return true
            }
            guard let exploration = await discovery() else {
                await discardCurrentObservation()
                return true
            }
            _ = exploration
            return !Task.isCancelled
        }
    }

    /// One pulse, one reading, committed either way.
    ///
    /// Returning early when the admitted observation still holds looks free and
    /// is not: "nothing changed" is the answer stillness waits for, and skipping
    /// the read makes it unobtainable. The next reading only arrives when the
    /// tree moves, so a tree that reached the asked-for state and stayed there
    /// would never say so, and every expectation with a drained predicate would
    /// time out waiting for the tree to stop changing.
    private func observeVisibleSemanticState() async -> Bool {
        _ = await tripwire.waitForNextTick(
            timeout: .milliseconds(Int(TheTripwire.singleTickSettleTimeout * 1_000)),
            demand: .ambient
        )
        await discardIfSignalChanged(to: currentTripwireSignal())
        guard !Task.isCancelled else { return false }
        _ = await refreshVisibleObservation()
        return !Task.isCancelled
    }

    func discardIfSignalChanged(to signal: TheTripwire.TripwireSignal) async {
        await storeOwner.discardIfSignalChanged(to: signal)
    }

}
}

extension Observation.Stream {
    struct VisibleRefreshToken: Equatable {
        let rawValue: UInt64
    }

    struct VisibleRefreshBoundary: Equatable {
        let nextTokenRawValue: UInt64
    }

    struct VisibleRefreshTask {
        let token: VisibleRefreshToken
        let task: Task<ObservationSettlement, Never>
    }

    enum VisibleRefreshPhase {
        case idle
        case refreshing(VisibleRefreshTask)

        var task: VisibleRefreshTask? {
            switch self {
            case .idle:
                nil
            case .refreshing(let task):
                task
            }
        }

        mutating func cancel() {
            task?.task.cancel()
            self = .idle
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
