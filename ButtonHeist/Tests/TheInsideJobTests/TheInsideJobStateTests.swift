#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheInsideJobStateTests: XCTestCase {

    // MARK: - ServerState: Initial

    func testInitialServerStateIsStopped() {
        let job = TheInsideJob()
        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped, got \(job.serverState)")
            return
        }
    }

    // MARK: - ServerState: stop()

    func testStopFromStoppedIsNoOp() {
        let job = TheInsideJob()
        job.stop()
        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped after stop(), got \(job.serverState)")
            return
        }
    }

    func testStopFromRunningTransitionsToStopped() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverState = .running(transport: transport)

        job.stop()

        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped after stop(), got \(job.serverState)")
            return
        }
    }

    func testStopFromSuspendedTransitionsToStopped() {
        let job = TheInsideJob()
        job.serverState = .suspended

        job.stop()

        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped after stop(), got \(job.serverState)")
            return
        }
    }

    func testStopFromResumingCancelsTaskAndTransitionsToStopped() {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Task cancelled")
        let resumeTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(60)) } catch {}
            if Task.isCancelled { cancellationExpectation.fulfill() }
        }
        job.serverState = .resuming(task: resumeTask)

        job.stop()

        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped after stop(), got \(job.serverState)")
            return
        }
        wait(for: [cancellationExpectation], timeout: 1.0)
    }

    // MARK: - ServerState: suspend()

    func testSuspendFromRunningTransitionsToSuspended() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverState = .running(transport: transport)

        job.suspend()

        guard case .suspended = job.serverState else {
            XCTFail("Expected .suspended, got \(job.serverState)")
            return
        }
    }

    func testSuspendFromResumingCancelsTaskAndSuspends() {
        let job = TheInsideJob()
        let cancellationExpectation = XCTestExpectation(description: "Resume task cancelled")
        let resumeTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(60)) } catch {}
            if Task.isCancelled { cancellationExpectation.fulfill() }
        }
        job.serverState = .resuming(task: resumeTask)

        job.suspend()

        guard case .suspended = job.serverState else {
            XCTFail("Expected .suspended after suspend during resume, got \(job.serverState)")
            return
        }
        wait(for: [cancellationExpectation], timeout: 1.0)
    }

    func testSuspendFromStoppedIsNoOp() {
        let job = TheInsideJob()

        job.suspend()

        guard case .stopped = job.serverState else {
            XCTFail("Expected .stopped (no-op), got \(job.serverState)")
            return
        }
    }

    func testSuspendFromSuspendedIsNoOp() {
        let job = TheInsideJob()
        job.serverState = .suspended

        job.suspend()

        guard case .suspended = job.serverState else {
            XCTFail("Expected .suspended (no-op), got \(job.serverState)")
            return
        }
    }

    // MARK: - ServerState: Impossible states eliminated

    func testRunningStateCarriesTransport() {
        let transport = ServerTransport()
        let state = TheInsideJob.ServerState.running(transport: transport)
        if case .running(let carried) = state {
            XCTAssertTrue(carried === transport)
        } else {
            XCTFail("Pattern match failed")
        }
    }

    func testResumingStateCarriesTask() {
        let task = Task { @MainActor in }
        let state = TheInsideJob.ServerState.resuming(task: task)
        guard case .resuming = state else {
            XCTFail("Expected .resuming")
            return
        }
    }

    // MARK: - PollingState: Initial

    func testInitialPollingStateIsDisabled() {
        let job = TheInsideJob()
        guard case .disabled = job.pollingState else {
            XCTFail("Expected .disabled, got \(job.pollingState)")
            return
        }
        XCTAssertFalse(job.isPollingEnabled)
    }

    // MARK: - PollingState: startPolling / stopPolling

    func testStartPollingTransitionsToActive() {
        let job = TheInsideJob()

        job.startPolling(interval: 3.0)

        guard case .active(_, let interval) = job.pollingState else {
            XCTFail("Expected .active, got \(job.pollingState)")
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

        guard case .active(_, let interval) = job.pollingState else {
            XCTFail("Expected .active, got \(job.pollingState)")
            return
        }
        XCTAssertEqual(interval, 0.5)

        job.stopPolling()
    }

    func testStopPollingFromActiveTransitionsToDisabled() {
        let job = TheInsideJob()
        job.startPolling(interval: 2.0)

        job.stopPolling()

        guard case .disabled = job.pollingState else {
            XCTFail("Expected .disabled, got \(job.pollingState)")
            return
        }
        XCTAssertFalse(job.isPollingEnabled)
    }

    func testStopPollingFromDisabledIsNoOp() {
        let job = TheInsideJob()

        job.stopPolling()

        guard case .disabled = job.pollingState else {
            XCTFail("Expected .disabled, got \(job.pollingState)")
            return
        }
    }

    func testStopPollingFromPausedTransitionsToDisabled() {
        let job = TheInsideJob()
        job.pollingState = .paused(interval: 2.0)

        job.stopPolling()

        guard case .disabled = job.pollingState else {
            XCTFail("Expected .disabled, got \(job.pollingState)")
            return
        }
    }

    // MARK: - PollingState: suspend pauses active polling

    func testSuspendPausesActivePollingPreservingInterval() {
        let job = TheInsideJob()
        let transport = ServerTransport()
        job.serverState = .running(transport: transport)
        job.startPolling(interval: 5.0)

        job.suspend()

        guard case .paused(let interval) = job.pollingState else {
            XCTFail("Expected .paused, got \(job.pollingState)")
            return
        }
        XCTAssertEqual(interval, 5.0)
        XCTAssertTrue(job.isPollingEnabled)
    }

    func testSuspendFromResumingPausesActivePolling() {
        let job = TheInsideJob()
        let resumeTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(60)) } catch {}
        }
        job.serverState = .resuming(task: resumeTask)
        job.startPolling(interval: 4.0)

        job.suspend()

        guard case .paused(let interval) = job.pollingState else {
            XCTFail("Expected .paused, got \(job.pollingState)")
            return
        }
        XCTAssertEqual(interval, 4.0)

        job.stopPolling()
    }

    // MARK: - PollingState: Computed properties

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
        job.pollingState = .paused(interval: 3.5)
        XCTAssertEqual(job.pollingTimeoutSeconds, 3.5)
    }

    // MARK: - RecordingState

    func testInitialRecordingStateIsIdle() {
        let job = TheInsideJob()
        guard case .idle = job.recordingState else {
            XCTFail("Expected .idle, got \(job.recordingState)")
            return
        }
        XCTAssertNil(job.stakeout)
    }

    func testRecordingStateExposesStakeout() {
        let job = TheInsideJob()
        let recorder = TheStakeout()
        job.recordingState = .recording(stakeout: recorder)

        XCTAssertTrue(job.stakeout === recorder)
    }

    func testIdleRecordingStateHidesStakeout() {
        let job = TheInsideJob()
        let recorder = TheStakeout()
        job.recordingState = .recording(stakeout: recorder)

        job.recordingState = .idle

        XCTAssertNil(job.stakeout)
    }
}

#endif // canImport(UIKit)
