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

    private struct CycleAdmissionTransition: Equatable, Sendable {
        let state: CyclePhase
        let effect: CycleAdmission
    }

    private struct CycleFinishTransition: Equatable, Sendable {
        let state: CyclePhase
        let completion: CycleCompletion
        let shouldCompleteWaiters: Bool
    }

    private enum CycleMachine {
        static func begin(
            _ state: CyclePhase,
            scope: SemanticObservationScope
        ) -> CycleAdmissionTransition {
            switch state {
            case .idle(var progress):
                progress.latestStarted = progress.latestStarted.advanced()
                let cycle = Cycle(cursor: progress.latestStarted, scope: scope)
                return CycleAdmissionTransition(
                    state: .running(cycle, progress: progress),
                    effect: .started(cycle)
                )
            case .running(let cycle, _):
                return CycleAdmissionTransition(state: state, effect: .alreadyRunning(cycle))
            }
        }

        static func finish(
            _ state: CyclePhase,
            cycle: Cycle,
            result: CycleResult
        ) -> CycleFinishTransition {
            switch (state, result) {
            case (.running(let running, let progress), .completed(let settledSequence))
                where running == cycle:
                return CycleFinishTransition(
                    state: .idle(progress.recordingCompletion(
                        of: cycle,
                        settledSequence: settledSequence
                    )),
                    completion: .completed,
                    shouldCompleteWaiters: true
                )
            case (.running(let running, let progress), .interrupted) where running == cycle:
                return CycleFinishTransition(
                    state: .idle(progress),
                    completion: .completed,
                    shouldCompleteWaiters: false
                )
            case (.idle, _), (.running, _):
                return CycleFinishTransition(
                    state: state,
                    completion: .ignoredStaleToken,
                    shouldCompleteWaiters: false
                )
            }
        }

        static func cancel(_ state: CyclePhase) -> CyclePhase {
            switch state {
            case .running(_, let progress):
                return .idle(progress)
            case .idle:
                return state
            }
        }
    }

    private struct WaiterKey: Hashable, Sendable {
        let id: UInt64
        let scope: SemanticObservationScope
        let afterCursor: Cursor
    }

    private var phase = CyclePhase.idle(CycleProgress())
    private var nextWaiterID: UInt64 = 0
    private var waiters = WaiterStore<WaiterKey, TimedOneShot<CycleFulfillment?>>()

    var waiterCount: Int {
        waiters.count
    }

    func cursor() -> Cursor {
        phase.progress.latestStarted
    }

    func beginCycle(scope: SemanticObservationScope) -> CycleAdmission {
        let transition = CycleMachine.begin(phase, scope: scope)
        phase = transition.state
        return transition.effect
    }

    @discardableResult
    func finishCycle(token cycle: Cycle, result: CycleResult) -> CycleCompletion {
        let transition = CycleMachine.finish(phase, cycle: cycle, result: result)
        phase = transition.state
        if transition.shouldCompleteWaiters {
            completeWaiters()
        }
        return transition.completion
    }

    func cancelRunningCycle() {
        phase = CycleMachine.cancel(phase)
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
