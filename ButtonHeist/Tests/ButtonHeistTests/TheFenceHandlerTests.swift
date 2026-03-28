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
        fence.handoff.makeDiscovery = { mockDisc }
        fence.handoff.makeConnection = { _, _, _ in mockConn }

        makeReachabilityConnection = { _ in
            let probe = MockConnection()
            probe.emitTransportReadyOnConnect = true
            probe.autoResponse = { message in
                if case .status = message {
                    return .status(StatusPayload(
                        identity: StatusIdentity(
                            appName: "Mock", bundleIdentifier: "com.test",
                            appBuild: "1", deviceName: "Mock",
                            systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                        ),
                        session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                    ))
                }
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return probe
        }

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
    func testSwipeWithUnitPointsPassesValidation() async {
        await assertPassesValidation(
            ["command": "swipe", "heistId": "row_5",
             "start": ["x": 0.8, "y": 0.5],
             "end": ["x": 0.2, "y": 0.5]]
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsMissingEndReturnsError() async {
        await assertValidationError(
            ["command": "swipe", "heistId": "row_5",
             "start": ["x": 0.8, "y": 0.5]],
            contains: "both start and end"
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsMissingStartReturnsError() async {
        await assertValidationError(
            ["command": "swipe", "heistId": "row_5",
             "end": ["x": 0.2, "y": 0.5]],
            contains: "both start and end"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementPassesValidation() async {
        await assertPassesValidation(
            ["command": "swipe", "heistId": "row_5", "direction": "left"]
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
    func testDragXYAliasForStartXY() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "drag", "x": 100.0, "y": 300.0, "endX": 300.0, "endY": 600.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchDrag(let target) = message else {
            XCTFail("Expected touchDrag message")
            return
        }
        XCTAssertEqual(target.startX, 100.0)
        XCTAssertEqual(target.startY, 300.0)
        XCTAssertEqual(target.endX, 300.0)
        XCTAssertEqual(target.endY, 600.0)
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
    func testPinchXYAliasForCenterXY() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "pinch", "scale": 2.0, "x": 200.0, "y": 500.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchPinch(let target) = message else {
            XCTFail("Expected touchPinch message")
            return
        }
        XCTAssertEqual(target.centerX, 200.0)
        XCTAssertEqual(target.centerY, 500.0)
    }

    @ButtonHeistActor
    func testPinchCenterXYTakesPrecedenceOverXY() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "pinch", "scale": 2.0,
            "centerX": 100.0, "centerY": 300.0,
            "x": 999.0, "y": 999.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchPinch(let target) = message else {
            XCTFail("Expected touchPinch message")
            return
        }
        XCTAssertEqual(target.centerX, 100.0)
        XCTAssertEqual(target.centerY, 300.0)
    }

    @ButtonHeistActor
    func testRotateXYAliasForCenterXY() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "rotate", "angle": 1.57, "x": 150.0, "y": 400.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchRotate(let target) = message else {
            XCTFail("Expected touchRotate message")
            return
        }
        XCTAssertEqual(target.centerX, 150.0)
        XCTAssertEqual(target.centerY, 400.0)
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

    // MARK: - Two Finger Tap

    @ButtonHeistActor
    func testTwoFingerTapXYAliasForCenterXY() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "two_finger_tap", "x": 200.0, "y": 500.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchTwoFingerTap(let target) = message else {
            XCTFail("Expected touchTwoFingerTap message")
            return
        }
        XCTAssertEqual(target.centerX, 200.0)
        XCTAssertEqual(target.centerY, 500.0)
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
            contains: "Must specify at least one match field"
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
            ["command": "perform_custom_action", "action": "doSomething"],
            contains: "Must specify element"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionMissingAction() async {
        await assertValidationError(
            ["command": "perform_custom_action", "identifier": "myElement"],
            contains: "action is required"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "perform_custom_action", "identifier": "myElement", "action": "doSomething"]
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionRejectsActionNameKey() async {
        await assertValidationError(
            ["command": "perform_custom_action", "identifier": "myElement", "actionName": "doSomething"],
            contains: "action is required"
        )
    }

    @ButtonHeistActor
    func testActivateWithCustomActionDispatches() async {
        await assertPassesValidation(
            ["command": "activate", "identifier": "myElement", "action": "Delete"]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementDispatches() async {
        await assertPassesValidation(
            ["command": "activate", "identifier": "myElement", "action": "increment"]
        )
    }

    @ButtonHeistActor
    func testActivateWithDecrementDispatches() async {
        await assertPassesValidation(
            ["command": "activate", "identifier": "myElement", "action": "decrement"]
        )
    }

    // MARK: - Text Input Validation

    @ButtonHeistActor
    func testTypeTextMissingBothFields() async {
        await assertValidationError(
            ["command": "type_text"],
            contains: "Must specify text, deleteCount, clearFirst, or a combination"
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

    // MARK: - Pasteboard Validation

    @ButtonHeistActor
    func testSetPasteboardMissingText() async {
        await assertValidationError(
            ["command": "set_pasteboard"],
            contains: "text is required"
        )
    }

    @ButtonHeistActor
    func testSetPasteboardWithTextPassesValidation() async {
        await assertPassesValidation(
            ["command": "set_pasteboard", "text": "hello"]
        )
    }

    @ButtonHeistActor
    func testGetPasteboardPassesValidation() async {
        await assertPassesValidation(
            ["command": "get_pasteboard"]
        )
    }

    // MARK: - Expectation Parsing

    @ButtonHeistActor
    func testParseExpectationNilWhenAbsent() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation(["command": "activate"])
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedSnakeCase() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation(["expect": "screen_changed"])
        XCTAssertEqual(result, .screenChanged)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedCamelCaseThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": "screenChanged"])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation tier"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationLayoutChangedSnakeCaseThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": "layout_changed"])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation tier"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationLayoutChangedCamelCaseThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": "layoutChanged"])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation tier"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationUnknownStringThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": "bogus"])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation tier"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationElementUpdatedWithSubObject() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": ["elementUpdated": ["heistId": "counter", "newValue": "5"]]
        ])
        XCTAssertEqual(result, .elementUpdated(heistId: "counter", newValue: "5"))
    }

    @ButtonHeistActor
    func testParseExpectationElementUpdatedAllFields() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": ["elementUpdated": ["heistId": "slider", "property": "value", "oldValue": "0", "newValue": "50"]]
        ])
        XCTAssertEqual(result, .elementUpdated(heistId: "slider", property: .value, oldValue: "0", newValue: "50"))
    }

    @ButtonHeistActor
    func testParseExpectationElementUpdatedBareKey() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation(["expect": ["elementUpdated": true]])
        XCTAssertEqual(result, .elementUpdated())
    }

    @ButtonHeistActor
    func testParseExpectationElementUpdatedEmptyObject() throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": ["elementUpdated": [String: Any]()]
        ])
        XCTAssertEqual(result, .elementUpdated())

    }

    @ButtonHeistActor
    func testParseExpectationLegacyValueChangedThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": ["valueChanged": ["heistId": "counter", "newValue": "5"]]
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("elementUpdated"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidObjectThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": ["wrong": "key"]])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid expectation object"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidTypeThrows() {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": 42])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid expectation type"))
        }
    }

    // MARK: - Batch Expectation Counting

    @ButtonHeistActor
    func testBatchCountsOnlyExplicitExpectations() async throws {
        let (fence, mockConn) = makeConnectedFence()
        // Mock returns a successful action result with an elementsChanged delta (updates only)
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, interfaceDelta: delta))
        }

        // Step 1 has expect → should count. Step 2 has no expect → should NOT count.
        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "btn1", "expect": "elements_changed"],
                ["command": "activate", "identifier": "btn2"],
            ] as [[String: Any]],
        ])

        guard case .batch(_, _, _, _, let checked, let met, _, _) = response else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        // Only step 1 had "expect", so checked should be 1
        XCTAssertEqual(checked, 1, "Only steps with explicit 'expect' should be counted")
        XCTAssertEqual(met, 1)
    }

    @ButtonHeistActor
    func testBatchCountsMetExpectations() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 10)
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, interfaceDelta: delta))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "btn1", "expect": "screen_changed"],
                ["command": "activate", "identifier": "btn2", "expect": "elements_changed"],
            ] as [[String: Any]],
        ])

        guard case .batch(_, _, _, _, let checked, let met, _, _) = response else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        // Both steps have expect and the delta is screenChanged (satisfies both tiers)
        XCTAssertEqual(checked, 2)
        XCTAssertEqual(met, 2)
    }

    @ButtonHeistActor
    func testBatchStopsOnErrorResponse() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        // Step 0 is an unknown command → .error response. Step 1 should not run.
        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "not_a_real_command"],
                ["command": "activate", "identifier": "btn1"],
            ] as [[String: Any]],
        ])

        guard case .batch(let results, _, let failedIndex, _, _, _, _, _) = response else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(results.count, 1, "Batch should stop after the error step")
        XCTAssertEqual(failedIndex, 0, "Failed index should be the error step")
    }

    @ButtonHeistActor
    func testBatchWithNoExpectationsShowsZeroCounts() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "btn1"],
                ["command": "activate", "identifier": "btn2"],
            ] as [[String: Any]],
        ])

        guard case .batch(_, _, _, _, let checked, let met, _, _) = response else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(checked, 0)
        XCTAssertEqual(met, 0)
    }
}
