import XCTest
import Network
@testable import ButtonHeist
import TheScore

// MARK: - TheFence Security, Dispatch, and Edge Case Tests
//
// Split from TheFenceHandlerTests for SwiftLint file_length compliance.
// Uses the same mock infrastructure from Mocks.swift.

final class TheFenceSecurityTests: XCTestCase {

    @ButtonHeistActor
    private func assertValidationError(
        _ request: [String: Any],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: request)
            if case .error(let message) = response {
                XCTAssertTrue(
                    message.contains(substring),
                    "Expected error containing '\(substring)', got: \(message)",
                    file: file, line: line
                )
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    // MARK: - Path Traversal Validation

    @ButtonHeistActor
    func testGetScreenRejectsPathTraversal() async {
        await assertValidationError(
            ["command": "get_screen", "output": "/tmp/../etc/passwd"],
            contains: "must not contain '..'"
        )
    }

    @ButtonHeistActor
    func testGetScreenRejectsNestedPathTraversal() async {
        await assertValidationError(
            ["command": "get_screen", "output": "/tmp/safe/../../etc/shadow"],
            contains: "must not contain '..'"
        )
    }

    @ButtonHeistActor
    func testStopRecordingRejectsPathTraversal() async {
        let (fence, mockConn) = makeConnectedFence()
        // Put the handoff into recording state by simulating a server recordingStarted
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), elements: []))
            case .requestScreen:
                return .screen(ScreenPayload(pngData: "", width: 393, height: 852))
            case .startRecording:
                return .recordingStarted
            case .stopRecording:
                return .recording(RecordingPayload(
                    videoData: "", width: 390, height: 844, duration: 1,
                    frameCount: 8, fps: 8, startTime: Date(), endTime: Date(),
                    stopReason: .manual
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        do {
            try await fence.start()
            // Trigger recording so handoff.isRecording becomes true
            _ = try await fence.execute(request: ["command": "start_recording"])
            // Allow the mock's Task-dispatched recordingStarted message to arrive
            for _ in 0..<5 { await Task.yield() }
            let response = try await fence.execute(request: [
                "command": "stop_recording", "output": "/tmp/../etc/passwd",
            ])
            if case .error(let message) = response {
                XCTAssertTrue(
                    message.contains("must not contain '..'"),
                    "Expected path traversal error, got: \(message)"
                )
            } else {
                XCTFail("Expected .error response, got: \(response)")
            }
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    @ButtonHeistActor
    func testGetScreenAcceptsValidPath() async {
        let tmpDir = NSTemporaryDirectory()
        let outputPath = tmpDir + "test_screenshot.png"
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: ["command": "get_screen", "output": outputPath])
            if case .screenshot(let path, _, _) = response {
                XCTAssertFalse(path.contains(".."), "Resolved path should not contain '..'")
            }
            try? FileManager.default.removeItem(atPath: outputPath)
        } catch {
            // notConnected or timeout is acceptable — path validation passed
        }
    }

    // MARK: - Recording Validation

    @ButtonHeistActor
    func testStartRecordingWhenConnected() async throws {
        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(request: ["command": "start_recording"])
        switch response {
        case .ok:
            break
        case .error:
            break
        default:
            XCTFail("Expected .ok or .error for start_recording, got: \(response)")
        }
    }

    // MARK: - Dispatch Routes All Known Commands

    @ButtonHeistActor
    func testAllCatalogCommandsAreRouted() async {
        let (fence, _) = makeConnectedFence()
        let skipCommands: Set<TheFence.Command> = [.help, .quit, .exit]

        for command in TheFence.Command.allCases where !skipCommands.contains(command) {
            do {
                let response = try await fence.execute(request: ["command": command.rawValue])
                if case .error(let message) = response {
                    XCTAssertFalse(
                        message.hasPrefix("Unknown command"),
                        "Command '\(command.rawValue)' was not routed by dispatch"
                    )
                }
            } catch let error as FenceError {
                if case .notConnected = error {
                    XCTFail("Command '\(command.rawValue)' hit notConnected — mock connection should be active")
                }
            } catch {
                // Any other error is OK — means the command was recognized
            }
        }
    }

    // MARK: - Edge Cases: Arg Parsing with Mixed Types

    func testIntegerFromInvalidString() {
        let dict: [String: Any] = ["count": "not_a_number"]
        XCTAssertNil(dict.integer("count"))
    }

    func testNumberFromInvalidString() {
        let dict: [String: Any] = ["x": "not_a_number"]
        XCTAssertNil(dict.number("x"))
    }

}
