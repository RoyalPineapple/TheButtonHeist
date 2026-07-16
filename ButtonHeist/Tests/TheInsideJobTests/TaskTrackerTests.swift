import XCTest
import os
@testable import TheInsideJob

final class TaskTrackerTests: XCTestCase {

    func testImmediateCompletionCannotOutrunInsertion() async {
        let tracker = TaskTracker()
        let completions = LockedCounter()

        XCTAssertEqual(tracker.spawn { completions.increment() }, .accepted)
        await tracker.waitForIdle()

        XCTAssertEqual(completions.value, 1)
    }

    func testCompletionRacingDrainIsAccountedExactlyOnce() async {
        let tracker = TaskTracker()
        let entered = AsyncGate()
        let cancelled = AsyncGate()
        let terminalGate = AsyncGate()
        let completions = LockedCounter()

        XCTAssertEqual(
            tracker.spawn {
                entered.open()
                await withTaskCancellationHandler {
                    await terminalGate.wait()
                    completions.increment()
                } onCancel: {
                    cancelled.open()
                }
            },
            .accepted
        )
        await entered.wait()

        let drain = Task { await tracker.drain() }
        await cancelled.wait()
        terminalGate.open()
        await drain.value

        XCTAssertEqual(completions.value, 1)
        XCTAssertEqual(tracker.spawn {}, .rejected(.drained))
    }

    func testConcurrentDrainCallersAwaitOneCancellationInsensitiveOperation() async {
        let tracker = TaskTracker()
        let cancelled = AsyncGate()
        let terminalGate = AsyncGate()
        let firstReturned = AsyncGate()
        let secondStarted = AsyncGate()

        XCTAssertEqual(
            tracker.spawn {
                await withTaskCancellationHandler {
                    await terminalGate.wait()
                } onCancel: {
                    cancelled.open()
                }
            },
            .accepted
        )

        let firstDrain = Task {
            await tracker.drain()
            firstReturned.open()
        }
        await cancelled.wait()
        firstDrain.cancel()

        let secondDrain = Task {
            secondStarted.open()
            await tracker.drain()
        }
        await secondStarted.wait()

        XCTAssertFalse(firstReturned.isOpen)
        XCTAssertEqual(tracker.spawn {}, .rejected(.draining))

        terminalGate.open()
        await firstDrain.value
        await secondDrain.value

        XCTAssertTrue(firstReturned.isOpen)
        XCTAssertEqual(tracker.spawn {}, .rejected(.drained))
    }

    func testIdleWaitIncludesNewlyAdmittedWorkWithoutCancellingIt() async {
        let tracker = TaskTracker()
        let admitSecond = AsyncGate()
        let secondEntered = AsyncGate()
        let secondTerminalGate = AsyncGate()
        let idleStarted = AsyncGate()
        let idleReturned = AsyncGate()
        let cancellations = LockedCounter()

        XCTAssertEqual(
            tracker.spawn {
                await admitSecond.wait()
                tracker.spawn {
                    secondEntered.open()
                    await withTaskCancellationHandler {
                        await secondTerminalGate.wait()
                    } onCancel: {
                        cancellations.increment()
                    }
                }
            },
            .accepted
        )

        let idle = Task {
            idleStarted.open()
            await tracker.waitForIdle()
            idleReturned.open()
        }
        await idleStarted.wait()
        admitSecond.open()
        await secondEntered.wait()

        XCTAssertFalse(idleReturned.isOpen)
        secondTerminalGate.open()
        await idle.value

        XCTAssertEqual(cancellations.value, 0)
        XCTAssertTrue(idleReturned.isOpen)
    }

    func testDrainRunsCancellationCleanupAndReleasesTrackerAndCaptures() async {
        let terminalGate = AsyncGate()
        let operationRan = AsyncGate()
        var tracker: TaskTracker? = TaskTracker()
        weak let weakTracker = tracker
        var captured: LifetimeSentinel? = LifetimeSentinel()
        weak let weakCaptured = captured

        XCTAssertEqual(
            tracker?.spawn { [captured] in
                withExtendedLifetime(captured) {
                    operationRan.open()
                }
                await withTaskCancellationHandler {
                    await terminalGate.wait()
                } onCancel: {
                    terminalGate.open()
                }
            },
            .accepted
        )
        captured = nil

        await tracker?.drain()
        XCTAssertTrue(operationRan.isOpen)
        tracker = nil

        XCTAssertNil(weakTracker)
        XCTAssertNil(weakCaptured)
    }
}

private final class AsyncGate: Sendable {
    private enum State {
        case closed([CheckedContinuation<Void, Never>])
        case open
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: .closed([]))

    func wait() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock { state -> Bool in
                guard case .closed(var waiters) = state else { return true }
                waiters.append(continuation)
                state = .closed(waiters)
                return false
            }
            if isOpen {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            guard case .closed(let waiters) = state else { return [] }
            state = .open
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    var isOpen: Bool {
        state.withLock { state in
            guard case .open = state else { return false }
            return true
        }
    }
}

private final class LockedCounter: Sendable {
    private let count = OSAllocatedUnfairLock<Int>(initialState: 0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int {
        count.withLock { $0 }
    }
}

private final class LifetimeSentinel: Sendable {}
