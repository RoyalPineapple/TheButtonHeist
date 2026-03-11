import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceTests: XCTestCase {

    // MARK: - Command Enum

    func testCommandCaseCount() {
        XCTAssertEqual(TheFence.Command.allCases.count, 31)
    }

    func testCommandRawValuesMatchWireFormat() {
        let expected: [TheFence.Command: String] = [
            .help: "help",
            .status: "status",
            .quit: "quit",
            .exit: "exit",
            .listDevices: "list_devices",
            .getInterface: "get_interface",
            .getScreen: "get_screen",
            .waitForIdle: "wait_for_idle",
            .oneFingerTap: "one_finger_tap",
            .longPress: "long_press",
            .swipe: "swipe",
            .drag: "drag",
            .pinch: "pinch",
            .rotate: "rotate",
            .twoFingerTap: "two_finger_tap",
            .drawPath: "draw_path",
            .drawBezier: "draw_bezier",
            .scroll: "scroll",
            .scrollToVisible: "scroll_to_visible",
            .scrollToEdge: "scroll_to_edge",
            .activate: "activate",
            .increment: "increment",
            .decrement: "decrement",
            .performCustomAction: "perform_custom_action",
            .typeText: "type_text",
            .editAction: "edit_action",
            .dismissKeyboard: "dismiss_keyboard",
            .startRecording: "start_recording",
            .stopRecording: "stop_recording",
            .runBatch: "run_batch",
            .getSessionState: "get_session_state",
        ]
        XCTAssertEqual(expected.count, TheFence.Command.allCases.count)
        for (command, wire) in expected {
            XCTAssertEqual(command.rawValue, wire)
        }
    }

    // MARK: - FenceResponse Human Formatting

    func testOkResponseFormatting() {
        let response = FenceResponse.ok(message: "done")
        XCTAssertEqual(response.humanFormatted(), "done")
    }

    func testErrorResponseFormatting() {
        let response = FenceResponse.error("something broke")
        XCTAssertEqual(response.humanFormatted(), "Error: something broke")
    }

    func testHelpResponseFormatting() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let formatted = response.humanFormatted()
        XCTAssertTrue(formatted.contains("one_finger_tap"))
        XCTAssertTrue(formatted.contains("swipe"))
        XCTAssertTrue(formatted.hasPrefix("Commands:"))
    }

    func testStatusResponseConnected() {
        let response = FenceResponse.status(connected: true, deviceName: "TestApp")
        XCTAssertEqual(response.humanFormatted(), "Connected to TestApp")
    }

    func testStatusResponseDisconnected() {
        let response = FenceResponse.status(connected: false, deviceName: nil)
        XCTAssertEqual(response.humanFormatted(), "Not connected")
    }

    func testDevicesResponseEmpty() {
        let response = FenceResponse.devices([])
        XCTAssertEqual(response.humanFormatted(), "No devices found")
    }

    // MARK: - FenceResponse JSON Serialization

    func testOkResponseJSON() {
        let response = FenceResponse.ok(message: "done")
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(json?["message"] as? String, "done")
    }

    func testErrorResponseJSON() {
        let response = FenceResponse.error("failed")
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "error")
        XCTAssertEqual(json?["message"] as? String, "failed")
    }

    func testHelpResponseJSON() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        let commands = json?["commands"] as? [String]
        XCTAssertEqual(commands, ["one_finger_tap", "swipe"])
    }

    func testStatusResponseJSON() {
        let response = FenceResponse.status(connected: true, deviceName: "MyApp")
        let json = response.jsonDict()
        XCTAssertEqual(json?["connected"] as? Bool, true)
        XCTAssertEqual(json?["device"] as? String, "MyApp")
    }

    func testScreenshotResponseJSON() {
        let response = FenceResponse.screenshot(path: "/tmp/shot.png", width: 390, height: 844)
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(json?["path"] as? String, "/tmp/shot.png")
        XCTAssertEqual(json?["width"] as? Double, 390)
        XCTAssertEqual(json?["height"] as? Double, 844)
    }

    // MARK: - FenceError

    func testFenceErrorDescriptions() {
        XCTAssertNotNil(FenceError.noDeviceFound.errorDescription)
        XCTAssertNotNil(FenceError.connectionTimeout.errorDescription)
        XCTAssertNotNil(FenceError.notConnected.errorDescription)
        XCTAssertNotNil(FenceError.actionTimeout.errorDescription)
        XCTAssertNotNil(FenceError.invalidRequest("bad").errorDescription)
        XCTAssertNotNil(FenceError.connectionFailed("refused").errorDescription)
        XCTAssertNotNil(FenceError.sessionLocked("busy").errorDescription)
        XCTAssertNotNil(FenceError.authFailed("denied").errorDescription)
    }

    func testNoMatchingDeviceError() {
        let error = FenceError.noMatchingDevice(filter: "MyApp", available: ["OtherApp"])
        XCTAssertTrue(error.errorDescription?.contains("MyApp") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("OtherApp") ?? false)
    }

    func testNoMatchingDeviceErrorEmptyAvailable() {
        let error = FenceError.noMatchingDevice(filter: "MyApp", available: [])
        XCTAssertTrue(error.errorDescription?.contains("(none)") ?? false)
    }

    // MARK: - Timeouts

    func testTimeoutConstants() {
        XCTAssertEqual(Timeouts.action, 15_000_000_000)
        XCTAssertEqual(Timeouts.actionSeconds, 15)
        XCTAssertEqual(Timeouts.longAction, 30_000_000_000)
        XCTAssertEqual(Timeouts.longActionSeconds, 30)
        XCTAssertEqual(Timeouts.interfaceRequest, 10_000_000_000)
    }

    // MARK: - TheFence execute (error cases)

    @ButtonHeistActor
    func testExecuteWithMissingCommand() async {
        let fence = TheFence()
        do {
            _ = try await fence.execute(request: [:])
            XCTFail("Expected FenceError.invalidRequest")
        } catch let error as FenceError {
            if case .invalidRequest = error {
                // Expected
            } else {
                XCTFail("Expected invalidRequest, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @ButtonHeistActor
    func testExecuteHelp() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "help"])
        if case .help(let commands) = response {
            XCTAssertFalse(commands.isEmpty)
            XCTAssertTrue(commands.contains("one_finger_tap"))
        } else {
            XCTFail("Expected help response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteQuit() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "quit"])
        if case .ok(let message) = response {
            XCTAssertEqual(message, "bye")
        } else {
            XCTFail("Expected ok(bye), got \(response)")
        }
    }

    @ButtonHeistActor
    func testGetSessionStateDoesNotConnectWhenDisconnected() async throws {
        let device = DiscoveredDevice(
            id: "mock-device",
            name: "MockApp#test",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        let mockConnection = MockConnection()

        let fence = TheFence()
        fence.client.handoff.makeDiscovery = { mockDiscovery }
        fence.client.handoff.makeConnection = { _, _, _ in mockConnection }

        let response = try await fence.execute(request: ["command": "get_session_state"])

        if case .sessionState(let payload) = response {
            XCTAssertEqual(payload["connected"] as? Bool, false)
        } else {
            XCTFail("Expected sessionState response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 0)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }

    @ButtonHeistActor
    func testListDevicesFiltersOutUnreachableDevicesWithoutConnecting() async throws {
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "ReachableApp#live",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:reachable"
        )
        let staleDevice = DiscoveredDevice(
            id: "stale-device",
            name: "StaleApp#dead",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 2),
            certFingerprint: "sha256:stale"
        )

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [reachableDevice, staleDevice]
        let mockConnection = MockConnection()

        let fence = TheFence()
        fence.client.handoff.makeDiscovery = { mockDiscovery }
        fence.client.handoff.makeConnection = { _, _, _ in mockConnection }

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

        let response = try await fence.execute(request: ["command": "list_devices"])

        if case .devices(let devices) = response {
            XCTAssertEqual(devices, [reachableDevice])
        } else {
            XCTFail("Expected devices response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }
}
