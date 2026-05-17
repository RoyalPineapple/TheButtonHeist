#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

@MainActor
final class TheInsideJobStateTests: XCTestCase {

    // MARK: - ServerPhase: Initial

    func testInitialServerPhaseIsStopped() {
        let job = TheInsideJob()
        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped, got \(job.serverPhase)")
            return
        }
    }

    // MARK: - ServerPhase: stop()

    func testStopFromStoppedIsNoOp() async {
        let job = TheInsideJob()
        await job.stop()
        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromRunningTransitionsToStopped() async {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)

        await job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromSuspendedTransitionsToStopped() async {
        let job = TheInsideJob()
        job.serverPhase = .suspended

        await job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromResumingCancelsTaskAndTransitionsToStopped() async {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Task cancelled")
        let resumeTask = neverEndingTask {
            cancellationExpectation.fulfill()
        }
        job.serverPhase = .resuming(task: resumeTask)

        await job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
        await fulfillment(of: [cancellationExpectation], timeout: 1.0)
    }

    // MARK: - ServerPhase: suspend()

    func testSuspendFromRunningTransitionsToSuspended() async {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)

        await job.suspend()

        guard case .suspended = job.serverPhase else {
            XCTFail("Expected .suspended, got \(job.serverPhase)")
            return
        }
    }

    func testSuspendFromResumingCancelsTaskAndSuspends() async {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Resume task cancelled")
        let resumeTask = neverEndingTask {
            cancellationExpectation.fulfill()
        }
        job.serverPhase = .resuming(task: resumeTask)

        await job.suspend()

        guard case .suspended = job.serverPhase else {
            XCTFail("Expected .suspended after suspend during resume, got \(job.serverPhase)")
            return
        }
        await fulfillment(of: [cancellationExpectation], timeout: 1.0)
    }

    func testSuspendFromStoppedIsNoOp() async {
        let job = TheInsideJob()

        await job.suspend()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped (no-op), got \(job.serverPhase)")
            return
        }
    }

    func testSuspendFromSuspendedIsNoOp() async {
        let job = TheInsideJob()
        job.serverPhase = .suspended

        await job.suspend()

        guard case .suspended = job.serverPhase else {
            XCTFail("Expected .suspended (no-op), got \(job.serverPhase)")
            return
        }
    }

    // MARK: - ServerPhase: Impossible states eliminated

    func testRunningStateCarriesTransport() {
        let transport = ServerTransport()
        let state = TheInsideJob.ServerPhase.running(transport: transport)
        if case .running(let carried) = state {
            XCTAssertTrue(carried === transport)
        } else {
            XCTFail("Pattern match failed")
        }
    }

    func testResumingStateCarriesTask() {
        let task = Task { @MainActor in }
        let state = TheInsideJob.ServerPhase.resuming(task: task)
        guard case .resuming = state else {
            XCTFail("Expected .resuming")
            return
        }
    }

    // MARK: - PollingPhase: Initial

    func testInitialPollingPhaseIsDisabled() {
        let job = TheInsideJob()
        guard case .disabled = job.pollingPhase else {
            XCTFail("Expected .disabled, got \(job.pollingPhase)")
            return
        }
        XCTAssertFalse(job.isPollingEnabled)
    }

    // MARK: - PollingPhase: startPolling / stopPolling

    func testStartPollingTransitionsToActive() {
        let job = TheInsideJob()

        job.startPolling(interval: 3.0)

        guard case .active(_, let interval) = job.pollingPhase else {
            XCTFail("Expected .active, got \(job.pollingPhase)")
            return
        }
        XCTAssertEqual(interval, 3.0)
        XCTAssertTrue(job.isPollingEnabled)
        XCTAssertEqual(job.pollingTimeoutSeconds, 3.0)

        job.stopPolling()
    }

    func testStartPollingClampsMinimumInterval() {
        let job = TheInsideJob()

        job.startPolling(interval: 0.1)

        guard case .active(_, let interval) = job.pollingPhase else {
            XCTFail("Expected .active, got \(job.pollingPhase)")
            return
        }
        XCTAssertEqual(interval, 0.5)

        job.stopPolling()
    }

    func testStopPollingFromActiveTransitionsToDisabled() {
        let job = TheInsideJob()
        job.startPolling(interval: 2.0)

        job.stopPolling()

        guard case .disabled = job.pollingPhase else {
            XCTFail("Expected .disabled, got \(job.pollingPhase)")
            return
        }
        XCTAssertFalse(job.isPollingEnabled)
    }

    func testStopPollingFromDisabledIsNoOp() {
        let job = TheInsideJob()

        job.stopPolling()

        guard case .disabled = job.pollingPhase else {
            XCTFail("Expected .disabled, got \(job.pollingPhase)")
            return
        }
    }

    func testStopPollingFromPausedTransitionsToDisabled() {
        let job = TheInsideJob()
        job.pollingPhase = .paused(interval: 2.0)

        job.stopPolling()

        guard case .disabled = job.pollingPhase else {
            XCTFail("Expected .disabled, got \(job.pollingPhase)")
            return
        }
    }

    // MARK: - PollingPhase: suspend pauses active polling

    func testSuspendPausesActivePollingPreservingInterval() async {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)
        job.startPolling(interval: 5.0)

        await job.suspend()

        guard case .paused(let interval) = job.pollingPhase else {
            XCTFail("Expected .paused, got \(job.pollingPhase)")
            return
        }
        XCTAssertEqual(interval, 5.0)
        XCTAssertTrue(job.isPollingEnabled)
    }

    func testSuspendFromResumingPausesActivePolling() async {
        let job = TheInsideJob()
        let resumeTask = neverEndingTask()
        job.serverPhase = .resuming(task: resumeTask)
        job.startPolling(interval: 4.0)

        await job.suspend()

        guard case .paused(let interval) = job.pollingPhase else {
            XCTFail("Expected .paused, got \(job.pollingPhase)")
            return
        }
        XCTAssertEqual(interval, 4.0)

        job.stopPolling()
    }

    // MARK: - PollingPhase: Computed properties

    func testPollingTimeoutReturnsDefaultWhenDisabled() {
        let job = TheInsideJob()
        XCTAssertEqual(job.pollingTimeoutSeconds, 2.0)
    }

    func testPollingTimeoutReturnsIntervalWhenActive() {
        let job = TheInsideJob()
        job.startPolling(interval: 7.0)

        XCTAssertEqual(job.pollingTimeoutSeconds, 7.0)

        job.stopPolling()
    }

    func testPollingTimeoutReturnsIntervalWhenPaused() {
        let job = TheInsideJob()
        job.pollingPhase = .paused(interval: 3.5)
        XCTAssertEqual(job.pollingTimeoutSeconds, 3.5)
    }

    // MARK: - RecordingPhase

    func testInitialRecordingPhaseIsIdle() {
        let job = TheInsideJob()
        guard case .idle = job.recordingPhase else {
            XCTFail("Expected .idle, got \(job.recordingPhase)")
            return
        }
        XCTAssertNil(job.stakeout)
    }

    func testRecordingPhaseExposesStakeout() {
        let job = TheInsideJob()
        let recorder = TheStakeout(captureFrame: { nil })
        job.recordingPhase = .recording(stakeout: recorder)

        XCTAssertTrue(job.stakeout === recorder)
    }

    func testIdleRecordingPhaseHidesStakeout() {
        let job = TheInsideJob()
        let recorder = TheStakeout(captureFrame: { nil })
        job.recordingPhase = .recording(stakeout: recorder)

        job.recordingPhase = .idle

        XCTAssertNil(job.stakeout)
    }

    // MARK: - stop() awaits muscle.tearDown()

    /// Regression: previously `stop()` was sync and spawned an untracked
    /// `Task { await muscle.tearDown() }`, returning before the tearDown's
    /// `lockoutTasks` cancellation had a chance to run. A subsequent
    /// `start()` could race against that in-flight tearDown. The fix makes
    /// `stop()` async and awaits `muscle.tearDown()` inline; this test
    /// asserts the contract: after `await job.stop()` returns, no lockout
    /// Tasks remain in flight.
    func testStopAwaitsMuscleTearDownDrainingLockoutTasks() async throws {
        let job = TheInsideJob()

        // Seed a lockout Task: a bad-token authenticate triggers
        // `scheduleDelayedDisconnect`, which inserts into `lockoutTasks`.
        let sink: @Sendable (Data) -> Void = { _ in }
        await job.muscle.registerClientAddress(1, address: "127.0.0.1")
        let helloData = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        await job.muscle.handleUnauthenticatedMessage(1, data: helloData, respond: sink)
        let badAuth = try JSONEncoder().encode(
            RequestEnvelope(message: .authenticate(AuthenticatePayload(token: "WRONG", driverId: nil)))
        )
        await job.muscle.handleUnauthenticatedMessage(1, data: badAuth, respond: sink)

        let beforeCount = await job.muscle.pendingLockoutTaskCount
        XCTAssertGreaterThan(
            beforeCount, 0,
            "Test precondition: bad-token authenticate must seed a lockout Task"
        )

        await job.stop()

        let afterCount = await job.muscle.pendingLockoutTaskCount
        XCTAssertEqual(
            afterCount, 0,
            "After `await stop()` returns, every lockout Task must have been cancelled and drained by muscle.tearDown(). Got \(afterCount) still pending."
        )
    }

    // MARK: - resume() drains pendingLifecycleTasks before guarding on .suspended

    /// Regression for findings PR #356 M1+M2: a rapid background→foreground
    /// cycle delivered `appDidEnterBackground` (which spawns a Task wrapping
    /// `await suspend()`) and `appWillEnterForeground` back-to-back on the
    /// @MainActor. The previous `resume()` was synchronous and checked
    /// `guard case .suspended = serverPhase else { return }` at the top —
    /// before the in-flight suspend wrapper had a chance to set
    /// `.suspended`. The guard failed, resume returned silently, and the
    /// server stayed dead after foreground.
    ///
    /// The fix makes `resume()` async and drains `pendingLifecycleTasks`
    /// before checking phase. This test seeds the same race: serverPhase is
    /// `.running`, a tracked suspend wrapper is spawned (but its body has
    /// not run yet), then `await resume()` is called. Expectation: after
    /// resume() returns, the server is `.resuming` (the internal resume
    /// Task is in flight) — proving the drain observed the suspended state
    /// rather than no-op'ing.
    func testResumeDrainsPendingSuspendBeforeGuard() async {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)

        // Simulate what `appDidEnterBackground` does: enroll a suspend
        // wrapper into pendingLifecycleTasks without awaiting it. The Task
        // body runs asynchronously on @MainActor.
        job.spawnLifecycleTask { [weak job] in
            await job?.suspend()
        }

        // Without yielding, call resume(). The drain at the top of resume()
        // must await the suspend wrapper, observe `.suspended`, and proceed.
        await job.resume()

        // resume() spawns an internal Task and sets `.resuming` before
        // returning. The server may then complete the resume cycle and
        // become `.running`, OR remain `.resuming` while the internal task
        // is in flight. Anything except `.suspended` proves the drain
        // worked — `.suspended` would mean resume() returned without
        // kicking off the resume cycle.
        switch job.serverPhase {
        case .resuming, .running:
            break
        case .suspended:
            XCTFail("resume() no-op'd because guard observed pre-suspend state — drain failed")
        case .stopped:
            XCTFail("Unexpected .stopped after resume() — state machine corrupted")
        }
    }

    // MARK: - LifecycleBoundaryTasks

    func testLifecycleBoundaryTasksDrainRunsQueuedTasks() async {
        let tasks = TheInsideJob.LifecycleBoundaryTasks()
        var events: [String] = []

        tasks.spawn {
            events.append("first")
        }

        await tasks.drain()

        XCTAssertEqual(events, ["first"])
        XCTAssertTrue(tasks.isEmpty)
    }

    func testLifecycleBoundaryTasksDrainIncludesTasksSpawnedDuringDrain() async {
        let tasks = TheInsideJob.LifecycleBoundaryTasks()
        var events: [String] = []

        tasks.spawn {
            events.append("first")
            tasks.spawn {
                events.append("second")
            }
        }

        await tasks.drain()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertTrue(tasks.isEmpty)
    }

    /// Regression for findings PR #356 M2: `pendingLifecycleTasks` must not
    /// grow without bound across many background/foreground cycles. Each
    /// spawned Task removes itself from the set when its body completes.
    func testSpawnLifecycleTaskSelfRemovesOnCompletion() async {
        let job = TheInsideJob()

        let completed = expectation(description: "Tracked Task body ran")
        job.spawnLifecycleTask {
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1.0)

        // The body has completed; the self-removal closure runs on the
        // same @MainActor right after. Yield once so the continuation
        // following `await body()` inside spawnLifecycleTask gets a turn.
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(
            job.pendingLifecycleTasksIsEmpty,
            "Completed lifecycle Task should have removed itself from pendingLifecycleTasks"
        )
    }
}

#endif // canImport(UIKit)
