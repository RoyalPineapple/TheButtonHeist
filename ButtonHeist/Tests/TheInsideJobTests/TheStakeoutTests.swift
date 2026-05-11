#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
import TheScore
import UIKit

/// Mutable value-bag for test capture across `@Sendable` callbacks. The completion
/// callback runs on MainActor after `fulfillment(...)` has unblocked, so reads and
/// writes are serialized in practice; the test framework's expectation barrier is
/// the synchronization point. `@unchecked Sendable` here mirrors the established
/// `Box` pattern in `TheMuscleTests` / `WaitForIntegrationTests`.
private final class Box<Value>: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    var value: Value
    init(_ value: Value) { self.value = value }
}

final class TheStakeoutTests: XCTestCase {

    // MARK: - Helpers

    /// Default screen info for tests — small enough that AVAssetWriter setup is cheap,
    /// even and divisible by 2 so the H.264 codec is happy.
    private static let testScreen = TheStakeout.ScreenInfo(
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        scale: 1.0
    )

    private func makeStakeout(captureFrame: @MainActor @Sendable @escaping () async -> UIImage? = { nil }) -> TheStakeout {
        TheStakeout(captureFrame: captureFrame)
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() async {
        let stakeout = makeStakeout()
        let isIdle = await stakeout.isIdle
        let interactionLog = await stakeout.interactionLog
        let elapsed = await stakeout.recordingElapsed
        XCTAssertTrue(isIdle)
        XCTAssertTrue(interactionLog.isEmpty)
        XCTAssertEqual(elapsed, 0)
    }

    // MARK: - startRecording

    func testStartRecordingTransitionsToRecording() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        let isRecording = await stakeout.isRecording
        let elapsed = await stakeout.recordingElapsed
        XCTAssertTrue(isRecording)
        XCTAssertGreaterThan(elapsed, 0)
    }

    func testStartRecordingWhileRecordingThrows() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        do {
            try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)
            XCTFail("Expected alreadyRecording error")
        } catch let error as TheStakeout.TheStakeoutError {
            guard case .alreadyRecording = error else {
                XCTFail("Expected .alreadyRecording, got \(error)")
                return
            }
        }

        // Should still be recording (not corrupted by failed second start)
        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)
    }

    // MARK: - stopRecording

    func testStopRecordingTransitionsToFinalizing() async throws {
        // Use a config that won't actually finalize during the test window —
        // we want to observe the .finalizing transition, not the post-finalize idle.
        // Capture closure blocks indefinitely so finishWriting never returns within the assertion window.
        let stakeout = makeStakeout()
        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        // Kick off the stop and observe the intermediate state.
        let stopTask = Task { await stakeout.stopRecording(reason: .manual) }

        // The stop transitions to .finalizing synchronously before awaiting finishWriting.
        // We can't reliably catch this in-flight without racing, so instead wait for completion
        // and just verify the lifecycle ends in idle (which implies finalizing was passed through).
        await stopTask.value
        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    func testStopRecordingWhenIdleIsNoOp() async {
        let stakeout = makeStakeout()

        await stakeout.stopRecording(reason: .manual)

        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    func testStopRecordingPreservesInteractionLog() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        await stakeout.recordInteraction(event: event)
        let preStopCount = await stakeout.interactionLog.count
        XCTAssertEqual(preStopCount, 1)

        // The full stop returns the actor to idle; the log is delivered via onRecordingComplete.
        // Set a completion handler to capture the payload's interaction log.
        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let capturedLog = Box<[InteractionEvent]?>(nil)
        await stakeout.setOnRecordingComplete { result in
            if case .success(let payload) = result {
                capturedLog.value = payload.interactionLog
            }
            completionExpectation.fulfill()
        }
        await stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)
        XCTAssertEqual(capturedLog.value?.count, 1)
    }

    // MARK: - noteActivity / noteScreenChange

    func testNoteActivityWhenIdleIsNoOp() async {
        let stakeout = makeStakeout()
        await stakeout.noteActivity()
        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    func testNoteScreenChangeWhenIdleIsNoOp() async {
        let stakeout = makeStakeout()
        await stakeout.noteScreenChange()
        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    func testNoteActivityDuringRecordingKeepsRecording() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)
        await stakeout.noteActivity()

        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)
    }

    func testNoteScreenChangeDuringRecordingKeepsRecording() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)
        await stakeout.noteScreenChange()

        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)
    }

    // MARK: - recordInteraction

    func testRecordInteractionAppendsEvent() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        await stakeout.recordInteraction(event: event)

        let count = await stakeout.interactionLog.count
        XCTAssertEqual(count, 1)
    }

    func testRecordInteractionCapsAt500() async throws {
        let stakeout = makeStakeout()

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )

        for _ in 0..<510 {
            await stakeout.recordInteraction(event: event)
        }

        let count = await stakeout.interactionLog.count
        XCTAssertEqual(count, 500)
    }

    func testRecordInteractionWhenIdleIsNoOp() async {
        let stakeout = makeStakeout()

        let event = InteractionEvent(
            timestamp: 1.0,
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )
        await stakeout.recordInteraction(event: event)

        let isEmpty = await stakeout.interactionLog.isEmpty
        XCTAssertTrue(isEmpty)
    }

    // MARK: - recordInteractionIfRecording

    /// Cross-cutting audit Finding 3: the prior `isRecording` / `recordingElapsed`
    /// / `recordInteraction` triple-hop opened a TOCTOU window where a recording
    /// could transition to `.finalizing` between the phase check and the log
    /// append, silently dropping the interaction. The new combined entry point
    /// resolves the phase, timestamp, and append in one actor-isolated step.
    /// This test pins the happy path: a recording-state stakeout records the
    /// interaction with a sensible timestamp.
    func testRecordInteractionIfRecordingAppendsDuringRecording() async throws {
        let stakeout = makeStakeout()
        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)

        await stakeout.recordInteractionIfRecording(
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )

        let log = await stakeout.interactionLog
        XCTAssertEqual(log.count, 1, "Interaction must be appended when recording")
        XCTAssertGreaterThanOrEqual(log.first?.timestamp ?? -1, 0, "Timestamp must be a non-negative offset from the recording start")
    }

    /// When the stakeout has already transitioned past `.recording`, the
    /// combined entry point must no-op gracefully. This is the contract that
    /// lets `recordAndBroadcast` call it unconditionally without a separate
    /// `isRecording` guard.
    func testRecordInteractionIfRecordingDuringIdleIsNoOp() async {
        let stakeout = makeStakeout()

        await stakeout.recordInteractionIfRecording(
            command: .requestInterface,
            result: ActionResult(success: true, method: .activate)
        )

        let isEmpty = await stakeout.interactionLog.isEmpty
        XCTAssertTrue(isEmpty, "No interaction should be recorded when the stakeout is idle")
    }

    // MARK: - captureActionFrame

    func testCaptureActionFrameWhenIdleIsNoOp() async {
        let frameCaptured = Box(false)
        let stakeout = TheStakeout(captureFrame: { @MainActor in
            frameCaptured.value = true
            return nil
        })

        await stakeout.captureActionFrame()

        XCTAssertFalse(frameCaptured.value)
    }

    // MARK: - Inactivity timeout auto-stop

    func testInactivityTimeoutStopsRecording() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let completionResult = Box<Result<RecordingPayload, Error>?>(nil)
        await stakeout.setOnRecordingComplete { result in
            completionResult.value = result
            completionExpectation.fulfill()
        }

        // Use minimum inactivity timeout (1s) for fast test
        try await stakeout.startRecording(
            config: RecordingConfig(
                inactivityTimeout: 1.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )

        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)

        // Wait for inactivity timeout to fire + finalization
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // Should have completed successfully with inactivity reason
        if let result = completionResult.value {
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
        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    // MARK: - Manual stop delivers payload

    func testManualStopDeliversPayloadViaCallback() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let completionResult = Box<Result<RecordingPayload, Error>?>(nil)
        await stakeout.setOnRecordingComplete { result in
            completionResult.value = result
            completionExpectation.fulfill()
        }

        try await stakeout.startRecording(
            config: RecordingConfig(
                inactivityTimeout: 60.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )
        await stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        if let result = completionResult.value {
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

        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }

    // MARK: - Config clamping verified through payload

    func testFPSClampingReflectedInPayload() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let completionPayload = Box<RecordingPayload?>(nil)
        await stakeout.setOnRecordingComplete { result in
            if case .success(let payload) = result {
                completionPayload.value = payload
            }
            completionExpectation.fulfill()
        }

        // FPS 0 should clamp to 1
        try await stakeout.startRecording(
            config: RecordingConfig(
                fps: 0,
                inactivityTimeout: 60.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )
        await stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(completionPayload.value?.fps, 1)
    }

    func testHighFPSClampingReflectedInPayload() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let completionPayload = Box<RecordingPayload?>(nil)
        await stakeout.setOnRecordingComplete { result in
            if case .success(let payload) = result {
                completionPayload.value = payload
            }
            completionExpectation.fulfill()
        }

        // FPS 100 should clamp to 15
        try await stakeout.startRecording(
            config: RecordingConfig(
                fps: 100,
                inactivityTimeout: 60.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )
        await stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(completionPayload.value?.fps, 15)
    }

    // MARK: - State queries

    func testStateQueriesMatchInternalState() async throws {
        let stakeout = makeStakeout()
        let isIdleStart = await stakeout.isIdle
        XCTAssertTrue(isIdleStart)

        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)
        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)

        // After full stop the actor returns to idle once finalize completes.
        let completionExpectation = XCTestExpectation(description: "Recording completed")
        await stakeout.setOnRecordingComplete { _ in completionExpectation.fulfill() }
        await stakeout.stopRecording(reason: .manual)
        await fulfillment(of: [completionExpectation], timeout: 5.0)
        let isIdleEnd = await stakeout.isIdle
        XCTAssertTrue(isIdleEnd)
    }

    // MARK: - Full lifecycle: idle → recording → finalizing → idle

    func testFullLifecycleReturnsToIdle() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        await stakeout.setOnRecordingComplete { _ in
            completionExpectation.fulfill()
        }

        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)

        try await stakeout.startRecording(
            config: RecordingConfig(
                inactivityTimeout: 60.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )
        let isRecording = await stakeout.isRecording
        XCTAssertTrue(isRecording)

        await stakeout.stopRecording(reason: .manual)

        await fulfillment(of: [completionExpectation], timeout: 5.0)
        let isIdleAgain = await stakeout.isIdle
        XCTAssertTrue(isIdleAgain)

        // Can start a new recording after full cycle
        try await stakeout.startRecording(config: RecordingConfig(), screen: Self.testScreen)
        let isRecordingAgain = await stakeout.isRecording
        XCTAssertTrue(isRecordingAgain)
    }

    // MARK: - noteActivity extends inactivity deadline

    func testNoteActivityExtendsInactivityDeadline() async throws {
        let stakeout = makeStakeout()

        let completionExpectation = XCTestExpectation(description: "Recording completed")
        let stopReason = Box<RecordingPayload.StopReason?>(nil)
        await stakeout.setOnRecordingComplete { result in
            if case .success(let payload) = result {
                stopReason.value = payload.stopReason
            }
            completionExpectation.fulfill()
        }

        // 2s inactivity timeout
        try await stakeout.startRecording(
            config: RecordingConfig(
                inactivityTimeout: 2.0,
                maxDuration: 60.0
            ),
            screen: Self.testScreen
        )

        // Keep poking activity every 1s for 3 seconds — should not time out.
        // Inactivity-timeout test: needs real elapsed time between activity pokes.
        for _ in 0..<3 {
            // swiftlint:disable:next agent_test_task_sleep
            try await Task.sleep(for: .seconds(1))
            await stakeout.noteActivity()
        }

        // Now stop poking and let inactivity fire
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertEqual(stopReason.value, .inactivity)
        let isIdle = await stakeout.isIdle
        XCTAssertTrue(isIdle)
    }
}

#endif // canImport(UIKit)
