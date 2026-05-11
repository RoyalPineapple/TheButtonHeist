#if canImport(UIKit)
import XCTest
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

    func testStopFromStoppedIsNoOp() {
        let job = TheInsideJob()
        job.stop()
        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromRunningTransitionsToStopped() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)

        job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromSuspendedTransitionsToStopped() {
        let job = TheInsideJob()
        job.serverPhase = .suspended

        job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
    }

    func testStopFromResumingCancelsTaskAndTransitionsToStopped() {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Task cancelled")
        let resumeTask = neverEndingTask {
            cancellationExpectation.fulfill()
        }
        job.serverPhase = .resuming(task: resumeTask)

        job.stop()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped after stop(), got \(job.serverPhase)")
            return
        }
        wait(for: [cancellationExpectation], timeout: 1.0)
    }

    // MARK: - ServerPhase: suspend()

    func testSuspendFromRunningTransitionsToSuspended() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)

        job.suspend()

        guard case .suspended = job.serverPhase else {
            XCTFail("Expected .suspended, got \(job.serverPhase)")
            return
        }
    }

    func testSuspendFromResumingCancelsTaskAndSuspends() {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Resume task cancelled")
        let resumeTask = neverEndingTask {
            cancellationExpectation.fulfill()
        }
        job.serverPhase = .resuming(task: resumeTask)

        job.suspend()

        guard case .suspended = job.serverPhase else {
            XCTFail("Expected .suspended after suspend during resume, got \(job.serverPhase)")
            return
        }
        wait(for: [cancellationExpectation], timeout: 1.0)
    }

    func testSuspendFromStoppedIsNoOp() {
        let job = TheInsideJob()

        job.suspend()

        guard case .stopped = job.serverPhase else {
            XCTFail("Expected .stopped (no-op), got \(job.serverPhase)")
            return
        }
    }

    func testSuspendFromSuspendedIsNoOp() {
        let job = TheInsideJob()
        job.serverPhase = .suspended

        job.suspend()

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

    func testSuspendPausesActivePollingPreservingInterval() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverPhase = .running(transport: transport)
        job.startPolling(interval: 5.0)

        job.suspend()

        guard case .paused(let interval) = job.pollingPhase else {
            XCTFail("Expected .paused, got \(job.pollingPhase)")
            return
        }
        XCTAssertEqual(interval, 5.0)
        XCTAssertTrue(job.isPollingEnabled)
    }

    func testSuspendFromResumingPausesActivePolling() {
        let job = TheInsideJob()
        let resumeTask = neverEndingTask()
        job.serverPhase = .resuming(task: resumeTask)
        job.startPolling(interval: 4.0)

        job.suspend()

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
}

#endif // canImport(UIKit)
