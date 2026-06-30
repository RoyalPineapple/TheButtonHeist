#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
final class SemanticObservationCycles {
    struct Cycle {
        let id: UInt64
        let scope: SemanticObservationScope
        let baseline: UInt64

        fileprivate init(id: UInt64, scope: SemanticObservationScope, baseline: UInt64) {
            self.id = id
            self.scope = scope
            self.baseline = baseline
        }
    }

    private enum CyclePhase {
        case idle(completed: UInt64)
        case running(Cycle)

        var baseline: UInt64 {
            switch self {
            case .idle(let completed):
                completed
            case .running(let cycle):
                cycle.id
            }
        }
    }

    private struct Waiter {
        let scope: SemanticObservationScope
        let afterCycle: UInt64
        let continuation: SemanticObservationWaiterContinuation<Void>
    }

    private var phase: CyclePhase = .idle(completed: 0)
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: Waiter] = [:]

    var waiterCount: Int {
        waiters.count
    }

    func baselineCycle() -> UInt64 {
        phase.baseline
    }

    func beginCycle(scope: SemanticObservationScope) -> Cycle {
        guard case .idle(let completed) = phase else {
            preconditionFailure("Semantic observation cycle already running")
        }
        let cycle = Cycle(id: completed + 1, scope: scope, baseline: completed)
        phase = .running(cycle)
        return cycle
    }

    func finishCycle(token cycle: Cycle, didObserve: Bool) {
        guard case .running(let running) = phase,
              running.id == cycle.id,
              running.scope == cycle.scope,
              running.baseline == cycle.baseline
        else {
            preconditionFailure("Semantic observation cycle finished with a stale token")
        }

        guard didObserve else {
            phase = .idle(completed: cycle.baseline)
            return
        }
        phase = .idle(completed: cycle.id)
        completeWaiters(scope: cycle.scope)
    }

    func waitForNextCycle(scope: SemanticObservationScope, after cycle: UInt64) async {
        let id = nextWaiterID
        nextWaiterID += 1
        let continuationBox = SemanticObservationWaiterContinuation<Void>()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                guard continuationBox.register(continuation) else {
                    continuation.resume()
                    return
                }

                waiters[id] = Waiter(
                    scope: scope,
                    afterCycle: cycle,
                    continuation: continuationBox
                )
            }
        } onCancel: {
            continuationBox.resume(returning: ())
        }
        completeWaiter(id)
    }

    func completeAllWaiters() {
        for id in Array(waiters.keys) {
            completeWaiter(id)
        }
    }

    private func completeWaiters(scope: SemanticObservationScope) {
        for (id, waiter) in waiters {
            guard scope.canFulfill(waiter.scope) else { continue }
            guard phase.baseline > waiter.afterCycle else { continue }
            completeWaiter(id)
        }
    }

    private func completeWaiter(_ id: UInt64) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: ())
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
