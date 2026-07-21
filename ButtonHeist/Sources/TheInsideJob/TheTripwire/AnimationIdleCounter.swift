#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import ButtonHeistSupport

final class AnimationIdleCounter: Sendable {
    enum StopOutcome: Equatable {
        case active(remaining: Int)
        case becameIdle
        case unmatchedStop
    }

    private struct State: Sendable {
        var activeCount = 0
        var waiters = WaiterStore<UUID, TimedOneShot<Bool>>()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var activeCount: Int {
        state.withLock(\.activeCount)
    }

    var waiterCount: Int {
        state.withLock { $0.waiters.count }
    }

    func observeAnimationStarted() {
        state.withLock { state in
            precondition(state.activeCount < Int.max, "Animation idle count overflowed")
            state.activeCount += 1
        }
    }

    @discardableResult
    func observeAnimationStopped() -> StopOutcome {
        let transition = state.withLock { state -> (StopOutcome, [TimedOneShot<Bool>]) in
            guard state.activeCount > 0 else {
                return (.unmatchedStop, [])
            }
            state.activeCount -= 1
            guard state.activeCount == 0 else {
                return (.active(remaining: state.activeCount), [])
            }
            return (.becameIdle, state.waiters.removeAll())
        }
        transition.1.forEach { $0.resolve(returning: true) }
        return transition.0
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        guard timeout > .zero else { return activeCount == 0 }

        let waiterID = UUID()
        let oneShot = TimedOneShot<Bool>()
        return await oneShot.wait(
            isolation: nil,
            cancellationValue: false,
            onRegistered: { oneShot in
                let registered = state.withLock { state -> Bool in
                    guard state.activeCount > 0 else { return false }
                    state.waiters.insert(oneShot, for: waiterID)
                    return true
                }
                guard registered else {
                    oneShot.resolve(returning: true)
                    return
                }
                oneShot.armTimeout(after: timeout) { [weak self] in
                    self?.resolve(waiterID, returning: false)
                }
            },
            onFinished: { [weak self] in
                self?.remove(waiterID)
            }
        )
    }

    func cancelAll() {
        let waiters = state.withLock { $0.waiters.removeAll() }
        waiters.forEach { $0.resolve(returning: false) }
    }

    private func resolve(_ waiterID: UUID, returning value: Bool) {
        let waiter = state.withLock { $0.waiters.remove(waiterID) }
        waiter?.resolve(returning: value)
    }

    private func remove(_ waiterID: UUID) {
        _ = state.withLock { $0.waiters.remove(waiterID) }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
