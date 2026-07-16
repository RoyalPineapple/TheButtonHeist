import Foundation
import os

/// Lock-owned callback tasks with one accepting/draining/drained lifecycle.
final class TaskTracker: Sendable {

    enum Rejection: Equatable, Sendable {
        case draining
        case drained
    }

    enum Admission: Equatable, Sendable {
        case accepted
        case rejected(Rejection)
    }

    struct Snapshot: Equatable, Sendable {
        let taskCount: Int
    }

    private struct DrainOperation {
        let taskCount: Int
        let task: Task<Void, Never>
    }

    private enum State {
        case accepting([UUID: Task<Void, Never>])
        case draining(DrainOperation)
        case drained
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: .accepting([:]))

    /// Creates one wrapper that owns the operation and its completion removal.
    /// Admission is rejected once draining begins.
    @discardableResult
    func spawn(
        _ operation: @escaping @Sendable () async -> Void
    ) -> Admission {
        let lock = state
        return state.withLock { state -> Admission in
            switch state {
            case .accepting(var tasks):
                let id = UUID()
                let wrapper = Task {
                    // `spawn` holds this lock until the wrapper is stored.
                    lock.withLock { _ in }
                    await operation()
                    lock.withLock { state in
                        guard case .accepting(var tasks) = state else { return }
                        _ = tasks.removeValue(forKey: id)
                        state = .accepting(tasks)
                    }
                }
                tasks[id] = wrapper
                state = .accepting(tasks)
                return .accepted
            case .draining:
                return .rejected(.draining)
            case .drained:
                return .rejected(.drained)
            }
        }
    }

    /// Cancels and awaits every task admitted before the accepting-to-draining
    /// transition. Concurrent and repeated callers join the drain operation
    /// stored in `.draining` and converge on the same terminal state.
    func drain() async {
        let drainTask = state.withLock { state -> Task<Void, Never>? in
            switch state {
            case .accepting(let tasks):
                let taskSnapshot = Array(tasks.values)
                let drainTask = Task {
                    taskSnapshot.forEach { $0.cancel() }
                    for task in taskSnapshot {
                        await task.value
                    }
                }
                let operation = DrainOperation(
                    taskCount: taskSnapshot.count,
                    task: drainTask
                )
                state = .draining(operation)
                return drainTask
            case .draining(let operation):
                return operation.task
            case .drained:
                return nil
            }
        }

        guard let drainTask else { return }
        await drainTask.value
        state.withLock { state in
            guard case .draining = state else { return }
            state = .drained
        }
    }

    /// Waits until the accepting tracker is quiescent without cancelling it.
    /// Tasks admitted while waiting are included before this returns.
    func waitForIdle() async {
        while true {
            let tasks = state.withLock { state -> [Task<Void, Never>]? in
                switch state {
                case .accepting(let tasks):
                    return Array(tasks.values)
                case .draining:
                    return nil
                case .drained:
                    return []
                }
            }
            guard let tasks else {
                await drain()
                continue
            }
            guard !tasks.isEmpty else { return }
            for task in tasks {
                await task.value
            }
        }
    }

    var snapshot: Snapshot {
        state.withLock { state in
            switch state {
            case .accepting(let tasks):
                return Snapshot(taskCount: tasks.count)
            case .draining(let operation):
                return Snapshot(taskCount: operation.taskCount)
            case .drained:
                return Snapshot(taskCount: 0)
            }
        }
    }
}
