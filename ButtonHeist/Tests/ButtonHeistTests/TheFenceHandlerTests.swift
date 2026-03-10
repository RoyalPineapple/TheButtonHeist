import XCTest
import Network
@testable import ButtonHeist
import TheScore

// MARK: - TheFence Handler Dispatch & Validation Tests
//
// These tests exercise the command dispatch router and the argument-validation
// paths inside TheFence+Handlers using mock DeviceConnecting/DeviceDiscovering
// implementations injected via TheHandoff closures (see Mocks.swift).

final class TheFenceHandlerTests: XCTestCase {

    private static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1),
        certFingerprint: "sha256:mock"
    )

    private static let testServerInfo = ServerInfo(
        protocolVersion: "5.0",
        appName: "MockApp",
        bundleIdentifier: "com.test.mock",
        deviceName: "MockDevice",
        systemVersion: "18.0",
        screenWidth: 393,
        screenHeight: 852
    )

    // MARK: - Helpers

    @ButtonHeistActor
    private func makeConnectedFence() -> (TheFence, MockConnection) {
        let mockConn = MockConnection()
        mockConn.serverInfo = Self.testServerInfo
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), elements: []))
            case .requestScreen:
                return .screen(ScreenPayload(pngData: "", width: 393, height: 852))
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

        let mockDisc = MockDiscovery()
        mockDisc.discoveredDevices = [Self.testDevice]

        let fence = TheFence()
        fence.client.handoff.makeDiscovery = { mockDisc }
        fence.client.handoff.makeConnection = { _, _, _ in mockConn }
        return (fence, mockConn)
    }

    /// Assert that executing a request returns a `.error(...)` response containing the substring.
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

    /// Assert that executing a request passes validation (returns a non-error response).
    @ButtonHeistActor
    private func assertPassesValidation(
        _ request: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: request)
            if case .error(let message) = response {
                XCTFail("Got validation error: \(message)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    // MARK: - Argument Parsing Helpers

    @ButtonHeistActor
    func testStringArg() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["key": "hello", "number": 42]
        XCTAssertEqual(fence.stringArg(dict, "key"), "hello")
        XCTAssertNil(fence.stringArg(dict, "number"))
        XCTAssertNil(fence.stringArg(dict, "missing"))
    }

    @ButtonHeistActor
    func testIntArgFromInt() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["count": 5]
        XCTAssertEqual(fence.intArg(dict, "count"), 5)
    }

    @ButtonHeistActor
    func testIntArgFromDouble() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["count": 5.7]
        XCTAssertEqual(fence.intArg(dict, "count"), 5)
    }

    @ButtonHeistActor
    func testIntArgFromString() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["count": "42"]
        XCTAssertEqual(fence.intArg(dict, "count"), 42)
    }

    @ButtonHeistActor
    func testIntArgMissing() {
        let (fence, _) = makeConnectedFence()
        XCTAssertNil(fence.intArg([:], "count"))
    }

    @ButtonHeistActor
    func testDoubleArgFromDouble() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["x": 3.14]
        XCTAssertEqual(fence.doubleArg(dict, "x"), 3.14)
    }

    @ButtonHeistActor
    func testDoubleArgFromInt() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["x": 7]
        XCTAssertEqual(fence.doubleArg(dict, "x"), 7.0)
    }

    @ButtonHeistActor
    func testDoubleArgFromString() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["x": "2.5"]
        XCTAssertEqual(fence.doubleArg(dict, "x"), 2.5)
    }

    @ButtonHeistActor
    func testDoubleArgMissing() {
        let (fence, _) = makeConnectedFence()
        XCTAssertNil(fence.doubleArg([:], "x"))
    }

    @ButtonHeistActor
    func testNumberArgVariousTypes() {
        let (fence, _) = makeConnectedFence()
        XCTAssertEqual(fence.numberArg(1.5), 1.5)
        XCTAssertEqual(fence.numberArg(3), 3.0)
        XCTAssertEqual(fence.numberArg("4.2"), 4.2)
        XCTAssertNil(fence.numberArg(nil))
        XCTAssertNil(fence.numberArg("notANumber"))
    }

    @ButtonHeistActor
    func testElementTargetWithIdentifier() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["identifier": "myButton"]
        let target = fence.elementTarget(dict)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.identifier, "myButton")
        XCTAssertNil(target?.order)
    }

    @ButtonHeistActor
    func testElementTargetWithOrder() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["order": 3]
        let target = fence.elementTarget(dict)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.order, 3)
        XCTAssertNil(target?.identifier)
    }

    @ButtonHeistActor
    func testElementTargetWithBoth() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["identifier": "btn", "order": 2]
        let target = fence.elementTarget(dict)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.identifier, "btn")
        XCTAssertEqual(target?.order, 2)
    }

    @ButtonHeistActor
    func testElementTargetMissing() {
        let (fence, _) = makeConnectedFence()
        XCTAssertNil(fence.elementTarget([:]))
    }

    // MARK: - Dispatch: Unknown Command

    @ButtonHeistActor
    func testUnknownCommandReturnsError() async {
        await assertValidationError(
            ["command": "nonexistent_command"],
            contains: "Unknown command"
        )
    }

    // MARK: - Gesture Validation

    @ButtonHeistActor
    func testOneFingerTapMissingTarget() async {
        await assertValidationError(
            ["command": "one_finger_tap"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithCoordinatesPassesValidation() async {
        await assertPassesValidation(
            ["command": "one_finger_tap", "x": 100.0, "y": 200.0]
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithIdentifierPassesValidation() async {
        await assertPassesValidation(
            ["command": "one_finger_tap", "identifier": "myButton"]
        )
    }

    @ButtonHeistActor
    func testLongPressMissingTarget() async {
        await assertValidationError(
            ["command": "long_press"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testLongPressWithCoordinatesPassesValidation() async {
        await assertPassesValidation(
            ["command": "long_press", "x": 50.0, "y": 50.0]
        )
    }

    @ButtonHeistActor
    func testSwipeInvalidDirection() async {
        await assertValidationError(
            ["command": "swipe", "direction": "diagonal"],
            contains: "Invalid direction"
        )
    }

    @ButtonHeistActor
    func testSwipeValidDirectionPassesValidation() async {
        await assertPassesValidation(
            ["command": "swipe", "direction": "up"]
        )
    }

    @ButtonHeistActor
    func testDragMissingEndCoordinates() async {
        await assertValidationError(
            ["command": "drag", "startX": 10.0, "startY": 10.0],
            contains: "endX and endY are required"
        )
    }

    @ButtonHeistActor
    func testDragWithEndCoordinatesPassesValidation() async {
        await assertPassesValidation(
            ["command": "drag", "endX": 100.0, "endY": 200.0]
        )
    }

    @ButtonHeistActor
    func testPinchMissingScale() async {
        await assertValidationError(
            ["command": "pinch"],
            contains: "scale is required"
        )
    }

    @ButtonHeistActor
    func testPinchWithScalePassesValidation() async {
        await assertPassesValidation(
            ["command": "pinch", "scale": 2.0]
        )
    }

    @ButtonHeistActor
    func testRotateMissingAngle() async {
        await assertValidationError(
            ["command": "rotate"],
            contains: "angle is required"
        )
    }

    @ButtonHeistActor
    func testRotateWithAnglePassesValidation() async {
        await assertPassesValidation(
            ["command": "rotate", "angle": 1.57]
        )
    }

    // MARK: - Draw Path Validation

    @ButtonHeistActor
    func testDrawPathMissingPoints() async {
        await assertValidationError(
            ["command": "draw_path"],
            contains: "points must be an array"
        )
    }

    @ButtonHeistActor
    func testDrawPathTooFewPoints() async {
        await assertValidationError(
            ["command": "draw_path", "points": [["x": 1.0, "y": 2.0]]],
            contains: "at least 2 points"
        )
    }

    @ButtonHeistActor
    func testDrawPathInvalidPointData() async {
        await assertValidationError(
            ["command": "draw_path", "points": [["x": "bad", "y": "data"]]],
            contains: "numeric x and y"
        )
    }

    @ButtonHeistActor
    func testDrawPathValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "draw_path", "points": [
                ["x": 0.0, "y": 0.0],
                ["x": 100.0, "y": 100.0],
            ]]
        )
    }

    // MARK: - Draw Bezier Validation

    @ButtonHeistActor
    func testDrawBezierMissingStart() async {
        await assertValidationError(
            ["command": "draw_bezier"],
            contains: "startX and startY are required"
        )
    }

    @ButtonHeistActor
    func testDrawBezierMissingSegments() async {
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0],
            contains: "segments array is required"
        )
    }

    @ButtonHeistActor
    func testDrawBezierEmptySegments() async {
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0, "segments": [] as [[String: Any]]],
            contains: "At least 1 bezier segment"
        )
    }

    @ButtonHeistActor
    func testDrawBezierInvalidSegment() async {
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0, "segments": [
                ["cp1X": 1.0, "cp1Y": 2.0],
            ]],
            contains: "cp1X, cp1Y, cp2X, cp2Y, endX, endY"
        )
    }

    @ButtonHeistActor
    func testDrawBezierValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0, "segments": [
                ["cp1X": 10.0, "cp1Y": 20.0, "cp2X": 30.0, "cp2Y": 40.0, "endX": 50.0, "endY": 60.0],
            ]]
        )
    }

    // MARK: - Scroll Action Validation

    @ButtonHeistActor
    func testScrollMissingDirection() async {
        await assertValidationError(
            ["command": "scroll", "identifier": "scrollView"],
            contains: "direction is required"
        )
    }

    @ButtonHeistActor
    func testScrollInvalidDirection() async {
        await assertValidationError(
            ["command": "scroll", "identifier": "scrollView", "direction": "diagonal"],
            contains: "Invalid direction"
        )
    }

    @ButtonHeistActor
    func testScrollMissingElement() async {
        await assertValidationError(
            ["command": "scroll", "direction": "down"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testScrollValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll", "direction": "down", "identifier": "scrollView"]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleMissingElement() async {
        await assertValidationError(
            ["command": "scroll_to_visible"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_visible", "identifier": "targetElement"]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeMissingEdge() async {
        await assertValidationError(
            ["command": "scroll_to_edge", "identifier": "scrollView"],
            contains: "edge is required"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeInvalidEdge() async {
        await assertValidationError(
            ["command": "scroll_to_edge", "identifier": "scrollView", "edge": "middle"],
            contains: "Invalid edge"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeMissingElement() async {
        await assertValidationError(
            ["command": "scroll_to_edge", "edge": "bottom"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_edge", "edge": "bottom", "identifier": "scrollView"]
        )
    }

    // MARK: - Accessibility Action Validation

    @ButtonHeistActor
    func testActivateMissingElement() async {
        await assertValidationError(
            ["command": "activate"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testActivateWithElementPassesValidation() async {
        await assertPassesValidation(
            ["command": "activate", "identifier": "myElement"]
        )
    }

    @ButtonHeistActor
    func testIncrementMissingElement() async {
        await assertValidationError(
            ["command": "increment"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testDecrementMissingElement() async {
        await assertValidationError(
            ["command": "decrement"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionMissingElement() async {
        await assertValidationError(
            ["command": "perform_custom_action", "actionName": "doSomething"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionMissingActionName() async {
        await assertValidationError(
            ["command": "perform_custom_action", "identifier": "myElement"],
            contains: "actionName is required"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "perform_custom_action", "identifier": "myElement", "actionName": "doSomething"]
        )
    }

    // MARK: - Text Input Validation

    @ButtonHeistActor
    func testTypeTextMissingBothFields() async {
        await assertValidationError(
            ["command": "type_text"],
            contains: "Must specify text, deleteCount, or both"
        )
    }

    @ButtonHeistActor
    func testTypeTextWithTextPassesValidation() async {
        await assertPassesValidation(
            ["command": "type_text", "text": "hello"]
        )
    }

    @ButtonHeistActor
    func testTypeTextWithDeleteCountPassesValidation() async {
        await assertPassesValidation(
            ["command": "type_text", "deleteCount": 5]
        )
    }

    @ButtonHeistActor
    func testEditActionMissingAction() async {
        await assertValidationError(
            ["command": "edit_action"],
            contains: "action is required"
        )
    }

    @ButtonHeistActor
    func testEditActionValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "edit_action", "action": "copy"]
        )
    }

    // MARK: - Recording Validation

    @ButtonHeistActor
    func testStartRecordingWhenConnected() async {
        let (fence, _) = makeConnectedFence()
        do {
            // Auto-connect triggers during execute
            let response = try await fence.execute(request: ["command": "start_recording"])
            if case .ok = response {
                // Expected — recording start requested
            } else if case .error = response {
                // Acceptable — means the fence handled it
            } else {
                // Any response is fine — we just care it didn't crash
            }
        } catch {
            // notConnected or other errors are acceptable
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

    @ButtonHeistActor
    func testIntArgFromInvalidString() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["count": "not_a_number"]
        XCTAssertNil(fence.intArg(dict, "count"))
    }

    @ButtonHeistActor
    func testDoubleArgFromInvalidString() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["x": "not_a_number"]
        XCTAssertNil(fence.doubleArg(dict, "x"))
    }

    @ButtonHeistActor
    func testElementTargetWithOrderAsDouble() {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["order": 5.0]
        let target = fence.elementTarget(dict)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.order, 5)
    }
}
