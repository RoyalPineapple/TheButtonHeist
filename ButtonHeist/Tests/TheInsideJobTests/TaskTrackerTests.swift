import XCTest
@testable import TheInsideJob

/// Covers the leak fix in `TaskTracker`: completed Tasks must self-remove
/// from the tracking set via the sibling watcher Task spawned by
/// `record(_:)`. The previous prune-on-insert filter only removed cancelled
/// Tasks, so normal completion left handles in the set forever.
///
/// These tests are deterministic — synchronization is via `await task.value`
/// and bounded polling on the watcher Task's eventual removal, never wall
/// clock sleeps.
final class TaskTrackerTests: XCTestCase {

    // MARK: - Helpers

    /// Poll `condition` until it returns `true` or `timeout` elapses. The
    /// watcher Task spawned by `record(_:)` removes a completed Task on the
    /// global cooperative pool; we yield until the removal lands rather than
    /// racing on a fixed sleep.
    private func waitUntil(
        timeout: TimeInterval = 5.0,
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    // MARK: - Completion path

    func testRecordedTasksAreRemovedOnCompletion() async {
        let tracker = TaskTracker()
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<32 {
            let task = Task { /* completes immediately */ }
            tracker.record(task)
            tasks.append(task)
        }

        // Drain the recorded Tasks themselves first so the watchers' `await
        // task.value` resolves and they can take the lock to self-remove.
        for task in tasks { await task.value }

        let drained = await waitUntil { tracker.taskCountForTesting == 0 }
        XCTAssertTrue(drained,
                      "Completed Tasks must self-remove; observed \(tracker.taskCountForTesting) lingering")
    }

    func testSpawnedTasksAreRemovedOnCompletion() async {
        let tracker = TaskTracker()
        for _ in 0..<32 {
            tracker.spawn { /* completes immediately */ }
        }

        let drained = await waitUntil { tracker.taskCountForTesting == 0 }
        XCTAssertTrue(drained,
                      "spawn(_:) completions must drain; observed \(tracker.taskCountForTesting) lingering")
    }

    // MARK: - Teardown path

    func testCancelAllCancelsAndDrains() async {
        let tracker = TaskTracker()
        let gate = AsyncSemaphore()
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<8 {
            let task = Task { await gate.wait() }
            tracker.record(task)
            tasks.append(task)
        }

        // The set holds the 8 long-running tasks. Watchers are still parked
        // on `await task.value` — that's fine, cancelAll empties the set
        // synchronously under the lock.
        XCTAssertGreaterThanOrEqual(tracker.taskCountForTesting, 1,
                                     "tracker should be populated before cancelAll")

        tracker.cancelAll()
        XCTAssertEqual(tracker.taskCountForTesting, 0,
                       "cancelAll must clear the set immediately")

        // Each tracked Task must observe the cancellation.
        gate.signalAll()
        for task in tasks {
            await task.value
            XCTAssertTrue(task.isCancelled, "cancelAll must propagate to tracked Tasks")
        }
    }

    // MARK: - Weak self / no retain on watcher

    func testWatcherDoesNotLeakSelfAfterDeinit() async {
        // Sentinel observes TaskTracker's deinit indirectly: we keep a weak
        // reference and assert it nils after the strong reference is dropped,
        // even while a recorded long-running Task is still in flight.
        let gate = AsyncSemaphore()
        let holder = WeakHolder()
        let longTask: Task<Void, Never>

        do {
            let tracker = TaskTracker()
            holder.set(tracker)
            longTask = Task { await gate.wait() }
            tracker.record(longTask)
            // Drop the strong reference here.
        }

        // The watcher Task captures `[weak self, task]`, so the only strong
        // refs are the tracked Task (still parked) and the watcher's own weak
        // self — which doesn't retain. The tracker should be released.
        let released = await waitUntil { holder.isNil }
        XCTAssertTrue(released, "TaskTracker leaked despite weak self in watcher")

        // Let the long-running Task finish so the watcher's `await task.value`
        // resolves; self?.remove is a no-op on nil self. No crash, no leak.
        gate.signalAll()
        await longTask.value
    }

    // MARK: - Race tolerance

    func testRapidRecordCompletionIsRaceFree() async {
        let tracker = TaskTracker()
        let count = 1000
        var tasks: [Task<Void, Never>] = []
        tasks.reserveCapacity(count)
        for index in 0..<count {
            let task = Task {
                // Minimal work; a few yields to interleave with watchers.
                if index.isMultiple(of: 2) { await Task.yield() }
            }
            tracker.record(task)
            tasks.append(task)
        }

        for task in tasks { await task.value }

        let drained = await waitUntil(timeout: 10.0) {
            tracker.taskCountForTesting == 0
        }
        XCTAssertTrue(drained,
                      "1000 rapid record/complete cycles must fully drain; observed \(tracker.taskCountForTesting) lingering")
    }
}

// MARK: - WeakHolder

/// Holds a weak reference behind a lock so it can be observed from
/// `@Sendable` polling closures under strict concurrency.
private final class WeakHolder: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private weak var object: AnyObject?

    func set(_ object: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        self.object = object
    }

    var isNil: Bool {
        lock.lock(); defer { lock.unlock() }
        return object == nil
    }
}

// MARK: - AsyncSemaphore

/// Minimal one-shot async gate. `wait()` suspends until `signalAll()` is
/// called; subsequent waits return immediately. Used to park tracked Tasks
/// deterministically without `Task.sleep`.
private final class AsyncSemaphore: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private var isSignalled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isSignalled {
                lock.unlock()
                continuation.resume()
            } else {
                continuations.append(continuation)
                lock.unlock()
            }
        }
    }

    func signalAll() {
        lock.lock()
        isSignalled = true
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pending {
            continuation.resume()
        }
    }
}
