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
    struct CycleExecutionIdentity: Equatable {
        fileprivate let generation: UInt64
    }

    struct CycleExecutionOwnership<Handle> {
        private enum Phase {
            case idle(lastGeneration: UInt64)
            case active(identity: CycleExecutionIdentity, handle: Handle)
        }

        private var phase = Phase.idle(lastGeneration: 0)

        mutating func begin(
            execution: (CycleExecutionIdentity) -> Handle
        ) -> CycleExecutionIdentity {
            guard case .idle(let lastGeneration) = phase else {
                preconditionFailure("A semantic observation cycle is already active")
            }
            let (generation, overflow) = lastGeneration.addingReportingOverflow(1)
            precondition(!overflow, "Semantic observation cycle generation overflow")
            let identity = CycleExecutionIdentity(generation: generation)
            phase = .active(
                identity: identity,
                handle: execution(identity)
            )
            return identity
        }

        mutating func invalidate() -> Handle? {
            guard case .active(let identity, let handle) = phase else {
                return nil
            }
            phase = .idle(lastGeneration: identity.generation)
            return handle
        }

        mutating func admitCompletion(
            for identity: CycleExecutionIdentity
        ) -> Handle? {
            guard case .active(let activeIdentity, let handle) = phase,
                  activeIdentity == identity
            else { return nil }
            phase = .idle(lastGeneration: activeIdentity.generation)
            return handle
        }

        func owns(_ identity: CycleExecutionIdentity) -> Bool {
            guard case .active(let activeIdentity, _) = phase else {
                return false
            }
            return activeIdentity == identity
        }
    }

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

    weak var vault: TheVault?
    let tripwire: TheTripwire
    var readTripwireSignal: @MainActor () -> TheTripwire.TripwireSignal
    private var cycle = SemanticObservationCycle()
    private var cycleExecution = CycleExecutionOwnership<Task<Void, Never>>()
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
        guard lifecycle.start() else { return }
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
        guard lifecycle.stop() else { return }
        tripwire.stopObservingPulses()
        let task = cycleExecution.invalidate()
        task?.cancel()
        cycle.stop()
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
    ) -> SemanticObservationSubscription {
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
        let replay = events(after: historyIndex)
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
        updateCycleDemand()
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
        let scope = lifecycle.isRunning
            ? scopePressure.demandedObservationScope
            : nil
        tripwire.setObservationPulseDemand(
            cycle.demand(scope: scope, pulseDemand: pulseDemand)
        )
    }

    private func receive(_ pulse: TheTripwire.PulseReading) {
        if let request = cycle.receive(pulse) {
            startCycle(request)
        }
    }

    private func startCycle(_ request: SemanticObservationCycle.Request) {
        var nextExecution = cycleExecution
        _ = nextExecution.begin { [weak self] identity in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let committed = await self.performObservationCycle(
                    executionIdentity: identity,
                    scope: request.scope,
                    pulse: request.pulse
                )
                self.finishCycle(
                    executionIdentity: identity,
                    attemptedScope: request.scope,
                    observationCommitted: committed
                )
            }
        }
        cycleExecution = nextExecution
    }

    private func finishCycle(
        executionIdentity: CycleExecutionIdentity,
        attemptedScope: SemanticObservationScope,
        observationCommitted: Bool
    ) {
        guard cycleExecution.admitCompletion(for: executionIdentity) != nil else {
            return
        }
        completeObservationWaiters(
            completedScope: attemptedScope,
            observationCommitted: observationCommitted
        )
        cycle.complete()
    }

    private func performObservationCycle(
        executionIdentity: CycleExecutionIdentity,
        scope: SemanticObservationScope,
        pulse: TheTripwire.PulseReading
    ) async -> Bool {
        guard cycleExecution.owns(executionIdentity) else { return false }
        guard let vault else {
            stop()
            return false
        }
        let claim = vault.accessibilityNotifications.freezeObservationCycleClaim()
        let committed = await observeSemanticState(
            scope: scope,
            pulse: pulse,
            notificationBatch: claim.batch
        )
        guard committed, cycleExecution.owns(executionIdentity) else {
            return false
        }
        precondition(
            claim.acknowledgeObservationCycle(),
            "A committed observation must acknowledge its exact notification claim"
        )
        return true
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

    internal func notificationIndex() -> AccessibilityNotificationCursor {
        state.notificationIndex
    }

    internal func historyEndIndex() -> Int {
        state.history.endIndex
    }

    internal func notifications() -> [Observation.Notification] {
        state.notifications
    }

    internal func scopedScreenChangedSequence() -> UInt64 {
        state.scopedScreenChangedSequence
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
