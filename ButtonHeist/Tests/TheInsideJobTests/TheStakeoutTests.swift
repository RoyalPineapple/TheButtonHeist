#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
import TheScore

@MainActor
final class TheStakeoutTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        let stakeout = TheStakeout()
        XCTAssertEqual(stakeout.state, .idle)
        XCTAssertTrue(stakeout.interactionLog.isEmpty)
        XCTAssertEqual(stakeout.recordingElapsed, 0)
    }

    // MARK: - startRecording

    func testStartRecordingTransitionsToRecording() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())

        XCTAssertEqual(stakeout.state, .recording)
        XCTAssertGreaterThan(stakeout.recordingElapsed, 0)
    }

    func testStartRecordingWhileRecordingThrows() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())

        do {
            try stakeout.startRecording(config: RecordingConfig())
            XCTFail("Expected alreadyRecording error")
        } catch let error as TheStakeout.TheStakeoutError {
            guard case .alreadyRecording = error else {
                XCTFail("Expected .alreadyRecording, got \(error)")
                return
            }
        }

        // Should still be recording (not corrupted by failed second start)
        XCTAssertEqual(stakeout.state, .recording)
    }

    // MARK: - stopRecording

    func testStopRecordingTransitionsToFinalizing() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())
        stakeout.stopRecording(reason: .manual)

        XCTAssertEqual(stakeout.state, .finalizing)
    }

    func testStopRecordingWhenIdleIsNoOp() {
        let stakeout = TheStakeout()

        stakeout.stopRecording(reason: .manual)

        XCTAssertEqual(stakeout.state, .idle)
    }

    func testStopRecordingPreservesInteractionLog() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        stakeout.recordInteraction(event: event)
        XCTAssertEqual(stakeout.interactionLog.count, 1)

        stakeout.stopRecording(reason: .manual)

        // interactionLog should still be accessible in finalizing state
        XCTAssertEqual(stakeout.interactionLog.count, 1)
    }

    // MARK: - noteActivity / noteScreenChange

    func testNoteActivityWhenIdleIsNoOp() {
        let stakeout = TheStakeout()
        stakeout.noteActivity()
        XCTAssertEqual(stakeout.state, .idle)
    }

    func testNoteScreenChangeWhenIdleIsNoOp() {
        let stakeout = TheStakeout()
        stakeout.noteScreenChange()
        XCTAssertEqual(stakeout.state, .idle)
    }

    func testNoteActivityDuringRecordingKeepsRecording() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())
        stakeout.noteActivity()

        XCTAssertEqual(stakeout.state, .recording)
    }

    func testNoteScreenChangeDuringRecordingKeepsRecording() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())
        stakeout.noteScreenChange()

        XCTAssertEqual(stakeout.state, .recording)
    }

    // MARK: - recordInteraction

    func testRecordInteractionAppendsEvent() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        stakeout.recordInteraction(event: event)

        XCTAssertEqual(stakeout.interactionLog.count, 1)
    }

    func testRecordInteractionCapsAt500() throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        try stakeout.startRecording(config: RecordingConfig())

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )

        for _ in 0..<510 {
            stakeout.recordInteraction(event: event)
        }

        XCTAssertEqual(stakeout.interactionLog.count, 500)
    }

    func testRecordInteractionWhenIdleIsNoOp() {
        let stakeout = TheStakeout()

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        stakeout.recordInteraction(event: event)

        XCTAssertTrue(stakeout.interactionLog.isEmpty)
    }

    // MARK: - captureActionFrame

    func testCaptureActionFrameWhenIdleIsNoOp() {
        let stakeout = TheStakeout()
        var frameCaptured = false
        stakeout.captureFrame = {
            frameCaptured = true
            return nil
        }

        stakeout.captureActionFrame()

        XCTAssertFalse(frameCaptured)
    }

    // MARK: - Inactivity timeout auto-stop

    func testInactivityTimeoutStopsRecording() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        var completionResult: Result<RecordingPayload, Error>?
        stakeout.onRecordingComplete = { result in
            completionResult = result
            completionExpectation.fulfill()
        }

        // Use minimum inactivity timeout (1s) for fast test
        try stakeout.startRecording(config: RecordingConfig(
            inactivityTimeout: 1.0,
            maxDuration: 60.0
        ))

        XCTAssertEqual(stakeout.state, .recording)

        // Wait for inactivity timeout to fire + finalization
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // Should have completed successfully with inactivity reason
        if let result = completionResult {
            switch result {
            case .success(let payload):
                XCTAssertEqual(payload.stopReason, .inactivity)
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
        } else {
            XCTFail("No completion result received")
        }

        // State should be back to idle after cleanup
        XCTAssertEqual(stakeout.state, .idle)
    }

    // MARK: - Manual stop delivers payload

    func testManualStopDeliversPayloadViaCallback() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        var completionResult: Result<RecordingPayload, Error>?
        stakeout.onRecordingComplete = { result in
            completionResult = result
            completionExpectation.fulfill()
        }

        try stakeout.startRecording(config: RecordingConfig(
            inactivityTimeout: 60.0,
            maxDuration: 60.0
        ))
        stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        if let result = completionResult {
            switch result {
            case .success(let payload):
                XCTAssertEqual(payload.stopReason, .manual)
                XCTAssertGreaterThanOrEqual(payload.duration, 0)
                // Verify even pixel dimensions in payload
                XCTAssertEqual(payload.width % 2, 0)
                XCTAssertEqual(payload.height % 2, 0)
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
        } else {
            XCTFail("No completion result received")
        }

        XCTAssertEqual(stakeout.state, .idle)
    }

    // MARK: - Config clamping verified through payload

    func testFPSClampingReflectedInPayload() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        var completionPayload: RecordingPayload?
        stakeout.onRecordingComplete = { result in
            if case .success(let payload) = result {
                completionPayload = payload
            }
            completionExpectation.fulfill()
        }

        // FPS 0 should clamp to 1
        try stakeout.startRecording(config: RecordingConfig(
            fps: 0,
            inactivityTimeout: 60.0,
            maxDuration: 60.0
        ))
        stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(completionPayload?.fps, 1)
    }

    func testHighFPSClampingReflectedInPayload() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        var completionPayload: RecordingPayload?
        stakeout.onRecordingComplete = { result in
            if case .success(let payload) = result {
                completionPayload = payload
            }
            completionExpectation.fulfill()
        }

        // FPS 100 should clamp to 15
        try stakeout.startRecording(config: RecordingConfig(
            fps: 100,
            inactivityTimeout: 60.0,
            maxDuration: 60.0
        ))
        stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(completionPayload?.fps, 15)
    }

    // MARK: - State projection

    func testStateProjectionMatchesInternalState() throws {
        let stakeout = TheStakeout()
        XCTAssertEqual(stakeout.state, .idle)

        stakeout.captureFrame = { nil }
        try stakeout.startRecording(config: RecordingConfig())
        XCTAssertEqual(stakeout.state, .recording)

        stakeout.stopRecording(reason: .manual)
        XCTAssertEqual(stakeout.state, .finalizing)
    }

    // MARK: - Full lifecycle: idle → recording → finalizing → idle

    func testFullLifecycleReturnsToIdle() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        stakeout.onRecordingComplete = { _ in
            completionExpectation.fulfill()
        }

        XCTAssertEqual(stakeout.state, .idle)

        try stakeout.startRecording(config: RecordingConfig(
            inactivityTimeout: 60.0,
            maxDuration: 60.0
        ))
        XCTAssertEqual(stakeout.state, .recording)

        stakeout.stopRecording(reason: .manual)
        XCTAssertEqual(stakeout.state, .finalizing)

        await fulfillment(of: [completionExpectation], timeout: 5.0)
        XCTAssertEqual(stakeout.state, .idle)

        // Can start a new recording after full cycle
        try stakeout.startRecording(config: RecordingConfig())
        XCTAssertEqual(stakeout.state, .recording)
    }

    // MARK: - noteActivity extends inactivity deadline

    func testNoteActivityExtendsInactivityDeadline() async throws {
        let stakeout = TheStakeout()
        stakeout.captureFrame = { nil }

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        var stopReason: RecordingPayload.StopReason?
        stakeout.onRecordingComplete = { result in
            if case .success(let payload) = result {
                stopReason = payload.stopReason
            }
            completionExpectation.fulfill()
        }

        // 2s inactivity timeout
        try stakeout.startRecording(config: RecordingConfig(
            inactivityTimeout: 2.0,
            maxDuration: 60.0
        ))

        // Keep poking activity every 1s for 3 seconds — should not time out
        for _ in 0..<3 {
            try await Task.sleep(for: .seconds(1))
            stakeout.noteActivity()
        }

        // Now stop poking and let inactivity fire
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(stopReason, .inactivity)
        XCTAssertEqual(stakeout.state, .idle)
    }
}

#endif // canImport(UIKit)
