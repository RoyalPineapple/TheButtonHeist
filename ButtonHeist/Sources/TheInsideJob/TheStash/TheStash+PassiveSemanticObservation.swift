#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheStash {
    typealias DiscoveryObservation = @MainActor () async -> Void

    func startPassiveSemanticObservation(discovery: @escaping DiscoveryObservation) {
        passiveSemanticDiscoveryObservation = discovery
        guard passiveSemanticObservationTask == nil else { return }
        latestSettledSemanticObservationIsDirty = true
        passiveSemanticObservationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveSemanticObservationCycle(discovery: discovery)
            }
        }
    }

    func stopPassiveSemanticObservation() {
        passiveSemanticObservationTask?.cancel()
        passiveSemanticObservationTask = nil
        passiveSemanticDiscoveryObservation = nil
        passiveObservationSettledReading = nil
        completeAllSettledSemanticWaiters(returning: nil)
        completeAllSemanticObservationCycleWaiters()
    }

    func subscribeSemanticObservation(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = nextSemanticObservationSubscriptionID
        nextSemanticObservationSubscriptionID += 1
        semanticObservationSubscriptions[id] = scope
        return SemanticObservationSubscription(id: id, scope: scope, stash: self)
    }

    func removeSemanticObservationSubscription(_ id: UInt64) {
        semanticObservationSubscriptions[id] = nil
    }

    func currentSubscribedObservationScope() -> SemanticObservationScope {
        semanticObservationSubscriptions.values.max() ?? .visible
    }

    func settledSemanticObservationEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let subscription = subscribeSemanticObservation(scope: scope)
        defer { _ = subscription }

        let requiredSequence = semanticObservationBaselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard passiveSemanticObservationTask != nil else { return nil }
            await waitForNextSemanticObservationCycle(
                scope: scope,
                after: semanticObservationBaselineCycle()
            )
            return cleanSettledSemanticObservationEvent(scope: scope, after: requiredSequence)
        }

        if sequence == nil, scope == .visible {
            if passiveSemanticObservationTask != nil {
                await waitForNextSemanticObservationCycle(
                    scope: scope,
                    after: semanticObservationBaselineCycle()
                )
            } else {
                return await waitForNextSettledSemanticObservationEvent(
                    scope: scope,
                    after: latestSettledSemanticObservation?.sequence,
                    timeout: timeout
                )
            }
        }

        if let latest = cleanSettledSemanticObservationEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        return await waitForNextSettledSemanticObservationEvent(
            scope: scope,
            after: requiredSequence,
            timeout: timeout
        )
    }

    private func waitForNextSettledSemanticObservationEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let requiredSequence = semanticObservationBaselineSequence(for: scope, after: sequence)

        if let latest = cleanSettledSemanticObservationEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let id = nextSettledSemanticWaiterID
        nextSettledSemanticWaiterID += 1

        return await withCheckedContinuation { continuation in
            let timeoutTask: Task<Void, Never>? = observationWaitTimeout(timeout).map { timeout in
                Task { [weak self] in
                    let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                    guard await Task.cancellableSleep(for: .nanoseconds(nanoseconds)) else { return }
                    self?.completeSettledSemanticWaiter(id, returning: nil)
                }
            }
            settledSemanticWaiters[id] = SettledSemanticWaiter(
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

    private func semanticObservationBaselineSequence(
        for scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> UInt64? {
        let currentSequence = latestSettledSemanticObservationEvent?.sequence
        if scope == .discovery {
            let baseline = sequence ?? currentSequence
            return max(baseline ?? 0, currentSequence ?? 0)
        }
        if sequence == nil, passiveSemanticObservationTask == nil {
            return currentSequence
        }
        return sequence
    }

    private func semanticObservationBaselineCycle() -> UInt64 {
        semanticObservationCycleSequence + (semanticObservationCycleInProgress ? 1 : 0)
    }

    private func cleanSettledSemanticObservationEvent(
        scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> SettledSemanticObservationEvent? {
        guard !latestSettledSemanticObservationIsDirty,
              let latest = latestSettledSemanticObservationEvent,
              latest.scope >= scope,
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }

    func markDirtyFromTripwire() {
        latestSettledSemanticObservationIsDirty = true
    }

    func markCurrentSemanticObservationSettled(scope: SemanticObservationScope = .visible) {
        settledSemanticSequence += 1
        let observation = SettledSemanticObservation(
            sequence: settledSemanticSequence,
            scope: scope,
            screen: currentScreen,
            tripwireSignal: tripwire.tripwireSignal()
        )
        let event = makeSettledSemanticObservationEvent(
            observation: observation,
            previous: latestSettledSemanticObservationEvent
        )
        latestSettledSemanticObservationEvent = event
        latestSettledSemanticObservationIsDirty = false
        passiveObservationSettledReading = tripwire.latestReading
        completeSettledSemanticWaiters(with: event)
    }

    private func makeSettledSemanticObservationEvent(
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservationEvent?
    ) -> SettledSemanticObservationEvent {
        let previousCapture = previous?.trace.captures.last
        let currentCapture = semanticTraceCapture(
            for: observation,
            sequence: previousCapture == nil ? 1 : 2,
            parentHash: previousCapture?.hash
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
            delta: trace.endpointDeltaProjection
        )
    }

    private func semanticTraceCapture(
        for observation: SettledSemanticObservation,
        sequence: Int,
        parentHash: String?
    ) -> AccessibilityTrace.Capture {
        let interface = semanticInterfaceWithHash(for: observation.screen).interface
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

    private func runPassiveSemanticObservationCycle(discovery: @escaping DiscoveryObservation) async {
        let scope = currentSubscribedObservationScope()
        semanticObservationCycleInProgress = true
        let didObserve = await performSemanticObservationCycle(scope: scope, discovery: discovery)
        semanticObservationCycleInProgress = false
        guard didObserve else { return }
        semanticObservationCycleSequence += 1
        completeSemanticObservationCycleWaiters(scope: scope)
        await Task.yield()
    }

    private func performSemanticObservationCycle(
        scope: SemanticObservationScope,
        discovery: DiscoveryObservation?
    ) async -> Bool {
        switch scope {
        case .visible:
            return await observeVisibleSemanticState()
        case .discovery:
            guard let discovery else {
                markDirtyFromTripwire()
                await Task.yield()
                return true
            }
            await discovery()
            markCurrentSemanticObservationSettled(scope: .discovery)
            await Task.yield()
            return true
        }
    }

    private func observeVisibleSemanticState() async -> Bool {
        if let reading = tripwire.latestReading,
           !latestSettledSemanticObservationIsDirty,
           passiveObservationSettledReading?.tick == reading.tick {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            return true
        }

        guard await tripwire.waitForAllClear(timeout: 0.5) else {
            markDirtyFromTripwire()
            await Task.yield()
            return true
        }

        let baselineSignal = latestSettledSemanticObservationEvent?.observation.tripwireSignal ?? tripwire.tripwireSignal()
        let settleSession = SettleSession.live(stash: self, tripwire: tripwire, timeoutMs: 1_000)
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineSignal
        )

        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else {
            markDirtyFromTripwire()
            await Task.yield()
            return true
        }

        recordSettledSemanticObservation(screen, scope: .visible)
        await Task.yield()
        return true
    }

    private func waitForNextSemanticObservationCycle(
        scope: SemanticObservationScope,
        after cycle: UInt64
    ) async {
        let id = nextSemanticObservationCycleWaiterID
        nextSemanticObservationCycleWaiterID += 1

        return await withCheckedContinuation { continuation in
            semanticObservationCycleWaiters[id] = SemanticObservationCycleWaiter(
                scope: scope,
                afterCycle: cycle,
                continuation: continuation
            )
        }
    }

    private func completeSemanticObservationCycleWaiters(scope: SemanticObservationScope) {
        for (id, waiter) in semanticObservationCycleWaiters {
            guard scope >= waiter.scope else { continue }
            guard semanticObservationCycleSequence > waiter.afterCycle else { continue }
            completeSemanticObservationCycleWaiter(id)
        }
    }

    private func completeAllSemanticObservationCycleWaiters() {
        for id in Array(semanticObservationCycleWaiters.keys) {
            completeSemanticObservationCycleWaiter(id)
        }
    }

    private func completeSemanticObservationCycleWaiter(_ id: UInt64) {
        guard let waiter = semanticObservationCycleWaiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume()
    }

    private func completeSettledSemanticWaiters(with event: SettledSemanticObservationEvent) {
        for (id, waiter) in settledSemanticWaiters {
            guard event.scope >= waiter.scope else { continue }
            guard event.sequence > (waiter.afterSequence ?? 0) else { continue }
            completeSettledSemanticWaiter(id, returning: event)
        }
    }

    func completeAllSettledSemanticWaiters(returning event: SettledSemanticObservationEvent?) {
        for id in Array(settledSemanticWaiters.keys) {
            completeSettledSemanticWaiter(id, returning: event)
        }
    }

    private func completeSettledSemanticWaiter(
        _ id: UInt64,
        returning event: SettledSemanticObservationEvent?
    ) {
        guard let waiter = settledSemanticWaiters.removeValue(forKey: id) else { return }
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: event)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
