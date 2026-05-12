import Foundation
import os

/// Lock-protected set of in-flight `Task<Void, Never>` handles with a
/// drain-and-cancel teardown.
///
/// Three crew members track callback-bridge Tasks the same way: hold a set,
/// insert on spawn (pruning already-cancelled handles to keep the set
/// bounded), and cancel-all on teardown. The pattern needs a lock because
/// inserts happen from arbitrary isolation contexts — NWConnection /
/// NWListener callbacks, UIAlertController button handlers — that can't hop
/// onto the owning actor synchronously.
///
/// Use `record(_:)` when the call site has already created the Task (e.g. to
/// pin a specific isolation like `Task { @MainActor in ... }`). Use
/// `spawn(_:)` when the call site just wants a `@Sendable` closure scheduled
/// and tracked in one step.
///
/// `cancelAll()` snapshots the set under the lock, clears it, then cancels
/// each handle outside the lock so a Task's completion handler can't deadlock
/// against the same lock while we're tearing down.
///
/// `@unchecked Sendable`: the only mutable state is `tasks`, protected by
/// `OSAllocatedUnfairLock`. All access goes through `withLock`, so concurrent
/// reads/writes from any isolation are safe.
final class TaskTracker: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment

    private let tasks = OSAllocatedUnfairLock<Set<Task<Void, Never>>>(initialState: [])

    /// Insert an already-created Task into the tracking set. Prunes
    /// already-cancelled handles on every insert so the set does not grow
    /// across many call sites. Safe to call from any isolation context.
    func record(_ task: Task<Void, Never>) {
        tasks.withLock { current in
            current = current.filter { !$0.isCancelled }
            current.insert(task)
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
}
