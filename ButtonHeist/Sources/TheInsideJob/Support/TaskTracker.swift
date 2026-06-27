import Foundation
import os

/// Lock-protected table of in-flight `Task<Void, Never>` handles with a
/// drain-and-cancel teardown.
///
/// **Ownership.** Task-lifetime tracker, not product state. Owned by the crew
/// members that spawn callback-bridge Tasks (transport/connection callbacks).
/// Key: an internal monotonic `UInt64` id. Lifetime: per spawned Task, from
/// `record`/`spawn` until completion or cancellation. Invalidation: each Task
/// self-removes on completion (sibling watcher); `cancelAll()` clears the rest
/// at teardown. See `docs/ARCHITECTURE.md#state-has-one-owner`.
///
/// Three crew members track callback-bridge Tasks the same way: hold a table,
/// insert on spawn, and cancel-all on teardown. The pattern needs a lock
/// because inserts happen from arbitrary isolation contexts — NWConnection /
/// NWListener callbacks, UIAlertController button handlers — that can't hop
/// onto the owning actor synchronously.
///
/// Use `record(_:)` when the call site has already created the Task (e.g. to
/// pin a specific isolation like `Task { @MainActor in ... }`). Use
/// `spawn(_:)` when the call site just wants a `@Sendable` closure scheduled
/// and tracked in one step.
///
/// **Lifecycle invariant.** Every tracked Task is removed from the table via
/// exactly one of two paths:
///
/// 1. **Completion path.** When `record(_:)` or `spawn(_:)` accepts a Task, a
///    sibling watcher Task is spawned that awaits the tracked Task's value
///    and then removes it under the lock. This handles the common case of a
///    Task that finishes normally — `Task.isCancelled` is `false` for tasks
///    that completed without cancellation, so without explicit self-removal
///    a completed Task would linger in the table until `cancelAll()` ran. On
///    hot paths (every receive callback, every send completion) that lingering
///    is an unbounded slow leak.
/// 2. **Teardown path.** `cancelAll()` snapshots the table under the lock,
///    clears it, then cancels each handle outside the lock. A Task that
///    completes and self-removes between snapshot and cancel is fine —
///    `.cancel()` on a completed Task is a no-op.
///
/// The two paths race benignly: removal is idempotent (`Dictionary.removeValue`
/// on a missing key is a no-op), and the watcher task's removal happens under
/// the same lock that protects `tasks`, so there is no torn read.
///
/// `cancelAll()` cancels handles outside the lock so a Task's cleanup body
/// cannot deadlock against the same lock while we're tearing down.
///
/// `@unchecked Sendable`: the only mutable state is `tasks`, protected by
/// `OSAllocatedUnfairLock`. All access goes through `withLock`, so concurrent
/// reads/writes from any isolation are safe.
final class TaskTracker: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment

    private struct State {
        var nextTaskID: UInt64 = 0
        var tasks: [UInt64: Task<Void, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    /// Insert an already-created Task into the tracking table and arm
    /// completion-removal. When the Task finishes (normally or via
    /// cancellation), a sibling watcher Task removes it from the table. Safe to
    /// call from any isolation context.
    func record(_ task: Task<Void, Never>) {
        let taskID = state.withLock { current -> UInt64 in
            let taskID = current.nextTaskID
            current.nextTaskID &+= 1
            current.tasks[taskID] = task
            return taskID
        }
        Task { [weak self, task, taskID] in
            await task.value
            self?.remove(taskID)
        }
    }

    /// Spawn a `@Sendable` async closure as a tracked Task. Equivalent to
    /// `record(Task { await body() })` but lets call sites skip the
    /// intermediate `let task = ...` binding.
    func spawn(_ body: @escaping @Sendable () async -> Void) {
        record(Task(operation: body))
    }

    /// Snapshot the tracked table, clear it, then cancel each handle.
    /// Cancellation happens outside the lock so a Task's cleanup body cannot
    /// re-enter the tracker on the same thread.
    func cancelAll() {
        let snapshot = state.withLock { current -> [Task<Void, Never>] in
            let copy = Array(current.tasks.values)
            current.tasks.removeAll()
            return copy
        }
        for task in snapshot {
            task.cancel()
        }
    }

    /// Remove a single Task from the tracking table. Idempotent: removing a
    /// Task that is not present (e.g. because `cancelAll()` already cleared
    /// the table) is a no-op.
    private func remove(_ taskID: UInt64) {
        state.withLock { current in
            _ = current.tasks.removeValue(forKey: taskID)
        }
    }

    #if DEBUG
    /// Test-only snapshot of the tracked Task count. Reads under the same
    /// lock as mutators, so the value is consistent at the moment of read.
    var taskCountForTesting: Int {
        state.withLock { current in current.tasks.count }
    }
    #endif
}
