import XCTest
@testable import ButtonHeist
import TheScore

@MainActor
final class TheClientTests: XCTestCase {

    func testInitialState() {
        let client = TheClient()

        XCTAssertTrue(client.discoveredDevices.isEmpty)
        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentInterface)
        XCTAssertFalse(client.isDiscovering)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testDisconnectClearsState() {
        let client = TheClient()

        // Call disconnect (even without connection should be safe)
        client.disconnect()

        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentInterface)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testStopDiscoveryClearsFlag() {
        let client = TheClient()

        // Start and stop discovery
        client.startDiscovery()
        client.stopDiscovery()

        XCTAssertFalse(client.isDiscovering)
    }

    func testMultipleDisconnectsSafe() {
        let client = TheClient()

        // Multiple disconnects should be safe
        client.disconnect()
        client.disconnect()
        client.disconnect()

        XCTAssertEqual(client.connectionState, .disconnected)
    }

    // MARK: - waitForRecording

    func testWaitForRecordingSuccess() async throws {
        let client = TheClient()
        let expectedPayload = makeRecordingPayload(stopReason: .manual)

        let task = Task {
            try await client.waitForRecording(timeout: 5.0)
        }

        // Allow the task to install its callbacks
        await Task.yield()

        client.onRecording?(expectedPayload)

        let result = try await task.value
        XCTAssertEqual(result.frameCount, expectedPayload.frameCount)
        XCTAssertEqual(result.stopReason, .manual)
    }

    func testWaitForRecordingServerError() async throws {
        let client = TheClient()

        let task = Task {
            try await client.waitForRecording(timeout: 5.0)
        }

        await Task.yield()

        client.onRecordingError?("AVAssetWriter failed")

        do {
            _ = try await task.value
            XCTFail("Expected RecordingError.serverError to be thrown")
        } catch let error as TheClient.RecordingError {
            if case .serverError(let message) = error {
                XCTAssertEqual(message, "AVAssetWriter failed")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        }
    }

    func testWaitForRecordingTimeout() async throws {
        let client = TheClient()

        do {
            _ = try await client.waitForRecording(timeout: 0.05)
            XCTFail("Expected ActionError.timeout to be thrown")
        } catch is TheClient.ActionError {
            // Expected
        }
    }

    // MARK: - Helpers

    private func makeRecordingPayload(stopReason: RecordingPayload.StopReason) -> RecordingPayload {
        let start = Date()
        return RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390,
            height: 844,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: start,
            endTime: start.addingTimeInterval(5.0),
            stopReason: stopReason
        )
    }
}
