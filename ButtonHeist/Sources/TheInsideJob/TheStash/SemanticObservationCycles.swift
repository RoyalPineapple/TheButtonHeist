#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport

@MainActor
final class SemanticObservationCycles {
    struct Cursor: Equatable, Hashable, Sendable, Comparable {
        fileprivate let rawValue: UInt64

        static let initial = Cursor(rawValue: 0)

        static func < (lhs: Cursor, rhs: Cursor) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        func advanced() -> Cursor {
            precondition(rawValue < UInt64.max, "Semantic observation cycle cursor exhausted")
            return Cursor(rawValue: rawValue + 1)
        }
    }

    struct Cycle: Equatable, Sendable {
        let cursor: Cursor
        let scope: SemanticObservationScope
    }

    enum CycleAdmission: Equatable, Sendable {
        case started(Cycle)
        case alreadyRunning(Cycle)
    }

    enum CycleCompletion: Equatable, Sendable {
        case completed
        case ignoredStaleToken
    }

    private struct CycleProgress: Equatable, Sendable {
        var latestStarted: Cursor = .initial
        var fulfilledThrough: [SemanticObservationScope: Cursor] = [:]

        func fulfills(scope: SemanticObservationScope, after cursor: Cursor) -> Bool {
            (fulfilledThrough[scope] ?? .initial) > cursor
        }

        func recordingCompletion(of cycle: Cycle) -> CycleProgress {
            var progress = self
            for scope in cycle.scope.fulfilledScopes {
                progress.fulfilledThrough[scope] = cycle.cursor
            }
            return progress
        }
    }

    private enum CyclePhase: Equatable, Sendable {
        case idle(CycleProgress)
        case running(Cycle, progress: CycleProgress)

        var progress: CycleProgress {
            switch self {
            case .idle(let progress), .running(_, let progress):
                progress
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
        case completeWaiters
    }

    private enum CycleRejection: Equatable, Sendable {}

    private struct CycleMachine: SimpleStateMachine {
        func advance(_ state: CyclePhase, with event: CycleEvent) -> StateChange<CyclePhase, CycleEffect, CycleRejection> {
            switch (state, event) {
            case (.idle(var progress), .begin(let scope)):
                progress.latestStarted = progress.latestStarted.advanced()
                let cycle = Cycle(cursor: progress.latestStarted, scope: scope)
                return .changed(
                    to: .running(cycle, progress: progress),
                    effects: [.admission(.started(cycle))]
                )

            case (.running(let cycle, _), .begin):
                return .changed(to: state, effects: [.admission(.alreadyRunning(cycle))])

            case (.running(let running, let progress), .finish(let cycle, let didObserve)) where running == cycle:
                let completedProgress = didObserve ? progress.recordingCompletion(of: cycle) : progress
                let effects: [CycleEffect] = didObserve
                    ? [.completion(.completed), .completeWaiters]
                    : [.completion(.completed)]
                return .changed(
                    to: .idle(completedProgress),
                    effects: effects
                )

            case (_, .finish):
                return .changed(to: state, effects: [.completion(.ignoredStaleToken)])

            case (.running(_, let progress), .cancel):
                return .changed(to: .idle(progress))

            case (.idle, .cancel):
                return .changed(to: state)
            }
        }
    }

    private struct WaiterKey: Hashable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let afterCursor: Cursor
    }

    private var driver = StateDriver(initial: CyclePhase.idle(CycleProgress()), machine: CycleMachine())
    private var nextWaiterID: UInt64 = 0
    private var waiters = WaiterStore<WaiterKey, TimedOneShot<Void>>()

    private var phase: CyclePhase {
        driver.state
    }

    var waiterCount: Int {
        waiters.count
    }

    func cursor() -> Cursor {
        phase.progress.latestStarted
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
            case .completeWaiters:
                completeWaiters()
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

    func waitForNextCycle(scope: SemanticObservationScope, after cursor: Cursor) async {
        guard !phase.progress.fulfills(scope: scope, after: cursor) else { return }

        let key = reserveWaiterKey(scope: scope, afterCursor: cursor)
        let oneShot = TimedOneShot<Void>()

        await oneShot.wait(
            cancellationValue: (),
            onRegistered: { oneShot in
                waiters.insert(oneShot, for: key)
                completeWaiterIfFulfilled(key)
            },
            onFinished: {
                waiters.resolve(key, returning: ())
            }
        )
    }

    func completeAllWaiters() {
        for waiter in waiters.removeAll() {
            waiter.resolve(returning: ())
        }
    }

    private func completeWaiters() {
        let progress = phase.progress
        let completed = waiters.removeAll { key in
            progress.fulfills(scope: key.scope, after: key.afterCursor)
        }
        for removal in completed {
            removal.waiter.resolve(returning: ())
        }
    }

    private func completeWaiterIfFulfilled(_ key: WaiterKey) {
        guard waiterIsFulfilled(key) else { return }
        waiters.resolve(key, returning: ())
    }

    private func waiterIsFulfilled(_ key: WaiterKey) -> Bool {
        phase.progress.fulfills(scope: key.scope, after: key.afterCursor)
    }

    private func reserveWaiterKey(scope: SemanticObservationScope, afterCursor: Cursor) -> WaiterKey {
        defer { nextWaiterID &+= 1 }
        return WaiterKey(id: nextWaiterID, scope: scope, afterCursor: afterCursor)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
