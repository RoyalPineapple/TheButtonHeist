#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport

@MainActor
final class SemanticObservationCycles {
    struct Cycle: Equatable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let baseline: UInt64
        fileprivate let generation: UInt64
    }

    enum CycleAdmission: Equatable, Sendable {
        case started(Cycle)
        case alreadyRunning(Cycle)
    }

    enum CycleCompletion: Equatable, Sendable {
        case completed
        case ignoredStaleToken
    }

    private enum CyclePhase: Equatable, Sendable {
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

    private enum CycleEvent: Equatable, Sendable {
        case begin(scope: SemanticObservationScope)
        case finish(Cycle, didObserve: Bool)
        case cancel
    }

    private enum CycleEffect: Equatable, Sendable {
        case admission(CycleAdmission)
        case completion(CycleCompletion)
        case completeWaiters(scope: SemanticObservationScope)
    }

    private enum CycleRejection: Equatable, Sendable {}

    private struct CycleMachine: SimpleStateMachine {
        func advance(_ state: CyclePhase, with event: CycleEvent) -> StateChange<CyclePhase, CycleEffect, CycleRejection> {
            switch (state, event) {
            case (.idle(let completed, let generation), .begin(let scope)):
                let cycle = Cycle(
                    id: completed + 1,
                    scope: scope,
                    baseline: completed,
                    generation: generation
                )
                return .changed(to: .running(cycle), effects: [.admission(.started(cycle))])

            case (.running(let cycle), .begin):
                return .changed(to: state, effects: [.admission(.alreadyRunning(cycle))])

            case (.running(let running), .finish(let cycle, let didObserve)) where running == cycle:
                let completedCycle = didObserve ? cycle.id : cycle.baseline
                let effects: [CycleEffect] = didObserve
                    ? [.completion(.completed), .completeWaiters(scope: cycle.scope)]
                    : [.completion(.completed)]
                return .changed(
                    to: .idle(completed: completedCycle, generation: cycle.generation),
                    effects: effects
                )

            case (_, .finish):
                return .changed(to: state, effects: [.completion(.ignoredStaleToken)])

            case (.running(let cycle), .cancel):
                return .changed(to: .idle(completed: cycle.baseline, generation: cycle.generation + 1))

            case (.idle, .cancel):
                return .changed(to: state)
            }
        }
    }

    private struct WaiterKey: Hashable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let afterCycle: UInt64
    }

    private var driver = StateDriver(initial: CyclePhase.idle(completed: 0, generation: 0), machine: CycleMachine())
    private var nextWaiterID: UInt64 = 0
    private var waiters = AsyncWaiterRegistry<WaiterKey, Void>()

    private var phase: CyclePhase {
        driver.state
    }

    var waiterCount: Int {
        waiters.count
    }

    func baselineCycle() -> UInt64 {
        phase.baseline
    }

    func beginCycle(scope: SemanticObservationScope) -> CycleAdmission {
        let change = driver.send(.begin(scope: scope))
        guard case .admission(let admission)? = change.singleEffect else {
            preconditionFailure("Semantic observation cycle begin must emit one admission")
        }
        return admission
    }

    @discardableResult
    func finishCycle(token cycle: Cycle, didObserve: Bool) -> CycleCompletion {
        let change = driver.send(.finish(cycle, didObserve: didObserve))
        var completion: CycleCompletion?
        for effect in change.effects {
            switch effect {
            case .admission:
                preconditionFailure("Semantic observation cycle finish emitted admission")
            case .completion(let nextCompletion):
                completion = nextCompletion
            case .completeWaiters(let scope):
                completeWaiters(scope: scope)
            }
        }
        guard let completion else {
            preconditionFailure("Semantic observation cycle finish must emit completion")
        }
        return completion
    }

    func cancelRunningCycle() {
        driver.send(.cancel)
    }

    func waitForNextCycle(scope: SemanticObservationScope, after cycle: UInt64) async {
        let key = reserveWaiterKey(scope: scope, afterCycle: cycle)
        let oneShot = TimedOneShot<Void>()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                guard oneShot.register(continuation) else {
                    continuation.resume()
                    return
                }

                waiters.insert(oneShot, for: key)
            }
        } onCancel: {
            oneShot.resolve(returning: ())
        }
        completeWaiter(key)
    }

    func completeAllWaiters() {
        for waiter in waiters.removeAll() {
            waiter.resolve(returning: ())
        }
    }

    private func completeWaiters(scope: SemanticObservationScope) {
        let completed = waiters.removeAll { key in
            scope.canFulfill(key.scope) && phase.baseline > key.afterCycle
        }
        for (_, waiter) in completed {
            waiter.resolve(returning: ())
        }
    }

    private func completeWaiter(_ key: WaiterKey) {
        waiters.resolve(key, returning: ())
    }

    private func reserveWaiterKey(scope: SemanticObservationScope, afterCycle: UInt64) -> WaiterKey {
        defer { nextWaiterID &+= 1 }
        return WaiterKey(id: nextWaiterID, scope: scope, afterCycle: afterCycle)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
