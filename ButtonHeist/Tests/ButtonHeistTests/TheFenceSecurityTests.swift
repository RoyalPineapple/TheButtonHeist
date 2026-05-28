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
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(
                operation: normalizedOperation(command: command, arguments: arguments)
            )
            if case .error(let message, _) = response {
                XCTAssertTrue(
                    message.contains(substring),
                    "Expected error containing '\(substring)', got: \(message)",
                    file: file, line: line
                )
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got: \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                message.contains(substring),
                "Expected error containing '\(substring)', got: \(message)",
                file: file, line: line
            )
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    // MARK: - Path Traversal Validation

    @ButtonHeistActor
    func testGetScreenRejectsPathTraversal() async {
        await assertValidationError(
            command: .getScreen,
            arguments: ["output": .string("/tmp/../etc/passwd")],
            contains: "must not contain '..'"
        )
    }

    @ButtonHeistActor
    func testGetScreenRejectsNestedPathTraversal() async {
        await assertValidationError(
            command: .getScreen,
            arguments: ["output": .string("/tmp/safe/../../etc/shadow")],
            contains: "must not contain '..'"
        )
    }

    @ButtonHeistActor
    func testStopRecordingRejectsPathTraversal() async {
        let (fence, mockConn) = makeConnectedFence()
        // Put TheFence into recording state by simulating a server recordingStarted.
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            case .requestScreen:
                return .screen(ScreenPayload(pngData: "", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: [])))
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
            // Trigger recording so TheFence's recording phase becomes active.
            _ = try await fence.execute(operation: normalizedOperation(command: .startRecording))
            // Allow the mock's Task-dispatched recordingStarted message to arrive
            for _ in 0..<5 { await Task.yield() }
            _ = try await fence.execute(
                operation: normalizedOperation(
                    command: .stopRecording,
                    arguments: ["output": .string("/tmp/../etc/passwd")]
                )
            )
            XCTFail("Expected invalid output path to throw")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got: \(error)")
            }
            XCTAssertTrue(
                message.contains("must not contain '..'"),
                "Expected path traversal error, got: \(message)"
            )
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
            let response = try await fence.execute(
                operation: normalizedOperation(command: .getScreen, arguments: ["output": .string(outputPath)])
            )
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
        let response = try await fence.execute(operation: normalizedOperation(command: .startRecording))
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
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        let skipCommands: Set<TheFence.Command> = [.help, .quit]

        for command in TheFence.Command.allCases where !skipCommands.contains(command) {
            do {
                let response = try await fence.execute(operation: normalizedOperation(command: command))
                if case .error(let message, _) = response {
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

    func testIntegerFromInvalidStringThrowsTypedSchemaError() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: ["count": .string("not_a_number")])
        XCTAssertThrowsError(try envelope.schemaInteger("count")) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.expected, "integer")
        }
    }

    func testNumberFromInvalidStringThrowsTypedSchemaError() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: ["x": .string("not_a_number")])
        XCTAssertThrowsError(try envelope.schemaNumber("x")) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.expected, "number")
        }
    }

}

private func normalizedOperation(
    command: TheFence.Command,
    arguments: [String: HeistValue] = [:]
) -> NormalizedOperation {
    NormalizedOperation(
        command: command,
        arguments: TheFence.CommandArgumentEnvelope(values: arguments)
    )
}
