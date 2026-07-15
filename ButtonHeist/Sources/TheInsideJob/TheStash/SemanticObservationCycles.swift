#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport
import TheScore

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

    enum CycleResult: Equatable, Sendable {
        case interrupted
        case completed(settledSequence: SettledObservationSequence?)
    }

    struct CycleFulfillment: Equatable, Sendable {
        let cycle: Cycle
        let settledSequence: SettledObservationSequence?
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
        var fulfilledThrough: [SemanticObservationScope: CycleFulfillment] = [:]

        func fulfillment(
            for scope: SemanticObservationScope,
            after cursor: Cursor
        ) -> CycleFulfillment? {
            guard let fulfillment = fulfilledThrough[scope],
                  fulfillment.cycle.cursor > cursor else { return nil }
            return fulfillment
        }

        func recordingCompletion(
            of cycle: Cycle,
            settledSequence: SettledObservationSequence?
        ) -> CycleProgress {
            var progress = self
            let fulfillment = CycleFulfillment(
                cycle: cycle,
                settledSequence: settledSequence
            )
            for scope in cycle.scope.fulfilledScopes {
                progress.fulfilledThrough[scope] = fulfillment
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
        case finish(Cycle, result: CycleResult)
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

            case (
                .running(let running, let progress),
                .finish(let cycle, .completed(let settledSequence))
            ) where running == cycle:
                return .changed(
                    to: .idle(progress.recordingCompletion(
                        of: cycle,
                        settledSequence: settledSequence
                    )),
                    effects: [.completion(.completed), .completeWaiters]
                )

            case (
                .running(let running, let progress),
                .finish(let cycle, .interrupted)
            ) where running == cycle:
                return .changed(
                    to: .idle(progress),
                    effects: [.completion(.completed)]
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
    private var waiters = WaiterStore<WaiterKey, TimedOneShot<CycleFulfillment?>>()

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
    func finishCycle(token cycle: Cycle, result: CycleResult) -> CycleCompletion {
        let change = driver.send(.finish(cycle, result: result))
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

    func waitForNextCycle(
        scope: SemanticObservationScope,
        after cursor: Cursor
    ) async -> CycleFulfillment? {
        if let fulfillment = phase.progress.fulfillment(for: scope, after: cursor) {
            return fulfillment
        }

        let key = reserveWaiterKey(scope: scope, afterCursor: cursor)
        let oneShot = TimedOneShot<CycleFulfillment?>()

        return await oneShot.wait(
            cancellationValue: nil,
            onRegistered: { oneShot in
                waiters.insert(oneShot, for: key)
                completeWaiterIfFulfilled(key)
            },
            onFinished: {
                waiters.resolve(key, returning: nil)
            }
        )
    }

    func completeAllWaiters() {
        for waiter in waiters.removeAll() {
            waiter.resolve(returning: nil)
        }
    }

    private func completeWaiters() {
        let progress = phase.progress
        let completed = waiters.removeAll { key in
            progress.fulfillment(for: key.scope, after: key.afterCursor) != nil
        }
        for removal in completed {
            guard let fulfillment = progress.fulfillment(
                for: removal.key.scope,
                after: removal.key.afterCursor
            ) else {
                preconditionFailure("Completed cycle waiter must have fulfillment evidence")
            }
            removal.waiter.resolve(returning: fulfillment)
        }
    }

    private func completeWaiterIfFulfilled(_ key: WaiterKey) {
        guard let fulfillment = phase.progress.fulfillment(
            for: key.scope,
            after: key.afterCursor
        ) else { return }
        waiters.resolve(key, returning: fulfillment)
    }

    private func reserveWaiterKey(scope: SemanticObservationScope, afterCursor: Cursor) -> WaiterKey {
        defer { nextWaiterID &+= 1 }
        return WaiterKey(id: nextWaiterID, scope: scope, afterCursor: afterCursor)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
