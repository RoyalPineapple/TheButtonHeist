import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceTests: XCTestCase {

    // MARK: - CommandCatalog

    func testCommandCatalogContainsExpectedCommands() {
        let commands = TheFence.CommandCatalog.all
        XCTAssertTrue(commands.contains("help"))
        XCTAssertTrue(commands.contains("one_finger_tap"))
        XCTAssertTrue(commands.contains("get_interface"))
        XCTAssertTrue(commands.contains("get_screen"))
        XCTAssertTrue(commands.contains("type_text"))
        XCTAssertTrue(commands.contains("start_recording"))
        XCTAssertTrue(commands.contains("stop_recording"))
        XCTAssertTrue(commands.contains("dismiss_keyboard"))
    }

    func testCommandCatalogHasNoDuplicates() {
        let commands = TheFence.CommandCatalog.all
        let unique = Set(commands)
        XCTAssertEqual(commands.count, unique.count, "CommandCatalog should not have duplicate entries")
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
}
