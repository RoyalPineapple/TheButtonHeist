import Foundation
import os

/// Lock-protected set of in-flight `Task<Void, Never>` handles with a
/// drain-and-cancel teardown.
///
/// Three crew members track callback-bridge Tasks the same way: hold a set,
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
/// **Lifecycle invariant.** Every tracked Task is removed from the set via
/// exactly one of two paths:
///
/// 1. **Completion path.** When `record(_:)` or `spawn(_:)` accepts a Task, a
///    sibling watcher Task is spawned that awaits the tracked Task's value
///    and then removes it under the lock. This handles the common case of a
///    Task that finishes normally — `Task.isCancelled` is `false` for tasks
///    that completed without cancellation, so without explicit self-removal
///    a completed Task would linger in the set until `cancelAll()` ran. On
///    hot paths (every receive callback, every send completion) that lingering
///    is an unbounded slow leak.
/// 2. **Teardown path.** `cancelAll()` snapshots the set under the lock,
///    clears it, then cancels each handle outside the lock. A Task that
///    completes and self-removes between snapshot and cancel is fine —
///    `.cancel()` on a completed Task is a no-op.
///
/// The two paths race benignly: removal is idempotent (`Set.remove` on a
/// missing element is a no-op), and the watcher task's removal happens under
/// the same lock that protects `tasks`, so there is no torn read.
///
/// `cancelAll()` cancels handles outside the lock so a Task's cleanup body
/// cannot deadlock against the same lock while we're tearing down.
///
/// `@unchecked Sendable`: the only mutable state is `tasks`, protected by
/// `OSAllocatedUnfairLock`. All access goes through `withLock`, so concurrent
/// reads/writes from any isolation are safe.
final class TaskTracker: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment

    private let tasks = OSAllocatedUnfairLock<Set<Task<Void, Never>>>(initialState: [])

    /// Insert an already-created Task into the tracking set and arm
    /// completion-removal. When the Task finishes (normally or via
    /// cancellation), a sibling watcher Task removes it from the set. Safe to
    /// call from any isolation context.
    func record(_ task: Task<Void, Never>) {
        tasks.withLock { current in
            _ = current.insert(task)
        }
        Task { [weak self, task] in
            await task.value
            self?.remove(task)
        }
    }

    /// Spawn a `@Sendable` async closure as a tracked Task. Equivalent to
    /// `record(Task { await body() })` but lets call sites skip the
    /// intermediate `let task = ...` binding.
    func spawn(_ body: @escaping @Sendable () async -> Void) {
        record(Task(operation: body))
    }

    /// Snapshot the tracked set, clear it, then cancel each handle.
    /// Cancellation happens outside the lock so a Task's cleanup body cannot
    /// re-enter the tracker on the same thread.
    func cancelAll() {
        let snapshot = tasks.withLock { current -> Set<Task<Void, Never>> in
            let copy = current
            current.removeAll()
            return copy
        }
        for task in snapshot {
            task.cancel()
        }
    }

    /// Remove a single Task from the tracking set. Idempotent: removing a
    /// Task that is not present (e.g. because `cancelAll()` already cleared
    /// the set) is a no-op.
    private func remove(_ task: Task<Void, Never>) {
        tasks.withLock { current in
            _ = current.remove(task)
        }
    }
}
