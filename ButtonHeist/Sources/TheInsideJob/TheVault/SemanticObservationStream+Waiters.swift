#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
import Foundation
import TheScore

internal enum SemanticObservationWaitResult: Sendable, Equatable {
    case observation(TheVault.State.Current)
    case cycleCompleted
    case deadlineReached
    case cancelled
    case unavailable(Observation.History.ReadError)
}

internal struct SemanticObservationWaiter: Sendable {
    let historyIndex: Int
    let scope: SemanticObservationScope
    let completesAfterObservationCycle: Bool
    let oneShot: TimedOneShot<SemanticObservationWaitResult>
}

@MainActor
extension Observation.Stream {
    internal func waitForObservation(
        after historyIndex: Int,
        scope: SemanticObservationScope,
        deadline: SemanticObservationDeadline?,
        completingAfterCurrentCycle: Bool = false
    ) async -> SemanticObservationWaitResult {
        if Task.isCancelled {
            return .cancelled
        }
        if let deadline,
           !deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            return .deadlineReached
        }

        let waiterID = observationWaiters.reserveID()
        let oneShot = TimedOneShot<SemanticObservationWaitResult>()
        let subscription = subscribe(scope: scope)
        defer { subscription.cancel() }

        return await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { oneShot in
                observationWaiters.insert(SemanticObservationWaiter(
                    historyIndex: historyIndex,
                    scope: scope,
                    completesAfterObservationCycle: completingAfterCurrentCycle,
                    oneShot: oneShot
                ), id: waiterID)
                Task { @MainActor in
                    await resolveObservationWaiterIfAvailable(waiterID)
                }
                armObservationDeadline(deadline, waiterID: waiterID, oneShot: oneShot)
            },
            onFinished: {
                observationWaiters.remove(id: waiterID)?.oneShot.cancelTimeout()
            }
        )
    }

    internal func nextObservation(
        scope: SemanticObservationScope,
        after historyIndex: Int?,
        timeout: Double?
    ) async -> TheVault.State.Current? {
        if timeout == 0 {
            guard isActive else { return nil }
            if scope != .discovery {
                return await admittedObservation(
                    scope: scope,
                    after: historyIndex
                )
            }
        }
        let deadline = timeout == 0 ? nil : timeout.map {
            SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeoutSeconds: $0
            )
        }
        var cursor = historyIndex ?? (await stateOwner.historyEndIndex())
        while true {
            switch await waitForObservation(
                after: cursor,
                scope: scope,
                deadline: deadline,
                completingAfterCurrentCycle: timeout == 0 && scope == .discovery
            ) {
            case .observation:
                if let latest = await admittedObservation(
                    scope: scope,
                    after: cursor
                ) {
                    return latest
                }
                cursor = await stateOwner.historyEndIndex()
            case .cycleCompleted:
                return await admittedObservation(
                    scope: scope,
                    after: historyIndex
                )
            case .deadlineReached, .cancelled, .unavailable:
                return nil
            }
        }
    }

    static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else {
            return Int(SemanticObservationTiming.defaultTimeout / .milliseconds(1))
        }
        guard timeout > 0 else { return 0 }
        let milliseconds = (timeout * 1_000).rounded(.up)
        return milliseconds >= Double(Int.max) ? Int.max : max(1, Int(milliseconds))
    }

    func completeObservationWaiters(
        completedScope: SemanticObservationScope? = nil
    ) async {
        var candidates: [(UInt64, SemanticObservationWaiter)] = []
        observationWaiters.updateAll { id, waiter in
            candidates.append((id, waiter))
        }
        for (id, waiter) in candidates {
            guard let result = await observationWaitResult(
                for: waiter,
                completedScope: completedScope
            ) else { continue }
            resolveObservationWaiter(id, with: result)
        }
    }

    func cancelObservationWaiters() {
        for waiter in observationWaiters.removeAll() {
            waiter.oneShot.resolve(returning: .cancelled)
        }
    }

    private func resolveObservationWaiterIfAvailable(
        _ waiterID: UInt64,
        completedScope: SemanticObservationScope? = nil
    ) async {
        guard let waiter = observationWaiters[waiterID],
              let result = await observationWaitResult(
                for: waiter,
                completedScope: completedScope
              )
        else { return }
        resolveObservationWaiter(waiterID, with: result)
    }

    private func observationWaitResult(
        for waiter: SemanticObservationWaiter,
        completedScope: SemanticObservationScope?
    ) async -> SemanticObservationWaitResult? {
        switch await stateOwner.current(
            after: waiter.historyIndex,
            scope: waiter.scope
        ) {
        case .success(.some(let current)):
            return .observation(current)
        case .failure(let error):
            return .unavailable(error)
        case .success(nil):
            if waiter.completesAfterObservationCycle,
               let completedScope,
               completedScope.canFulfill(waiter.scope) {
                return .cycleCompleted
            }
            return nil
        }
    }

    private func resolveObservationWaiter(
        _ waiterID: UInt64,
        with result: SemanticObservationWaitResult
    ) {
        guard let waiter = observationWaiters.remove(id: waiterID) else { return }
        waiter.oneShot.resolve(returning: result)
    }

    private func armObservationDeadline(
        _ deadline: SemanticObservationDeadline?,
        waiterID: UInt64,
        oneShot: TimedOneShot<SemanticObservationWaitResult>
    ) {
        guard let deadline else { return }
        let remaining = deadline.remainingSeconds()
        guard remaining > 0 else {
            resolveObservationWaiter(waiterID, with: .deadlineReached)
            return
        }
        oneShot.armTimeout(after: .seconds(remaining)) { [weak self] in
            await self?.resolveObservationWaiter(waiterID, with: .deadlineReached)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
