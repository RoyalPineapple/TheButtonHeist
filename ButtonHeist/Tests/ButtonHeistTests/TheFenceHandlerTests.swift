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
        let arguments = try TheFence.CommandArgumentEnvelope(
            arguments: request,
            droppingCommandKey: true
        )
        return try fence.decodeRunBatchRequest(arguments)
    }

    @ButtonHeistActor
    private func assertRunBatchDecodeError(
        steps: [[String: Any]],
        contains expectedSubstring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            _ = try decodedRunBatch(fence, steps: steps)
            XCTFail("Expected run_batch decode to fail", file: file, line: line)
        } catch {
            let message: String
            if let schemaError = error as? SchemaValidationError {
                message = schemaError.message
            } else if let fenceError = error as? FenceError {
                message = fenceError.coreMessage
            } else {
                message = String(describing: error)
            }
            XCTAssertTrue(
                message.contains(expectedSubstring),
                "Expected error containing '\(expectedSubstring)', got: \(message)",
                file: file,
                line: line
            )
        }
    }

    private func plannedBatchSteps(
        from batch: TheFence.RunBatchRequest
    ) -> [TheFence.RunBatchPreparedStep] {
        batch.steps
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
        let statusRequest = try fence.parseRequest(command: .getSessionState, request: [
            "command": "get_session_state",
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

    // MARK: - Typed Argument Parsing

    func testCommandArgumentEnvelopePreservesJSONScalarTypes() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "bool": NSNumber(value: true),
            "int": NSNumber(value: 3),
            "double": NSNumber(value: 2.5),
        ])

        XCTAssertEqual(try envelope.schemaBoolean("bool"), true)
        XCTAssertEqual(try envelope.schemaInteger("int"), 3)
        XCTAssertEqual(try envelope.schemaNumber("double"), 2.5)
        XCTAssertNil(envelope.observedValue(for: "missing"))
    }

    func testCommandArgumentEnvelopeRejectsNullValues() {
        XCTAssertThrowsError(try TheFence.CommandArgumentEnvelope(arguments: [
            "null": NSNull(),
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "SchemaValidationError(field: \"null\", observed: \"null\", expected: \"JSON scalar, array, or object\")"
            )
        }
    }

    func testCommandArgumentEnvelopePreservesNestedJSONValues() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "object": [
                "label": "Pay",
                "traits": ["button", "selected"],
            ],
            "array": [
                ["x": 0.25, "y": 0.75],
                ["x": 0.5, "y": 0.5],
            ],
        ] as [String: Any])

        let object = try XCTUnwrap(try envelope.schemaDictionary("object"))
        XCTAssertEqual(try object.schemaString("label"), "Pay")
        XCTAssertEqual(try object.schemaStringArray("traits"), ["button", "selected"])

        guard case .array(let array)? = envelope.argumentValues["array"] else {
            return XCTFail("Expected typed array")
        }
        XCTAssertEqual(array.count, 2)
        guard case .object(let firstObject) = array[0] else {
            return XCTFail("Expected typed object")
        }
        let first = TheFence.CommandArgumentObject(values: firstObject, fieldPrefix: "array[0]")
        XCTAssertEqual(try first.schemaNumber("x"), 0.25)
        XCTAssertEqual(try first.schemaNumber("y"), 0.75)
        guard case .object(let secondObject) = array[1] else {
            return XCTFail("Expected typed object")
        }
        let second = TheFence.CommandArgumentObject(values: secondObject, fieldPrefix: "array[1]")
        XCTAssertEqual(try second.schemaNumber("x"), 0.5)
        XCTAssertEqual(try second.schemaNumber("y"), 0.5)
    }

    func testCommandArgumentEnvelopeReadsNestedTypedObjects() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "subtree": [
                "element": [
                    "label": "Pay",
                    "traits": ["button", "selected"],
                ],
                "container": [
                    "type": "scrollable",
                    "isModalBoundary": true,
                    "ratio": 0.5,
                ],
                "ordinal": 2,
            ],
        ] as [String: Any])

        let subtree = try XCTUnwrap(try envelope.schemaDictionary("subtree"))
        let element = try XCTUnwrap(try subtree.schemaDictionary("element"))
        let container = try XCTUnwrap(try subtree.schemaDictionary("container"))
        XCTAssertEqual(try subtree.schemaInteger("ordinal"), 2)
        XCTAssertEqual(try element.schemaString("label"), "Pay")
        XCTAssertEqual(try element.schemaStringArray("traits"), ["button", "selected"])
        XCTAssertEqual(try container.schemaEnum("type", as: ContainerTypeName.self), .scrollable)
        XCTAssertEqual(try container.schemaBoolean("isModalBoundary"), true)
        XCTAssertEqual(try container.schemaNumber("ratio"), 0.5)
    }

    func testCommandArgumentEnvelopeNestedSchemaErrorsUseQualifiedFields() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "subtree": [
                "element": [
                    "traits": [7],
                ],
            ],
        ] as [String: Any])

        let subtree = try XCTUnwrap(try envelope.schemaDictionary("subtree"))
        let element = try XCTUnwrap(try subtree.schemaDictionary("element"))
        XCTAssertThrowsError(try element.schemaStringArray("traits")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for subtree.element.traits[0]: observed integer 7; expected string"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsTypedObjectArrays() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "points": [
                ["x": 0.25, "y": 0.75],
                ["x": 1, "y": 2],
            ],
        ] as [String: Any])

        let points = try envelope.requiredSchemaObjectArray("points")
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(try points[0].requiredSchemaNumber("x"), 0.25)
        XCTAssertEqual(try points[0].requiredSchemaNumber("y"), 0.75)
        XCTAssertEqual(try points[1].requiredSchemaNumber("x"), 1)
        XCTAssertEqual(try points[1].requiredSchemaNumber("y"), 2)
    }

    func testCommandArgumentEnvelopeObjectArrayErrorsUseIndexedFields() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "points": [
                ["x": "bad"],
            ],
        ] as [String: Any])

        let points = try envelope.requiredSchemaObjectArray("points")
        XCTAssertThrowsError(try points[0].requiredSchemaNumber("x")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for points[0].x: observed string \"bad\"; expected number"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsUnitPoint() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "start": ["x": 0.25, "y": 0.75],
        ] as [String: Any])

        XCTAssertEqual(try envelope.schemaUnitPoint("start"), UnitPoint(x: 0.25, y: 0.75))
    }

    func testCommandArgumentEnvelopeUnitPointErrorsUseQualifiedFields() throws {
        let missingField = try TheFence.CommandArgumentEnvelope(arguments: [
            "start": ["x": 0.25],
        ] as [String: Any])
        XCTAssertThrowsError(try missingField.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.y: observed missing; expected number"
            )
        }

        let outOfRange = try TheFence.CommandArgumentEnvelope(arguments: [
            "start": ["x": 1.2, "y": 0.5],
        ] as [String: Any])
        XCTAssertThrowsError(try outOfRange.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.x: observed number 1.2; expected number in 0...1"
            )
        }

        let extraField = try TheFence.CommandArgumentEnvelope(arguments: [
            "start": ["x": 0.25, "y": 0.75, "z": 0.5],
        ] as [String: Any])
        XCTAssertThrowsError(try extraField.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.z: observed number 0.5; expected valid unit point field"
            )
        }
    }

    func testCommandArgumentEnvelopeUnitPointRejectsNonObjectWithSpecificExpectedShape() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "start": "left",
        ])

        XCTAssertThrowsError(try envelope.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start: observed string \"left\"; expected object with numeric x and y"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsRequiredEnum() throws {
        let envelope = try TheFence.CommandArgumentEnvelope(arguments: [
            "direction": "up",
        ])

        XCTAssertEqual(
            try envelope.requiredSchemaEnum("direction", as: SwipeDirection.self),
            .up
        )
    }

    func testCommandArgumentEnvelopeRequiredEnumErrorsUseExpectedCases() throws {
        let missing = try TheFence.CommandArgumentEnvelope(arguments: [:])
        XCTAssertThrowsError(try missing.requiredSchemaEnum("direction", as: SwipeDirection.self)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for direction: observed missing; expected enum one of up, down, left, right"
            )
        }

        let invalid = try TheFence.CommandArgumentEnvelope(arguments: [
            "direction": "diagonal",
        ])
        XCTAssertThrowsError(try invalid.requiredSchemaEnum("direction", as: SwipeDirection.self)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetWithIdentifier() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": matcherTarget(identifier: "myButton")]
        guard let target = try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict)),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.identifier, "myButton")
    }

    @ButtonHeistActor
    func testElementTargetWithHeistId() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": heistTarget("button_save")]
        guard let target = try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict)),
              case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "button_save")
    }

    @ButtonHeistActor
    func testElementTargetWithMatcherFields() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": matcherTarget(label: "Save", traits: ["button"])]
        guard let target = try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict)),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
    }

    @ButtonHeistActor
    func testElementTargetRejectsHeistIdAndMatcher() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": ["heistId": "button_save", "matcher": ["label": "Save"]]]
        XCTAssertThrowsError(try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict))) { error in
            XCTAssertTrue(
                "\(error)".contains("either heistId or matcher"),
                "Expected mixed selector rejection, got \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetWithOrdinal() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": matcherTarget(label: "Save", ordinal: 2)]
        guard let target = try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict)),
              case .matcher(let matcher, let ordinal) = target else {
            return XCTFail("Expected .matcher with ordinal")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(ordinal, 2)
    }

    @ButtonHeistActor
    func testRequestTargetRejectsNegativeOrdinal() async {
        await assertValidationError(
            ["command": "activate", "target": ["matcher": ["label": "Save"], "ordinal": -1]],
            equals: "schema validation failed for target.ordinal: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testElementTargetWithoutOrdinal() async throws {
        let (fence, _) = makeConnectedFence()
        let dict: [String: Any] = ["target": matcherTarget(label: "Save")]
        guard let target = try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: dict)),
              case .matcher(_, let ordinal) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testElementTargetMissing() async throws {
        let (fence, _) = makeConnectedFence()
        XCTAssertNil(try fence.decodedElementTarget(try TheFence.CommandArgumentEnvelope(arguments: [:])))
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
            contains: "Must specify target object"
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
            equals: "schema validation failed for x: observed number nan; expected finite JSON number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsInfiniteCoordinate() async {
        await assertValidationError(
            ["command": "one_finger_tap", "x": Double.infinity, "y": 200.0],
            equals: "schema validation failed for x: observed number inf; expected finite JSON number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithIdentifierPassesValidation() async {
        await assertPassesValidation(
            ["command": "one_finger_tap", "target": matcherTarget(identifier: "myButton")]
        )
    }

    @ButtonHeistActor
    func testLongPressMissingTarget() async {
        await assertValidationError(
            ["command": "long_press"],
            contains: "Must specify target object"
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
    func testSwipeDirectionWithoutTargetOrCoordinatesIsRejected() async {
        await assertValidationError(
            ["command": "swipe", "direction": "up"],
            equals: "Swipe requires target object or start coordinates (startX, startY)"
        )
    }

    @ButtonHeistActor
    func testSwipeWithUnitPointsPassesValidation() async {
        await assertPassesValidation(
            ["command": "swipe", "target": heistTarget("row_5"),
             "start": ["x": 0.8, "y": 0.5],
             "end": ["x": 0.2, "y": 0.5]]
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsRejectOutOfRangeCoordinate() async {
        await assertValidationError(
            ["command": "swipe", "target": heistTarget("row_5"),
             "start": ["x": 1.2, "y": 0.5],
             "end": ["x": 0.2, "y": 0.5]],
            equals: "schema validation failed for start.x: observed number 1.2; expected number in 0...1"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementPassesValidation() async {
        await assertPassesValidation(
            ["command": "swipe", "target": heistTarget("row_5"), "direction": "left"]
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
              case .drag(let target) = message else {
            XCTFail("Expected drag message")
            return
        }
        XCTAssertEqual(target.start, .coordinate(ScreenPoint(x: 100.0, y: 300.0)))
        XCTAssertEqual(target.end, ScreenPoint(x: 300.0, y: 600.0))
    }

    @ButtonHeistActor
    func testPinchMissingScale() async {
        await assertValidationError(
            ["command": "pinch"],
            equals: "schema validation failed for scale: observed missing; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testPinchRequiresCenter() async {
        await assertValidationError(
            ["command": "pinch", "scale": 2.0],
            equals: "Pinch requires target object or center coordinates (centerX, centerY)"
        )
    }

    @ButtonHeistActor
    func testPinchWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "pinch", "scale": 2.0, "centerX": 200.0, "centerY": 500.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .pinch(let target) = message else {
            XCTFail("Expected pinch message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 200.0, y: 500.0)))
    }

    @ButtonHeistActor
    func testRotateWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(request: [
            "command": "rotate", "angle": 1.57, "centerX": 150.0, "centerY": 400.0
        ])
        guard let (message, _) = mockConn.sent.last,
              case .rotate(let target) = message else {
            XCTFail("Expected rotate message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 150.0, y: 400.0)))
    }

    @ButtonHeistActor
    func testRotateMissingAngle() async {
        await assertValidationError(
            ["command": "rotate"],
            equals: "schema validation failed for angle: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testRotateRequiresCenter() async {
        await assertValidationError(
            ["command": "rotate", "angle": 1.57],
            equals: "Rotate requires target object or center coordinates (centerX, centerY)"
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
              case .twoFingerTap(let target) = message else {
            XCTFail("Expected twoFingerTap message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 200.0, y: 500.0)))
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
    func testDrawPathRejectsExtraPointFields() async {
        await assertValidationError(
            ["command": "draw_path", "points": [
                ["x": 0.0, "y": 0.0, "pressure": 0.5],
                ["x": 1.0, "y": 1.0],
            ]],
            equals: "schema validation failed for points[0].pressure: observed number 0.5; expected valid draw path point field"
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
    func testDrawBezierRejectsExtraSegmentFields() async {
        await assertValidationError(
            ["command": "draw_bezier", "startX": 0.0, "startY": 0.0, "segments": [
                [
                    "cp1X": 1.0, "cp1Y": 2.0,
                    "cp2X": 3.0, "cp2Y": 4.0,
                    "endX": 5.0, "endY": 6.0,
                    "weight": 0.5,
                ],
            ]],
            equals: "schema validation failed for segments[0].weight: observed number 0.5; expected valid bezier segment field"
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
            ["command": "scroll", "target": matcherTarget(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollInvalidDirection() async {
        await assertValidationError(
            ["command": "scroll", "target": matcherTarget(identifier: "scrollView"), "direction": "diagonal"],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
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
            ["command": "scroll", "direction": "down", "target": matcherTarget(identifier: "scrollView")]
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
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_visible", "target": matcherTarget(identifier: "targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleHeistIdPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_visible", "target": heistTarget("targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeDefaultsEdge() async {
        await assertPassesValidation(
            ["command": "scroll_to_edge", "target": matcherTarget(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeInvalidEdge() async {
        await assertValidationError(
            ["command": "scroll_to_edge", "target": matcherTarget(identifier: "scrollView"), "edge": "middle"],
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
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeValidPassesValidation() async {
        await assertPassesValidation(
            ["command": "scroll_to_edge", "edge": "bottom", "target": matcherTarget(identifier: "scrollView")]
        )
    }

    // MARK: - Accessibility Action Validation

    @ButtonHeistActor
    func testActivateMissingElement() async {
        await assertContractError(
            ["command": "activate"],
            contains: [
                "activate request contract failed: missing target",
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testActivateWithElementPassesValidation() async {
        await assertPassesValidation(
            ["command": "activate", "target": matcherTarget(identifier: "myElement")]
        )
    }

    @ButtonHeistActor
    func testRotorMissingElement() async {
        await assertContractError(
            ["command": "rotor", "rotor": "Errors"],
            contains: [
                "rotor request contract failed: missing target",
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testRotorNegativeIndex() async {
        await assertValidationError(
            ["command": "rotor", "target": matcherTarget(identifier: "myElement"), "rotorIndex": -1],
            equals: "schema validation failed for rotorIndex: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsMixedSelectorShape() async {
        await assertValidationError(
            ["command": "rotor", "target": matcherTarget(identifier: "myElement"), "rotor": "Errors", "rotorIndex": 1],
            contains: "either rotor or rotorIndex"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidDirection() async {
        await assertValidationError(
            ["command": "rotor", "target": matcherTarget(identifier: "myElement"), "direction": "sideways"],
            equals: "schema validation failed for direction: observed string \"sideways\"; expected enum one of next, previous"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresBothOffsets() async {
        await assertValidationError(
            ["command": "rotor", "target": matcherTarget(identifier: "myElement"), "currentTextStartOffset": 4],
            contains: "currentTextStartOffset and currentTextEndOffset"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresCurrentHeistId() async {
        await assertValidationError(
            [
                "command": "rotor",
                "target": matcherTarget(identifier: "myElement"),
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
                "target": matcherTarget(identifier: "myElement"),
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
            ["command": "rotor", "target": matcherTarget(identifier: "myElement"), "rotor": "Errors"]
        )
    }

    @ButtonHeistActor
    func testRotorPreviousValidTextRangeCursorPassesValidation() async {
        await assertPassesValidation(
            [
                "command": "rotor",
                "target": matcherTarget(identifier: "myElement"),
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
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "Delete"]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementDispatches() async {
        await assertPassesValidation(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "increment"]
        )
    }

    @ButtonHeistActor
    func testActivateWithDecrementDispatches() async {
        await assertPassesValidation(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "decrement"]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountOmittedDispatchesOnce() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "target": matcherTarget(identifier: "myElement"),
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
            "target": matcherTarget(identifier: "myElement"),
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
            "target": matcherTarget(identifier: "myElement"),
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
    func testActivateWithDecrementCountDispatchesMultipleExistingCommands() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "activate",
            "target": matcherTarget(identifier: "myElement"),
            "action": "decrement",
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
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "increment", "count": 0],
            contains: "schema validation failed for count: observed integer 0; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsNegativeCount() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "increment", "count": -1],
            contains: "schema validation failed for count: observed integer -1; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsCountAboveMaximum() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "increment", "count": 101],
            contains: "schema validation failed for count: observed integer 101; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithoutAdjustmentAction() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithCustomAction() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "Delete", "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsOutOfRangeCountWithCustomActionAsNonAdjustment() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "Delete", "count": 200],
            contains: "schema validation failed for count: observed integer 200; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateTreatsActionPrefixAsLiteralCustomActionName() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": "action:increment", "count": 2],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsEmptyActionNameAtRequestBoundary() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "myElement"), "action": ""],
            equals: "schema validation failed for action: observed string \"\"; expected non-empty string"
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
            "target": matcherTarget(identifier: "myElement"),
            "action": "increment",
            "count": 3,
        ])

        guard case .action(let result, _) = response else {
            return XCTFail("Expected action failure response, got \(response)")
        }
        XCTAssertEqual(mockConn.sent.adjustmentMessages.count, 2)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(result.message, "adjustment failed")
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
            "target": matcherTarget(identifier: "myElement"),
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
    func testTypeTextTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "type_text",
            "text": "hello",
            "target": heistTarget("search_field"),
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
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: "request.missing_target",
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testWaitForWithLabelPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "target": matcherTarget(label: "Loading")]
        )
    }

    @ButtonHeistActor
    func testWaitForWithIdentifierPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "target": matcherTarget(identifier: "spinner")]
        )
    }

    @ButtonHeistActor
    func testWaitForWithTraitsPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "target": matcherTarget(traits: ["button"])]
        )
    }

    @ButtonHeistActor
    func testWaitForWithAbsentPassesValidation() async {
        await assertPassesValidation(
            ["command": "wait_for", "target": matcherTarget(label: "Loading"), "absent": true, "timeout": 5.0]
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
    func testWaitForChangeRequiresTraceDerivedExpectationMatch() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            guard case .waitForChange = message else {
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return .actionResult(ActionResult(
                success: true,
                method: .waitForChange,
                message: "expectation met after observed change",
                traceProjecting: .noChange(.init(elementCount: 1))
            ))
        }

        let response = try await fence.execute(request: [
            "command": "wait_for_change",
            "expect": ["type": "element_disappeared", "matcher": ["label": "Loading"]],
        ])

        guard case .action(_, let expectation) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(expectation?.met, false)
        XCTAssertEqual(expectation?.actual, "no elements removed")
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
                traceProjecting: .noChange(.init(elementCount: 1))
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
            "target": matcherTarget(identifier: "myElement"),
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
        let result = try parseExpectation(["command": "activate"])
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedObject() async throws {
        let result = try parseExpectation(["expect": ["type": "screen_changed"]])
        XCTAssertEqual(result, .screenChanged)
    }

    func testNormalizeToolCallParsesExpectationPayloadAtCatalogEdge() throws {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "activate",
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "target": .object(["matcher": .object(["identifier": .string("submit")])]),
                "expect": .object(["type": .string("screen_changed")]),
                "timeout": .double(0.25),
            ])
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }

        XCTAssertEqual(operation.command, .activate)
        XCTAssertNil(operation.stringArgument("identifier"))
        XCTAssertNil(operation.stringArgument("expect"))
        XCTAssertEqual(operation.request.expectationPayload?.expectation, .screenChanged)
        XCTAssertEqual(operation.request.expectationPayload?.timeout, 0.25)
    }

    @ButtonHeistActor
    func testNormalizedToolOperationUsesTypedExpectationPayload() async throws {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "wait_for_change",
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "expect": .object(["type": .string("elements_changed")]),
            ])
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }

        XCTAssertNil(operation.stringArgument("expect"))
        XCTAssertEqual(operation.request.expectationPayload?.expectation, .elementsChanged)
    }

    func testNormalizeToolCallReportsExpectationParseFailure() {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "activate",
            arguments: TheFence.CommandArgumentEnvelope(values: ["expect": .string("screen_changed")])
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected routing failure, got \(result)")
        }
        XCTAssertEqual(error.message, "Invalid expectation type: expected object with a \"type\" discriminator")
    }

    func testNormalizeToolCallLeavesUnsupportedExpectationForRequestValidation() throws {
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "get_screen",
            arguments: TheFence.CommandArgumentEnvelope(values: ["expect": .string("screen_changed")])
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }
        XCTAssertEqual(operation.stringArgument("expect"), "screen_changed")
        XCTAssertNil(operation.request.expectationPayload)
    }

    @ButtonHeistActor
    func testParseExpectationStringValuesThrowObjectRequired() async {
        for value in ["screen_changed", "elements_changed", "element_updated", "layout_changed", "bogus"] {
            XCTAssertThrowsError(try parseExpectation(["expect": value])) { error in
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
        XCTAssertThrowsError(try parseExpectation(["expect": ["wrong": "key"]])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("\"type\" discriminator"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidTypeThrows() async {
        XCTAssertThrowsError(try parseExpectation(["expect": 42])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid expectation type"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationTopLevelArrayThrows() async {
        XCTAssertThrowsError(try parseExpectation([
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

        let result = try parseExpectation(operation.requestDecodeInputArguments())

        XCTAssertEqual(
            result,
            .elementUpdated(heistId: "counter", property: .value, newValue: "5")
        )
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorScreenChanged() async throws {
        let result = try parseExpectation([
            "expect": ["type": "screen_changed"]
        ])
        XCTAssertEqual(result, .screenChanged)
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseExpectation([
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
        XCTAssertThrowsError(try parseExpectation([
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
        let result = try parseExpectation([
            "expect": ["type": "element_updated"]
        ])
        XCTAssertEqual(result, .elementUpdated())
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithMatcher() async throws {
        let result = try parseExpectation([
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
    func testParseExpectationTypedPayloadPreservesMatcherTraits() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_disappeared"),
            "matcher": .object([
                "label": .string("Spinner"),
                "traits": .array([.string("button")]),
                "excludeTraits": .array([.string("selected")]),
            ]),
        ]))

        XCTAssertEqual(
            result,
            .elementDisappeared(
                ElementMatcher(label: "Spinner", traits: [.button], excludeTraits: [.selected])
            )
        )
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadBadMatcherFieldNamesField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "matcher": .object([
                "traits": .array([.int(7)]),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "matcher.traits[0]")
            XCTAssertEqual(error.expected, "string")
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsExtraKeysForType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("delivery"),
            "matcher": .object(["label": .string("Done")]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"delivery expectation does not accept "matcher""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsExtraMatcherKeys() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "matcher": .object([
                "label": .string("Done"),
                "unknown": .string("ignored before"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"expectation matcher does not accept "matcher.unknown""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadNonStringTypeNamesTypeField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .int(7),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("string \"type\" discriminator"))
            XCTAssertTrue(message.contains("type: 7"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationTypedCompoundBadNestedFieldNamesField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("compound"),
            "expectations": .array([
                .object([
                    "type": .string("element_updated"),
                    "property": .int(7),
                ]),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "expectations[0].property")
            XCTAssertEqual(error.expected, "string")
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithoutMatcherThrows() async {
        XCTAssertThrowsError(try parseExpectation([
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
        let result = try parseExpectation([
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
        XCTAssertThrowsError(try parseExpectation([
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
        XCTAssertThrowsError(try parseExpectation([
            "expect": ["type": "bogus_type"]
        ])) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown expectation type"))
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
                    "target": matcherTarget(identifier: "save-button"),
                    "expect": ["type": "elements_changed"],
                ],
            ]
        )

        guard let step = batch.steps.first else {
            return XCTFail("Expected planned batch step")
        }
        XCTAssertEqual(step.originalIndex, 0)
        XCTAssertEqual(step.commandName, "activate")
        XCTAssertEqual(step.typedStep.expectation, .elementsChanged)

        let singlePlan = try fence.clientMessageExecutionPlan(for: try fence.parseRequest(command: .activate, request: [
            "target": matcherTarget(identifier: "save-button"),
        ]))
        XCTAssertEqual(singlePlan.messages.count, 1)

        guard case .activate(let actionTarget) = step.typedStep.command else {
            return XCTFail("Expected activate command, got \(step.typedStep.command)")
        }
        XCTAssertEqual(actionTarget, .matcher(ElementMatcher(identifier: "save-button")))
        guard case .activate(let singleActionTarget)? = singlePlan.messages.first else {
            return XCTFail("Expected single activate command, got \(String(describing: singlePlan.messages.first))")
        }
        XCTAssertEqual(singleActionTarget, actionTarget)
    }

    @ButtonHeistActor
    func testBatchAndSingleCommandsUseSameClientMessageLowering() async throws {
        let (fence, _) = makeConnectedFence()
        let cases: [(command: TheFence.Command, request: [String: Any])] = [
            (.oneFingerTap, ["x": 12.0, "y": 34.0]),
            (.scroll, ["direction": "up"]),
            (.activate, ["target": matcherTarget(identifier: "save-button")]),
            (.waitFor, ["target": matcherTarget(identifier: "toast")]),
            (.setPasteboard, ["text": "copied"]),
        ]

        for testCase in cases {
            var step = testCase.request
            step["command"] = testCase.command.rawValue
            let batch = try decodedRunBatch(fence, steps: [step])
            guard let plannedStep = plannedBatchSteps(from: batch).first else {
                return XCTFail("Expected planned batch step for \(testCase.command.rawValue)")
            }
            let singleRequest = try fence.parseRequest(command: testCase.command, request: step)
            let singlePlan = try fence.clientMessageExecutionPlan(for: singleRequest)
            XCTAssertEqual(
                String(reflecting: singlePlan.messages),
                String(reflecting: [plannedStep.typedStep.command]),
                testCase.command.rawValue
            )
        }
    }

    @ButtonHeistActor
    func testBatchRejectsUnsupportedCommandsAtDecodeBoundary() async throws {
        let (fence, _) = makeConnectedFence()

        do {
            _ = try decodedRunBatch(
                fence,
                steps: [
                    ["command": "activate", "target": matcherTarget(label: "Save")],
                    ["command": "get_screen"],
                ] as [[String: Any]]
            )
            XCTFail("Expected unsupported batch command to fail at decode boundary")
        } catch FenceError.invalidRequest(let message) {
            XCTAssertTrue(message.contains("run_batch step command \"get_screen\" is not supported"))
        } catch {
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }

        let validBatch = try decodedRunBatch(
            fence,
            steps: [
                ["command": "activate", "target": matcherTarget(label: "Save")],
                ["command": "wait_for", "target": matcherTarget(identifier: "toast")],
                ["command": "wait_for_change", "expect": ["type": "screen_changed"]],
            ] as [[String: Any]]
        )
        XCTAssertEqual(validBatch.steps.map(\.commandName), ["activate", "wait_for", "wait_for_change"])
        XCTAssertEqual(validBatch.steps.map(\.originalIndex), [0, 1, 2])
    }

    @ButtonHeistActor
    func testBatchWaitDefaultsComeFromTypedCommand() async throws {
        let (fence, _) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                ["command": "wait_for", "target": matcherTarget(identifier: "toast")],
                ["command": "wait_for_change"],
            ] as [[String: Any]]
        )

        let steps = plannedBatchSteps(from: batch)
        XCTAssertEqual(steps[0].typedStep.expectation, .elementAppeared(ElementMatcher(identifier: "toast")))
        XCTAssertEqual(steps[0].typedStep.deadline, Deadline(timeout: 10.0))
        guard case .waitFor(let waitTarget) = steps[0].typedStep.command else {
            return XCTFail("Expected wait_for command, got \(steps[0].typedStep.command)")
        }
        XCTAssertNil(waitTarget.timeout)

        XCTAssertEqual(steps[1].typedStep.expectation, .screenChanged)
        XCTAssertEqual(steps[1].typedStep.deadline, Deadline(timeout: 30.0))
        guard case .waitForChange(let waitChangeTarget) = steps[1].typedStep.command else {
            return XCTFail("Expected wait_for_change command, got \(steps[1].typedStep.command)")
        }
        XCTAssertNil(waitChangeTarget.expect)
        XCTAssertNil(waitChangeTarget.timeout)
    }

    @ButtonHeistActor
    func testBatchPreparationRecognizesHeistIdTargetsWithoutLookup() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                ["command": "activate", "target": heistTarget("leaf-123")],
                ["command": "wait_for", "target": heistTarget("leaf-456")],
            ] as [[String: Any]]
        )

        XCTAssertTrue(mockConn.sent.isEmpty, "Batch normalization must not perform raw heistId lookup")
        let steps = plannedBatchSteps(from: batch)
        XCTAssertEqual(steps.map(\.commandName), ["activate", "wait_for"])

        guard case .activate(let actionTarget) = steps[0].typedStep.command else {
            return XCTFail("Expected activate command with heistId target")
        }
        XCTAssertEqual(actionTarget, .heistId("leaf-123"))

        XCTAssertEqual(steps[1].typedStep.expectation, .delivery)
    }

    @ButtonHeistActor
    func testBatchPreparationUsesNormalCommandTargetEnvelope() async throws {
        let (fence, _) = makeConnectedFence()

        let batch = try decodedRunBatch(
            fence,
            steps: [
                [
                    "command": "activate",
                    "target": matcherTarget(
                        traits: ["button"],
                        excludeTraits: ["header"],
                        ordinal: 1
                    ),
                ],
            ]
        )

        let steps = plannedBatchSteps(from: batch)
        guard case .activate(let actionTarget) = steps.first?.typedStep.command else {
            return XCTFail("Expected activate command")
        }
        XCTAssertEqual(actionTarget, .matcher(
            ElementMatcher(traits: [.button], excludeTraits: [.header]),
            ordinal: 1
        ))
    }

    @ButtonHeistActor
    func testBatchRoutedTargetRejectsInvalidTraitName() async {
        await assertRunBatchDecodeError(
            steps: [
                ["command": "activate", "target": ["matcher": ["traits": ["notATrait"]]]],
            ],
            contains: "schema validation failed for steps[0].target.matcher.traits[0]: observed string \"notATrait\"; expected enum one of"
        )
    }

    @ButtonHeistActor
    func testBatchRoutedTargetRejectsNonIntegerOrdinal() async {
        await assertRunBatchDecodeError(
            steps: [
                ["command": "activate", "target": ["matcher": ["label": "Save"], "ordinal": "first"]],
            ],
            contains: "schema validation failed for steps[0].target.ordinal: observed string \"first\"; expected integer"
        )
    }

    @ButtonHeistActor
    func testBatchRoutingReportsNonStringCommandClearly() async {
        await assertRunBatchDecodeError(
            steps: [
                ["command": 7, "target": matcherTarget(identifier: "btn")],
            ],
            contains: "run_batch step 0: schema validation failed for steps[0].command: observed integer 7; expected string"
        )
    }

    @ButtonHeistActor
    func testBatchRoutedTargetRejectsNegativeOrdinal() async {
        await assertRunBatchDecodeError(
            steps: [
                ["command": "activate", "target": ["matcher": ["label": "Save"], "ordinal": -1]],
            ],
            contains: "schema validation failed for steps[0].target.ordinal: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testBatchCountsOnlyExplicitExpectations() async throws {
        let (fence, mockConn) = makeConnectedFence()
        // Mock returns a successful action result with an elementsChanged delta (updates only)
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, traceProjecting: delta))
        }

        // Step 1 has expect → should count. Step 2 has no expect → should NOT count.
        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "btn1"), "expect": ["type": "elements_changed"]],
                ["command": "activate", "target": matcherTarget(identifier: "btn2")],
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
            .actionResult(ActionResult(success: true, method: .activate, traceProjecting: delta))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "btn1"), "expect": ["type": "screen_changed"]],
                ["command": "activate", "target": matcherTarget(identifier: "btn2"), "expect": ["type": "elements_changed"]],
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
                message: "first"
            ),
            ActionResult(
                success: true,
                method: .activate,
                message: "second"
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
                ["command": "activate", "target": matcherTarget(identifier: "first")],
                ["command": "activate", "target": matcherTarget(identifier: "second")],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            return XCTFail("Expected batch response, got \(response)")
        }
        XCTAssertEqual(batch.completedSteps, 2)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.results.compactMap { $0["message"] as? String }, ["first", "second"])
        XCTAssertEqual(batch.summaries.map(\.deltaKind), [nil, nil])
        XCTAssertNil(batch.results[0]["delta"])
        XCTAssertNil(batch.results[1]["delta"])

        let json = publicJSONObject(response)
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
                traceProjecting: .screenChanged(.init(
                    elementCount: 0,
                    newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
                )),
                accessibilityTrace: makeReceiptTestTrace(before: counter0, after: counter1)
            ),
            ActionResult(
                success: true,
                method: .activate,
                message: "second",
                traceProjecting: .noChange(.init(elementCount: 0)),
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
                ["command": "activate", "target": matcherTarget(identifier: "first")],
                ["command": "activate", "target": matcherTarget(identifier: "second")],
            ] as [[String: Any]],
        ])

        guard let batch = inspectBatch(response) else {
            return XCTFail("Expected batch response, got \(response)")
        }
        XCTAssertEqual(batch.summaries.map(\.deltaKind), ["elementsChanged", "elementsChanged"])
        XCTAssertEqual(batch.accessibilityTrace?.captures.count, 3)

        let json = publicJSONObject(response)
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
    func testBatchRejectsUnknownCommandAtRequestBoundary() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "not_a_real_command"],
                ["command": "activate", "target": matcherTarget(identifier: "btn1")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        XCTAssertTrue(message.contains("unknown command \"not_a_real_command\""))
        XCTAssertEqual(details?.errorCode, "request.invalid")
        XCTAssertFalse(
            mockConn.sent.contains { sent in
                if case .batchExecutionPlan = sent.0 { return true }
                return false
            },
            "Invalid run_batch input must not dispatch a partial plan"
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
                message: "activate failed: target could not be made actionable",
                errorKind: .actionFailed,
                traceProjecting: delta
            ))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "stale-button")],
                ["command": "activate", "target": matcherTarget(identifier: "later-button")],
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
        XCTAssertEqual(batch.summaries[0].error, "activate failed: target could not be made actionable")
        XCTAssertEqual(batch.summaries[1].error, "skipped: stop_on_error stopped batch after step 0")
    }

    @ButtonHeistActor
    func testBatchStopOnErrorRejectsInvalidStepBeforeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "btn1")],
                ["command": "not_a_real_command"],
                ["command": "activate", "target": matcherTarget(identifier: "btn2")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        XCTAssertTrue(message.contains("unknown command \"not_a_real_command\""))
        XCTAssertEqual(details?.errorCode, "request.invalid")
        XCTAssertTrue(mockConn.sent.isEmpty, "Invalid batch input must not dispatch valid sibling steps")
    }

    @ButtonHeistActor
    func testBatchExpectationFailureSummarizesSkippedSteps() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate, traceProjecting: delta))
        }

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "btn1"), "expect": ["type": "screen_changed"]],
                ["command": "activate", "target": matcherTarget(identifier: "btn2")],
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
    func testBatchRejectsUnknownStepParameterBeforeExecution() async {
        await assertValidationError([
            "command": "run_batch",
            "steps": [
                ["command": "scroll", "unexpected": "value", "target": matcherTarget(label: "Done")],
            ] as [[String: Any]],
        ], contains: "run_batch step 0: Unknown parameter 'unexpected' for scroll")
    }

    @ButtonHeistActor
    func testBatchAllowsContainerTargetedScrollThroughNormalCommandPath() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .scroll))
        }

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
        XCTAssertEqual(batch.results.count, 1)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.summaries.map(\.command), ["scroll"])
        let batchPlans = mockConn.sent.compactMap { sent -> BatchPlan? in
            if case .batchExecutionPlan(let plan) = sent.0 { return plan }
            return nil
        }
        XCTAssertEqual(batchPlans.count, 1)
        guard case .scroll(let target)? = batchPlans.first?.steps.first?.command else {
            return XCTFail("Expected scroll command")
        }
        XCTAssertEqual(target.containerTarget?.stableId, "main_scroll")
        XCTAssertEqual(target.direction, .down)
    }

    @ButtonHeistActor
    func testBatchRejectsTooManyStepsBeforeExecution() async {
        let steps = Array(
            repeating: ["command": "activate", "target": matcherTarget(identifier: "btn")],
            count: TheFence.DecodeLimits.maxRunBatchSteps + 1
        )
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
                    [
                        "command": "activate",
                        "target": matcherTarget(identifier: "btn"),
                        "expect": nested(TheFence.DecodeLimits.maxRunBatchNestingDepth),
                    ],
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
                    ["command": "activate", "target": matcherTarget(identifier: payload)],
                ] as [[String: Any]],
            ],
            contains: "expected JSON request <= \(TheFence.DecodeLimits.maxRunBatchRequestBytes) bytes"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsNonBatchExecutableCommandsBeforeExecution() async {
        let nonBatchCommands = TheFence.Command.descriptors
            .filter { !$0.isBatchExecutable }
            .map(\.command)

        for command in nonBatchCommands {
            await assertValidationError([
                "command": "run_batch",
                "steps": [
                    ["command": command.rawValue],
                ] as [[String: Any]],
            ], contains: "run_batch step command \"\(command.rawValue)\" is not supported")
        }
    }

    @ButtonHeistActor
    func testBatchRejectsGetScreenBeforePayloadValidation() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "steps": [
                ["command": "get_screen", "inlineData": true],
                ["command": "activate", "target": matcherTarget(identifier: "skipped")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        XCTAssertTrue(message.contains("run_batch step command \"get_screen\" is not supported"), message)
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
                ["command": "swipe", "target": heistTarget("row_1"), "direction": "left"],
                ["command": "scroll_to_visible", "target": matcherTarget(label: "Done")],
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

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "continue_on_error",
            "steps": [
                ["command": "type_text", "text": ""],
                ["command": "activate", "target": matcherTarget(identifier: "btn")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        let expectedError = "schema validation failed for steps[0].text: observed string \"\"; expected non-empty string"
        XCTAssertEqual(message, expectedError)
        XCTAssertTrue(mockConn.sent.isEmpty, "Invalid batch input must not dispatch valid sibling steps")
    }

    @ButtonHeistActor
    func testBatchReportsUnknownCanonicalCommandWithStepIndex() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "activate", "target": matcherTarget(identifier: "first")],
                ["command": "unknown_command"],
                ["command": "activate", "target": matcherTarget(identifier: "skipped")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        let expectedError = "run_batch step 1: run_batch step command must be a canonical TheFence.Command; unknown command \"unknown_command\""
        XCTAssertEqual(message, expectedError)
        XCTAssertTrue(mockConn.sent.isEmpty, "Invalid batch input must not dispatch valid sibling steps")
    }

    @ButtonHeistActor
    func testBatchPreservesContractErrorPhaseAndNextCommand() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(request: [
            "command": "run_batch",
            "policy": "stop_on_error",
            "steps": [
                ["command": "wait_for"],
                ["command": "activate", "target": matcherTarget(identifier: "skipped")],
            ] as [[String: Any]],
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected request-boundary error, got \(response)")
        }
        XCTAssertTrue(message.contains("wait_for request contract failed: missing target"), message)
        XCTAssertEqual(details?.phase, .request)
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
    }

    @ButtonHeistActor
    func testUnexpectedParameterIsRejectedByCommandContract() async {
        await assertValidationError(
            ["command": "activate", "target": matcherTarget(identifier: "save"), "mode": "tap"],
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

        let json = publicJSONObject(response)
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

        let json = publicJSONObject(response)
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

        let json = publicJSONObject(response)
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

        let json = publicJSONObject(response)
        let responseInterface = json["interface"] as! [String: Any]
        let tree = responseInterface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 1)
        let element = tree[0]["element"] as! [String: Any]
        XCTAssertEqual(element["heistId"] as? String, "submit")
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
                ["command": "activate", "target": matcherTarget(identifier: "btn1")],
                ["command": "activate", "target": matcherTarget(identifier: "btn2")],
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
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn2")),
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn3")),
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
                        target: semanticTarget(identifier: "email", ordinal: 1),
                        arguments: ["text": .string("user@example.com")],
                        recorded: RecordedMetadata(heistId: "recorded-email")
                    ),
                    HeistEvidence(command: "activate", target: semanticTarget(identifier: "submit")),
                ]
            )
        )
        let operation = playback.steps[0]

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.totalStepCount, 2)
        XCTAssertEqual(operation.command, .typeText)
        XCTAssertEqual(playback.steps[1].command, .activate)
        XCTAssertEqual(operation.target?.matcher.identifier, "email")
        XCTAssertEqual(operation.target?.ordinal, 1)

        let normalizedOperation = operation.normalizedOperation()
        XCTAssertEqual(normalizedOperation.command, .typeText)
        XCTAssertNil(normalizedOperation.stringArgument("identifier"))
        XCTAssertEqual(normalizedOperation.stringArgument("text"), "user@example.com")
        XCTAssertNil(normalizedOperation.stringArgument("_recorded"))
    }

    @ButtonHeistActor
    func testTypedPlaybackLoadsHeistFileAtFileEdge() async throws {
        let heist = HeistPlayback(
            app: "com.test.mock",
            steps: [
                HeistEvidence(
                    command: "activate",
                    target: semanticTarget(identifier: "submit"),
                    arguments: ["expect": .object(["type": .string("screen_changed")])]
                ),
            ]
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let playback = try TheFence.TypedHeistPlayback(contentsOf: heistURL)

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.steps.map(\.command), [.activate])
        XCTAssertEqual(playback.steps.first?.target?.matcher.identifier, "submit")
        let expect = playback.steps.first?.requestDecodeInputArguments()["expect"] as? [String: Any]
        XCTAssertEqual(expect?["type"] as? String, "screen_changed")
    }

    @ButtonHeistActor
    func testTypedPlaybackFileEdgeRejectsUnsupportedVersion() async throws {
        let heist = HeistPlayback(
            version: HeistPlayback.currentVersion + 1,
            app: "com.test.mock",
            steps: [HeistEvidence(command: "activate", target: semanticTarget(identifier: "submit"))]
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
                target: semanticTarget(identifier: "email"),
                arguments: ["expect": .object(["type": .string("screen_changed")])]
            ),
            index: 0
        )

        let expect = operation.requestDecodeInputArguments()["expect"] as? [String: Any]
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
    func testTypedPlaybackRejectsUnknownCommandName() async throws {
        XCTAssertThrowsError(
            try TheFence.TypedHeistPlayback(
                wire: HeistPlayback(
                    app: "com.test.mock",
                    steps: [
                        HeistEvidence(
                            command: "unknown_command",
                            arguments: [:]
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
                message.contains("heist step command must be a canonical TheFence.Command; unknown command \"unknown_command\""),
                "Unexpected error: \(message)"
            )
        }
    }

    @ButtonHeistActor
    func testPlaybackInvalidCurrentShapeUsesRequestValidation() async throws {
        let cases: [(name: String, operation: TheFence.PlaybackOperation, message: String)] = [
            (
                "unknown scroll parameter",
                try TheFence.PlaybackOperation(
                    evidence: HeistEvidence(
                        command: "scroll",
                        arguments: ["unexpected": .string("value")]
                    ),
                    index: 0
                ),
                "schema validation failed for unexpected: observed string \"value\"; expected valid scroll parameter"
            ),
            (
                "edit_action invalid action type",
                try TheFence.PlaybackOperation(
                    evidence: HeistEvidence(
                        command: "edit_action",
                        arguments: ["action": .int(7)]
                    ),
                    index: 0
                ),
                "schema validation failed for action: observed integer 7; expected string"
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
            evidence: HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
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
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "offscreen")),
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
    func testPlayHeistMapsServerErrorResponseToCommandFailure() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            case .activate:
                return .error(ServerError(kind: .general, message: "server exploded"))
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

        guard case .fenceError(let step, let message, _, _) = failure else {
            return XCTFail("Expected typed fenceError playback failure, got \(String(describing: failure))")
        }
        XCTAssertEqual(step.command, "activate")
        XCTAssertTrue(message.contains("server exploded"))

        guard case .failed(let reportMessage, let errorKind) = report?.steps.first?.outcome else {
            return XCTFail("Expected failed playback report step, got \(String(describing: report?.steps.first))")
        }
        XCTAssertEqual(reportMessage, message)
        XCTAssertEqual(errorKind, .commandError)
    }

    @ButtonHeistActor
    func testPlayHeistPreservesPlaybackFailureWhenDiagnosticInterfaceCaptureFails() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
        ])
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, mockConn) = makeConnectedFence()
        var interfaceRequestCount = 0
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                interfaceRequestCount += 1
                guard interfaceRequestCount > 1 else {
                    return .interface(Interface(timestamp: Date(), tree: []))
                }
                return .error(ServerError(
                    kind: .general,
                    message: "diagnostic interface unavailable"
                ))
            case .activate:
                return .actionResult(ActionResult(
                    success: false,
                    method: .elementNotFound,
                    message: "missing",
                    errorKind: .elementNotFound
                ))
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

        guard case .actionFailed(let step, let result, _, let interface, let diagnosticCaptureFailure) = failure else {
            return XCTFail("Expected actionFailed playback failure, got \(String(describing: failure))")
        }
        XCTAssertEqual(step.command, "activate")
        XCTAssertEqual(result.method, .elementNotFound)
        XCTAssertEqual(result.message, "missing")
        XCTAssertNil(interface)
        XCTAssertEqual(diagnosticCaptureFailure, "Action failed: diagnostic interface unavailable")

        guard case .failed(let reportMessage, let errorKind) = report?.steps.first?.outcome else {
            return XCTFail("Expected failed playback report step, got \(String(describing: report?.steps.first))")
        }
        XCTAssertEqual(reportMessage, "missing")
        XCTAssertEqual(errorKind, .action(.elementNotFound))

        XCTAssertEqual(interfaceRequestCount, 2)
        let activateMessages = mockConn.sent.filter { message, _ in
            if case .activate = message { return true }
            return false
        }
        XCTAssertEqual(activateMessages.count, 1)
    }

    @ButtonHeistActor
    func testPlaybackDoesNotUseRecordedHeistIdAsAuthority() async throws {
        let operation = try TheFence.PlaybackOperation(
            evidence: HeistEvidence(
                command: "activate",
                target: semanticTarget(identifier: "btn1"),
                recorded: RecordedMetadata(heistId: "stale_debug_id")
            ),
            index: 0
        )

        let arguments = operation.requestDecodeInputArguments()
        let target = try XCTUnwrap(arguments["target"] as? [String: Any])
        let matcher = try XCTUnwrap(target["matcher"] as? [String: Any])
        XCTAssertEqual(matcher["identifier"] as? String, "btn1")
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
                target: semanticTarget(identifier: "btn1"),
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
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
            HeistEvidence(command: "not_a_real_command"),
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn3")),
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
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
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
        try fence.playback.begin()
        defer { fence.playback.end() }

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
    func testPlayHeistInvalidInputResetsPlaybackLifecycle() async throws {
        let (fence, _) = makeConnectedFence()

        do {
            _ = try await fence.execute(request: [
                "command": "play_heist", "input": "../bad.heist",
            ])
            XCTFail("Expected invalid input to fail")
        } catch FenceError.invalidRequest(let message) {
            XCTAssertEqual(message, "Invalid input path: must not be empty or contain '..' components")
        } catch {
            XCTFail("Expected invalidRequest, got \(error)")
        }

        XCTAssertTrue(fence.playback.isIdle)
    }

    @ButtonHeistActor
    func testPlayHeistReportsTimingMs() async throws {
        let heist = HeistPlayback(app: "com.test.mock", steps: [
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
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
            HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1")),
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

}

private func heistTarget(_ heistId: String) -> [String: Any] {
    ["heistId": heistId]
}

private func matcherTarget(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    excludeTraits: [String]? = nil,
    ordinal: Int? = nil
) -> [String: Any] {
    var matcher: [String: Any] = [:]
    matcher["label"] = label
    matcher["identifier"] = identifier
    matcher["value"] = value
    matcher["traits"] = traits
    matcher["excludeTraits"] = excludeTraits
    var target: [String: Any] = ["matcher": matcher]
    target["ordinal"] = ordinal
    return target
}

private func parseExpectation(_ request: [String: Any]) throws -> ActionExpectation? {
    try TheFence.ExpectationPayload(
        arguments: TheFence.CommandArgumentEnvelope(arguments: request)
    ).expectation
}

private func parseTypedExpectation(_ expectation: HeistValue?) throws -> ActionExpectation? {
    var values: [String: HeistValue] = [:]
    if let expectation {
        values["expect"] = expectation
    }
    return try TheFence.ExpectationPayload(
        arguments: TheFence.CommandArgumentEnvelope(values: values)
    ).expectation
}
