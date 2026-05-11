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
}

#endif // canImport(UIKit)
