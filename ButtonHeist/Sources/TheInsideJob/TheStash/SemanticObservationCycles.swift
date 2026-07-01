#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
final class SemanticObservationCycles {
    struct Cycle: Equatable {
        let id: UInt64
        let scope: SemanticObservationScope
        let baseline: UInt64
        fileprivate let generation: UInt64
    }

    enum CycleAdmission: Equatable {
        case started(Cycle)
        case alreadyRunning(Cycle)
    }

    enum CycleCompletion: Equatable {
        case completed
        case ignoredStaleToken
    }

    private enum CyclePhase {
        case idle(completed: UInt64, generation: UInt64)
        case running(Cycle)

        var baseline: UInt64 {
            switch self {
            case .idle(let completed, _):
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

    private var phase: CyclePhase = .idle(completed: 0, generation: 0)
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: Waiter] = [:]

    var waiterCount: Int {
        waiters.count
    }

    func baselineCycle() -> UInt64 {
        phase.baseline
    }

    func beginCycle(scope: SemanticObservationScope) -> CycleAdmission {
        switch phase {
        case .idle(let completed, let generation):
            let cycle = Cycle(id: completed + 1, scope: scope, baseline: completed, generation: generation)
            phase = .running(cycle)
            return .started(cycle)
        case .running(let cycle):
            return .alreadyRunning(cycle)
        }
    }

    @discardableResult
    func finishCycle(token cycle: Cycle, didObserve: Bool) -> CycleCompletion {
        guard case .running(let running) = phase,
              running == cycle
        else {
            return .ignoredStaleToken
        }

        guard didObserve else {
            phase = .idle(completed: cycle.baseline, generation: cycle.generation)
            return .completed
        }
        phase = .idle(completed: cycle.id, generation: cycle.generation)
        completeWaiters(scope: cycle.scope)
        return .completed
    }

    func cancelRunningCycle() {
        guard case .running(let cycle) = phase else { return }
        phase = .idle(completed: cycle.baseline, generation: cycle.generation + 1)
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
