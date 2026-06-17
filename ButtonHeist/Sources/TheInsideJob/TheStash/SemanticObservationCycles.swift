#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
final class SemanticObservationCycles {
    private struct Waiter {
        let scope: SemanticObservationScope
        let afterCycle: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private var sequence: UInt64 = 0
    private var inProgress = false
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: Waiter] = [:]

    func baselineCycle() -> UInt64 {
        sequence + (inProgress ? 1 : 0)
    }

    func beginCycle() {
        inProgress = true
    }

    func finishCycle(didObserve: Bool, scope: SemanticObservationScope) {
        inProgress = false
        guard didObserve else { return }
        sequence += 1
        completeWaiters(scope: scope)
    }

    func waitForNextCycle(scope: SemanticObservationScope, after cycle: UInt64) async {
        let id = nextWaiterID
        nextWaiterID += 1

        return await withCheckedContinuation { continuation in
            waiters[id] = Waiter(
                scope: scope,
                afterCycle: cycle,
                continuation: continuation
            )
        }
    }

    func completeAllWaiters() {
        for id in Array(waiters.keys) {
            completeWaiter(id)
        }
    }

    private func completeWaiters(scope: SemanticObservationScope) {
        for (id, waiter) in waiters {
            guard scope >= waiter.scope else { continue }
            guard sequence > waiter.afterCycle else { continue }
            completeWaiter(id)
        }
    }

    private func completeWaiter(_ id: UInt64) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
