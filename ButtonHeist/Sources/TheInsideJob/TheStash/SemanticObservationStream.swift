#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct SettledSemanticObservation: Sendable {
    let sequence: SettledObservationSequence
    let scope: SemanticObservationScope
    let tripwireSignal: TheTripwire.TripwireSignal
    private let semantic: SemanticScreen
    private let captureSnapshot: LiveCapture.Snapshot

    var screen: Screen {
        Screen(semantic: semantic, captureSnapshot: captureSnapshot)
    }

    init(
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal
    ) {
        self.sequence = sequence
        self.scope = scope
        self.tripwireSignal = tripwireSignal
        self.semantic = screen.semantic
        self.captureSnapshot = screen.liveCapture.snapshot
    }
}

struct SettledSemanticObservationEvent: Sendable {
    let sequence: SettledObservationSequence
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
    let settledObservationSequence: SettledObservationSequence?
    let settleOutcome: SettleOutcome
}

struct PostActionSettleObservation {
    enum Result {
        case committed(SettledSemanticObservationEvent)
        case diagnostic(Screen)
        case unavailable
    }

    let settle: SettleSession.Outcome
    let result: Result
}

private struct SemanticObservationFulfillmentState {
    typealias EventsByFulfilledScope = [SemanticObservationScope: SettledSemanticObservationEvent]

    struct CurrentFulfillment {
        let sourceEvent: SettledSemanticObservationEvent
        var eventsByFulfilledScope: EventsByFulfilledScope
    }

    enum State {
        case empty
        case clean(CurrentFulfillment)
        case invalidated(CurrentFulfillment?)
    }

    private var state: State = .empty

    var latestSourceEvent: SettledSemanticObservationEvent? {
        currentFulfillment?.sourceEvent
    }

    var latestSettledObservationInvalidated: Bool {
        switch state {
        case .empty, .invalidated:
            true
        case .clean:
            false
        }
    }

    var latestObservation: SettledSemanticObservation? {
        latestSourceEvent?.observation
    }

    mutating func clear() {
        state = .empty
    }

    mutating func invalidate() {
        switch state {
        case .empty:
            state = .invalidated(nil)
        case .clean(let fulfillment):
            state = .invalidated(fulfillment)
        case .invalidated(.some(let fulfillment)):
            state = .invalidated(fulfillment)
        case .invalidated(.none):
            break
        }
    }

    @MainActor
    mutating func publish(
        sourceScope: SemanticObservationScope,
        sequence: SettledObservationSequence,
        screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal,
        stash: TheStash
    ) -> EventsByFulfilledScope {
        var currentEvents = currentFulfillment?.eventsByFulfilledScope ?? [:]
        var events: EventsByFulfilledScope = [:]
        let pendingAccessibilityNotifications = stash.accessibilityNotifications.drainPendingEvents()
        var sourceEvent: SettledSemanticObservationEvent?
        for fulfilledScope in sourceScope.fulfilledScopes {
            let observation = SettledSemanticObservation(
                sequence: sequence,
                scope: fulfilledScope,
                screen: screen.semanticObservationProjection(for: fulfilledScope),
                tripwireSignal: tripwireSignal
            )
            let event = SemanticObservationEventFactory.makeEvent(
                observation: observation,
                previous: currentEvents[fulfilledScope],
                stash: stash,
                pendingAccessibilityNotifications: pendingAccessibilityNotifications
            )
            currentEvents[fulfilledScope] = event
            events[fulfilledScope] = event

            if fulfilledScope == sourceScope {
                sourceEvent = event
            }
        }
        guard let sourceEvent else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        state = .clean(CurrentFulfillment(
            sourceEvent: sourceEvent,
            eventsByFulfilledScope: currentEvents
        ))
        return events
    }

    func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard case .clean(let fulfillment) = state,
              let latest = fulfillment.eventsByFulfilledScope[scope],
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }

    private var currentFulfillment: CurrentFulfillment? {
        switch state {
        case .empty:
            return nil
        case .clean(let fulfillment):
            return fulfillment
        case .invalidated(let fulfillment):
            return fulfillment
        }
    }
}

@MainActor
final class SemanticObservationStream {
    /// An active stream is an observation lease. Baseline cycles observe the
    /// visible world; subscribers can widen demand to discovery.
    typealias DiscoveryObservation = @MainActor () async -> Screen?

    private enum PassiveObservationState {
        case stopped
        case running(
            task: Task<Void, Never>,
            discovery: DiscoveryObservation,
            settledReading: TheTripwire.PulseReading?
        )

        var isRunning: Bool {
            switch self {
            case .stopped:
                return false
            case .running:
                return true
            }
        }

        var task: Task<Void, Never>? {
            switch self {
            case .stopped:
                return nil
            case .running(let task, _, _):
                return task
            }
        }

        var discovery: DiscoveryObservation? {
            switch self {
            case .stopped:
                return nil
            case .running(_, let discovery, _):
                return discovery
            }
        }

        var settledReading: TheTripwire.PulseReading? {
            switch self {
            case .stopped:
                return nil
            case .running(_, _, let settledReading):
                return settledReading
            }
        }

        mutating func replaceDiscovery(_ discovery: @escaping DiscoveryObservation) {
            guard case .running(let task, _, let settledReading) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: settledReading)
        }

        mutating func updateSettledReading(_ reading: TheTripwire.PulseReading?) {
            guard case .running(let task, let discovery, _) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: reading)
        }
    }

    private weak var stash: TheStash?
    private let tripwire: TheTripwire
    private static let rootUnavailableRecoveryTimeoutMs = 3_000

    // MARK: - Observation Bookkeeping

    private var scopePressure = SemanticObservationScopePressure()
    private let settledWaiters = SemanticObservationSettledWaiters()
    private let cycles = SemanticObservationCycles()

    // MARK: - Subscriber-Facing Settled Observation History

    private var settledSequence: SettledObservationSequence = 0
    private var fulfillmentState = SemanticObservationFulfillmentState()
    var latestEvent: SettledSemanticObservationEvent? {
        fulfillmentState.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheStash` until the next explicit
    /// commit.
    var latestSettledObservationInvalidated: Bool {
        fulfillmentState.latestSettledObservationInvalidated
    }
    private(set) var latestSettleFailureDiagnostic: String?

    // MARK: - Passive Observation Scheduling

    private var passiveObservationState: PassiveObservationState = .stopped

    var latestObservation: SettledSemanticObservation? {
        fulfillmentState.latestObservation
    }

    var isActive: Bool {
        passiveObservationState.isRunning
    }

    var settledWaiterCount: Int {
        settledWaiters.count
    }

    var cycleWaiterCount: Int {
        cycles.waiterCount
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
        guard !passiveObservationState.isRunning else {
            passiveObservationState.replaceDiscovery(discovery)
            return
        }
        if let stash {
            AccessibilityNotificationObserver.shared.subscribe(stash.accessibilityNotifications)
        }
        fulfillmentState.invalidate()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
        passiveObservationState = .running(task: task, discovery: discovery, settledReading: nil)
    }

    func stop() {
        passiveObservationState.task?.cancel()
        passiveObservationState = .stopped
        cycles.cancelRunningCycle()
        settledWaiters.completeAll(returning: nil)
        cycles.completeAllWaiters()
        if let stash {
            AccessibilityNotificationObserver.shared.unsubscribe(stash.accessibilityNotifications)
            stash.accessibilityNotifications.clearPendingEvents()
        }
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
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard isActive else { return nil }
            if scope == .visible {
                _ = stash?.refreshCurrentVisibleTree()
                return cleanEvent(scope: scope, after: requiredSequence)
            }
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

        let initialOutcome = await SemanticObservationSettleCadence.settleVisibleObservationForCurrentDemand(
            hasActiveDemand: hasActiveObservationDemand,
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: latestEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal(),
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        let outcome = await recoverTransientRootUnavailableIfNeeded(
            initialOutcome,
            stash: stash,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )

        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordFailedSettleDiagnosticEvidence(outcome.finalScreen, stash: stash)
            return nil
        }

        guard let screen = outcome.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordFailedSettleDiagnosticEvidence(nil, stash: stash)
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
        recordFailedSettleDiagnosticEvidence(screen, stash: stash)
        return nil
    }

    private func recoverTransientRootUnavailableIfNeeded(
        _ outcome: SettleSession.Outcome,
        stash: TheStash,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        guard timeoutMs >= 1_000,
              outcome.finalScreen == nil,
              latestEvent != nil
        else { return outcome }
        if case .cancelled = outcome.outcome {
            return outcome
        }
        return await SemanticObservationSettleCadence.settleVisibleObservationAtIdleCadence(
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: tripwire.tripwireSignal(),
            timeoutMs: Self.rootUnavailableRecoveryTimeoutMs
        )
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
        commitScope: SemanticObservationScope = .visible,
        settleOutcome providedOutcome: SettleSession.Outcome? = nil
    ) async -> PostActionSettleObservation {
        guard let stash else {
            return PostActionSettleObservation(
                settle: SettleSession.Outcome(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalScreen: nil,
                    elementsByKey: [:]
                ),
                result: .unavailable
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
            recordFailedSettleDiagnosticEvidence(outcome.finalScreen, stash: stash)
            return PostActionSettleObservation(settle: outcome, result: .unavailable)
        }

        guard let finalScreen = outcome.finalScreen else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordFailedSettleDiagnosticEvidence(nil, stash: stash)
            return PostActionSettleObservation(settle: outcome, result: .unavailable)
        }
        if outcome.outcome.didSettleCleanly {
            let event: SettledSemanticObservationEvent
            switch commitScope {
            case .visible:
                event = commitSettledVisibleObservation(finalScreen)
            case .discovery:
                event = commitSettledDiscoveryObservation(stash.settledSemanticScreen.merging(finalScreen))
            }
            return PostActionSettleObservation(settle: outcome, result: .committed(event))
        }

        latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
        recordFailedSettleDiagnosticEvidence(finalScreen, stash: stash)
        return PostActionSettleObservation(
            settle: outcome,
            result: stash.latestFailedSettleDiagnosticEvidence.map { .diagnostic($0) } ?? .unavailable
        )
    }

    func clearSettledObservationHistory() {
        fulfillmentState.clear()
        passiveObservationState.updateSettledReading(nil)
        latestSettleFailureDiagnostic = nil
    }

    func invalidateLatestSettledObservation() {
        fulfillmentState.invalidate()
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        stash: TheStash
    ) -> SettledSemanticObservationEvent {
        settledSequence += 1
        let events = fulfillmentState.publish(
            sourceScope: scope,
            sequence: settledSequence,
            screen: stash.settledSemanticScreen,
            tripwireSignal: tripwire.tripwireSignal(),
            stash: stash
        )
        guard let sourceEvent = events[scope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        latestSettleFailureDiagnostic = nil
        passiveObservationState.updateSettledReading(tripwire.latestReading)
        settledWaiters.completeWaiters(with: events)
        return sourceEvent
    }

    private func waitForNextSettledEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: SettledObservationSequence?,
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
        after sequence: SettledObservationSequence?
    ) -> SettledObservationSequence? {
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
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        fulfillmentState.cleanEvent(scope: scope, after: sequence)
    }

    private func runPassiveObservationCycle() async {
        let scope = subscribedObservationScope()
        guard case .started(let cycle) = cycles.beginCycle(scope: scope) else {
            _ = await Task.cancellableSleep(for: .milliseconds(10))
            return
        }
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, didObserve: false)
            return
        }
        let didObserve = await performObservationCycle(scope: scope)
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, didObserve: false)
            return
        }
        cycles.finishCycle(token: cycle, didObserve: didObserve)
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
            guard let discovery = passiveObservationState.discovery else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            guard let exploredScreen = await discovery() else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            guard !Task.isCancelled else { return false }
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
           passiveObservationState.settledReading?.tick == reading.tick {
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
            recordFailedSettleDiagnosticEvidence(settle.finalScreen, stash: stash)
            await Task.yield()
            return true
        }

        guard !Task.isCancelled else { return false }
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
            recordFailedSettleDiagnosticEvidence(settle.finalScreen, stash: stash)
            await Task.yield()
            return true
        }

        guard !Task.isCancelled else { return false }
        _ = commitSettledVisibleObservation(screen)
        await Task.yield()
        return true
    }

    private func recordFailedSettleDiagnosticEvidence(_ screen: Screen?, stash: TheStash) {
        stash.accessibilityNotifications.clearPendingEvents()
        stash.recordFailedSettleDiagnosticEvidence(screen)
    }

}

private extension Screen {
    func semanticObservationProjection(for scope: SemanticObservationScope) -> Screen {
        switch scope {
        case .visible:
            return visibleOnly
        case .discovery:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
