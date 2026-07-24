import os
import XCTest

@testable import TheInsideJob
import TheScore

final class MainThreadProbeTests: XCTestCase {
    @MainActor
    func testWireAdapterMapsCompletedWorkToResponsiveWithoutOverflow() async throws {
        let request = try XCTUnwrap(MainThreadProbeRequest.admit(
            responsivenessTimeoutMilliseconds: .max,
            workTimeoutMilliseconds: .max
        ))

        let response = try await MainThreadProbe.execute(request)

        XCTAssertEqual(response.outcome, .responsive)
    }

    @MainActor
    func testCompletedWorkReturnsCompleted() async throws {
        let scheduler = ManualMainScheduler()
        let workCount = OSAllocatedUnfairLock(initialState: 0)

        let outcome = try await MainThreadProbe.execute(
            timeouts: .immediate,
            dependencies: dependencies(scheduler: scheduler),
            work: {
                workCount.withLock { $0 += 1 }
            }
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(workCount.withLock { $0 }, 1)
    }

    @MainActor
    func testMissingMainRunLoopTurnReturnsUnresponsive() async throws {
        let scheduler = ManualMainScheduler()
        let workCount = OSAllocatedUnfairLock(initialState: 0)

        let outcome = try await MainThreadProbe.execute(
            timeouts: .immediate,
            dependencies: dependencies(scheduler: scheduler, runScheduledWork: false),
            work: {
                workCount.withLock { $0 += 1 }
            }
        )

        XCTAssertEqual(outcome, .mainThreadUnresponsive)
        scheduler.runOnMain()
        XCTAssertEqual(workCount.withLock { $0 }, 0)
    }

    @MainActor
    func testStartedWorkWithoutCompletionReturnsWorkTimedOut() async throws {
        let scheduler = ManualMainScheduler()
        let deferredWork = DeferredMainWork()

        let outcome = try await MainThreadProbe.execute(
            timeouts: .immediate,
            dependencies: dependencies(
                scheduler: scheduler,
                executeWork: deferredWork.store
            ),
            work: {}
        )

        XCTAssertEqual(outcome, .workTimedOut)
        deferredWork.completeOnMain()
    }

    @MainActor
    func testLateMainRunLoopTurnSuppressesWork() async throws {
        let scheduler = ManualMainScheduler()
        let executionCount = OSAllocatedUnfairLock(initialState: 0)

        let outcome = try await MainThreadProbe.execute(
            timeouts: .immediate,
            dependencies: dependencies(scheduler: scheduler, runScheduledWork: false),
            work: {
                executionCount.withLock { $0 += 1 }
            }
        )

        scheduler.runOnMain()
        scheduler.runOnMain()

        XCTAssertEqual(outcome, .mainThreadUnresponsive)
        XCTAssertEqual(executionCount.withLock { $0 }, 0)
    }

    @MainActor
    func testCompletionWinsAConcurrentWorkTimeout() async throws {
        let scheduler = ManualMainScheduler()
        let deferredWork = DeferredMainWork()
        let waitCount = OSAllocatedUnfairLock(initialState: 0)

        let outcome = try await MainThreadProbe.execute(
            timeouts: .immediate,
            dependencies: MainThreadProbe.Dependencies(
                schedule: scheduler.schedule,
                executeWork: deferredWork.store,
                wait: { semaphore, _ in
                    let stage = waitCount.withLock { count in
                        defer { count += 1 }
                        return count
                    }
                    if stage == 0 {
                        scheduler.runFromWaitQueue()
                        return semaphore.wait(timeout: .now())
                    }
                    deferredWork.completeFromWaitQueue()
                    return .timedOut
                },
                waitQueue: probeWaitQueue
            ),
            work: {}
        )

        XCTAssertEqual(outcome, .completed)
    }

    func testCancellationWakesAnUnboundedWait() async {
        let waitStarted = DispatchSemaphore(value: 0)
        let task = Task {
            try await MainThreadProbe.execute(
                timeouts: MainThreadProbe.Timeouts(
                    responsiveness: MainThreadProbe.Timeout(nanoseconds: .max),
                    work: MainThreadProbe.Timeout(nanoseconds: .max)
                ),
                dependencies: MainThreadProbe.Dependencies(
                    schedule: { _ in },
                    executeWork: { _, _ in },
                    wait: { semaphore, _ in
                        waitStarted.signal()
                        return semaphore.wait(timeout: .distantFuture)
                    },
                    waitQueue: probeWaitQueue
                ),
                work: {}
            )
        }

        await Task {
            waitStarted.wait()
        }.value
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected probe cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}

private let probeWaitQueue = DispatchQueue(
    label: "com.buttonheist.main-thread-probe-tests"
)

private extension MainThreadProbe.Timeouts {
    static let immediate = Self(
        responsiveness: MainThreadProbe.Timeout(nanoseconds: 0),
        work: MainThreadProbe.Timeout(nanoseconds: 0)
    )
}

private func dependencies(
    scheduler: ManualMainScheduler,
    runScheduledWork: Bool = true,
    executeWork: @escaping @MainActor @Sendable (
        @escaping MainThreadProbe.MainOperation,
        @escaping @Sendable () -> Void
    ) -> Void = { work, completion in
        work()
        completion()
    }
) -> MainThreadProbe.Dependencies {
    let waitCount = OSAllocatedUnfairLock(initialState: 0)
    return MainThreadProbe.Dependencies(
        schedule: scheduler.schedule,
        executeWork: executeWork,
        wait: { semaphore, _ in
            let isFirstWait = waitCount.withLock { count in
                defer { count += 1 }
                return count == 0
            }
            if isFirstWait, runScheduledWork {
                scheduler.runFromWaitQueue()
            }
            return semaphore.wait(timeout: .now())
        },
        waitQueue: probeWaitQueue
    )
}

private final class ManualMainScheduler: @unchecked Sendable {
    private let scheduled = OSAllocatedUnfairLock<MainThreadProbe.MainOperation?>(
        initialState: nil
    )

    func schedule(_ operation: @escaping MainThreadProbe.MainOperation) {
        scheduled.withLock { $0 = operation }
    }

    func runFromWaitQueue() {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                runOnMain()
            }
        }
    }

    @MainActor
    func runOnMain() {
        scheduled.withLock { operation in
            let operationToRun = operation
            operation = nil
            return operationToRun
        }?()
    }
}

private final class DeferredMainWork: @unchecked Sendable {
    private struct Pending {
        let work: MainThreadProbe.MainOperation
        let completion: @Sendable () -> Void
    }

    private let pending = OSAllocatedUnfairLock<Pending?>(initialState: nil)

    @MainActor
    func store(
        work: @escaping MainThreadProbe.MainOperation,
        completion: @escaping @Sendable () -> Void
    ) {
        pending.withLock {
            $0 = Pending(work: work, completion: completion)
        }
    }

    func completeFromWaitQueue() {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                completeOnMain()
            }
        }
    }

    @MainActor
    func completeOnMain() {
        let pendingWork = pending.withLock { pending in
            let work = pending
            pending = nil
            return work
        }
        pendingWork?.work()
        pendingWork?.completion()
    }
}
