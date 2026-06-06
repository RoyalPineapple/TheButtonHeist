#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct SettledSemanticObservation {
    let sequence: UInt64
    let scope: SemanticObservationScope
    let screen: Screen
    let tripwireSignal: TheTripwire.TripwireSignal
}

struct SettledSemanticObservationEvent {
    let sequence: UInt64
    let scope: SemanticObservationScope
    let observation: SettledSemanticObservation
    let previous: SettledSemanticObservation?
    let trace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?

    var currentCaptureRef: AccessibilityTrace.CaptureRef? {
        trace.captures.last.map(AccessibilityTrace.CaptureRef.init(capture:))
    }
}

struct VisibleSemanticObservationEvidence {
    let screen: Screen
    let tripwireSignal: TheTripwire.TripwireSignal
    let settledObservationSequence: UInt64?
    let settleOutcome: SettleOutcome
}

@MainActor
final class SemanticObservationStream {
    typealias DiscoveryObservation = @MainActor () async -> Void

    struct SettledSemanticWaiter {
        let scope: SemanticObservationScope
        let afterSequence: UInt64?
        let continuation: CheckedContinuation<SettledSemanticObservationEvent?, Never>
        let timeoutTask: Task<Void, Never>?
    }

    private struct SemanticObservationCycleWaiter {
        let scope: SemanticObservationScope
        let afterCycle: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private weak var stash: TheStash?
    private let tripwire: TheTripwire

    private var nextSubscriptionID: UInt64 = 0
    private var subscriptions: [UInt64: SemanticObservationScope] = [:]

    private var nextSettledWaiterID: UInt64 = 0
    private var settledWaitersByID: [UInt64: SettledSemanticWaiter] = [:]

    private var nextCycleWaiterID: UInt64 = 0
    private var cycleWaiters: [UInt64: SemanticObservationCycleWaiter] = [:]
    private var cycleSequence: UInt64 = 0
    private var cycleInProgress = false

    private var settledSequence: UInt64 = 0
    private(set) var latestEvent: SettledSemanticObservationEvent?
    private(set) var latestObservationIsDirty = true
    private(set) var latestSettleFailureDiagnostic: String?

    private(set) var passiveObservationTask: Task<Void, Never>?
    private var discoveryObservation: DiscoveryObservation?
    private var passiveObservationSettledReading: TheTripwire.PulseReading?

    var latestObservation: SettledSemanticObservation? {
        latestEvent?.observation
    }

    var isActive: Bool {
        passiveObservationTask != nil
    }

    var settledWaiterCount: Int {
        settledWaitersByID.count
    }

    init(stash: TheStash, tripwire: TheTripwire) {
        self.stash = stash
        self.tripwire = tripwire
    }

    func start(discovery: @escaping DiscoveryObservation) {
        discoveryObservation = discovery
        guard passiveObservationTask == nil else { return }
        latestObservationIsDirty = true
        passiveObservationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
    }

    func stop() {
        passiveObservationTask?.cancel()
        passiveObservationTask = nil
        discoveryObservation = nil
        passiveObservationSettledReading = nil
        completeAllWaiters(returning: nil)
        completeAllCycleWaiters()
    }

    func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = nextSubscriptionID
        nextSubscriptionID += 1
        subscriptions[id] = scope
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    func removeSubscription(_ id: UInt64) {
        subscriptions[id] = nil
    }

    func currentSubscribedScope() -> SemanticObservationScope {
        subscriptions.values.max() ?? .visible
    }

    func settledEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard isActive else { return nil }
            await waitForNextCycle(scope: scope, after: baselineCycle())
            return cleanEvent(scope: scope, after: requiredSequence)
        }

        if sequence == nil, scope == .visible {
            if isActive {
                await waitForNextCycle(scope: scope, after: baselineCycle())
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
            await waitForNextCycle(scope: scope, after: baselineCycle())
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

        let settleSession = SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        let outcome = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: latestEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal()
        )

        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = Self.failureDiagnostic(for: outcome)
            return nil
        }

        guard let screen = outcome.finalScreen else {
            latestSettleFailureDiagnostic = Self.failureDiagnostic(for: outcome)
            return nil
        }

        if outcome.outcome.didSettleCleanly {
            let event = commitSettledObservation(screen, scope: .visible)
            return VisibleSemanticObservationEvidence(
                screen: event.observation.screen,
                tripwireSignal: event.observation.tripwireSignal,
                settledObservationSequence: event.sequence,
                settleOutcome: outcome.outcome
            )
        }

        latestSettleFailureDiagnostic = Self.failureDiagnostic(for: outcome)
        stash.commitVisibleRefresh(screen)
        return VisibleSemanticObservationEvidence(
            screen: stash.currentScreen,
            tripwireSignal: tripwire.tripwireSignal(),
            settledObservationSequence: nil,
            settleOutcome: outcome.outcome
        )
    }

    @discardableResult
    func commitSettledObservation(
        _ screen: Screen,
        scope: SemanticObservationScope = .visible
    ) -> SettledSemanticObservationEvent {
        guard let stash else {
            preconditionFailure("SemanticObservationStream cannot commit after TheStash is released")
        }
        stash.storeSettledSemanticObservationForStream(screen)
        return publishCurrentSettledObservation(scope: scope, stash: stash)
    }

    func settlePostActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        settleOutcome providedOutcome: SettleSession.Outcome? = nil
    ) async -> (settle: SettleSession.Outcome, event: SettledSemanticObservationEvent?, diagnosticScreen: Screen?) {
        guard let stash else {
            return (
                SettleSession.Outcome(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalScreen: nil,
                    elementsByKey: [:]
                ),
                nil,
                nil
            )
        }
        let outcome: SettleSession.Outcome
        if let providedOutcome {
            outcome = providedOutcome
        } else {
            let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
            outcome = await settleSession.run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: baselineTripwireSignal
            )
        }

        if case .cancelled = outcome.outcome {
            return (outcome, nil, nil)
        }

        guard let finalScreen = outcome.finalScreen else { return (outcome, nil, nil) }
        if outcome.outcome.didSettleCleanly {
            return (outcome, commitSettledObservation(finalScreen, scope: .visible), nil)
        }

        latestSettleFailureDiagnostic = Self.failureDiagnostic(for: outcome)
        stash.commitVisibleRefresh(finalScreen)
        return (outcome, nil, stash.currentScreen)
    }

    func clearLatestObservation() {
        latestEvent = nil
        latestObservationIsDirty = true
        passiveObservationSettledReading = nil
        latestSettleFailureDiagnostic = nil
    }

    func markDirtyFromTripwire() {
        latestObservationIsDirty = true
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        stash: TheStash
    ) -> SettledSemanticObservationEvent {
        settledSequence += 1
        let observation = SettledSemanticObservation(
            sequence: settledSequence,
            scope: scope,
            screen: stash.currentScreen,
            tripwireSignal: tripwire.tripwireSignal()
        )
        let event = makeEvent(observation: observation, previous: latestEvent, stash: stash)
        latestEvent = event
        latestObservationIsDirty = false
        latestSettleFailureDiagnostic = nil
        passiveObservationSettledReading = tripwire.latestReading
        completeWaiters(with: event)
        return event
    }

    func completeAllWaiters(returning event: SettledSemanticObservationEvent?) {
        for id in Array(settledWaitersByID.keys) {
            completeWaiter(id, returning: event)
        }
    }

    private func waitForNextSettledEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if let latest = cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let id = nextSettledWaiterID
        nextSettledWaiterID += 1

        return await withCheckedContinuation { continuation in
            let timeoutTask: Task<Void, Never>? = observationWaitTimeout(timeout).map { timeout in
                Task { [weak self] in
                    let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                    guard await Task.cancellableSleep(for: .nanoseconds(nanoseconds)) else { return }
                    self?.completeWaiter(id, returning: nil)
                }
            }
            settledWaitersByID[id] = SettledSemanticWaiter(
                scope: scope,
                afterSequence: requiredSequence,
                continuation: continuation,
                timeoutTask: timeoutTask
            )
        }
    }

    private func observationWaitTimeout(_ timeout: Double?) -> Double? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return nil }
        return timeout
    }

    private static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        return max(1, Int((timeout * 1_000).rounded(.up)))
    }

    private func baselineSequence(
        for scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> UInt64? {
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

    private func baselineCycle() -> UInt64 {
        cycleSequence + (cycleInProgress ? 1 : 0)
    }

    private func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> SettledSemanticObservationEvent? {
        guard !latestObservationIsDirty,
              let latest = latestEvent,
              latest.scope >= scope,
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }

    private func makeEvent(
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservationEvent?,
        stash: TheStash
    ) -> SettledSemanticObservationEvent {
        let previousCapture = previous?.trace.captures.last
        let currentCapture = semanticTraceCapture(
            for: observation,
            sequence: previousCapture == nil ? 1 : 2,
            parentHash: previousCapture?.hash,
            stash: stash
        )
        let trace = if let previousCapture {
            AccessibilityTrace(captures: [previousCapture, currentCapture])
        } else {
            AccessibilityTrace(capture: currentCapture)
        }
        return SettledSemanticObservationEvent(
            sequence: observation.sequence,
            scope: observation.scope,
            observation: observation,
            previous: previous?.observation,
            trace: trace,
            delta: trace.endpointDelta
        )
    }

    private func semanticTraceCapture(
        for observation: SettledSemanticObservation,
        sequence: Int,
        parentHash: String?,
        stash: TheStash
    ) -> AccessibilityTrace.Capture {
        let interface = stash.semanticInterfaceWithHash(for: observation.screen).interface
        let windows = observation.tripwireSignal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: AccessibilityTrace.Context(
                screenId: observation.screen.id,
                windowStack: windows
            )
        )
    }

    private func runPassiveObservationCycle() async {
        let scope = currentSubscribedScope()
        cycleInProgress = true
        let didObserve = await performObservationCycle(scope: scope)
        cycleInProgress = false
        guard didObserve else { return }
        cycleSequence += 1
        completeCycleWaiters(scope: scope)
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
            guard let discoveryObservation else {
                markDirtyFromTripwire()
                await Task.yield()
                return true
            }
            await discoveryObservation()
            _ = publishCurrentSettledObservation(scope: .discovery, stash: stash)
            await Task.yield()
            return true
        }
    }

    private func observeVisibleSemanticState(stash: TheStash) async -> Bool {
        if let reading = tripwire.latestReading,
           !latestObservationIsDirty,
           passiveObservationSettledReading?.tick == reading.tick {
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
            latestSettleFailureDiagnostic = Self.failureDiagnostic(
                for: settle,
                layerGateWasClear: layerGateWasClear
            )
            markDirtyFromTripwire()
            await Task.yield()
            return true
        }

        _ = commitSettledObservation(screen, scope: .visible)
        await Task.yield()
        return true
    }

    private static func failureDiagnostic(
        for outcome: SettleSession.Outcome,
        layerGateWasClear: Bool? = nil
    ) -> String {
        var parts = ["settle \(outcome.outcome.outcomeDescription)"]
        if let finalScreen = outcome.finalScreen {
            parts.append("last parsed: \(finalScreen.liveCapture.hierarchy.sortedElements.count) elements")
        } else {
            parts.append("last parsed: no accessibility tree")
        }
        if let instability = outcome.instabilityDescription {
            parts.append(instability)
        }
        if layerGateWasClear == false {
            parts.append("layer motion still active while AX settle ran")
        }
        return parts.joined(separator: "; ")
    }

    private func waitForNextCycle(scope: SemanticObservationScope, after cycle: UInt64) async {
        let id = nextCycleWaiterID
        nextCycleWaiterID += 1

        return await withCheckedContinuation { continuation in
            cycleWaiters[id] = SemanticObservationCycleWaiter(
                scope: scope,
                afterCycle: cycle,
                continuation: continuation
            )
        }
    }

    private func completeCycleWaiters(scope: SemanticObservationScope) {
        for (id, waiter) in cycleWaiters {
            guard scope >= waiter.scope else { continue }
            guard cycleSequence > waiter.afterCycle else { continue }
            completeCycleWaiter(id)
        }
    }

    private func completeAllCycleWaiters() {
        for id in Array(cycleWaiters.keys) {
            completeCycleWaiter(id)
        }
    }

    private func completeCycleWaiter(_ id: UInt64) {
        guard let waiter = cycleWaiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume()
    }

    private func completeWaiters(with event: SettledSemanticObservationEvent) {
        for (id, waiter) in settledWaitersByID {
            guard event.scope >= waiter.scope else { continue }
            guard event.sequence > (waiter.afterSequence ?? 0) else { continue }
            completeWaiter(id, returning: event)
        }
    }

    private func completeWaiter(_ id: UInt64, returning event: SettledSemanticObservationEvent?) {
        guard let waiter = settledWaitersByID.removeValue(forKey: id) else { return }
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: event)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
