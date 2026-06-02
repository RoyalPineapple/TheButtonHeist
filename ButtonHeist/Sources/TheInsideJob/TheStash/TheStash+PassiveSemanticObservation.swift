#if canImport(UIKit)
#if DEBUG
import Foundation

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

    func settledSemanticObservation(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservation? {
        let subscription = subscribeSemanticObservation(scope: scope)
        defer { _ = subscription }

        let requiredSequence = semanticObservationBaselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            await performSingleSemanticObservationCycle(scope: scope)
            return cleanSettledSemanticObservation(scope: scope, after: requiredSequence)
        }

        if let latest = cleanSettledSemanticObservation(scope: scope, after: requiredSequence) {
            return latest
        }

        return await waitForNextSettledSemanticObservation(
            scope: scope,
            after: requiredSequence,
            timeout: timeout
        )
    }

    private func waitForNextSettledSemanticObservation(
        scope: SemanticObservationScope = .visible,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> SettledSemanticObservation? {
        let requiredSequence = semanticObservationBaselineSequence(for: scope, after: sequence)

        if let latest = cleanSettledSemanticObservation(scope: scope, after: requiredSequence) {
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
        let currentSequence = latestSettledSemanticObservation?.sequence
        let baseline = sequence ?? currentSequence
        if scope == .discovery {
            return max(baseline ?? 0, currentSequence ?? 0)
        }
        return baseline
    }

    private func cleanSettledSemanticObservation(
        scope: SemanticObservationScope,
        after sequence: UInt64?
    ) -> SettledSemanticObservation? {
        guard !latestSettledSemanticObservationIsDirty,
              let latest = latestSettledSemanticObservation,
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
        latestSettledSemanticObservation = observation
        latestSettledSemanticObservationIsDirty = false
        passiveObservationSettledReading = tripwire.latestReading
        completeSettledSemanticWaiters(with: observation)
    }

    private func runPassiveSemanticObservationCycle(discovery: @escaping DiscoveryObservation) async {
        let scope = currentSubscribedObservationScope()
        await performSemanticObservationCycle(scope: scope, discovery: discovery)
    }

    private func performSingleSemanticObservationCycle(scope: SemanticObservationScope) async {
        await performSemanticObservationCycle(
            scope: scope,
            discovery: passiveSemanticDiscoveryObservation
        )
    }

    private func performSemanticObservationCycle(
        scope: SemanticObservationScope,
        discovery: DiscoveryObservation?
    ) async {
        switch scope {
        case .visible:
            await observeVisibleSemanticState()
        case .discovery:
            guard let discovery else {
                markDirtyFromTripwire()
                await Task.yield()
                return
            }
            await discovery()
            markCurrentSemanticObservationSettled(scope: .discovery)
            await Task.yield()
        }
    }

    private func observeVisibleSemanticState() async {
        if let reading = tripwire.latestReading,
           !latestSettledSemanticObservationIsDirty,
           passiveObservationSettledReading?.tick == reading.tick {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            return
        }

        guard await tripwire.waitForAllClear(timeout: 0.5) else {
            markDirtyFromTripwire()
            await Task.yield()
            return
        }

        let baselineSignal = latestSettledSemanticObservation?.tripwireSignal ?? tripwire.tripwireSignal()
        let settleSession = SettleSession.live(stash: self, tripwire: tripwire, timeoutMs: 1_000)
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineSignal
        )

        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else {
            markDirtyFromTripwire()
            await Task.yield()
            return
        }

        recordSettledSemanticObservation(screen, scope: .visible)
        await Task.yield()
    }

    private func completeSettledSemanticWaiters(with observation: SettledSemanticObservation) {
        for (id, waiter) in settledSemanticWaiters {
            guard observation.scope >= waiter.scope else { continue }
            guard observation.sequence > (waiter.afterSequence ?? 0) else { continue }
            completeSettledSemanticWaiter(id, returning: observation)
        }
    }

    func completeAllSettledSemanticWaiters(returning observation: SettledSemanticObservation?) {
        for id in Array(settledSemanticWaiters.keys) {
            completeSettledSemanticWaiter(id, returning: observation)
        }
    }

    private func completeSettledSemanticWaiter(
        _ id: UInt64,
        returning observation: SettledSemanticObservation?
    ) {
        guard let waiter = settledSemanticWaiters.removeValue(forKey: id) else { return }
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: observation)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
