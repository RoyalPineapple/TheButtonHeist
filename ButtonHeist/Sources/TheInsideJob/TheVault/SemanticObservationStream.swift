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
    let storeOwner = StoreOwner()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()
    private var subscribers: [UInt64: Subscriber] = [:]
    var deliveryState = DeliveryState()
    private var publicationWaiters: [
        StoreOwner.DeliveryToken: CheckedContinuation<PublicationOutcome, Never>
    ] = [:]
    /// Runs at the top of every visible reading, before the tree is read.
    /// The seam tests use to count readings and to hold one open while they
    /// check whether a second consumer starts its own or joins this one.
    var beforeVisibleReading: @MainActor () async -> Void = {}
    var beforeCommittedDelivery: @MainActor (StoreOwner.DeliveryToken) async -> Void = { _ in }
    var beforeResolvedDeliveryEnqueue: @MainActor (StoreOwner.DeliveryToken) async -> Void = { _ in }
    var latestDeliveredSnapshotEvent: SnapshotEvent?
    var latestDeliveredInterfaceTree: InterfaceTree = .empty

    // MARK: - Subscriber-Facing Settled Observation History

    var lifecycle = SemanticObservationLifecycle.stopped
    internal func latestCommittedEvent() async -> SnapshotEvent? {
        await storeOwner.latestCommittedEvent()
    }
    /// Invalidates only latest fulfilled events as admitted waiter results.
    /// Settled semantic truth remains in `TheVault` until the next explicit
    /// commit.
    internal func latestSettledObservationInvalidated() async -> Bool {
        await storeOwner.latestSettledObservationInvalidated()
    }
    internal func latestSettleFailureDiagnostic() async -> String? {
        await storeOwner.latestSettleFailureDiagnostic()
    }

    internal func latestCommittedSnapshot() async -> Snapshot? {
        await storeOwner.latestCommittedSnapshot()
    }

    internal var isActive: Bool {
        lifecycle.isRunning
    }

    internal var observationWaiterCount: Int {
        observationWaiters.count
    }

    internal var publicationWaiterCount: Int {
        publicationWaiters.count
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
        let generation = await storeOwner.invalidateCurrentObservation()
        synchronizeDeliveryGeneration(generation, clearingSource: true)
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

    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        subscribe(scope: scope, receive: { _ in })
    }

    internal func subscribe(
        scope: SemanticObservationScope,
        receive: @escaping @MainActor (Event) -> Void
    ) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        subscribers[id] = Subscriber(scope: scope, receive: receive)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    internal func removeSubscription(_ id: UInt64) {
        subscribers.removeValue(forKey: id)
        scopePressure.removeSubscription(id)
    }

    func publishImmediately(_ event: Event) {
        if case .snapshot(let snapshotEvent) = event {
            latestDeliveredSnapshotEvent = snapshotEvent
            latestDeliveredInterfaceTree = snapshotEvent.snapshot.observation.tree
        }
        for subscriber in subscribers.values where event.canFulfill(subscriber.scope) {
            subscriber.receive(event)
        }
    }

    func synchronizeDeliveryGeneration(
        _ generation: StoreOwner.DeliveryGeneration,
        clearingProjection: Bool = false,
        clearingSource: Bool = false
    ) {
        guard deliveryState.synchronize(to: generation, clearingSource: clearingSource) else { return }
        let waiters = publicationWaiters.values
        publicationWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: .superseded) }
        guard clearingProjection else { return }
        latestDeliveredSnapshotEvent = nil
        latestDeliveredInterfaceTree = .empty
    }

    func waitForPublication(
        of token: StoreOwner.DeliveryToken
    ) async -> PublicationOutcome {
        await withCheckedContinuation { continuation in
            precondition(
                publicationWaiters.updateValue(continuation, forKey: token) == nil,
                "Observation delivery may have only one publication waiter"
            )
        }
    }

    func completePublication(
        of token: StoreOwner.DeliveryToken,
        with outcome: PublicationOutcome
    ) {
        publicationWaiters.removeValue(forKey: token)?.resume(returning: outcome)
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
                await invalidateLatestSettledObservation()
                return true
            }
            guard let exploration = await discovery() else {
                await invalidateLatestSettledObservation()
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
        await invalidateDeliveryIfSignalChanged(to: currentTripwireSignal())
        guard !Task.isCancelled else { return false }
        _ = await refreshVisibleObservation()
        return !Task.isCancelled
    }

    func invalidateDeliveryIfSignalChanged(
        to signal: TheTripwire.TripwireSignal
    ) async {
        guard let generation = await storeOwner.invalidateIfSignalChanged(to: signal) else { return }
        synchronizeDeliveryGeneration(generation, clearingSource: true)
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

    private struct Subscriber {
        let scope: SemanticObservationScope
        let receive: @MainActor (Observation.Event) -> Void
    }

    struct PendingDelivery {
        let delivery: Observation.StoreOwner.CommittedDelivery
        let sourceObservation: InterfaceObservation
    }

    struct ReadyDelivery {
        let pending: PendingDelivery
        let reattachesLiveCapture: Bool
    }

    struct DeliveryState {
        private(set) var generation = Observation.StoreOwner.DeliveryGeneration.initial
        private var nextOrder: UInt64 = 1
        private var pending: [UInt64: PendingDelivery] = [:]
        private var latestSourceCaptureID: InterfaceCaptureID?

        mutating func observeSourceCapture(_ captureID: InterfaceCaptureID) {
            latestSourceCaptureID = captureID
        }

        func isLatestSourceCapture(_ captureID: InterfaceCaptureID) -> Bool {
            latestSourceCaptureID == captureID
        }

        mutating func synchronize(
            to generation: Observation.StoreOwner.DeliveryGeneration,
            clearingSource: Bool = false
        ) -> Bool {
            guard generation > self.generation else { return false }
            self.generation = generation
            nextOrder = 1
            pending.removeAll(keepingCapacity: true)
            if clearingSource {
                latestSourceCaptureID = nil
            }
            return true
        }

        mutating func enqueue(
            _ delivery: PendingDelivery,
            currentCommitOrder: UInt64
        ) -> DeliveryEnqueueResult {
            guard delivery.delivery.token.generation >= generation else {
                return .superseded
            }
            _ = synchronize(to: delivery.delivery.token.generation)
            guard delivery.delivery.token.order >= nextOrder else {
                return .superseded
            }
            pending[delivery.delivery.token.order] = delivery

            var contiguous: [ReadyDelivery] = []
            while let next = pending.removeValue(forKey: nextOrder) {
                contiguous.append(ReadyDelivery(
                    pending: next,
                    reattachesLiveCapture: nextOrder == currentCommitOrder
                        && next.sourceObservation.captureID == latestSourceCaptureID
                ))
                nextOrder += 1
            }
            return .ready(contiguous)
        }
    }

    enum DeliveryEnqueueResult {
        case ready([ReadyDelivery])
        case superseded
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
