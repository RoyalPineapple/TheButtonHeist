import Foundation
import os

package final class CompletionSignal: Sendable {
    private struct State: Sendable {
        var isFinished = false
        var waiters = WaiterStore<UUID, TimedOneShot<Bool>>()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    package var isFinished: Bool {
        state.withLock { $0.isFinished }
    }

    package func wait() async {
        let waiter = TimedOneShot<Bool>()
        let waiterID = UUID()
        _ = await waiter.wait(
            cancellationValue: false,
            onRegistered: { waiter in
                register(waiter, id: waiterID)
            },
            onFinished: { [weak self] in
                self?.remove(waiterID)
            }
        )
    }

    package func wait(timeout: Duration) async -> Bool {
        guard timeout > .zero else { return isFinished }

        let waiter = TimedOneShot<Bool>()
        let waiterID = UUID()
        return await waiter.wait(
            cancellationValue: false,
            onRegistered: { waiter in
                guard register(waiter, id: waiterID) else { return }
                waiter.armTimeout(after: timeout) { [weak self] in
                    self?.timeout(waiterID)
                }
            },
            onFinished: { [weak self] in
                self?.remove(waiterID)
            }
        )
    }

    package func finish() {
        let waiters = state.withLock { state -> [TimedOneShot<Bool>] in
            guard !state.isFinished else { return [] }
            state.isFinished = true
            return state.waiters.removeAll()
        }
        waiters.forEach { $0.resolve(returning: true) }
    }

    @discardableResult
    private func register(_ waiter: TimedOneShot<Bool>, id: UUID) -> Bool {
        let isAlreadyFinished = state.withLock { state -> Bool in
            guard !state.isFinished else { return true }
            state.waiters.insert(waiter, for: id)
            return false
        }
        if isAlreadyFinished {
            waiter.resolve(returning: true)
        }
        return !isAlreadyFinished
    }

    private func timeout(_ waiterID: UUID) {
        let waiter = state.withLock { $0.waiters.remove(waiterID) }
        waiter?.resolve(returning: false)
    }

    private func remove(_ waiterID: UUID) {
        state.withLock { state in
            _ = state.waiters.remove(waiterID)
        }
    }
}
