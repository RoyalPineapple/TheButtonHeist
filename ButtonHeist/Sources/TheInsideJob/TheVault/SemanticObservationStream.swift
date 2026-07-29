#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, capture, and delivery.
extension Observation {
@MainActor
internal final class Stream {
    private enum EventReceiver {
        case installing(
            subscriptionID: UInt64,
            receive: @MainActor (Event) -> Void,
            buffered: [Publication]
        )
        case active(
            subscriptionID: UInt64,
            receive: @MainActor (Event) -> Void,
            pending: [Event],
            nextIndex: Int,
            isDelivering: Bool
        )

        var subscriptionID: UInt64 {
            switch self {
            case .installing(let subscriptionID, _, _),
                 .active(let subscriptionID, _, _, _, _):
                subscriptionID
            }
        }
    }

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
    private var activeViewportMovementCount = 0
    var captureLineage: ScreenLineage {
        activeViewportMovementCount == 0 ? .resting : .viewportMovement
    }
    let stateOwner = TheVault.StateOwner()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()
    private var eventReceiver: EventReceiver?
    /// Runs at the top of every visible reading, before the tree is read.
    var beforeVisibleReading: @MainActor () async -> Void = {}

    // MARK: - Subscriber-Facing Observation History

    var lifecycle = SemanticObservationLifecycle.stopped
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

    internal var tickDemand: TheTripwire.TickDemand {
        hasActiveObservationDemand ? .immediate : .ambient
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
        await stateOwner.discardCurrentObservation()
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
    /// the widest scope anyone holds. Event delivery is a separate question, and
    /// only the running heist asks for it.
    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    /// Raises the scope and receives retained and live events without a gap.
    ///
    /// The receiver is installed before history is read. Publications that race
    /// with that actor hop are buffered by range, then only the suffix not
    /// already present in retained history is delivered.
    internal func subscribe(
        scope: SemanticObservationScope,
        replayingAfter historyIndex: Int,
        receive: @escaping @MainActor (Event) -> Void,
        historyUnavailable: @escaping @MainActor (History.ReadError) -> Void
    ) async -> SemanticObservationSubscription {
        precondition(
            eventReceiver == nil,
            "Only one observation event consumer may be active"
        )
        let subscription = subscribe(scope: scope)
        eventReceiver = .installing(
            subscriptionID: subscription.id,
            receive: receive,
            buffered: []
        )
        let replay = await stateOwner.events(after: historyIndex)
        guard eventReceiver?.subscriptionID == subscription.id else {
            return subscription
        }
        guard case .installing(_, _, let buffered) = eventReceiver else {
            preconditionFailure("Observation receiver changed while installing")
        }
        switch replay {
        case .success(let retained):
            let replayEndIndex = historyIndex + retained.count
            let live = buffered.flatMap { publication in
                publication.events(after: replayEndIndex)
            }
            activate(
                retained + live,
                to: subscription.id,
                receive: receive
            )
        case .failure(let error):
            historyUnavailable(error)
            guard case .installing(_, _, let latestBuffered) = eventReceiver,
                  eventReceiver?.subscriptionID == subscription.id
            else { return subscription }
            activate(
                latestBuffered.flatMap(\.events),
                to: subscription.id,
                receive: receive
            )
        }
        return subscription
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
        if eventReceiver?.subscriptionID == id {
            eventReceiver = nil
        }
    }

    func publish(_ publication: Publication) {
        guard let receiver = eventReceiver else { return }
        switch receiver {
        case .installing(let subscriptionID, let receive, let buffered):
            self.eventReceiver = .installing(
                subscriptionID: subscriptionID,
                receive: receive,
                buffered: buffered + [publication]
            )
        case .active(
            let subscriptionID,
            let receive,
            let pending,
            let nextIndex,
            let isDelivering
        ):
            eventReceiver = .active(
                subscriptionID: subscriptionID,
                receive: receive,
                pending: pending + publication.events,
                nextIndex: nextIndex,
                isDelivering: isDelivering
            )
            drain(subscriptionID: subscriptionID)
        }
    }

    private func activate(
        _ events: [Event],
        to subscriptionID: UInt64,
        receive: @escaping @MainActor (Event) -> Void
    ) {
        eventReceiver = .active(
            subscriptionID: subscriptionID,
            receive: receive,
            pending: events,
            nextIndex: 0,
            isDelivering: false
        )
        drain(subscriptionID: subscriptionID)
    }

    private func drain(subscriptionID: UInt64) {
        guard case .active(
            let activeSubscriptionID,
            let receive,
            let initialPending,
            let initialIndex,
            false
        ) = eventReceiver,
              activeSubscriptionID == subscriptionID
        else { return }
        eventReceiver = .active(
            subscriptionID: subscriptionID,
            receive: receive,
            pending: initialPending,
            nextIndex: initialIndex,
            isDelivering: true
        )
        while case .active(
            let activeSubscriptionID,
            let currentReceive,
            let pending,
            let nextIndex,
            true
        ) = eventReceiver,
              activeSubscriptionID == subscriptionID {
            guard nextIndex < pending.count else {
                eventReceiver = .active(
                    subscriptionID: subscriptionID,
                    receive: currentReceive,
                    pending: [],
                    nextIndex: 0,
                    isDelivering: false
                )
                return
            }
            let event = pending[nextIndex]
            eventReceiver = .active(
                subscriptionID: subscriptionID,
                receive: currentReceive,
                pending: pending,
                nextIndex: nextIndex + 1,
                isDelivering: true
            )
            receive(event)
        }
    }

    /// Keeps committed semantic truth readable while requiring a fresh
    /// observation before it can be admitted to a waiter.
    func invalidateCurrentAdmission() async {
        await stateOwner.invalidateCurrentAdmission()
    }

    /// Runs `movement` with every reading taken during it attributed to the
    /// viewport movement it drives. A movement reached from inside another one
    /// is already covered, and the claim ends where the outermost one does.
    internal func movingViewport<Value>(_ movement: () async -> Value) async -> Value {
        activeViewportMovementCount += 1
        defer { activeViewportMovementCount -= 1 }
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
            demand: tickDemand
        )
        await invalidateAdmissionIfSignalChanged(to: currentTripwireSignal())
        guard !Task.isCancelled else { return false }
        _ = await refreshVisibleObservation()
        return !Task.isCancelled
    }

    func invalidateAdmissionIfSignalChanged(to signal: TheTripwire.TripwireSignal) async {
        await stateOwner.invalidateAdmissionIfSignalChanged(to: signal)
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
        let task: Task<VisibleObservationOutcome, Never>
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
