import XCTest
@testable import ButtonHeist
import TheScore

@ButtonHeistActor
final class TheMastermindTests: XCTestCase {

    func testInitialState() {
        let client = TheMastermind()

        XCTAssertTrue(client.discoveredDevices.isEmpty)
        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentInterface)
        XCTAssertFalse(client.isDiscovering)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testDisconnectClearsState() {
        let client = TheMastermind()

        // Call disconnect (even without connection should be safe)
        client.disconnect()

        XCTAssertNil(client.connectedDevice)
        XCTAssertNil(client.serverInfo)
        XCTAssertNil(client.currentInterface)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testStopDiscoveryClearsFlag() {
        let client = TheMastermind()

        // Start and stop discovery
        client.startDiscovery()
        client.stopDiscovery()

        XCTAssertFalse(client.isDiscovering)
    }

    func testMultipleDisconnectsSafe() {
        let client = TheMastermind()

        // Multiple disconnects should be safe
        client.disconnect()
        client.disconnect()
        client.disconnect()

        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testDiscoverReachableDevicesPreservesExistingDiscoverySession() async {
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "ReachableApp#live",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:reachable"
        )
        let client = TheMastermind()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [reachableDevice]
        client.handoff.makeDiscovery = { mockDiscovery }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { device in
            let connection = MockConnection()
            connection.emitTransportReadyOnConnect = true
            if device.id == reachableDevice.id {
                connection.autoResponse = { message in
                    switch message {
                    case .status:
                        return .status(StatusPayload(
                            identity: StatusIdentity(
                                appName: "ReachableApp",
                                bundleIdentifier: "com.test.reachable",
                                appBuild: "1",
                                deviceName: "Simulator",
                                systemVersion: "18.5",
                                buttonHeistVersion: "5.0"
                            ),
                            session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                        ))
                    default:
                        XCTFail("Unexpected probe message: \(message)")
                        return .error("unexpected")
                    }
                }
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        client.startDiscovery()
        XCTAssertTrue(client.isDiscovering)
        XCTAssertEqual(client.discoveredDevices, [reachableDevice])

        let devices = await client.discoverReachableDevices(timeout: 0.3)

        XCTAssertEqual(devices, [reachableDevice])
        XCTAssertTrue(client.isDiscovering)
        XCTAssertEqual(client.discoveredDevices, [reachableDevice])
        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockDiscovery.stopCount, 0)
    }

    // MARK: - waitForRecording

    func testWaitForRecordingSuccess() async throws {
        let client = TheMastermind()
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
        let client = TheMastermind()

        let task = Task {
            try await client.waitForRecording(timeout: 5.0)
        }

        await Task.yield()

        client.onRecordingError?("AVAssetWriter failed")

        do {
            _ = try await task.value
            XCTFail("Expected RecordingError.serverError to be thrown")
        } catch let error as TheMastermind.RecordingError {
            if case .serverError(let message) = error {
                XCTAssertEqual(message, "AVAssetWriter failed")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        }
    }

    func testWaitForRecordingTimeout() async throws {
        let client = TheMastermind()

        do {
            _ = try await client.waitForRecording(timeout: 0.05)
            XCTFail("Expected ActionError.timeout to be thrown")
        } catch is TheMastermind.ActionError {
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
