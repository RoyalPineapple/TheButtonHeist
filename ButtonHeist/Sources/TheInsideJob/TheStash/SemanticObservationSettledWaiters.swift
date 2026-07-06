#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport
import TheScore

@MainActor
final class SemanticObservationSettledWaiters {
    private struct WaiterKey: Hashable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let afterSequence: SettledObservationSequence?
    }

    private var nextWaiterID: UInt64 = 0
    private var waiters = AsyncWaiterRegistry<WaiterKey, SettledSemanticObservationEvent?>()

    var count: Int {
        waiters.count
    }

    func wait(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let key = reserveWaiterKey(scope: scope, afterSequence: afterSequence)
        let oneShot = TimedOneShot<SettledSemanticObservationEvent?>()

        let result: SettledSemanticObservationEvent? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<SettledSemanticObservationEvent?, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                guard oneShot.register(continuation) else {
                    continuation.resume(returning: nil)
                    return
                }

                waiters.insert(oneShot, for: key)
                if let timeoutDuration = observationWaitTimeout(timeout) {
                    oneShot.armTimeout(after: timeoutDuration) { [weak self] in
                        await self?.complete(key, returning: nil)
                    }
                }
            }
        } onCancel: {
            oneShot.resolve(returning: nil)
        }
        complete(key, returning: nil)
        return result
    }

    func completeAll(returning event: SettledSemanticObservationEvent?) {
        for waiter in waiters.removeAll() {
            waiter.resolve(returning: event)
        }
    }

    func completeWaiters(with eventsByFulfilledScope: [SemanticObservationScope: SettledSemanticObservationEvent]) {
        let completed = waiters.removeAll { key in
            guard let event = eventsByFulfilledScope[key.scope] else { return false }
            return event.sequence > (key.afterSequence ?? 0)
        }
        for (key, waiter) in completed {
            waiter.resolve(returning: eventsByFulfilledScope[key.scope])
        }
    }

    private func complete(_ key: WaiterKey, returning event: SettledSemanticObservationEvent?) {
        waiters.resolve(key, returning: event)
    }

    private func reserveWaiterKey(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?
    ) -> WaiterKey {
        defer { nextWaiterID &+= 1 }
        return WaiterKey(id: nextWaiterID, scope: scope, afterSequence: afterSequence)
    }

    private func observationWaitTimeout(_ timeout: Double?) -> Duration? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return nil }
        let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
        return .nanoseconds(nanoseconds)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
