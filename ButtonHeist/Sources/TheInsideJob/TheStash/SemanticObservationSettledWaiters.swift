#if canImport(UIKit)
#if DEBUG
import Foundation
import os
import TheScore

@MainActor
final class SemanticObservationSettledWaiters {
    private struct Waiter {
        let scope: SemanticObservationScope
        let afterSequence: SettledObservationSequence?
        let continuation: SemanticObservationWaiterContinuation<SettledSemanticObservationEvent?>
        let timeoutTask: Task<Void, Never>?
    }

    private var nextID: UInt64 = 0
    private var waitersByID: [UInt64: Waiter] = [:]

    var count: Int {
        waitersByID.count
    }

    func wait(
        scope: SemanticObservationScope,
        afterSequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let id = nextID
        nextID += 1
        let continuationBox = SemanticObservationWaiterContinuation<SettledSemanticObservationEvent?>()

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
                    Task { [weak self] in
                        let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                        guard await Task.cancellableSleep(for: .nanoseconds(nanoseconds)) else { return }
                        self?.complete(id, returning: nil)
                    }
                }
                waitersByID[id] = Waiter(
                    scope: scope,
                    afterSequence: afterSequence,
                    continuation: continuationBox,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            continuationBox.resume(returning: nil)
        }
        complete(id, returning: nil)
        return result
    }

    func completeAll(returning event: SettledSemanticObservationEvent?) {
        for id in Array(waitersByID.keys) {
            complete(id, returning: event)
        }
    }

    func completeWaiters(with eventsByFulfilledScope: [SemanticObservationScope: SettledSemanticObservationEvent]) {
        for (id, waiter) in waitersByID {
            guard let event = eventsByFulfilledScope[waiter.scope] else { continue }
            guard event.sequence > (waiter.afterSequence ?? 0) else { continue }
            complete(id, returning: event)
        }
    }

    private func complete(_ id: UInt64, returning event: SettledSemanticObservationEvent?) {
        guard let waiter = waitersByID.removeValue(forKey: id) else { return }
        waiter.timeoutTask?.cancel()
        waiter.continuation.resume(returning: event)
    }

    private func observationWaitTimeout(_ timeout: Double?) -> Double? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return nil }
        return timeout
    }
}

struct SemanticObservationWaiterContinuation<Value: Sendable> {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var didResume = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func register(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
        lock.withLock { state -> Bool in
            guard !state.didResume else { return false }
            state.continuation = continuation
            return true
        }
    }

    func resume(returning value: Value) {
        let continuationToResume = lock.withLock { state -> CheckedContinuation<Value, Never>? in
            guard !state.didResume else { return nil }
            state.didResume = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuationToResume?.resume(returning: value)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
