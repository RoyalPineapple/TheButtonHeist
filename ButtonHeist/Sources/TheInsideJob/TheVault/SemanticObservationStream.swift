#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport

import TheScore

@MainActor
enum AccessibilityNotificationIngress {
    case process
    case injected

    func start(deliveringTo bus: AccessibilityNotificationBus) {
        guard self == .process else { return }
        AccessibilityNotificationObserver.shared.subscribe(bus)
    }

    func stop(deliveringTo bus: AccessibilityNotificationBus) {
        guard self == .process else { return }
        AccessibilityNotificationObserver.shared.unsubscribe(bus)
    }
}

/// Coordinates semantic observation scheduling, capture, and delivery.
extension Observation {
@MainActor
internal final class Stream {
    private enum EventReceiver {
        case active(
            subscriptionID: UInt64,
            receive: @MainActor (Event) -> Void,
            pending: [Event],
            nextIndex: Int,
            isDelivering: Bool
        )

        var subscriptionID: UInt64 {
            switch self {
            case .active(let subscriptionID, _, _, _, _):
                subscriptionID
            }
        }
    }

    internal struct EventInstallation {
        internal let subscription: SemanticObservationSubscription
        internal let replay: Result<[Event], History.ReadError>
    }

    private struct CycleResult {
        let claim: AccessibilityNotificationCycleClaim
        let observationCommitted: Bool
    }

    weak var vault: TheVault?
    let tripwire: TheTripwire
    var readTripwireSignal: @MainActor () -> TheTripwire.TripwireSignal
    private var cycle = SemanticObservationCycle()
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
    var state = TheVault.State()
    var observationWaiters = WaiterStore<UInt64, SemanticObservationWaiter>()
    private var eventReceiver: EventReceiver?
    private let notificationIngress: AccessibilityNotificationIngress
    /// Runs at the top of every visible reading, before the tree is read.
    var beforeVisibleReading: @MainActor () async -> Void = {}
    var observationWaiterDidRegister: @MainActor () -> Void = {}

    // MARK: - Subscriber-Facing Observation History

    internal var isActive: Bool {
        cycle.isRunning
    }

    internal var observationWaiterCount: Int {
        observationWaiters.count
    }

    internal var activeObservationDemandCount: Int {
        scopePressure.activeDemandCount
    }

    internal var hasActiveObservationDemand: Bool {
        scopePressure.hasActiveDemand
    }

    var pulseDemand: TheTripwire.TickDemand {
        hasActiveObservationDemand ? .immediate : .ambient
    }

    internal init(
        vault: TheVault,
        tripwire: TheTripwire,
        notificationIngress: AccessibilityNotificationIngress
    ) {
        self.vault = vault
        self.tripwire = tripwire
        self.notificationIngress = notificationIngress
        self.readTripwireSignal = { tripwire.tripwireSignal() }
    }

    internal func start() {
        guard cycle.start() else { return }
        state.discardCurrentObservation()
        if let vault {
            notificationIngress.start(deliveringTo: vault.accessibilityNotifications)
        }
        tripwire.observePulses { [weak self] pulse in
            self?.receive(pulse)
        }
        updateCycleDemand()
    }

    internal func stop() {
        guard let stop = cycle.stop() else { return }
        tripwire.stopObservingPulses()
        stop.activeTask?.cancel()
        cancelObservationWaiters()
        if let vault {
            notificationIngress.stop(deliveringTo: vault.accessibilityNotifications)
        }
    }

    /// Raises the scope the vault reads at, without listening.
    ///
    /// Holding a scope is how a caller says how hard to look; the vault reads at
    /// the widest scope anyone holds. Event delivery is a separate question, and
    /// only the running heist asks for it.
    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        updateCycleDemand()
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    /// Raises the scope and atomically installs live delivery beside retained
    /// replay. The caller owns replay delivery after constructing its consumer.
    internal func subscribe(
        scope: SemanticObservationScope,
        replayingAfter historyIndex: Int,
        receive: @escaping @MainActor (Event) -> Void
    ) -> EventInstallation {
        precondition(
            eventReceiver == nil,
            "Only one observation event consumer may be active"
        )
        let subscription = subscribe(scope: scope)
        let replay = events(after: historyIndex)
        eventReceiver = .active(
            subscriptionID: subscription.id,
            receive: receive,
            pending: [],
            nextIndex: 0,
            isDelivering: false
        )
        return EventInstallation(subscription: subscription, replay: replay)
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
        if eventReceiver?.subscriptionID == id {
            eventReceiver = nil
        }
        updateCycleDemand()
    }

    func publish(_ publication: Publication) {
        guard let receiver = eventReceiver else { return }
        switch receiver {
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
    func invalidateCurrentAdmission() {
        state.invalidateCurrentAdmission()
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
        let demand = SemanticObservationDemand(
            id: scopePressure.addActiveDemand(),
            stream: self
        )
        updateCycleDemand()
        return demand
    }

    internal func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
        updateCycleDemand()
    }

    internal func currentTripwireSignal() -> TheTripwire.TripwireSignal {
        readTripwireSignal()
    }

    private func updateCycleDemand() {
        let scope = cycle.isRunning
            ? scopePressure.demandedObservationScope
            : nil
        tripwire.setObservationPulseDemand(
            cycle.demand(scope: scope, pulseDemand: pulseDemand)
        )
    }

    private func receive(_ pulse: TheTripwire.PulseReading) {
        cycle.receive(pulse) { [weak self] request in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.performObservationCycle(request)
                self.finishCycle(request.identity, result: result)
            }
        }
    }

    private func finishCycle(
        _ identity: SemanticObservationCycle.Identity,
        result: CycleResult?
    ) {
        guard let completedScope = cycle.complete(identity) else {
            return
        }
        let observationCommitted = result?.observationCommitted == true
        if observationCommitted, let result {
            precondition(
                result.claim.acknowledgeObservationCycle(),
                "A committed observation must acknowledge its exact notification claim"
            )
        }
        completeObservationWaiters(
            completedScope: completedScope,
            observationCommitted: observationCommitted
        )
    }

    private func performObservationCycle(
        _ request: SemanticObservationCycle.Request
    ) async -> CycleResult? {
        guard cycle.owns(request.identity) else {
            return nil
        }
        guard let vault else {
            stop()
            return nil
        }
        let claim = vault.accessibilityNotifications.freezeObservationCycleClaim()
        let committed = await observeSemanticState(
            scope: request.scope,
            pulse: request.pulse,
            notificationBatch: claim.batch
        )
        return CycleResult(
            claim: claim,
            observationCommitted: committed && cycle.owns(request.identity)
        )
    }

    /// One pulse, one reading, committed either way.
    ///
    /// Returning early when the admitted observation still holds looks free and
    /// is not: "nothing changed" is the answer stillness waits for, and skipping
    /// the read makes it unobtainable. The next reading only arrives when the
    /// tree moves, so a tree that reached the asked-for state and stayed there
    /// would never say so, and every expectation with a drained predicate would
    /// time out waiting for the tree to stop changing.
    private func observeSemanticState(
        scope: SemanticObservationScope,
        pulse: TheTripwire.PulseReading,
        notificationBatch: AccessibilityNotificationBatch
    ) async -> Bool {
        invalidateAdmissionIfSignalChanged(to: pulse.tripwireSignal)
        guard !Task.isCancelled else { return false }
        return await commitCurrentInterfaceObservation(
            tripwireSignal: pulse.tripwireSignal,
            scope: scope,
            notificationBatch: notificationBatch
        ).isCommitted
    }

    func invalidateAdmissionIfSignalChanged(to signal: TheTripwire.TripwireSignal) {
        state.invalidateAdmissionIfSignalChanged(to: signal)
    }

    internal func current() -> TheVault.State.Current? {
        state.current
    }

    internal func historyEndIndex() -> Int {
        state.history.endIndex
    }

    internal func notifications() -> [Observation.Notification] {
        state.notifications
    }

    internal var canonicalInterfaceTree: InterfaceTree {
        state.interfaceTree
    }

    internal func events(
        after historyIndex: Int
    ) -> Result<[Observation.Event], Observation.History.ReadError> {
        do {
            return .success(Array(
                try state.history.events(after: historyIndex)
            ))
        } catch {
            return .failure(error)
        }
    }

    internal func evidence(
        after boundary: TheVault.State.HistoryBoundary
    ) -> Observation.Evidence {
        state.evidence(after: boundary)
    }

    internal func observationBoundary(
        scope: SemanticObservationScope
    ) -> TheVault.State.HistoryBoundary {
        state.observationBoundary(scope: scope)
    }

    internal func protectHistory(from index: Int) {
        state.protectHistory(from: index)
    }

    internal func releaseHistory(from index: Int) {
        state.releaseHistory(from: index)
    }

    internal func advanceHistoryProtection(
        from index: Int,
        to nextIndex: Int
    ) {
        state.advanceHistoryProtection(from: index, to: nextIndex)
    }

    internal func reset(retentionLimit: Int = TheVault.State.defaultRetentionLimit) {
        state = TheVault.State(retentionLimit: retentionLimit)
    }

}
}

#endif // DEBUG
#endif // canImport(UIKit)
