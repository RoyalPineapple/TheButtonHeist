import XCTest
import Network
@testable import ButtonHeist
import TheScore

private extension Array where Element == (ClientMessage, String?) {
    var adjustmentMessages: [ClientMessage] {
        compactMap { message, _ in
            switch message {
            case .increment, .decrement:
                return message
            default:
                return nil
            }
        }
    }
}

private extension ClientMessage {
    var isIncrement: Bool {
        if case .increment = self { return true }
        return false
    }

    var isDecrement: Bool {
        if case .decrement = self { return true }
        return false
    }
}

// MARK: - TheFence Handler Dispatch & Validation Tests
//
// These tests exercise the command dispatch router and the argument-validation
// paths inside TheFence+Handlers using mock DeviceConnecting/DeviceDiscovering
// implementations injected via TheHandoff closures (see Mocks.swift).

final class TheFenceHandlerTests: XCTestCase {

    // MARK: - Helpers

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
            if case .error(let message, _) = response {
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

    /// Assert that executing a request returns a `.error(...)` response with the exact message.
    @ButtonHeistActor
    private func assertValidationError(
        _ request: [String: Any],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: request)
            if case .error(let message, _) = response {
                XCTAssertEqual(message, expected, file: file, line: line)
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertContractError(
        _ request: [String: Any],
        contains expectedSubstrings: [String],
        errorCode: String,
        nextCommand: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: request)
            guard case .error(let message, let details) = response else {
                return XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
            for substring in expectedSubstrings {
                XCTAssertTrue(
                    message.contains(substring),
                    "Expected error containing '\(substring)', got: \(message)",
                    file: file, line: line
                )
            }
            XCTAssertEqual(details?.errorCode, errorCode, file: file, line: line)
            XCTAssertEqual(details?.phase, .request, file: file, line: line)
            XCTAssertEqual(details?.retryable, false, file: file, line: line)
            XCTAssertEqual(details?.hint, nextCommand, file: file, line: line)
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
            if case .error(let message, _) = response {
                XCTFail("Got validation error: \(message)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func decodedRunBatch(
        _ fence: TheFence,
        steps: [[String: Any]],
        policy: String? = nil
    ) throws -> TheFence.RunBatchRequest {
        var request: [String: Any] = [
            "command": "run_batch",
            "steps": steps,
        ]
        if let policy {
            request["policy"] = policy
        }
        let parsed = try fence.parseRequest(request)
        guard case .runBatch(let batch) = parsed.payload else {
            throw XCTSkip("Expected run_batch payload")
        }
        return batch
    }

    private func plannedBatchSteps(
        from batch: TheFence.RunBatchRequest
    ) -> [TheFence.RunBatchPreparedStep] {
        batch.steps.compactMap { step in
            if case .planned(let plannedStep) = step {
                return plannedStep
            }
            return nil
        }
    }

    private func unsupportedBatchCommandNames(
        from batch: TheFence.RunBatchRequest
    ) -> [String] {
        batch.steps.compactMap { step in
            if case .invalid(let commandName, _) = step {
                return commandName
            }
            return nil
        }
    }

    private func testElement(
        _ heistId: HeistId,
        label: String,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: identifier,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 10,
            frameHeight: 10,
            actions: traits.contains(.button) ? [.activate] : []
        )
    }

    private func exploredActionResult(elements: [HeistElement]) -> ActionResult {
        ActionResult(
            success: true,
            method: .explore,
            payload: .explore(ExploreResult(
                elements: elements,
                scrollCount: 1,
                containersExplored: 1,
                explorationTime: 0.1
            ))
        )
    }

    private func exploredActionResult(interface: Interface) -> ActionResult {
        ActionResult(
            success: true,
            method: .explore,
            payload: .explore(ExploreResult(
                elements: interface.elements,
                scrollCount: 1,
                containersExplored: 1,
                explorationTime: 0.1
            )),
            accessibilityTrace: AccessibilityTrace(interface: interface)
        )
    }

    private func selectionTestInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = testElement("title", label: "Menu", traits: [.header])
        let submit = testElement("submit", label: "Submit", traits: [.button])
        let cancel = testElement("cancel", label: "Cancel", traits: [.button])
        let footer = testElement("footer", label: "Footer")
        var nodes: [ReceiptTestInterfaceNode] = [
            .element(header),
            .container(
                makeReceiptTestSemanticContainer(
                    label: "Actions",
                    identifier: "actions",
                    frameX: 0,
                    frameY: 40,
                    frameWidth: 200,
                    frameHeight: 100
                ),
                stableId: "semantic_actions__actions",
                children: [.element(submit), .element(cancel)]
            ),
            .element(footer),
        ]
        if includeDuplicateGroup {
            let archive = testElement("archive", label: "Archive", traits: [.button])
            nodes.insert(
                .container(
                    makeReceiptTestSemanticContainer(
                        label: "Actions",
                        identifier: "secondary_actions",
                        frameX: 0,
                        frameY: 160,
                        frameWidth: 200,
                        frameHeight: 60
                    ),
                    stableId: "semantic_actions__secondary_actions",
                    children: [.element(archive)]
                ),
                at: 2
            )
        }
        return makeReceiptTestInterface(nodes: nodes)
    }

    // MARK: - BookKeeper

    @ButtonHeistActor
    func testArchiveSessionRetriesClosingAfterCompressionFailure() async throws {
        let (fence, _) = makeConnectedFence()
        try fence.bookKeeper.beginSession(identifier: "archive-retry")
        let statusRequest = try fence.parseRequest(command: .status, request: [
            "command": "status",
            "requestId": "r1",
        ])
        try fence.bookKeeper.logCommand(statusRequest)
        guard case .active(let activeSession) = fence.bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }

        let sessionDirectory = activeSession.directory
        let compressedLogPath = sessionDirectory.appendingPathComponent("session.jsonl.gz")
        var archivePath: URL?
        defer {
            if let archivePath {
                try? FileManager.default.removeItem(at: archivePath)
            }
            try? FileManager.default.removeItem(at: sessionDirectory)
        }

        try Data("existing compressed log".utf8).write(to: compressedLogPath)
        do {
            _ = try await fence.handleArchiveSession(.init(deleteSource: false))
            XCTFail("Expected compression failure")
        } catch let error as BookKeeperError {
            guard case .compressionFailed = error else {
                return XCTFail("Expected compressionFailed, got \(error)")
            }
        }

        guard case .closing(let failedClosingSession) = fence.bookKeeper.phase else {
            return XCTFail("Expected closing phase after failed compression")
        }
        XCTAssertEqual(failedClosingSession.sessionId, activeSession.sessionId)
        XCTAssertNil(failedClosingSession.compressionTask)

        try FileManager.default.removeItem(at: compressedLogPath)
        let response = try await fence.handleArchiveSession(.init(deleteSource: false))

        guard case .archiveResult(let path, let snapshot) = response else {
            return XCTFail("Expected archiveResult, got \(response)")
        }
        archivePath = URL(fileURLWithPath: path)
        XCTAssertEqual(snapshot.manifest.sessionId, activeSession.sessionId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Connect

    @ButtonHeistActor
    func testConnectReturnsSessionStateWithoutInterfaceObservation() async throws {
        let mockConn = MockConnection()
        mockConn.serverInfo = TheFenceFixtures.testServerInfo

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [TheFenceFixtures.testDevice]

        let fence = TheFence(configuration: .init(
            deviceFilter: "MockApp",
            autoReconnect: false
        ))
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConn }

        let previousReachability = makeReachabilityConnection
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
        defer { makeReachabilityConnection = previousReachability }

        XCTAssertFalse(fence.handoff.isConnected)
        XCTAssertFalse(mockConn.isConnected)
        let response = try await fence.execute(request: ["command": "connect"])

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.connected, true)
        XCTAssertEqual(mockConn.connectCount, 1)

        for (message, _) in mockConn.sent {
            switch message {
            case .requestInterface, .explore:
                XCTFail("connect must not send UI observation message \(message)")
            default:
                break
            }
        }
    }

    // MARK: - Argument Parsing Helpers

    func testStringArg() {
        let dict: [String: Any] = ["key": "hello", "number": 42]
        XCTAssertEqual(dict.string("key"), "hello")
        XCTAssertNil(dict.string("number"))
        XCTAssertNil(dict.string("missing"))
    }

    func testIntegerFromInt() {
        let dict: [String: Any] = ["count": 5]
        XCTAssertEqual(dict.integer("count"), 5)
    }

    func testIntegerRejectsFractionalDouble() {
        let dict: [String: Any] = ["count": 5.7]
        XCTAssertNil(dict.integer("count"))
    }

    func testIntegerFromWholeDouble() {
        let dict: [String: Any] = ["count": 5.0]
        XCTAssertEqual(dict.integer("count"), 5)
    }

    func testIntegerRejectsOutOfRangeDouble() {
        let dict: [String: Any] = ["count": Double(Int.max)]
        XCTAssertNil(dict.integer("count"))
    }

    func testIntegerRejectsString() {
        let dict: [String: Any] = ["count": "42"]
        XCTAssertNil(dict.integer("count"))
    }

    func testIntegerRejectsBool() {
        let dict: [String: Any] = ["count": true]
        XCTAssertNil(dict.integer("count"))
    }

    func testIntegerMissing() {
        let dict: [String: Any] = [:]
        XCTAssertNil(dict.integer("count"))
    }

    func testNumberFromDouble() {
        let dict: [String: Any] = ["x": 3.14]
        XCTAssertEqual(dict.number("x"), 3.14)
    }

    func testNumberFromInt() {
        let dict: [String: Any] = ["x": 7]
        XCTAssertEqual(dict.number("x"), 7.0)
    }

    func testNumberRejectsString() {
        let dict: [String: Any] = ["x": "2.5"]
        XCTAssertNil(dict.number("x"))
    }

    func testNumberRejectsBool() {
        let dict: [String: Any] = ["x": true]
        XCTAssertNil(dict.number("x"))
    }

    func testNumberMissing() {
        let dict: [String: Any] = [:]
        XCTAssertNil(dict.number("x"))
    }

    func testNumberVariousTypes() {
        let dict: [String: Any] = ["d": 1.5, "i": 3, "s": "4.2", "bad": "notANumber"]
        XCTAssertEqual(dict.number("d"), 1.5)
        XCTAssertEqual(dict.number("i"), 3.0)
        XCTAssertNil(dict.number("s"))
        XCTAssertNil(dict.number("missing"))
        XCTAssertNil(dict.number("bad"))
    }

    @ButtonHeistActor
    func testElementTargetWithIdentifier() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["identifier": "myButton"]
        guard let target = try fence.elementTarget(dict),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.identifier, "myButton")
    }

    @ButtonHeistActor
    func testElementTargetWithHeistId() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["heistId": "button_save"]
        guard let target = try fence.elementTarget(dict),
              case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "button_save")
    }

    @ButtonHeistActor
    func testElementTargetWithMatcherFields() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["label": "Save", "traits": ["button"]]
        guard let target = try fence.elementTarget(dict),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
    }

    @ButtonHeistActor
    func testElementTargetWithHeistIdAndMatcher() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["heistId": "button_save", "label": "Save"]
        // heistId wins when both are present
        guard let target = try fence.elementTarget(dict),
              case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "button_save")
    }

    @ButtonHeistActor
    func testElementTargetWithOrdinal() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["label": "Save", "ordinal": 2]
        guard let target = try fence.elementTarget(dict),
              case .matcher(let matcher, let ordinal) = target else {
            return XCTFail("Expected .matcher with ordinal")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(ordinal, 2)
    }

    @ButtonHeistActor
    func testCommandTargetRejectsNegativeOrdinal() async {
        await assertValidationError(
            ["command": "activate", "label": "Save", "ordinal": -1],
            equals: "schema validation failed for ordinal: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testElementTargetWithoutOrdinal() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["label": "Save"]
        guard let target = try fence.elementTarget(dict),
              case .matcher(_, let ordinal) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testElementTargetMissing() async throws {
        let (fence, _) = makeConnectedFence()
        XCTAssertNil(try fence.elementTarget([:]))
    }

    // MARK: - Schema Validation Diagnostics

    @ButtonHeistActor
    func testSchemaValidationReportsBadFieldType() async {
        await assertValidationError(
            ["command": "type_text", "text": 3],
            equals: "schema validation failed for text: observed integer 3; expected string"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationReportsBadCoercedValue() async {
        await assertValidationError(
            ["command": "wait_for_change", "timeout": "forever"],
            equals: "schema validation failed for timeout: observed string \"forever\"; expected number"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationReportsRangeFailure() async {
        await assertValidationError(
            ["command": "start_recording", "fps": 16],
            equals: "schema validation failed for fps: observed integer 16; expected integer in 1...15"
        )
    }

    @ButtonHeistActor
    func testSchemaValidatedStrictTypesStillWork() async {
        await assertPassesValidation(
            ["command": "start_recording", "fps": 5]
        )
        await assertPassesValidation(
            ["command": "start_recording", "scale": 0.5]
        )
    }

    @ButtonHeistActor
    func testSchemaValidationRejectsStringIntegerCoercion() async {
        await assertValidationError(
            ["command": "start_recording", "fps": "5"],
            equals: "schema validation failed for fps: observed string \"5\"; expected integer"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationRejectsStringNumberCoercion() async {
        await assertValidationError(
            ["command": "start_recording", "scale": "0.5"],
            equals: "schema validation failed for scale: observed string \"0.5\"; expected number"
        )
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
    func testOneFingerTapRejectsNaNCoordinate() async {
        await assertValidationError(
            ["command": "one_finger_tap", "x": Double.nan, "y": 200.0],
            equals: "schema validation failed for x: observed number nan; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsInfiniteCoordinate() async {
        await assertValidationError(
            ["command": "one_finger_tap", "x": Double.infinity, "y": 200.0],
            equals: "schema validation failed for x: observed number inf; expected number"
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
    func testLongPressRejectsNegativeDuration() async {
        await assertValidationError(
            ["command": "long_press", "x": 50.0, "y": 50.0, "duration": -1.0],
            equals: "schema validation failed for duration: observed number -1.0; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsOversizedDurationBeforeExecution() async {
        await assertValidationError(
            ["command": "long_press", "x": 50.0, "y": 50.0, "duration": 61.0],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
        )
    }

    @ButtonHeistActor
    func testSwipeInvalidDirection() async {
        await assertValidationError(
            ["command": "swipe", "direction": "diagonal"],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
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
    func testSwipeUnitPointsRejectOutOfRangeCoordinate() async {
        await assertValidationError(
            ["command": "swipe", "heistId": "row_5",
             "start": ["x": 1.2, "y": 0.5],
             "end": ["x": 0.2, "y": 0.5]],
            equals: "schema validation failed for start.x: observed number 1.2; expected number in 0...1"
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
            equals: "schema validation failed for endX: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testDragWithEndCoordinatesPassesValidation() async {
        await assertPassesValidation(
            ["command": "drag", "endX": 100.0, "endY": 200.0]
        )
    }

    @ButtonHeistActor
    func testDragWithStartCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "drag", "startX": 100.0, "startY": 300.0, "endX": 300.0, "endY": 600.0
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
    func testDragRejectsLegacyXYStartAliases() async {
        await assertValidationError(
            ["command": "drag", "x": 100.0, "y": 300.0, "endX": 300.0, "endY": 600.0],
            equals: "schema validation failed for x: observed number 100.0; expected valid drag parameter"
        )
    }

    @ButtonHeistActor
    func testPinchMissingScale() async {
        await assertValidationError(
            ["command": "pinch"],
            equals: "schema validation failed for scale: observed missing; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testPinchWithScalePassesValidation() async {
        await assertPassesValidation(
            ["command": "pinch", "scale": 2.0]
        )
    }

    @ButtonHeistActor
    func testPinchRequestDecodesTypedPayloadBeforeDispatch() async throws {
        let (fence, _) = makeConnectedFence()
        let parsed = try fence.parseRequest([
            "command": "pinch",
            "heistId": "photo_view",
            "scale": 2.0,
            "centerX": 200.0,
            "centerY": 500.0,
            "spread": 24.0,
            "duration": 0.25,
        ])

        guard case .gesture(.pinch(let payload)) = parsed.payload else {
            return XCTFail("Expected typed pinch payload, got \(parsed.payload)")
        }
        XCTAssertEqual(payload.elementTarget, .heistId("photo_view"))
        XCTAssertEqual(payload.scale, 2.0)
        XCTAssertEqual(payload.centerX, 200.0)
        XCTAssertEqual(payload.centerY, 500.0)
        XCTAssertEqual(payload.spread, 24.0)
        XCTAssertEqual(payload.duration, 0.25)
    }

    @ButtonHeistActor
    func testPinchWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "pinch", "scale": 2.0, "centerX": 200.0, "centerY": 500.0
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
    func testGestureDispatchRejectsCommandPayloadMismatch() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let parsed = TheFence.ParsedRequest(
            command: .pinch,
            requestId: "gesture-mismatch",
            payload: .gesture(.rotate(.init(
                elementTarget: nil,
                centerX: 150.0,
                centerY: 400.0,
                angle: 1.57,
                radius: nil,
                duration: nil
            ))),
            expectationPayload: .init(expectation: nil, timeout: nil),
            immediateResponse: nil
        )

        let response = try await fence.execute(parsed: parsed)

        guard case .error(let message, _) = response else {
            return XCTFail("Expected payload mismatch error, got \(response)")
        }
        XCTAssertEqual(message, "Internal payload mismatch for command: pinch")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testPinchRejectsLegacyXYCenterAliases() async {
        await assertValidationError(
            ["command": "pinch", "scale": 2.0, "x": 200.0, "y": 500.0],
            equals: "schema validation failed for x: observed number 200.0; expected valid pinch parameter"
        )
    }

    @ButtonHeistActor
    func testRotateWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "rotate", "angle": 1.57, "centerX": 150.0, "centerY": 400.0
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
    func testRotateRejectsLegacyXYCenterAliases() async {
        await assertValidationError(
            ["command": "rotate", "angle": 1.57, "x": 150.0, "y": 400.0],
            equals: "schema validation failed for x: observed number 150.0; expected valid rotate parameter"
        )
    }

    @ButtonHeistActor
    func testRotateMissingAngle() async {
        await assertValidationError(
            ["command": "rotate"],
            equals: "schema validation failed for angle: observed missing; expected number"
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
    func testTwoFingerTapWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "two_finger_tap", "centerX": 200.0, "centerY": 500.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .touchTwoFingerTap(let target) = message else {
            XCTFail("Expected touchTwoFingerTap message")
            return
        }
        XCTAssertEqual(target.centerX, 200.0)
        XCTAssertEqual(target.centerY, 500.0)
    }

    @ButtonHeistActor
    func testTwoFingerTapRejectsLegacyXYCenterAliases() async {
        await assertValidationError(
            ["command": "two_finger_tap", "x": 200.0, "y": 500.0],
            equals: "schema validation failed for x: observed number 200.0; expected valid two_finger_tap parameter"
        )
    }

    // MARK: - Draw Path Validation

    @ButtonHeistActor
    func testDrawPathMissingPoints() async {
        await assertValidationError(
            ["command": "draw_path"],
            equals: "schema validation failed for points: observed missing; expected array of objects"
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
            ["command": "draw_path", "points": [["x": "bad", "y": "data"], ["x": 0.0, "y": 0.0]]],
            equals: "schema validation failed for points[0].x: observed string \"bad\"; expected number"
        )
    }

    @ButtonHeistActor
    func testDrawPathRejectsTooManyPointsBeforeExecution() async {
        let points = (0...TheFence.DecodeLimits.maxDrawPathPoints).map { index in
            ["x": Double(index), "y": Double(index)]
        }
        await assertValidationError(
            ["command": "draw_path", "points": points],
            equals: "schema validation failed for points: observed array count 10001; expected array count 2...10000 (at least 2 points)"
        )
    }

    @ButtonHeistActor
    func testDrawPathRejectsOversizedDurationBeforeExecution() async {
        await assertValidationError(
            [
                "command": "draw_path",
                "points": [["x": 0.0, "y": 0.0], ["x": 1.0, "y": 1.0]],
                "duration": 61.0,
            ],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
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
            equals: "schema validation failed for startX: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testDrawBezierMissingSegments() async {
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0],
            equals: "schema validation failed for segments: observed missing; expected array of objects"
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
            equals: "schema validation failed for segments[0].cp2X: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsTooManySegmentsBeforeExecution() async {
        let segment = [
            "cp1X": 10.0, "cp1Y": 20.0, "cp2X": 30.0,
            "cp2Y": 40.0, "endX": 50.0, "endY": 60.0,
        ]
        let segments = Array(repeating: segment, count: TheFence.DecodeLimits.maxDrawBezierSegments + 1)
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0, "segments": segments],
            equals: "schema validation failed for segments: observed array count 1001; expected array count 1...1000 (At least 1 bezier segment is required)"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsOversizedSamplesBeforeExecution() async {
        await assertValidationError(
            [
                "command": "draw_bezier",
                "startX": 0.0,
                "startY": 0.0,
                "segments": [["cp1X": 10.0, "cp1Y": 20.0, "cp2X": 30.0, "cp2Y": 40.0, "endX": 50.0, "endY": 60.0]],
                "samplesPerSegment": 1_001,
            ],
            equals: "schema validation failed for samplesPerSegment: observed integer 1001; expected integer in 2...1000"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsOversizedGeneratedPathBeforeExecution() async {
        let segment = [
            "cp1X": 10.0, "cp1Y": 20.0, "cp2X": 30.0,
            "cp2Y": 40.0, "endX": 50.0, "endY": 60.0,
        ]
        let segments = Array(repeating: segment, count: 1_000)
        await assertValidationError(
            [
                "command": "draw_bezier",
                "startX": 0.0,
                "startY": 0.0,
                "segments": segments,
                "samplesPerSegment": 52,
            ],
            equals: "schema validation failed for segments: observed generated path point count 51001; expected generated path point count <= 50000"
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
    func testScrollDefaultsDirection() async {
        await assertPassesValidation(
            ["command": "scroll", "identifier": "scrollView"]
        )
    }

    @ButtonHeistActor
    func testScrollInvalidDirection() async {
        await assertValidationError(
            ["command": "scroll", "identifier": "scrollView", "direction": "diagonal"],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right, next, previous"
        )
    }

    @ButtonHeistActor
    func testScrollAllowsMissingElement() async {
        await assertPassesValidation(
            ["command": "scroll", "direction": "down"]
        )
    }

    @ButtonHeistActor
    func testScrollValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll", "direction": "down", "identifier": "scrollView"]
        )
    }

    @ButtonHeistActor
    func testScrollDefaultsDirectionAndAllowsMissingTarget() async {
        await assertPassesValidation(
            ["command": "scroll"]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleMissingElement() async {
        await assertContractError(
            ["command": "scroll_to_visible"],
            contains: [
                "scroll_to_visible request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_visible", "identifier": "targetElement"]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleHeistIdPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_visible", "heistId": "targetElement"]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeDefaultsEdge() async {
        await assertPassesValidation(
            ["command": "scroll_to_edge", "identifier": "scrollView"]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeInvalidEdge() async {
        await assertValidationError(
            ["command": "scroll_to_edge", "identifier": "scrollView", "edge": "middle"],
            equals: "schema validation failed for edge: observed string \"middle\"; expected enum one of top, bottom, left, right"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeAllowsMissingTarget() async {
        await assertPassesValidation(
            ["command": "scroll_to_edge", "edge": "bottom"]
        )
    }

    @ButtonHeistActor
    func testElementSearchMissingElement() async {
        await assertContractError(
            ["command": "element_search"],
            contains: [
                "element_search request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
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
        await assertContractError(
            ["command": "activate"],
            contains: [
                "activate request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
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
        await assertContractError(
            ["command": "increment"],
            contains: [
                "increment request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testDecrementMissingElement() async {
        await assertContractError(
            ["command": "decrement"],
            contains: [
                "decrement request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionMissingElement() async {
        await assertContractError(
            ["command": "perform_custom_action", "action": "doSomething"],
            contains: [
                "perform_custom_action request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testPerformCustomActionMissingAction() async {
        await assertValidationError(
            ["command": "perform_custom_action", "identifier": "myElement"],
            equals: "schema validation failed for action: observed missing; expected string"
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
            equals: "schema validation failed for actionName: observed string \"doSomething\"; expected valid perform_custom_action parameter"
        )
    }

    @ButtonHeistActor
    func testRotorMissingElement() async {
        await assertContractError(
            ["command": "rotor", "rotor": "Errors"],
            contains: [
                "rotor request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testRotorNegativeIndex() async {
        await assertValidationError(
            ["command": "rotor", "identifier": "myElement", "rotorIndex": -1],
            equals: "schema validation failed for rotorIndex: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidDirection() async {
        await assertValidationError(
            ["command": "rotor", "identifier": "myElement", "direction": "sideways"],
            equals: "schema validation failed for direction: observed string \"sideways\"; expected enum one of next, previous"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresBothOffsets() async {
        await assertValidationError(
            ["command": "rotor", "identifier": "myElement", "currentTextStartOffset": 4],
            contains: "currentTextStartOffset and currentTextEndOffset"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresCurrentHeistId() async {
        await assertValidationError(
            [
                "command": "rotor",
                "identifier": "myElement",
                "currentTextStartOffset": 4,
                "currentTextEndOffset": 8,
            ],
            equals: "schema validation failed for currentHeistId: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsInvalidTextRangeOffsets() async {
        let expectedError = "schema validation failed for currentTextStartOffset/currentTextEndOffset: " +
            "observed 8..<4; expected integer range with start >= 0 and end >= start"
        await assertValidationError(
            [
                "command": "rotor",
                "identifier": "myElement",
                "currentHeistId": "notes",
                "currentTextStartOffset": 8,
                "currentTextEndOffset": 4,
            ],
            equals: expectedError
        )
    }

    @ButtonHeistActor
    func testRotorValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "rotor", "identifier": "myElement", "rotor": "Errors"]
        )
    }

    @ButtonHeistActor
    func testRotorPreviousValidTextRangeCursorPassesValidation() async {
        await assertPassesValidation(
            [
                "command": "rotor",
                "identifier": "myElement",
                "rotor": "Mentions",
                "direction": "previous",
                "currentHeistId": "notes",
                "currentTextStartOffset": 4,
                "currentTextEndOffset": 10,
            ]
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

    @ButtonHeistActor
    func testActivateWithIncrementCountOmittedDispatchesOnce() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "action": "increment",
        ])

        guard case .action = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 1)
        XCTAssertTrue(mockConn.sent.adjustmentMessages.allSatisfy { $0.isIncrement })
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountOneDispatchesOnce() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "action": "increment",
            "count": 1,
        ])

        guard case .action = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 1)
        XCTAssertTrue(mockConn.sent.adjustmentMessages.allSatisfy { $0.isIncrement })
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountDispatchesMultipleExistingCommands() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "action": "increment",
            "count": 3,
        ])

        guard case .action = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 3)
        XCTAssertTrue(mockConn.sent.adjustmentMessages.allSatisfy { $0.isIncrement })
    }

    @ButtonHeistActor
    func testRawDecrementWithCountDispatchesMultipleExistingCommands() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "decrement",
            "identifier": "myElement",
            "count": 2,
        ])

        guard case .action = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 2)
        XCTAssertTrue(mockConn.sent.adjustmentMessages.allSatisfy { $0.isDecrement })
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsCountZero() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "increment", "count": 0],
            contains: "schema validation failed for count: observed integer 0; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsNegativeCount() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "increment", "count": -1],
            contains: "schema validation failed for count: observed integer -1; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsCountAboveMaximum() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "increment", "count": 101],
            contains: "schema validation failed for count: observed integer 101; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithoutAdjustmentAction() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithCustomAction() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "Delete", "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsOutOfRangeCountWithCustomActionAsNonAdjustment() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "Delete", "count": 200],
            contains: "schema validation failed for count: observed integer 200; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithActionPrefixedCustomAction() async {
        await assertValidationError(
            ["command": "activate", "identifier": "myElement", "action": "action:increment", "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountFailsOnIntermediateFailure() async throws {
        let (fence, mockConn) = makeConnectedFence()
        var callCount = 0
        mockConn.autoResponse = { message in
            if case .increment = message {
                callCount += 1
                if callCount == 2 {
                    return .actionResult(ActionResult(
                        success: false,
                        method: .increment,
                        message: "adjustment failed"
                    ))
                }
            }
            return .actionResult(ActionResult(success: true, method: .increment))
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "action": "increment",
            "count": 3,
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 2)
        XCTAssertTrue(message.contains("increment repetition 2 of 3 failed"))
        XCTAssertTrue(message.contains("adjustment failed"))
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountReturnsFinalFailureResult() async throws {
        let (fence, mockConn) = makeConnectedFence()
        var callCount = 0
        mockConn.autoResponse = { message in
            if case .increment = message {
                callCount += 1
                if callCount == 3 {
                    return .actionResult(ActionResult(
                        success: false,
                        method: .increment,
                        message: "final adjustment failed"
                    ))
                }
            }
            return .actionResult(ActionResult(success: true, method: .increment))
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "action": "increment",
            "count": 3,
        ])

        guard case .action(let result, _) = response else {
            return XCTFail("Expected final action response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 3)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "final adjustment failed")
    }

    // MARK: - Text Input Validation

    @ButtonHeistActor
    func testTypeTextMissingBothFields() async {
        await assertValidationError(
            ["command": "type_text"],
            equals: "schema validation failed for text: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testTypeTextRejectsEmptyText() async {
        await assertValidationError(
            ["command": "type_text", "text": ""],
            equals: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testTypeTextWithTextPassesValidation() async {
        await assertPassesValidation(
            ["command": "type_text", "text": "hello"]
        )
    }

    @ButtonHeistActor
    func testTypeTextRequestDecodesTypedPayloadBeforeDispatch() async throws {
        let (fence, _) = makeConnectedFence()
        let parsed = try fence.parseRequest([
            "command": "type_text",
            "text": "hello",
            "heistId": "search_field",
        ])

        guard case .typeText(let target) = parsed.payload else {
            return XCTFail("Expected typed type_text payload, got \(parsed.payload)")
        }
        XCTAssertEqual(target.text, "hello")
        XCTAssertEqual(target.elementTarget, .heistId("search_field"))
    }

    @ButtonHeistActor
    func testTypeTextTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "type_text",
            "text": "hello",
            "heistId": "search_field",
        ])

        guard case .action = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        guard let (message, _) = mockConn.sent.last,
              case .typeText(let target) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.last))")
        }
        XCTAssertEqual(target.text, "hello")
        XCTAssertEqual(target.elementTarget, .heistId("search_field"))
    }

    @ButtonHeistActor
    func testTypeTextRejectsNonStringTextBeforeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "type_text",
            "text": 3,
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        XCTAssertEqual(message, "schema validation failed for text: observed integer 3; expected string")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testEditActionMissingAction() async {
        await assertValidationError(
            ["command": "edit_action"],
            equals: "schema validation failed for action: observed missing; expected enum one of copy, paste, cut, select, selectAll, delete"
        )
    }

    @ButtonHeistActor
    func testEditActionValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "edit_action", "action": "copy"]
        )
    }

    @ButtonHeistActor
    func testEditActionDeletePassesValidation() async {
        await assertPassesValidation(
            ["command": "edit_action", "action": "delete"]
        )
    }

    // MARK: - Pasteboard Validation

    @ButtonHeistActor
    func testSetPasteboardMissingText() async {
        await assertValidationError(
            ["command": "set_pasteboard"],
            equals: "schema validation failed for text: observed missing; expected string"
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

    @ButtonHeistActor
    func testGetPasteboardRejectsExpectationBecauseItIsARead() async {
        await assertValidationError(
            [
                "command": "get_pasteboard",
                "expect": ["type": "screen_changed"],
            ],
            contains: "valid get_pasteboard parameter"
        )
    }

    // MARK: - Ping

    @ButtonHeistActor
    func testPingSendsRequestScopedClientPingAndReturnsPayload() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(request: ["command": "ping"])

        guard case .pong(let payload) = response else {
            return XCTFail("Expected pong response, got \(response)")
        }
        XCTAssertEqual(payload.appName, "MockApp")
        XCTAssertEqual(payload.bundleIdentifier, "com.test.mock")
        XCTAssertEqual(payload.serverTimestampMs, 1_700_000_000_000)

        guard let sent = mockConn.sent.last else {
            return XCTFail("Expected ping to be sent")
        }
        guard case .ping = sent.0 else {
            return XCTFail("Expected ClientMessage.ping, got \(sent.0)")
        }
        XCTAssertNotNil(sent.1)
    }

    @ButtonHeistActor
    func testPingDoesNotAutoConnectWhenDisconnected() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConn = MockConnection()
        let fence = TheFence(configuration: .init(autoReconnect: false, directDevice: device))
        fence.handoff.makeConnection = { _, _, _ in mockConn }

        do {
            _ = try await fence.execute(request: ["command": "ping"])
            XCTFail("Expected notConnected")
        } catch FenceError.notConnected {
            XCTAssertEqual(mockConn.connectCount, 0)
        } catch {
            XCTFail("Expected notConnected, got \(error)")
        }
    }

    @ButtonHeistActor
    func testPingTimeoutUsesPongTracker() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        mockConn.autoResponse = nil

        do {
            _ = try await fence.sendAndAwaitPong(timeout: 0.01)
            XCTFail("Expected actionTimeout")
        } catch FenceError.actionTimeout {
            guard let sent = mockConn.sent.last else {
                return XCTFail("Expected ping to be sent")
            }
            guard case .ping = sent.0 else {
                return XCTFail("Expected ClientMessage.ping, got \(sent.0)")
            }
            XCTAssertNotNil(sent.1)
        } catch {
            XCTFail("Expected actionTimeout, got \(error)")
        }
    }

    // MARK: - Wait For Validation

    @ButtonHeistActor
    func testWaitForMissingMatchFields() async {
        await assertContractError(
            ["command": "wait_for"],
            contains: [
                "wait_for request contract failed: missing target",
                "requires heistId, ordinal, or at least one matcher field",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testWaitForWithLabelPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "label": "Loading"]
        )
    }

    @ButtonHeistActor
    func testWaitForWithIdentifierPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "identifier": "spinner"]
        )
    }

    @ButtonHeistActor
    func testWaitForWithTraitsPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "traits": ["button"]]
        )
    }

    @ButtonHeistActor
    func testWaitForWithAbsentPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "label": "Loading", "absent": true, "timeout": 5.0]
        )
    }

    // MARK: - Wait For Change Validation

    @ButtonHeistActor
    func testWaitForChangePassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for_change"]
        )
    }

    @ButtonHeistActor
    func testWaitForChangeWithExpectPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for_change", "expect": ["type": "screen_changed"]]
        )
    }

    @ButtonHeistActor
    func testWaitForChangeWithTimeoutPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for_change", "expect": ["type": "elements_changed"], "timeout": 5.0]
        )
    }

    @ButtonHeistActor
    func testWaitForChangeTimeoutWithoutExpectSendsTypedPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "wait_for_change",
            "timeout": 3.0,
        ])
        guard let (message, _) = mockConn.sent.last,
              case .waitForChange(let target) = message else {
            return XCTFail("Expected waitForChange message")
        }
        XCTAssertNil(target.expect)
        XCTAssertEqual(target.timeout, 3.0)
    }

    @ButtonHeistActor
    func testWaitForChangeSendsCorrectMessage() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "wait_for_change", "expect": ["type": "screen_changed"], "timeout": 8.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .waitForChange(let target) = message else {
            return XCTFail("Expected waitForChange message")
        }
        XCTAssertEqual(target.expect, .screenChanged)
        XCTAssertEqual(target.timeout, 8.0)
    }

    @ButtonHeistActor
    func testWaitForChangeTrustsServerSideExpectationEvaluation() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            guard case .waitForChange = message else {
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return .actionResult(ActionResult(
                success: true,
                method: .waitForChange,
                message: "expectation already met by current state (0.0s)",
                accessibilityDelta: .noChange(.init(elementCount: 1))
            ))
        }

        let response = try await fence.execute(request: [
            "command": "wait_for_change",
            "expect": ["type": "element_disappeared", "matcher": ["label": "Loading"]],
        ])

        guard case .action(_, let expectation) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(expectation?.met, true)
        XCTAssertEqual(expectation?.actual, "expectation already met by current state (0.0s)")
    }

    @ButtonHeistActor
    func testWaitForChangeTimeoutDoesNotClaimExpectationMet() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            guard case .waitForChange = message else {
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return .actionResult(ActionResult(
                success: false,
                method: .waitForChange,
                message: "timed out after 0.2s — expectation not met",
                errorKind: .timeout,
                accessibilityDelta: .noChange(.init(elementCount: 1))
            ))
        }

        let response = try await fence.execute(request: [
            "command": "wait_for_change",
            "expect": ["type": "element_disappeared", "matcher": ["label": "Loading"]],
            "timeout": 0.2,
        ])

        guard case .action(_, let expectation) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(expectation?.met, false)
        XCTAssertEqual(expectation?.actual, "timed out after 0.2s — expectation not met")
    }

    @ButtonHeistActor
    func testWaitForChangeNoArgsSendsNilExpect() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "wait_for_change"
        ])
        guard let (message, _) = mockConn.sent.last,
              case .waitForChange(let target) = message else {
            return XCTFail("Expected waitForChange message")
        }
        XCTAssertNil(target.expect)
        XCTAssertNil(target.timeout)
    }

    @ButtonHeistActor
    func testInvalidExpectationRejectedAtRequestEdge() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "identifier": "myElement",
            "expect": "screen_changed",
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected .error response, got \(response)")
        }
        XCTAssertEqual(message, "Invalid expectation type: expected object with a \"type\" discriminator")
        XCTAssertEqual(details?.errorCode, "request.invalid")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    // MARK: - Expectation Parsing

    @ButtonHeistActor
    func testParseExpectationNilWhenAbsent() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation(["command": "activate"])
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedObject() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation(["expect": ["type": "screen_changed"]])
        XCTAssertEqual(result, .screenChanged)
    }

    func testNormalizeToolCallParsesExpectationPayloadAtCatalogEdge() throws {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "activate",
            arguments: [
                "identifier": "submit",
                "expect": ["type": "screen_changed"],
                "timeout": 0.25,
            ] as [String: Any]
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }

        XCTAssertEqual(operation.command, .activate)
        XCTAssertEqual(operation.arguments["identifier"] as? String, "submit")
        XCTAssertNil(operation.arguments["expect"])
        XCTAssertEqual(operation.arguments["timeout"] as? Double, 0.25)
        XCTAssertEqual(operation.expectationPayload?.expectation, .screenChanged)
        XCTAssertEqual(operation.expectationPayload?.timeout, 0.25)
    }

    @ButtonHeistActor
    func testNormalizedToolOperationUsesTypedExpectationPayload() async throws {
        let (fence, _) = makeConnectedFence()
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "wait_for_change",
            arguments: ["expect": ["type": "elements_changed"]] as [String: Any]
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }

        XCTAssertNil(operation.arguments["expect"])
        let parsed = try fence.parseRequest(operation: operation)
        XCTAssertEqual(parsed.expectationPayload.expectation, .elementsChanged)
        guard case .waitForChange(let payload) = parsed.payload else {
            return XCTFail("Expected wait_for_change payload, got \(parsed.payload)")
        }
        XCTAssertEqual(payload.expectation, .elementsChanged)
    }

    func testNormalizeToolCallReportsExpectationParseFailure() {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "activate",
            arguments: ["expect": "screen_changed"]
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected routing failure, got \(result)")
        }
        XCTAssertEqual(error.message, "Invalid expectation type: expected object with a \"type\" discriminator")
    }

    func testNormalizeToolCallLeavesUnsupportedExpectationForRequestValidation() throws {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "get_screen",
            arguments: ["expect": "screen_changed"]
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }
        XCTAssertEqual(operation.arguments["expect"] as? String, "screen_changed")
        XCTAssertNil(operation.expectationPayload)
    }

    @ButtonHeistActor
    func testParseExpectationStringValuesThrowObjectRequired() async {
        let (fence, _) = makeConnectedFence()
        for value in ["screen_changed", "elements_changed", "element_updated", "layout_changed", "bogus"] {
            XCTAssertThrowsError(try fence.parseExpectation(["expect": value])) { error in
                guard case FenceError.invalidRequest(let msg) = error else {
                    XCTFail("Expected FenceError.invalidRequest, got \(error)")
                    return
                }
                XCTAssertEqual(msg, "Invalid expectation type: expected object with a \"type\" discriminator")
            }
        }
    }

    @ButtonHeistActor
    func testParseExpectationObjectWithoutTypeThrows() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": ["wrong": "key"]])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("\"type\" discriminator"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidTypeThrows() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation(["expect": 42])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid expectation type"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationTopLevelArrayThrows() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": [
                ["type": "screen_changed"],
                ["type": "elements_changed"],
            ],
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("expected object"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationFromTypedPlaybackRequestArguments() async throws {
        let (fence, _) = makeConnectedFence()
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(
                command: "activate",
                arguments: [
                    "expect": .object([
                        "type": .string("element_updated"),
                        "heistId": .string("counter"),
                        "property": .string("value"),
                        "newValue": .string("5"),
                    ]),
                ]
            ),
            index: 0
        )

        let result = try fence.parseExpectation(operation.requestArguments())

        XCTAssertEqual(
            result,
            .elementUpdated(heistId: "counter", property: .value, newValue: "5")
        )
    }

    @ButtonHeistActor
    func testParseExpectationRejectsLegacyHeistPlaybackExpectationString() async throws {
        let (fence, _) = makeConnectedFence()
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(
                command: "activate",
                arguments: ["expect": .string("screen_changed")]
            ),
            index: 0
        )

        XCTAssertThrowsError(try fence.parseExpectation(operation.requestArguments())) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertEqual(msg, "Invalid expectation type: expected object with a \"type\" discriminator")
        }
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorScreenChanged() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": ["type": "screen_changed"]
        ])
        XCTAssertEqual(result, .screenChanged)
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": [
                "type": "element_updated",
                "heistId": "slider", "property": "value",
                "oldValue": "0", "newValue": "50",
            ] as [String: Any]
        ])
        XCTAssertEqual(
            result,
            .elementUpdated(heistId: "slider", property: .value, oldValue: "0", newValue: "50")
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedInvalidPropertyListsValidValues() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": [
                "type": "element_updated",
                "property": "bogus",
            ] as [String: Any]
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown element property"))
            XCTAssertTrue(msg.contains("Valid:"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedBare() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": ["type": "element_updated"]
        ])
        XCTAssertEqual(result, .elementUpdated())
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithMatcher() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": [
                "type": "element_appeared",
                "matcher": ["label": "Cart", "identifier": "cart.button"],
            ] as [String: Any]
        ])
        XCTAssertEqual(
            result,
            .elementAppeared(ElementMatcher(label: "Cart", identifier: "cart.button"))
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithoutMatcherThrows() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": ["type": "element_appeared"]
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("matcher"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorCompound() async throws {
        let (fence, _) = makeConnectedFence()
        let result = try fence.parseExpectation([
            "expect": [
                "type": "compound",
                "expectations": [
                    ["type": "screen_changed"],
                    ["type": "element_updated", "heistId": "counter"] as [String: Any],
                ] as [Any],
            ] as [String: Any]
        ])
        XCTAssertEqual(
            result,
            .compound([
                .screenChanged,
                .elementUpdated(heistId: "counter"),
            ])
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorCompoundRejectsStringSubExpectation() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": [
                "type": "compound",
                "expectations": [
                    "screen_changed",
                    ["type": "elements_changed"] as [String: Any],
                ] as [Any],
            ] as [String: Any],
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("must be objects"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorUnknownTypeThrows() async {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.parseExpectation([
            "expect": ["type": "bogus_type"]
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation type"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorCoversAllWireTypes() async throws {
        let (fence, _) = makeConnectedFence()
        let cases: [(type: String, payload: [String: Any], expected: ActionExpectation)] = [
            ("delivery", ["type": "delivery"], .delivery),
            ("screen_changed", ["type": "screen_changed"], .screenChanged),
            ("elements_changed", ["type": "elements_changed"], .elementsChanged),
            ("element_updated", ["type": "element_updated"], .elementUpdated()),
            (
                "element_appeared",
                ["type": "element_appeared", "matcher": ["label": "Cart"]],
                .elementAppeared(ElementMatcher(label: "Cart"))
            ),
            (
                "element_disappeared",
                ["type": "element_disappeared", "matcher": ["label": "Spinner"]],
                .elementDisappeared(ElementMatcher(label: "Spinner"))
            ),
            (
                "compound",
                ["type": "compound", "expectations": [["type": "screen_changed"]]],
                .compound([.screenChanged])
            ),
        ]

        XCTAssertEqual(Set(cases.map(\.type)), Set(ActionExpectation.wireTypeValues))
        for testCase in cases {
            let result = try fence.parseExpectation(["expect": testCase.payload])
            XCTAssertEqual(result, testCase.expected, "Failed to parse \(testCase.type)")
        }
    }

    // MARK: - Batch Expectation Counting

    @ButtonHeistActor
    func testBatchStepLowersPublicCommandAdapterIntoActionExpectationPlan() async throws {
        let (fence, _) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                [
                    "command": "activate",
                    "identifier": "save-button",
                    "expect": ["type": "elements_changed"],
                ],
            ]
        )

        guard case .planned(let step) = batch.steps.first else {
            return XCTFail("Expected planned batch step")
        }
        XCTAssertEqual(step.originalIndex, 0)
        XCTAssertEqual(step.commandName, "activate")
        XCTAssertEqual(step.expectation, .elementsChanged)

        guard case .activate(let actionTarget) = step.action else {
            return XCTFail("Expected activate action, got \(step.action)")
        }
        XCTAssertNil(actionTarget.sourceHeistId)
        XCTAssertEqual(actionTarget.matcher.identifier, "save-button")
        XCTAssertNil(actionTarget.ordinal)
    }

    @ButtonHeistActor
    func testBatchPreparationClassifiesActionAndWaitCandidates() async throws {
        let (fence, _) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                ["command": "activate", "label": "Save"],
                ["command": "wait_for", "identifier": "toast"],
                ["command": "wait_for_change", "expect": ["type": "screen_changed"]],
                ["command": "get_screen"],
                ["command": "get_pasteboard"],
            ] as [[String: Any]]
        )

        let plannedSteps = plannedBatchSteps(from: batch)
        XCTAssertEqual(plannedSteps.map(\.commandName), ["activate", "wait_for", "wait_for_change"])
        XCTAssertEqual(plannedSteps.map(\.originalIndex), [0, 1, 2])
        XCTAssertEqual(unsupportedBatchCommandNames(from: batch), ["get_screen", "get_pasteboard"])
    }

    @ButtonHeistActor
    func testBatchPreparationRecognizesHeistIdTargetsWithoutLookup() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                ["command": "activate", "heistId": "leaf-123", "label": "Save"],
                ["command": "wait_for", "heistId": "leaf-456", "label": "Done"],
            ] as [[String: Any]]
        )

        XCTAssertTrue(mockConn.sent.isEmpty, "Batch normalization must not perform raw heistId lookup")
        let steps = plannedBatchSteps(from: batch)
        XCTAssertEqual(steps.map(\.commandName), ["activate", "wait_for"])

        guard case .activate(let actionTarget) = steps[0].action else {
            return XCTFail("Expected activate action with source heistId plus matcher target")
        }
        XCTAssertEqual(actionTarget.sourceHeistId, "leaf-123")
        XCTAssertNil(actionTarget.matcher.heistId)
        XCTAssertEqual(actionTarget.matcher.label, "Save")
        XCTAssertNil(actionTarget.ordinal)
        guard case .matcher(let executableMatcher, let executableOrdinal) = actionTarget.executableTarget else {
            return XCTFail("Expected matcher executable target")
        }
        XCTAssertNil(executableMatcher.heistId)
        XCTAssertEqual(executableMatcher.label, "Save")
        XCTAssertNil(executableOrdinal)

        XCTAssertEqual(steps[1].expectation, .elementAppeared(ElementMatcher(label: "Done")))
    }

    @ButtonHeistActor
    func testBatchCountsOnlyExplicitExpectations() async throws {
        let (fence, mockConn) = makeConnectedFence()
        // Mock returns a successful action result with an elementsChanged delta (updates only)
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, accessibilityDelta: delta))
        }

        // Step 1 has expect → should count. Step 2 has no expect → should NOT count.
        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "btn1", "expect": ["type": "elements_changed"]],
                ["command": "activate", "identifier": "btn2"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        // Only step 1 had "expect", so checked should be 1
        XCTAssertEqual(batch.expectationsChecked, 1, "Only steps with explicit 'expect' should be counted")
        XCTAssertEqual(batch.expectationsMet, 1)
    }

    @ButtonHeistActor
    func testBatchCountsMetExpectations() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 10, newInterface: interface))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, accessibilityDelta: delta))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "btn1", "expect": ["type": "screen_changed"]],
                ["command": "activate", "identifier": "btn2", "expect": ["type": "elements_changed"]],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        // Both steps have expect and the delta is screenChanged (satisfies both tiers)
        XCTAssertEqual(batch.expectationsChecked, 2)
        XCTAssertEqual(batch.expectationsMet, 2)
    }

    @ButtonHeistActor
    func testBatchPreservesOrderedPerStepResultsWithoutNetDelta() async throws {
        let (fence, mockConn) = makeConnectedFence()
        var responses = [
            ActionResult(
                success: true,
                method: .activate,
                message: "first",
                accessibilityDelta: .elementsChanged(.init(
                    elementCount: 1,
                    edits: ElementEdits(updated: [
                        ElementUpdate(heistId: "counter", changes: [
                            PropertyChange(property: .value, old: "0", new: "1"),
                        ]),
                    ])
                ))
            ),
            ActionResult(
                success: true,
                method: .activate,
                message: "second",
                accessibilityDelta: .noChange(.init(elementCount: 1))
            ),
        ]
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(responses.removeFirst())
            case .requestInterface:
                return .interface(Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "first"],
                ["command": "activate", "identifier": "second"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            return XCTFail("Expected batch response, got \(response)")
        }
        XCTAssertEqual(batch.completedSteps, 2)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.results.compactMap { $0["message"] as? String }, ["first", "second"])
        XCTAssertEqual(batch.summaries.map(\.deltaKind), ["elementsChanged", "noChange"])

        let firstDelta = try XCTUnwrap(batch.results[0]["delta"] as? [String: Any])
        XCTAssertEqual(firstDelta["kind"] as? String, "elementsChanged")
        let secondDelta = try XCTUnwrap(batch.results[1]["delta"] as? [String: Any])
        XCTAssertEqual(secondDelta["kind"] as? String, "noChange")

        let json = response.jsonDict()
        XCTAssertNil(json["netDelta"], "Batch JSON must not advertise a wrapper-synthesized cumulative delta")
    }

    @ButtonHeistActor
    func testBatchNetDeltaDerivesFromCaptureTraceEndpoints() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let counter0 = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "counter", label: "Counter", value: "0"),
        ])
        let counter1 = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "counter", label: "Counter", value: "1"),
        ])
        let counter2 = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "counter", label: "Counter", value: "2"),
        ])
        var responses = [
            ActionResult(
                success: true,
                method: .activate,
                message: "first",
                accessibilityDelta: .screenChanged(.init(
                    elementCount: 0,
                    newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
                )),
                accessibilityTrace: makeReceiptTestTrace(before: counter0, after: counter1)
            ),
            ActionResult(
                success: true,
                method: .activate,
                message: "second",
                accessibilityDelta: .noChange(.init(elementCount: 0)),
                accessibilityTrace: makeReceiptTestTrace(before: counter1, after: counter2)
            ),
        ]
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(responses.removeFirst())
            case .requestInterface:
                return .interface(Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "identifier": "first"],
                ["command": "activate", "identifier": "second"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            return XCTFail("Expected batch response, got \(response)")
        }
        XCTAssertEqual(batch.summaries.map(\.deltaKind), ["elementsChanged", "elementsChanged"])
        XCTAssertEqual(batch.accessibilityTrace?.captures.count, 3)

        let json = response.jsonDict()
        let netDelta = try XCTUnwrap(json["netDelta"] as? [String: Any])
        XCTAssertEqual(netDelta["kind"] as? String, "elementsChanged")
        let edits = try XCTUnwrap(netDelta["edits"] as? [String: Any])
        let updated = try XCTUnwrap(edits["updated"] as? [[String: Any]])
        XCTAssertEqual(updated.first?["heistId"] as? String, "counter")
        let changes = try XCTUnwrap(updated.first?["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.first?["old"] as? String, "0")
        XCTAssertEqual(changes.first?["new"] as? String, "2")
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

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 1, "Batch should stop after the error step")
        XCTAssertEqual(batch.failedIndex, 0, "Failed index should be the error step")
        XCTAssertFalse(
            mockConn.sent.contains { sent in
                if case .batchExecutionPlan = sent.0 { return true }
                return false
            },
            "Pre-dispatch stop_on_error should not send later valid steps to InsideJob"
        )
    }

    @ButtonHeistActor
    func testBatchStopsOnFailedActionResult() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 2,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(
                success: false,
                method: .activate,
                message: "Action skipped because target became stale after a screen change; retry against the current interface.",
                errorKind: .actionFailed,
                accessibilityDelta: delta
            ))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "identifier": "stale-button"],
                ["command": "activate", "identifier": "later-button"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 1, "Batch should stop after the failed action result")
        XCTAssertEqual(batch.failedIndex, 0)
        let batchCommands = mockConn.sent.compactMap { sent -> BatchPlan? in
            if case .batchExecutionPlan(let plan) = sent.0 { return plan }
            return nil
        }
        XCTAssertEqual(
            batchCommands.count,
            1,
            "run_batch should dispatch one typed plan; InsideJob owns stop-on-error after step failure"
        )
        XCTAssertEqual(batch.summaries.count, 2)
        XCTAssertEqual(batch.summaries[0].deltaKind, "screenChanged")
        XCTAssertEqual(batch.summaries[0].error, "Action skipped because target became stale after a screen change; retry against the current interface.")
        XCTAssertEqual(batch.summaries[1].error, "skipped: stop_on_error stopped batch after step 0")
    }

    @ButtonHeistActor
    func testBatchStopOnErrorSummarizesSkippedSteps() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "identifier": "btn1"],
                ["command": "not_a_real_command"],
                ["command": "activate", "identifier": "btn2"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 2, "Only executed steps should appear in results")
        XCTAssertEqual(batch.failedIndex, 1)
        XCTAssertEqual(batch.summaries.map(\.command), ["activate", "not_a_real_command", "activate"])
        XCTAssertNil(batch.summaries[0].error)
        XCTAssertNotNil(batch.summaries[1].error)
        XCTAssertEqual(batch.summaries[2].error, "skipped: stop_on_error stopped batch after step 1")
    }

    @ButtonHeistActor
    func testBatchExpectationFailureSummarizesSkippedSteps() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, accessibilityDelta: delta))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "identifier": "btn1", "expect": ["type": "screen_changed"]],
                ["command": "activate", "identifier": "btn2"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 1, "Batch should stop after the failed expectation")
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.expectationsChecked, 1)
        XCTAssertEqual(batch.expectationsMet, 0)
        XCTAssertEqual(batch.summaries.count, 2)
        XCTAssertEqual(batch.summaries[0].expectationMet, false)
        XCTAssertEqual(batch.summaries[1].command, "activate")
        XCTAssertEqual(batch.summaries[1].error, "skipped: stop_on_error stopped batch after step 0")
    }

    @ButtonHeistActor
    func testBatchRejectsGroupedMCPSelectorShapeBeforeExecution() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "scroll", "mode": "search", "label": "Done"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.summaries.map(\.command), ["scroll"])
        XCTAssertEqual(
            batch.summaries[0].error,
            "run_batch step 0: run_batch step \"scroll\" uses the MCP mode selector; " +
                "use canonical Fence commands scroll, scroll_to_visible, element_search, or scroll_to_edge."
        )
    }

    @ButtonHeistActor
    func testBatchRejectsContainerTargetedScrollBeforeExecution() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                [
                    "command": "scroll",
                    "container": ["stableId": "main_scroll"],
                    "direction": "down",
                ],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertTrue(mockConn.sent.isEmpty, "Invalid batch steps should fail before execution")
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.summaries.map(\.command), ["scroll"])
        XCTAssertEqual(
            batch.summaries[0].error,
            "run_batch step command \"scroll\" does not support container-targeted scrolling; " +
                "use an element target in run_batch or call scroll outside run_batch"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsRepeatedAdjustmentCountBeforeExecution() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "increment", "identifier": "quantity", "count": 2],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertTrue(mockConn.sent.isEmpty, "Invalid batch steps should fail before execution")
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.summaries.map(\.command), ["increment"])
        XCTAssertEqual(
            batch.summaries[0].error,
            "run_batch step command \"increment\" with count > 1 is not supported by typed batch execution"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsTooManyStepsBeforeExecution() async {
        let steps = Array(repeating: ["command": "activate", "identifier": "btn"], count: TheFence.DecodeLimits.maxRunBatchSteps + 1)
        await assertValidationError(
            ["command": "run_batch", "steps": steps],
            equals: "schema validation failed for steps: observed array count 101; expected array count 1...100"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsTooDeepRequestBeforeExecution() async {
        func nested(_ depth: Int) -> [String: Any] {
            depth == 0 ? ["type": "screen_changed"] : ["expectations": [nested(depth - 1)]]
        }
        await assertValidationError(
            [
                "command": "run_batch",
                "steps": [
                    ["command": "activate", "identifier": "btn", "expect": nested(TheFence.DecodeLimits.maxRunBatchNestingDepth)],
                ] as [[String: Any]],
            ],
            contains: "expected nesting depth <= 32"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsOversizedRequestBeforeExecution() async {
        let payload = String(repeating: "x", count: TheFence.DecodeLimits.maxRunBatchRequestBytes)
        await assertValidationError(
            [
                "command": "run_batch",
                "steps": [
                    ["command": "activate", "identifier": payload],
                ] as [[String: Any]],
            ],
            contains: "expected JSON request <= \(TheFence.DecodeLimits.maxRunBatchRequestBytes) bytes"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsNonBatchExecutableCommandsBeforeExecution() async throws {
        let nonBatchCommands: [TheFence.Command] = [
            .help, .status, .ping, .quit, .exit,
            .listDevices, .getInterface, .getScreen, .getPasteboard,
            .getSessionState, .connect, .listTargets,
            .getSessionLog, .archiveSession,
            .startRecording, .stopRecording, .runBatch,
            .startHeist, .stopHeist, .playHeist,
        ]

        for command in nonBatchCommands {
            let (fence, _) = makeConnectedFence()

            let response = try await fence.execute(request: [
                "command": "run_batch",
                "steps": [
                    ["command": command.rawValue],
                ] as [[String: Any]],
            ])

            guard let batch = inspectBatch(response) else {
                XCTFail("Expected batch response for \(command.rawValue), got \(response)")
                continue
            }

            XCTAssertEqual(batch.results.count, 1)
            XCTAssertEqual(batch.failedIndex, 0)
            XCTAssertEqual(batch.summaries.map(\.command), [command.rawValue])
            XCTAssertEqual(
                batch.summaries[0].error,
                "run_batch step 0: run_batch step command \"\(command.rawValue)\" " +
                    "is not batch-executable"
            )
        }
    }

    @ButtonHeistActor
    func testBatchRejectsGetScreenBeforePayloadValidation() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "get_screen", "inlineData": true],
                ["command": "activate", "identifier": "skipped"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        let expectedError = "run_batch step 0: run_batch step command \"get_screen\" is not batch-executable"
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.summaries.map(\.command), ["get_screen", "activate"])
        XCTAssertEqual(batch.summaries[0].error, expectedError)
        XCTAssertEqual(batch.summaries[1].error, "skipped: stop_on_error stopped batch after step 0")
        XCTAssertFalse(mockConn.sent.contains { sent in
            if case .requestScreen = sent.0 { return true }
            return false
        })
    }

    @ButtonHeistActor
    func testBatchStillAcceptsCanonicalFenceCommandShapes() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "swipe", "direction": "left"],
                ["command": "scroll_to_visible", "label": "Done"],
                ["command": "dismiss_keyboard"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 3)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.summaries.map(\.command), ["swipe", "scroll_to_visible", "dismiss_keyboard"])
    }

    @ButtonHeistActor
    func testBatchSchemaValidationFailureDoesNotDispatchInvalidStep() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(success: true, method: .activate, message: "ran"))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "continue_on_error",
            "steps": [
                ["command": "type_text", "text": ""],
                ["command": "activate", "identifier": "btn"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        let expectedError = "schema validation failed for text: observed string \"\"; expected non-empty string"
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.results.count, 2)
        XCTAssertEqual(batch.results[0]["message"] as? String, expectedError)
        XCTAssertEqual(batch.results[1]["message"] as? String, "ran")
        XCTAssertEqual(batch.summaries.map(\.command), ["type_text", "activate"])
        XCTAssertEqual(batch.summaries[0].error, expectedError)
        let batchPlans = mockConn.sent.compactMap { sent -> BatchPlan? in
            if case .batchExecutionPlan(let plan) = sent.0 { return plan }
            return nil
        }
        XCTAssertEqual(batchPlans.count, 1)
        XCTAssertEqual(batchPlans.first?.steps.count, 1)
    }

    @ButtonHeistActor
    func testBatchReportsUnknownCanonicalCommandWithStepIndex() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "identifier": "first"],
                ["command": "gesture"],
                ["command": "activate", "identifier": "skipped"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 2)
        XCTAssertEqual(batch.failedIndex, 1)
        XCTAssertEqual(batch.summaries.map(\.command), ["activate", "gesture", "activate"])
        let expectedError = "run_batch step 1: run_batch step command must be a canonical TheFence.Command; unknown command \"gesture\""
        XCTAssertEqual(
            batch.summaries[1].error,
            expectedError
        )
        XCTAssertEqual(batch.summaries[2].error, "skipped: stop_on_error stopped batch after step 1")
    }

    @ButtonHeistActor
    func testBatchPreservesContractErrorPhaseAndNextCommand() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "wait_for"],
                ["command": "activate", "identifier": "skipped"],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.summaries[0].errorCode, "request.missing_target")
        XCTAssertEqual(batch.summaries[0].phase, "request")
        XCTAssertEqual(batch.summaries[0].nextCommand, "get_interface()")
        XCTAssertEqual(batch.summaries[1].error, "skipped: stop_on_error stopped batch after step 0")
    }

    // MARK: - get_interface

    @ButtonHeistActor
    func testGetInterfaceDefaultSendsRequestInterfaceQuery() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: ["command": "get_interface"])
        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface message, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertNil(query.subtree)
        XCTAssertFalse(query.matcher.hasPredicates)
        XCTAssertNil(query.elementIds)
    }

    @ButtonHeistActor
    func testUnexpectedParameterIsRejectedByCommandContract() async {
        await assertValidationError(
            ["command": "activate", "identifier": "save", "mode": "tap"],
            equals: "schema validation failed for mode: observed string \"tap\"; expected valid activate parameter"
        )
    }

    @ButtonHeistActor
    func testTimeoutIsRejectedWhenCommandDoesNotConsumeIt() async {
        await assertValidationError(
            ["command": "get_interface", "timeout": 15],
            equals: "schema validation failed for timeout: observed integer 15; expected valid get_interface parameter"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceFullAliasUsesCommandContractRejection() async {
        await assertValidationError(
            ["command": "get_interface", "full": false],
            equals: "schema validation failed for full: observed boolean false; expected valid get_interface parameter"
        )
        await assertValidationError(
            ["command": "get_interface", "full": true],
            equals: "schema validation failed for full: observed boolean true; expected valid get_interface parameter"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceDefaultNoSubtreeReturnsWholeHierarchy() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let interfaceFixture = selectionTestInterface()
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(interfaceFixture)
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: ["command": "get_interface"])

        let json = response.jsonDict()
        let interface = json["interface"] as! [String: Any]
        let tree = interface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 3)
        let container = tree[1]["container"] as! [String: Any]
        XCTAssertEqual(container["stableId"] as? String, "semantic_actions__actions")
        let children = container["children"] as! [[String: Any]]
        XCTAssertEqual(children.count, 2)
    }

    @ButtonHeistActor
    func testGetInterfaceQueryIsSentToInsideJobBoundaryAndReturnsSelectedInterface() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                let source = self.selectionTestInterface()
                let selectedNode = source.tree[1]
                return .interface(Interface(
                    timestamp: source.timestamp,
                    tree: [selectedNode],
                    annotations: source.annotations(
                        forSubtree: selectedNode,
                        originalPath: TreePath([1]),
                        rootPath: TreePath([0])
                    )
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "get_interface",
            "subtree": ["container": ["stableId": "semantic_actions__actions"]],
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertNotNil(query.subtree)

        let json = response.jsonDict()
        let interface = json["interface"] as! [String: Any]
        let tree = interface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 1)
        let container = tree[0]["container"] as! [String: Any]
        XCTAssertEqual(container["stableId"] as? String, "semantic_actions__actions")
        let children = container["children"] as! [[String: Any]]
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual((children[0]["element"] as? [String: Any])?["heistId"] as? String, "submit")
        XCTAssertEqual((children[1]["element"] as? [String: Any])?["heistId"] as? String, "cancel")
    }

    func testContainerStableIdAppearsInSummaryJsonAndCompactOutput() {
        let response = FenceResponse.interface(selectionTestInterface(), detail: .summary)

        let json = response.jsonDict()
        let interface = json["interface"] as! [String: Any]
        let tree = interface["tree"] as! [[String: Any]]
        let container = tree[1]["container"] as! [String: Any]
        XCTAssertEqual(container["stableId"] as? String, "semantic_actions__actions")
        XCTAssertNil(container["frameX"], "summary should expose identity, not geometry")

        let compact = response.compactFormatted()
        XCTAssertTrue(
            compact.contains("semanticGroup stableId=\"semantic_actions__actions\" id=\"actions\" \"Actions\""),
            compact
        )
    }

    @ButtonHeistActor
    func testGetInterfaceSendsMatcherInObservationQuery() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let submit = testElement("submit", label: "Submit", traits: [.button])
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(makeReceiptTestInterface([submit]))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "get_interface",
            "label": "Submit",
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertEqual(query.matcher.label, "Submit")

        let json = response.jsonDict()
        let responseInterface = json["interface"] as! [String: Any]
        let tree = responseInterface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 1)
        let element = tree[0]["element"] as! [String: Any]
        XCTAssertEqual(element["heistId"] as? String, "submit")
    }

    @ButtonHeistActor
    func testGetInterfaceSendsElementIdsInObservationQuery() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let second = testElement("second", label: "Second")
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(makeReceiptTestInterface([second]))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "get_interface",
            "elements": ["second"],
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertEqual(query.elementIds, ["second"])

        let json = response.jsonDict()
        let responseInterface = json["interface"] as! [String: Any]
        let tree = responseInterface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 1)
        let element = tree[0]["element"] as! [String: Any]
        XCTAssertEqual(element["heistId"] as? String, "second")
    }

    @ButtonHeistActor
    func testGetInterfaceDetailDoesNotChangeObservationDispatch() async {
        let (fullFence, fullMock) = makeConnectedFence()
        _ = try? await fullFence.execute(request: [
            "command": "get_interface",
            "detail": "full",
        ])
        guard let (fullMessage, _) = fullMock.sent.last,
              case .requestInterface = fullMessage else {
            XCTFail("Expected detail=full on get_interface to send requestInterface, got \(String(describing: fullMock.sent.last))")
            return
        }
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsScopeParameter() async {
        await assertValidationError(
            ["command": "get_interface", "scope": "current"],
            equals: "schema validation failed for scope: observed string \"current\"; expected valid get_interface parameter"
        )
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

        guard let batch = inspectBatch(response) else {
            XCTFail("Expected batch response, got \(response)")
            return
        }
        XCTAssertEqual(batch.expectationsChecked, 0)
        XCTAssertEqual(batch.expectationsMet, 0)
    }

    // MARK: - Heist Playback

    @ButtonHeistActor
    private func writeTemporaryHeist(_ heist: HeistPlayback) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let heistURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).heist")
        try TheBookKeeper.writeHeist(heist, to: heistURL)
        return heistURL
    }

    @ButtonHeistActor
    func testPlayHeistMissingInputReturnsSchemaError() async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(request: ["command": "play_heist"])
            guard case .error(let message, _) = response else {
                return XCTFail("Expected .error response, got \(response)")
            }
            XCTAssertEqual(message, "schema validation failed for input: observed missing; expected string")
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    @ButtonHeistActor
    func testPlayHeistPathTraversalThrows() async {
        let (fence, _) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: ["command": "play_heist", "input": "/tmp/../etc/passwd"])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid input path"))
        }
    }

    @ButtonHeistActor
    func testPlayHeistEmptyPathThrows() async {
        let (fence, _) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: ["command": "play_heist", "input": ""])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid input path"))
        }
    }

    @ButtonHeistActor
    func testStopHeistMissingOutputDoesNotStopRecording() async throws {
        let (fence, _) = makeConnectedFence()
        try fence.bookKeeper.beginSession(identifier: "stop-heist-missing-output")
        try fence.bookKeeper.startHeistRecording(app: "com.test.mock")

        let response = try await fence.execute(request: ["command": "stop_heist"])
        guard case .error(let message, _) = response else {
            return XCTFail("Expected .error response, got \(response)")
        }
        XCTAssertEqual(message, "schema validation failed for output: observed missing; expected string")

        XCTAssertTrue(fence.bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testStopHeistInvalidOutputDoesNotStopRecording() async throws {
        let (fence, _) = makeConnectedFence()
        try fence.bookKeeper.beginSession(identifier: "stop-heist-invalid-output")
        try fence.bookKeeper.startHeistRecording(app: "com.test.mock")

        do {
            _ = try await fence.execute(request: [
                "command": "stop_heist",
                "output": "/tmp/../invalid.heist",
            ])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid output path"))
        }

        XCTAssertTrue(fence.bookKeeper.isRecordingHeist)
    }

    @ButtonHeistActor
    func testPlayHeistEmptyStepsCompletesSuccessfully() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path
        ])

        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, let report) = response else {
            return XCTFail("Expected heistPlayback response, got \(response)")
        }
        XCTAssertEqual(completedSteps, 0)
        XCTAssertNil(failedIndex)
        XCTAssertNil(failure)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.steps.count, 0)
        XCTAssertTrue(report?.allPassed ?? false)
    }

    @ButtonHeistActor
    func testPlayHeistExecutesStepsInOrder() async throws {
        let steps = [
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn2")),
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn3")),
        ]
        let heist = HeistPlayback(app: "com.test.mock", steps: steps)
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path
        ])

        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, let report) = response else {
            return XCTFail("Expected heistPlayback response, got \(response)")
        }
        XCTAssertEqual(completedSteps, 3)
        XCTAssertNil(failedIndex)
        XCTAssertNil(failure)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.steps.count, 3)
        XCTAssertTrue(report?.allPassed ?? false)
        for (stepIndex, stepResult) in (report?.steps ?? []).enumerated() {
            XCTAssertEqual(stepResult.index, stepIndex)
            XCTAssertEqual(stepResult.command, "activate")
            XCTAssertTrue(stepResult.passed)
        }

        // Verify all three activate commands were sent
        let activateMessages = mockConn.sent.filter { message, _ in
            if case .activate = message { return true }
            return false
        }
        XCTAssertEqual(activateMessages.count, 3)
        XCTAssertEqual(
            mockConn.sent.map { $0.0.canonicalName },
            [
                "request_interface",
                "activate",
                "request_interface",
                "activate",
                "request_interface",
                "activate",
            ]
        )
    }

    @ButtonHeistActor
    func testTypedPlaybackBindsFixtureStepsToTypedCommands() async throws {
        let playback = try TheFence.TypedHeistPlayback(
            wire: HeistPlayback(
                app: "com.test.mock",
                steps: [
                    HeistEvidence(
                        command: "type_text",
                        target: ElementMatcher(identifier: "email"),
                        ordinal: 1,
                        arguments: ["text": .string("user@example.com")],
                        recorded: RecordedMetadata(heistId: "recorded-email")
                    ),
                    HeistEvidence(command: "activate", target: ElementMatcher(identifier: "submit")),
                ]
            )
        )
        let operation = playback.steps[0]

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.totalStepCount, 2)
        XCTAssertEqual(operation.command, .typeText)
        XCTAssertEqual(playback.steps[1].command, .activate)
        XCTAssertEqual(operation.target?.identifier, "email")
        XCTAssertEqual(operation.ordinal, 1)

        let normalizedOperation = operation.normalizedOperation()
        let arguments = normalizedOperation.arguments
        XCTAssertEqual(normalizedOperation.command, .typeText)
        XCTAssertEqual(arguments["identifier"] as? String, "email")
        XCTAssertEqual(arguments["ordinal"] as? Int, 1)
        XCTAssertEqual(arguments["text"] as? String, "user@example.com")
        XCTAssertNil(arguments["_recorded"])
    }

    @ButtonHeistActor
    func testTypedPlaybackLoadsFlatHeistFileAtFileEdge() async throws {
        let heist = HeistPlayback(
            app: "com.test.mock",
            steps: [
                HeistEvidence(
                    command: "activate",
                    target: ElementMatcher(identifier: "submit"),
                    arguments: ["expect": .object(["type": .string("screen_changed")])]
                ),
            ]
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let playback = try TheFence.TypedHeistPlayback(contentsOf: heistURL)

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.steps.map(\.command), [.activate])
        XCTAssertEqual(playback.steps.first?.target?.identifier, "submit")
        let expect = playback.steps.first?.requestArguments()["expect"] as? [String: Any]
        XCTAssertEqual(expect?["type"] as? String, "screen_changed")
    }

    @ButtonHeistActor
    func testTypedPlaybackFileEdgeRejectsUnsupportedVersion() async throws {
        let heist = HeistPlayback(
            version: HeistPlayback.currentVersion + 1,
            app: "com.test.mock",
            steps: [HeistEvidence(command: "activate", target: ElementMatcher(identifier: "submit"))]
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        XCTAssertThrowsError(try TheFence.TypedHeistPlayback(contentsOf: heistURL)) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported heist file version \(HeistPlayback.currentVersion + 1)"))
            XCTAssertTrue(message.contains("supports version \(HeistPlayback.currentVersion)"))
        }
    }

    @ButtonHeistActor
    func testPlaybackOperationPreservesCanonicalExpectationPayload() async throws {
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(
                command: "type_text",
                target: ElementMatcher(identifier: "email"),
                arguments: ["expect": .object(["type": .string("screen_changed")])]
            ),
            index: 0
        )

        let expect = operation.requestArguments()["expect"] as? [String: Any]
        XCTAssertEqual(expect?["type"] as? String, "screen_changed")
    }

    @ButtonHeistActor
    func testTypedPlaybackAcceptsCanonicalPlaybackExecutableCommands() async throws {
        let playback = try TheFence.TypedHeistPlayback(
            wire: HeistPlayback(
                app: "com.test.mock",
                steps: TheFence.Command.playbackExecutableCases.map { command in
                    HeistEvidence(command: command.rawValue)
                }
            )
        )

        XCTAssertEqual(playback.steps.map(\.command), TheFence.Command.playbackExecutableCases)
    }

    @ButtonHeistActor
    func testTypedPlaybackRejectsUnknownGroupedMCPToolName() async throws {
        XCTAssertThrowsError(
            try TheFence.TypedHeistPlayback(
                wire: HeistPlayback(
                    app: "com.test.mock",
                    steps: [
                        HeistEvidence(
                            command: "gesture",
                            arguments: ["type": .string(TheFence.Command.swipe.rawValue)]
                        ),
                    ]
                )
            )
        ) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid heist step 0"))
            XCTAssertTrue(
                message.contains("heist step command must be a canonical TheFence.Command; unknown command \"gesture\""),
                "Unexpected error: \(message)"
            )
        }
    }

    @ButtonHeistActor
    func testPlaybackGroupedMCPSelectorShapesUseRequestValidation() async throws {
        let cases: [(name: String, operation: TheFence.PlaybackOperation, message: String)] = [
            (
                "scroll mode selector",
                try TheFence.PlaybackOperation(
                    evidence: HeistEvidence(
                        command: "scroll",
                        arguments: ["mode": .string(ScrollMode.search.rawValue)]
                    ),
                    index: 0
                ),
                "schema validation failed for mode: observed string \"search\"; expected valid scroll parameter"
            ),
            (
                "edit_action dismiss selector",
                try TheFence.PlaybackOperation(
                    evidence: HeistEvidence(
                        command: "edit_action",
                        arguments: ["action": .string("dismiss")]
                    ),
                    index: 0
                ),
                "schema validation failed for action: observed string \"dismiss\"; " +
                    "expected enum one of copy, paste, cut, select, selectAll, delete"
            ),
        ]

        let (fence, _) = makeConnectedFence()
        for testCase in cases {
            let response = try await fence.execute(playback: testCase.operation)
            guard case .error(let message, _) = response else {
                XCTFail("Expected playback validation error for \(testCase.name), got \(response)")
                continue
            }
            XCTAssertEqual(message, testCase.message)
        }
    }

    @ButtonHeistActor
    func testTypedPlaybackRejectsNonExecutableCommands() async throws {
        for command in TheFence.Command.allCases where !command.isPlaybackExecutable {
            XCTAssertThrowsError(
                try TheFence.TypedHeistPlayback(
                    wire: HeistPlayback(app: "com.test.mock", steps: [HeistEvidence(command: command.rawValue)])
                ),
                command.rawValue
            ) { error in
                guard case FenceError.invalidRequest(let message) = error else {
                    return XCTFail("Expected FenceError.invalidRequest, got \(error)")
                }
                XCTAssertTrue(message.contains("Invalid heist step 0"))
                XCTAssertTrue(
                    message.contains("heist step command \"\(command.rawValue)\" is not playback-executable"),
                    "Unexpected error for \(command.rawValue): \(message)"
                )
            }
        }
    }

    @ButtonHeistActor
    func testExecutePlaybackOperationUsesTypedCommand() async throws {
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
            index: 0
        )

        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(playback: operation)

        guard case .action(let result, _) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertTrue(result.success)

        let activateMessages = mockConn.sent.filter { message, _ in
            if case .activate = message { return true }
            return false
        }
        XCTAssertEqual(activateMessages.count, 1)
    }

    @ButtonHeistActor
    func testPlayHeistDoesNotImplicitlyRecoverElementNotFoundWithScrollToVisible() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "offscreen")),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            case .activate:
                return .actionResult(ActionResult(
                    success: false,
                    method: .elementNotFound,
                    message: "missing",
                    errorKind: .elementNotFound
                ))
            case .scrollToVisible:
                return .actionResult(ActionResult(success: true, method: .scrollToVisible))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path,
        ])

        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, let report) = response else {
            return XCTFail("Expected heistPlayback response, got \(response)")
        }
        XCTAssertEqual(completedSteps, 0)
        XCTAssertEqual(failedIndex, 0)
        XCTAssertNotNil(failure)
        XCTAssertEqual(report?.steps.count, 1)
        XCTAssertFalse(report?.allPassed ?? true)

        let activateMessages = mockConn.sent.filter { message, _ in
            if case .activate = message { return true }
            return false
        }
        let scrollToVisibleMessages = mockConn.sent.filter { message, _ in
            if case .scrollToVisible = message { return true }
            return false
        }
        XCTAssertEqual(activateMessages.count, 1)
        XCTAssertTrue(scrollToVisibleMessages.isEmpty)
    }

    @ButtonHeistActor
    func testPlaybackDoesNotUseRecordedHeistIdAsAuthority() async throws {
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(
                command: "activate",
                target: ElementMatcher(identifier: "btn1"),
                recorded: RecordedMetadata(heistId: "stale_debug_id")
            ),
            index: 0
        )

        let arguments = operation.requestArguments()
        XCTAssertEqual(arguments["identifier"] as? String, "btn1")
        XCTAssertNil(arguments["heistId"])

        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(playback: operation)

        guard case .action(let result, _) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertTrue(result.success)

        let activateMessages = mockConn.sent.compactMap { message, _ -> ClientMessage? in
            if case .activate = message { return message }
            return nil
        }
        XCTAssertEqual(activateMessages.count, 1)
        guard case .activate(.matcher(let matcher, _)) = activateMessages.first else {
            return XCTFail("Expected playback to dispatch matcher target, got \(String(describing: activateMessages.first))")
        }
        XCTAssertEqual(matcher.identifier, "btn1")
    }

    @ButtonHeistActor
    func testPlayHeistIgnoresRecordedAccessibilityTrace() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(
                command: "activate",
                target: ElementMatcher(identifier: "btn1"),
                recorded: RecordedMetadata(
                    accessibilityTrace: AccessibilityTrace(interface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: []
                    ))
                )
            ),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path,
        ])

        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, let report) = response else {
            return XCTFail("Expected heistPlayback response, got \(response)")
        }
        XCTAssertEqual(completedSteps, 1)
        XCTAssertNil(failedIndex)
        XCTAssertNil(failure)
        XCTAssertTrue(report?.allPassed ?? false)

        let activateMessages = mockConn.sent.filter { message, _ in
            if case .activate = message { return true }
            return false
        }
        XCTAssertEqual(activateMessages.count, 1)
    }

    @ButtonHeistActor
    func testPlayHeistRejectsInvalidCommandBeforeExecution() async throws {
        let steps = [
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
            HeistEvidence(command: "not_a_real_command"),
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn3")),
        ]
        let heist = HeistPlayback(app: "com.test.mock", steps: steps)
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": heistURL.path,
            ])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid heist step 1"))
            XCTAssertTrue(message.contains("unknown command \"not_a_real_command\""))
        }

        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testPlayHeistRejectsInvalidFirstCommandBeforePrimingInterface() async throws {
        let steps = [
            HeistEvidence(command: "not_a_real_command"),
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
        ]
        let heist = HeistPlayback(app: "com.test.mock", steps: steps)
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": heistURL.path,
            ])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid heist step 0"))
            XCTAssertTrue(message.contains("unknown command \"not_a_real_command\""))
        }

        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testPlayHeistReentrantGuard() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        fence.playbackPhase = .playing(startedAt: Date())
        defer { fence.playbackPhase = .idle }

        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": heistURL.path,
            ])
            XCTFail("Expected re-entrant playback to fail")
        } catch FenceError.invalidRequest(let message) {
            XCTAssertEqual(message, "Cannot nest play_heist inside an active playback")
        } catch {
            XCTFail("Expected invalidRequest, got \(error)")
        }
    }

    @ButtonHeistActor
    func testPlayHeistReportsTimingMs() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path
        ])

        guard case .heistPlayback(_, _, let totalTimingMs, _, _) = response else {
            return XCTFail("Expected heistPlayback response, got \(response)")
        }
        XCTAssertGreaterThanOrEqual(totalTimingMs, 0)
    }

    @ButtonHeistActor
    func testPlayHeistResetsPhaseAfterCompletion() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: ElementMatcher(identifier: "btn1")),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        // First playback should succeed
        let firstResponse = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path
        ])
        guard case .heistPlayback = firstResponse else {
            return XCTFail("Expected heistPlayback response")
        }

        // Second playback should also succeed (phase reset to idle)
        let secondResponse = try await fence.execute(request: [
            "command": "play_heist", "input": heistURL.path
        ])
        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, _) = secondResponse else {
            return XCTFail("Expected heistPlayback response")
        }
        XCTAssertEqual(completedSteps, 1)
        XCTAssertNil(failedIndex)
        XCTAssertNil(failure)
    }

    @ButtonHeistActor
    func testPlayHeistRejectsNewerVersion() async throws {
        let heist = HeistPlayback(
            version: HeistPlayback.currentVersion + 1,
            app: "com.test.mock",
            steps: []
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": heistURL.path,
            ])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported heist file version"))
            XCTAssertTrue(message.contains("Re-record the heist"))
        }
    }

    @ButtonHeistActor
    func testPlayHeistRejectsOlderVersion() async throws {
        let heist = HeistPlayback(
            version: HeistPlayback.currentVersion - 1,
            app: "com.test.mock",
            steps: []
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": heistURL.path,
            ])
            XCTFail("Expected FenceError.invalidRequest to be thrown")
        } catch {
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported heist file version"))
            XCTAssertTrue(message.contains("supports version \(HeistPlayback.currentVersion)"))
            XCTAssertTrue(message.contains("Re-record the heist"))
        }
    }
}
