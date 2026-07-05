#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport
import TheScore

@MainActor
final class SemanticObservationSettledWaiters {
    private struct Waiter {
        let scope: SemanticObservationScope
        let afterSequence: SettledObservationSequence?
        let continuation: OneShotContinuation<SettledSemanticObservationEvent?>
        let timeoutTask: Task<Void, Never>?
    }

    private var waiters = WaiterStore<Waiter>()

    var count: Int {
        waiters.count
    }

    func wait(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let id = waiters.reserveID()
        let continuationBox = OneShotContinuation<SettledSemanticObservationEvent?>()

        let result: SettledSemanticObservationEvent? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<SettledSemanticObservationEvent?, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                guard continuationBox.register(continuation) else {
                    continuation.resume(returning: nil)
                    return
                }

                let timeoutTask: Task<Void, Never>? = observationWaitTimeout(timeout).map { timeout in
                    let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                    return waiterTimeout(after: .nanoseconds(nanoseconds)) { [weak self] in
                        await self?.complete(id, returning: nil)
                    }
                }
                waiters.insert(Waiter(
                    scope: scope,
                    afterSequence: afterSequence,
                    continuation: continuationBox,
                    timeoutTask: timeoutTask
                ), id: id)
            }
        } onCancel: {
            continuationBox.resume(returning: nil)
        }
        complete(id, returning: nil)
        return result
    }

    func completeAll(returning event: SettledSemanticObservationEvent?) {
        for waiter in waiters.removeAll() {
            complete(waiter, returning: event)
        }
    }

    func completeWaiters(with eventsByFulfilledScope: [SemanticObservationScope: SettledSemanticObservationEvent]) {
        let completed = waiters.removeAll { waiter in
            guard let event = eventsByFulfilledScope[waiter.scope] else { return false }
            return event.sequence > (waiter.afterSequence ?? 0)
        }
        for waiter in completed {
            complete(waiter, returning: eventsByFulfilledScope[waiter.scope])
        }
    }

    private func complete(_ id: UInt64, returning event: SettledSemanticObservationEvent?) {
        guard let waiter = waiters.remove(id: id) else { return }
        complete(waiter, returning: event)
    }

    private func complete(_ waiter: Waiter, returning event: SettledSemanticObservationEvent?) {
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: event)
    }

    private func observationWaitTimeout(_ timeout: Double?) -> Double? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return nil }
        return timeout
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
