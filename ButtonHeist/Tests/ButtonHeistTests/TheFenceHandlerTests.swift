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

    /// Assert that executing a typed operation returns a `.error(...)` response containing the substring.
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
            let response = try await fence.execute(command: command, values: arguments)
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

    /// Assert that executing a typed operation returns a `.error(...)` response with the exact message.
    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
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
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains expectedSubstrings: [String],
        errorCode: String,
        nextCommand: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
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

    /// Assert that executing a typed operation passes validation (returns a non-error response).
    @ButtonHeistActor
    private func assertPassesValidation(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let message, _) = response {
                XCTFail("Got validation error: \(message)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertOperationValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(operation: normalizedOperation(command: command, arguments: arguments))
            if case .error(let message, _) = response {
                XCTAssertTrue(
                    message.contains(substring),
                    "Expected error containing '\(substring)', got: \(message)",
                    file: file,
                    line: line
                )
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertOperationValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(operation: normalizedOperation(command: command, arguments: arguments))
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
    private func assertOperationPassesValidation(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(operation: normalizedOperation(command: command, arguments: arguments))
            if case .error(let message, _) = response {
                XCTFail("Got validation error: \(message)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func decodedElementTarget(
        target: HeistValue? = nil
    ) throws -> ElementTarget? {
        var arguments: [String: HeistValue] = [:]
        if let target {
            arguments["target"] = target
        }
        return try TheFence.CommandArgumentEnvelope(values: arguments).elementTarget()
    }

    @ButtonHeistActor
    private func decodedRunBatch(
        _ fence: TheFence,
        steps: [HeistValue],
        policy: String? = nil
    ) throws -> TheFence.RunBatchRequest {
        var values: [String: HeistValue] = ["steps": .array(steps)]
        if let policy {
            values["policy"] = .string(policy)
        }
        return try fence.decodeRunBatchRequest(TheFence.CommandArgumentEnvelope(values: values))
    }

    @ButtonHeistActor
    private func assertRunBatchDecodeError(
        steps: [HeistValue],
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

    @ButtonHeistActor
    private func executeRunBatch(
        _ fence: TheFence,
        steps: [HeistValue],
        policy: String? = nil
    ) async throws -> FenceResponse {
        var values: [String: HeistValue] = ["steps": .array(steps)]
        if let policy {
            values["policy"] = .string(policy)
        }
        return try await fence.execute(command: .runBatch, values: values)
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
        let statusRequest = try fence.parseRequest(command: .getSessionState, values: ["requestId": .string("r1")])
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
        let response = try await fence.execute(command: .connect)

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

    func testCommandArgumentEnvelopeReadsTypedScalarValues() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "bool": .bool(true),
            "int": .int(3),
            "double": .double(2.5),
        ])

        XCTAssertEqual(try envelope.schemaBoolean("bool"), true)
        XCTAssertEqual(try envelope.schemaInteger("int"), 3)
        XCTAssertEqual(try envelope.schemaNumber("double"), 2.5)
        XCTAssertNil(envelope.observedDescription(for: "missing"))
    }

    func testCommandArgumentEnvelopeReadsNestedTypedValues() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "object": .object([
                "label": .string("Pay"),
                "traits": .array([.string("button"), .string("selected")]),
            ]),
            "array": .array([
                .object(["x": .double(0.25), "y": .double(0.75)]),
                .object(["x": .double(0.5), "y": .double(0.5)]),
            ]),
        ])

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
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "subtree": .object([
                "element": .object([
                    "label": .string("Pay"),
                    "traits": .array([.string("button"), .string("selected")]),
                ]),
                "container": .object([
                    "type": .string("scrollable"),
                    "isModalBoundary": .bool(true),
                    "ratio": .double(0.5),
                ]),
                "ordinal": .int(2),
            ]),
        ])

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
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "subtree": .object([
                "element": .object([
                    "traits": .array([.int(7)]),
                ]),
            ]),
        ])

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
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "points": .array([
                .object(["x": .double(0.25), "y": .double(0.75)]),
                .object(["x": .int(1), "y": .int(2)]),
            ]),
        ])

        let points = try envelope.requiredSchemaObjectArray("points")
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(try points[0].requiredSchemaNumber("x"), 0.25)
        XCTAssertEqual(try points[0].requiredSchemaNumber("y"), 0.75)
        XCTAssertEqual(try points[1].requiredSchemaNumber("x"), 1)
        XCTAssertEqual(try points[1].requiredSchemaNumber("y"), 2)
    }

    func testCommandArgumentEnvelopeObjectArrayErrorsUseIndexedFields() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "points": .array([
                .object(["x": .string("bad")]),
            ]),
        ])

        let points = try envelope.requiredSchemaObjectArray("points")
        XCTAssertThrowsError(try points[0].requiredSchemaNumber("x")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for points[0].x: observed string \"bad\"; expected number"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsUnitPoint() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "start": .object(["x": .double(0.25), "y": .double(0.75)]),
        ])

        XCTAssertEqual(try envelope.schemaUnitPoint("start"), UnitPoint(x: 0.25, y: 0.75))
    }

    func testCommandArgumentEnvelopeUnitPointErrorsUseQualifiedFields() throws {
        let missingField = TheFence.CommandArgumentEnvelope(values: [
            "start": .object(["x": .double(0.25)]),
        ])
        XCTAssertThrowsError(try missingField.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.y: observed missing; expected number"
            )
        }

        let outOfRange = TheFence.CommandArgumentEnvelope(values: [
            "start": .object(["x": .double(1.2), "y": .double(0.5)]),
        ])
        XCTAssertThrowsError(try outOfRange.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.x: observed number 1.2; expected number in 0...1"
            )
        }

        let extraField = TheFence.CommandArgumentEnvelope(values: [
            "start": .object(["x": .double(0.25), "y": .double(0.75), "z": .double(0.5)]),
        ])
        XCTAssertThrowsError(try extraField.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start.z: observed number 0.5; expected valid unit point field"
            )
        }
    }

    func testCommandArgumentEnvelopeUnitPointRejectsNonObjectWithSpecificExpectedShape() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "start": .string("left"),
        ])

        XCTAssertThrowsError(try envelope.schemaUnitPoint("start")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for start: observed string \"left\"; expected object with numeric x and y"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsRequiredEnum() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            "direction": .string("up"),
        ])

        XCTAssertEqual(
            try envelope.requiredSchemaEnum("direction", as: SwipeDirection.self),
            .up
        )
    }

    func testCommandArgumentEnvelopeRequiredEnumErrorsUseExpectedCases() throws {
        let missing = TheFence.CommandArgumentEnvelope(values: [:])
        XCTAssertThrowsError(try missing.requiredSchemaEnum("direction", as: SwipeDirection.self)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for direction: observed missing; expected enum one of up, down, left, right"
            )
        }

        let invalid = TheFence.CommandArgumentEnvelope(values: [
            "direction": .string("diagonal"),
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
        guard let target = try decodedElementTarget(target: targetValue(identifier: "myButton")),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.identifier, "myButton")
    }

    @ButtonHeistActor
    func testElementTargetWithHeistId() async throws {
        guard let target = try decodedElementTarget(target: heistTargetValue("button_save")),
              case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "button_save")
    }

    @ButtonHeistActor
    func testElementTargetWithMatcherFields() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save", traits: ["button"])),
              case .matcher(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
    }

    @ButtonHeistActor
    func testElementTargetRejectsHeistIdAndMatcher() async throws {
        XCTAssertThrowsError(
            try decodedElementTarget(
                target: elementTargetValue([
                    "heistId": .string("button_save"),
                    "label": .string("Save"),
                ])
            )
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("ElementTarget heistId cannot be combined with matcher fields or ordinal"),
                "Expected mixed selector rejection, got \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetRejectsHeistIdAndOrdinal() async throws {
        XCTAssertThrowsError(
            try decodedElementTarget(
                target: elementTargetValue([
                    "heistId": .string("button_save"),
                    "ordinal": .int(1),
                ])
            )
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("ElementTarget heistId cannot be combined with matcher fields or ordinal"),
                "Expected heistId+ordinal rejection, got \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetRejectsUnknownTargetField() async throws {
        XCTAssertThrowsError(
            try decodedElementTarget(
                target: elementTargetValue([
                    "label": .string("Save"),
                    "unexpectedTargetField": .string("button_save"),
                ])
            )
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("unexpectedTargetField"),
                "Expected unknown target field rejection, got \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetWithOrdinal() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save", ordinal: 2)),
              case .matcher(let matcher, let ordinal) = target else {
            return XCTFail("Expected .matcher with ordinal")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(ordinal, 2)
    }

    @ButtonHeistActor
    func testRequestTargetRejectsNegativeOrdinal() async {
        await assertOperationValidationError(
            command: .activate,
            arguments: ["target": targetValue(label: "Save", ordinal: -1)],
            equals: "schema validation failed for target.ordinal: observed integer -1; expected ordinal must be non-negative, got -1"
        )
    }

    @ButtonHeistActor
    func testElementTargetWithoutOrdinal() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save")),
              case .matcher(_, let ordinal) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testElementTargetMissing() async throws {
        XCTAssertNil(try decodedElementTarget())
    }

    // MARK: - Schema Validation Diagnostics

    @ButtonHeistActor
    func testSchemaValidationReportsBadFieldType() async {
        await assertOperationValidationError(
            command: .typeText,
            arguments: ["text": .int(3)],
            equals: "schema validation failed for text: observed integer 3; expected string"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationReportsBadCoercedValue() async {
        await assertOperationValidationError(
            command: .waitForChange,
            arguments: ["timeout": .string("forever")],
            equals: "schema validation failed for timeout: observed string \"forever\"; expected number"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationReportsRangeFailure() async {
        await assertOperationValidationError(
            command: .startRecording,
            arguments: ["fps": .int(16)],
            equals: "schema validation failed for fps: observed integer 16; expected integer in 1...15"
        )
    }

    @ButtonHeistActor
    func testSchemaValidatedStrictTypesStillWork() async {
        await assertOperationPassesValidation(
            command: .startRecording,
            arguments: ["fps": .int(5)]
        )
        await assertOperationPassesValidation(
            command: .startRecording,
            arguments: ["scale": .double(0.5)]
        )
    }

    @ButtonHeistActor
    func testSchemaValidationRejectsStringIntegerCoercion() async {
        await assertOperationValidationError(
            command: .startRecording,
            arguments: ["fps": .string("5")],
            equals: "schema validation failed for fps: observed string \"5\"; expected integer"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationRejectsStringNumberCoercion() async {
        await assertOperationValidationError(
            command: .startRecording,
            arguments: ["scale": .string("0.5")],
            equals: "schema validation failed for scale: observed string \"0.5\"; expected number"
        )
    }

    // MARK: - Gesture Validation

    @ButtonHeistActor
    func testOneFingerTapMissingTarget() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            contains: "Must specify target object"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["x": .double(100.0), "y": .double(200.0)]
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsPartialCoordinates() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["x": .double(100.0)],
            equals: "schema validation failed for x/y: observed partial coordinates; expected both x and y, or neither"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsNaNCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["x": .double(Double.nan), "y": .double(200.0)],
            equals: "schema validation failed for x: observed number nan; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsInfiniteCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["x": .double(Double.infinity), "y": .double(200.0)],
            equals: "schema validation failed for x: observed number inf; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithIdentifierPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["target": targetValue(identifier: "myButton")]
        )
    }

    @ButtonHeistActor
    func testGestureTargetRejectsHeistIdAndMatcher() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: [
                "target": elementTargetValue([
                    "heistId": .string("button_save"),
                    "label": .string("Save"),
                ]),
            ],
            contains: "ElementTarget heistId cannot be combined with matcher fields or ordinal"
        )
    }

    @ButtonHeistActor
    func testLongPressMissingTarget() async {
        await assertOperationValidationError(
            command: .longPress,
            contains: "Must specify target object"
        )
    }

    @ButtonHeistActor
    func testLongPressWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .longPress,
            arguments: ["x": .double(50.0), "y": .double(50.0)]
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsNegativeDuration() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: ["x": .double(50.0), "y": .double(50.0), "duration": .double(-1.0)],
            equals: "schema validation failed for duration: observed number -1.0; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsOversizedDurationBeforeExecution() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: ["x": .double(50.0), "y": .double(50.0), "duration": .double(61.0)],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
        )
    }

    @ButtonHeistActor
    func testSwipeInvalidDirection() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: ["direction": .string("diagonal")],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithoutTargetOrCoordinatesIsRejected() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: ["direction": .string("up")],
            equals: "Swipe requires target object or start coordinates (startX, startY)"
        )
    }

    @ButtonHeistActor
    func testSwipeRejectsPartialStartCoordinates() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "startX": .double(10.0),
                "endX": .double(100.0),
                "endY": .double(200.0),
            ],
            equals: "schema validation failed for startX/startY: observed partial coordinates; " +
                "expected both startX and startY, or neither"
        )
    }

    @ButtonHeistActor
    func testSwipeWithUnitPointsPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: [
                "target": heistTargetValue("row_5"),
                "start": .object(["x": .double(0.8), "y": .double(0.5)]),
                "end": .object(["x": .double(0.2), "y": .double(0.5)]),
            ]
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsRejectOutOfRangeCoordinate() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "target": heistTargetValue("row_5"),
                "start": .object(["x": .double(1.2), "y": .double(0.5)]),
                "end": .object(["x": .double(0.2), "y": .double(0.5)]),
            ],
            equals: "schema validation failed for start.x: observed number 1.2; expected number in 0...1"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: ["target": heistTargetValue("row_5"), "direction": .string("left")]
        )
    }

    @ButtonHeistActor
    func testDragMissingEndCoordinates() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: ["startX": .double(10.0), "startY": .double(10.0)],
            equals: "schema validation failed for endX: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testDragWithoutStartTargetIsRejected() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: ["endX": .double(100.0), "endY": .double(200.0)],
            equals: "Drag requires target object or start coordinates (startX, startY)"
        )
    }

    @ButtonHeistActor
    func testDragWithElementTargetAndEndCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .drag,
            arguments: [
                "target": heistTargetValue("source"),
                "endX": .double(100.0),
                "endY": .double(200.0),
            ]
        )
    }

    @ButtonHeistActor
    func testDragWithStartCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .drag,
            arguments: [
                "startX": .double(100.0),
                "startY": .double(300.0),
                "endX": .double(300.0),
                "endY": .double(600.0),
            ]
        ))
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
        await assertOperationValidationError(
            command: .pinch,
            equals: "schema validation failed for scale: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testPinchRequiresCenter() async {
        await assertOperationValidationError(
            command: .pinch,
            arguments: ["scale": .double(2.0)],
            equals: "center requires an element target or center coordinates"
        )
    }

    @ButtonHeistActor
    func testPinchWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .pinch,
            arguments: [
                "scale": .double(2.0),
                "centerX": .double(200.0),
                "centerY": .double(500.0),
            ]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .pinch(let target) = message else {
            XCTFail("Expected pinch message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 200.0, y: 500.0)))
    }

    @ButtonHeistActor
    func testPinchWithIdentifierDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .pinch,
            arguments: [
                "scale": .double(2.0),
                "target": targetValue(identifier: "map"),
            ]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .pinch(let target) = message else {
            XCTFail("Expected pinch message")
            return
        }
        XCTAssertEqual(target.center, .element(.matcher(ElementMatcher(identifier: "map"))))
    }

    @ButtonHeistActor
    func testRotateWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .rotate,
            arguments: [
                "angle": .double(1.57),
                "centerX": .double(150.0),
                "centerY": .double(400.0),
            ]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .rotate(let target) = message else {
            XCTFail("Expected rotate message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 150.0, y: 400.0)))
    }

    @ButtonHeistActor
    func testRotateWithIdentifierDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .rotate,
            arguments: [
                "angle": .double(1.57),
                "target": targetValue(identifier: "dial"),
            ]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .rotate(let target) = message else {
            XCTFail("Expected rotate message")
            return
        }
        XCTAssertEqual(target.center, .element(.matcher(ElementMatcher(identifier: "dial"))))
    }

    @ButtonHeistActor
    func testRotateMissingAngle() async {
        await assertOperationValidationError(
            command: .rotate,
            equals: "schema validation failed for angle: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testRotateRequiresCenter() async {
        await assertOperationValidationError(
            command: .rotate,
            arguments: ["angle": .double(1.57)],
            equals: "center requires an element target or center coordinates"
        )
    }

    // MARK: - Two Finger Tap

    @ButtonHeistActor
    func testTwoFingerTapWithCenterCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .twoFingerTap,
            arguments: [
                "centerX": .double(200.0),
                "centerY": .double(500.0),
            ]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .twoFingerTap(let target) = message else {
            XCTFail("Expected twoFingerTap message")
            return
        }
        XCTAssertEqual(target.center, .coordinate(ScreenPoint(x: 200.0, y: 500.0)))
    }

    @ButtonHeistActor
    func testTwoFingerTapWithIdentifierDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(operation: normalizedOperation(
            command: .twoFingerTap,
            arguments: ["target": targetValue(identifier: "photo")]
        ))
        guard let (message, _) = mockConn.sent.last,
              case .twoFingerTap(let target) = message else {
            XCTFail("Expected two finger tap message")
            return
        }
        XCTAssertEqual(target.center, .element(.matcher(ElementMatcher(identifier: "photo"))))
    }

    // MARK: - Draw Path Validation

    @ButtonHeistActor
    func testDrawPathMissingPoints() async {
        await assertValidationError(
            command: .drawPath,
            equals: "schema validation failed for points: observed missing; expected array of objects"
        )
    }

    @ButtonHeistActor
    func testDrawPathTooFewPoints() async {
        await assertValidationError(
            command: .drawPath,
            arguments: ["points": .array([.object(["x": .double(1.0), "y": .double(2.0)])])],
            contains: "at least 2 points"
        )
    }

    @ButtonHeistActor
    func testDrawPathInvalidPointData() async {
        await assertValidationError(
            command: .drawPath,
            arguments: [
                "points": .array([
                    .object(["x": .string("bad"), "y": .string("data")]),
                    .object(["x": .double(0.0), "y": .double(0.0)]),
                ]),
            ],
            equals: "schema validation failed for points[0].x: observed string \"bad\"; expected number"
        )
    }

    @ButtonHeistActor
    func testDrawPathRejectsExtraPointFields() async {
        await assertValidationError(
            command: .drawPath,
            arguments: [
                "points": .array([
                    .object(["x": .double(0.0), "y": .double(0.0), "pressure": .double(0.5)]),
                    .object(["x": .double(1.0), "y": .double(1.0)]),
                ]),
            ],
            equals: "schema validation failed for points[0].pressure: observed number 0.5; expected Unknown draw path point field \"pressure\""
        )
    }

    @ButtonHeistActor
    func testDrawPathRejectsTooManyPointsBeforeExecution() async {
        let points = (0...TheFence.DecodeLimits.maxDrawPathPoints).map { index in
            HeistValue.object(["x": .double(Double(index)), "y": .double(Double(index))])
        }
        await assertValidationError(
            command: .drawPath,
            arguments: ["points": .array(points)],
            equals: "schema validation failed for points: observed array count 10001; expected array count 2...10000 (at least 2 points)"
        )
    }

    @ButtonHeistActor
    func testDrawPathRejectsOversizedDurationBeforeExecution() async {
        await assertValidationError(
            command: .drawPath,
            arguments: [
                "points": .array([
                    .object(["x": .double(0.0), "y": .double(0.0)]),
                    .object(["x": .double(1.0), "y": .double(1.0)]),
                ]),
                "duration": .double(61.0),
            ],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
        )
    }

    @ButtonHeistActor
    func testDrawPathValidPassesValidation() async {
        await assertPassesValidation(
            command: .drawPath,
            arguments: [
                "points": .array([
                    .object(["x": .double(0.0), "y": .double(0.0)]),
                    .object(["x": .double(100.0), "y": .double(100.0)]),
                ]),
            ]
        )
    }

    // MARK: - Draw Bezier Validation

    @ButtonHeistActor
    func testDrawBezierMissingStart() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: [
                "segments": .array([
                    .object([
                        "cp1X": .double(10.0), "cp1Y": .double(20.0),
                        "cp2X": .double(30.0), "cp2Y": .double(40.0),
                        "endX": .double(50.0), "endY": .double(60.0),
                    ]),
                ]),
            ],
            equals: "schema validation failed for startX: observed missing; expected present"
        )
    }

    @ButtonHeistActor
    func testDrawBezierMissingSegments() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: ["startX": .double(0.0), "startY": .double(0.0)],
            equals: "schema validation failed for segments: observed missing; expected array of objects"
        )
    }

    @ButtonHeistActor
    func testDrawBezierEmptySegments() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: ["startX": .double(0.0), "startY": .double(0.0), "segments": .array([])],
            contains: "At least 1 bezier segment"
        )
    }

    @ButtonHeistActor
    func testDrawBezierInvalidSegment() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: [
                "startX": .double(0.0),
                "startY": .double(0.0),
                "segments": .array([.object(["cp1X": .double(1.0), "cp1Y": .double(2.0)])]),
            ],
            equals: "schema validation failed for segments[0].cp2X: observed missing; expected present"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsExtraSegmentFields() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: [
                "startX": .double(0.0),
                "startY": .double(0.0),
                "segments": .array([
                    .object([
                        "cp1X": .double(1.0), "cp1Y": .double(2.0),
                        "cp2X": .double(3.0), "cp2Y": .double(4.0),
                        "endX": .double(5.0), "endY": .double(6.0),
                        "weight": .double(0.5),
                    ]),
                ]),
            ],
            equals: "schema validation failed for segments[0].weight: observed number 0.5; expected Unknown bezier segment field \"weight\""
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsTooManySegmentsBeforeExecution() async {
        let segment = HeistValue.object([
            "cp1X": .double(10.0), "cp1Y": .double(20.0), "cp2X": .double(30.0),
            "cp2Y": .double(40.0), "endX": .double(50.0), "endY": .double(60.0),
        ])
        let segments = Array(repeating: segment, count: TheFence.DecodeLimits.maxDrawBezierSegments + 1)
        await assertValidationError(
            command: .drawBezier,
            arguments: ["startX": .double(0.0), "startY": .double(0.0), "segments": .array(segments)],
            equals: "schema validation failed for segments: observed array count 1001; expected array count 1...1000 (At least 1 bezier segment is required)"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsOversizedSamplesBeforeExecution() async {
        await assertValidationError(
            command: .drawBezier,
            arguments: [
                "startX": .double(0.0),
                "startY": .double(0.0),
                "segments": .array([
                    .object([
                        "cp1X": .double(10.0), "cp1Y": .double(20.0),
                        "cp2X": .double(30.0), "cp2Y": .double(40.0),
                        "endX": .double(50.0), "endY": .double(60.0),
                    ]),
                ]),
                "samplesPerSegment": .int(1_001),
            ],
            equals: "schema validation failed for samplesPerSegment: observed integer 1001; expected integer in 2...1000"
        )
    }

    @ButtonHeistActor
    func testDrawBezierRejectsOversizedGeneratedPathBeforeExecution() async {
        let segment = HeistValue.object([
            "cp1X": .double(10.0), "cp1Y": .double(20.0), "cp2X": .double(30.0),
            "cp2Y": .double(40.0), "endX": .double(50.0), "endY": .double(60.0),
        ])
        let segments = Array(repeating: segment, count: 1_000)
        await assertValidationError(
            command: .drawBezier,
            arguments: [
                "startX": .double(0.0),
                "startY": .double(0.0),
                "segments": .array(segments),
                "samplesPerSegment": .int(52),
            ],
            equals: "schema validation failed for segments: observed generated path point count 51001; expected generated path point count <= 50000"
        )
    }

    @ButtonHeistActor
    func testDrawBezierValidPassesValidation() async {
        await assertPassesValidation(
            command: .drawBezier,
            arguments: [
                "startX": .double(0.0),
                "startY": .double(0.0),
                "segments": .array([
                    .object([
                        "cp1X": .double(10.0), "cp1Y": .double(20.0),
                        "cp2X": .double(30.0), "cp2Y": .double(40.0),
                        "endX": .double(50.0), "endY": .double(60.0),
                    ]),
                ]),
            ]
        )
    }

    // MARK: - Scroll Action Validation

    @ButtonHeistActor
    func testScrollDefaultsDirection() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollInvalidDirection() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["target": targetValue(identifier: "scrollView"), "direction": .string("diagonal")],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
        )
    }

    @ButtonHeistActor
    func testScrollAllowsMissingElement() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down")]
        )
    }

    @ButtonHeistActor
    func testScrollValidPassesValidation() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down"), "target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollDefaultsDirectionAndAllowsMissingTarget() async {
        await assertPassesValidation(
            command: .scroll
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleMissingElement() async {
        await assertContractError(
            command: .scrollToVisible,
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
            command: .scrollToVisible,
            arguments: ["target": targetValue(identifier: "targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleHeistIdPassesValidation() async {
        await assertPassesValidation(
            command: .scrollToVisible,
            arguments: ["target": heistTargetValue("targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeDefaultsEdge() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeInvalidEdge() async {
        await assertValidationError(
            command: .scrollToEdge,
            arguments: ["target": targetValue(identifier: "scrollView"), "edge": .string("middle")],
            equals: "schema validation failed for edge: observed string \"middle\"; expected enum one of top, bottom, left, right"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeAllowsMissingTarget() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom")]
        )
    }

    @ButtonHeistActor
    func testElementSearchMissingElement() async {
        await assertContractError(
            command: .elementSearch,
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
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "target": targetValue(identifier: "scrollView")]
        )
    }

    // MARK: - Accessibility Action Validation

    @ButtonHeistActor
    func testActivateMissingElement() async {
        await assertContractError(
            command: .activate,
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
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement")]
        )
    }

    @ButtonHeistActor
    func testRotorMissingElement() async {
        await assertContractError(
            command: .rotor,
            arguments: ["rotor": .string("Errors")],
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
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "rotorIndex": .int(-1)],
            equals: "schema validation failed for rotorIndex: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsMixedSelectorShape() async {
        await assertValidationError(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "rotor": .string("Errors"),
                "rotorIndex": .int(1),
            ],
            contains: "either rotor or rotorIndex"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidDirection() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "direction": .string("sideways")],
            equals: "schema validation failed for direction: observed string \"sideways\"; expected enum one of next, previous"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresBothOffsets() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "currentTextStartOffset": .int(4)],
            contains: "currentTextStartOffset and currentTextEndOffset"
        )
    }

    @ButtonHeistActor
    func testRotorTextRangeRequiresCurrentHeistId() async {
        await assertValidationError(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "currentTextStartOffset": .int(4),
                "currentTextEndOffset": .int(8),
            ],
            equals: "schema validation failed for currentHeistId: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsInvalidTextRangeOffsets() async {
        let expectedError = "schema validation failed for currentTextStartOffset/currentTextEndOffset: " +
            "observed 8..<4; expected integer range with start >= 0 and end >= start"
        await assertValidationError(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "currentHeistId": .string("notes"),
                "currentTextStartOffset": .int(8),
                "currentTextEndOffset": .int(4),
            ],
            equals: expectedError
        )
    }

    @ButtonHeistActor
    func testRotorValidPassesValidation() async {
        await assertPassesValidation(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "rotor": .string("Errors")]
        )
    }

    @ButtonHeistActor
    func testRotorPreviousValidTextRangeCursorPassesValidation() async {
        await assertPassesValidation(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "rotor": .string("Mentions"),
                "direction": .string("previous"),
                "currentHeistId": .string("notes"),
                "currentTextStartOffset": .int(4),
                "currentTextEndOffset": .int(10),
            ]
        )
    }

    @ButtonHeistActor
    func testActivateWithCustomActionDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("Delete")]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("increment")]
        )
    }

    @ButtonHeistActor
    func testActivateWithDecrementDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("decrement")]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementCountOmittedDispatchesOnce() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
            "count": .int(1),
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
            "count": .int(3),
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("decrement"),
            "count": .int(2),
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
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("increment"),
                "count": .int(0),
            ],
            contains: "schema validation failed for count: observed integer 0; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsNegativeCount() async {
        await assertValidationError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("increment"),
                "count": .int(-1),
            ],
            contains: "schema validation failed for count: observed integer -1; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementRejectsCountAboveMaximum() async {
        await assertValidationError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("increment"),
                "count": .int(101),
            ],
            contains: "schema validation failed for count: observed integer 101; expected integer in 1...100"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithoutAdjustmentAction() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "count": .int(2)],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsCountWithCustomAction() async {
        await assertValidationError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("Delete"),
                "count": .int(2),
            ],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsOutOfRangeCountWithCustomActionAsNonAdjustment() async {
        await assertValidationError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("Delete"),
                "count": .int(200),
            ],
            contains: "schema validation failed for count: observed integer 200; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateTreatsActionPrefixAsLiteralCustomActionName() async {
        await assertValidationError(
            command: .activate,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "action": .string("action:increment"),
                "count": .int(2),
            ],
            contains: "schema validation failed for count: observed integer 2; expected only valid with increment or decrement"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsEmptyActionNameAtRequestBoundary() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("")],
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
            "count": .int(3),
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
            "count": .int(3),
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
            command: .typeText,
            equals: "schema validation failed for text: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testTypeTextRejectsEmptyText() async {
        await assertValidationError(
            command: .typeText,
            arguments: ["text": .string("")],
            equals: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testTypeTextWithTextPassesValidation() async {
        await assertPassesValidation(
            command: .typeText,
            arguments: ["text": .string("hello")]
        )
    }

    @ButtonHeistActor
    func testTypeTextTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .typeText, values: [
            "text": .string("hello"),
            "target": heistTargetValue("search_field"),
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

        let response = try await fence.execute(command: .typeText, values: [
            "text": .int(3),
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
            command: .editAction,
            equals: "schema validation failed for action: observed missing; expected enum one of copy, paste, cut, select, selectAll, delete"
        )
    }

    @ButtonHeistActor
    func testEditActionValidPassesValidation() async {
        await assertPassesValidation(
            command: .editAction,
            arguments: ["action": .string("copy")]
        )
    }

    @ButtonHeistActor
    func testEditActionDeletePassesValidation() async {
        await assertPassesValidation(
            command: .editAction,
            arguments: ["action": .string("delete")]
        )
    }

    // MARK: - Pasteboard Validation

    @ButtonHeistActor
    func testSetPasteboardMissingText() async {
        await assertValidationError(
            command: .setPasteboard,
            equals: "schema validation failed for text: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testSetPasteboardWithTextPassesValidation() async {
        await assertPassesValidation(
            command: .setPasteboard,
            arguments: ["text": .string("hello")]
        )
    }

    @ButtonHeistActor
    func testGetPasteboardPassesValidation() async {
        await assertPassesValidation(
            command: .getPasteboard
        )
    }

    @ButtonHeistActor
    func testGetPasteboardRejectsExpectationBecauseItIsARead() async {
        await assertValidationError(
            command: .getPasteboard,
            arguments: ["expect": .object(["type": .string("screen_changed")])],
            contains: "valid get_pasteboard parameter"
        )
    }

    // MARK: - Ping

    @ButtonHeistActor
    func testPingSendsRequestScopedClientPingAndReturnsPayload() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(command: .ping)

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
            _ = try await fence.execute(command: .ping)
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
            command: .waitFor,
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
            command: .waitFor,
            arguments: ["target": targetValue(label: "Loading")]
        )
    }

    @ButtonHeistActor
    func testWaitForWithIdentifierPassesValidation() async {
        await assertPassesValidation(
            command: .waitFor,
            arguments: ["target": targetValue(identifier: "spinner")]
        )
    }

    @ButtonHeistActor
    func testWaitForWithTraitsPassesValidation() async {
        await assertPassesValidation(
            command: .waitFor,
            arguments: ["target": targetValue(traits: ["button"])]
        )
    }

    @ButtonHeistActor
    func testWaitForWithAbsentPassesValidation() async {
        await assertPassesValidation(
            command: .waitFor,
            arguments: ["target": targetValue(label: "Loading"), "absent": .bool(true), "timeout": .double(5.0)]
        )
    }

    // MARK: - Wait For Change Validation

    @ButtonHeistActor
    func testWaitForChangePassesValidation() async {
        await assertPassesValidation(
            command: .waitForChange
        )
    }

    @ButtonHeistActor
    func testWaitForChangeWithExpectPassesValidation() async {
        await assertPassesValidation(
            command: .waitForChange,
            arguments: ["expect": .object(["type": .string("screen_changed")])]
        )
    }

    @ButtonHeistActor
    func testWaitForChangeWithTimeoutPassesValidation() async {
        await assertPassesValidation(
            command: .waitForChange,
            arguments: ["expect": .object(["type": .string("elements_changed")]), "timeout": .double(5.0)]
        )
    }

    @ButtonHeistActor
    func testWaitForChangeTimeoutWithoutExpectSendsTypedPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .waitForChange, values: ["timeout": .double(3.0)])
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
        _ = try? await fence.execute(command: .waitForChange, values: [
            "expect": .object(["type": .string("screen_changed")]),
            "timeout": .double(8.0),
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

        let response = try await fence.execute(command: .waitForChange, values: [
            "expect": .object([
                "type": .string("element_disappeared"),
                "matcher": .object(["label": .string("Loading")]),
            ]),
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

        let response = try await fence.execute(command: .waitForChange, values: [
            "expect": .object([
                "type": .string("element_disappeared"),
                "matcher": .object(["label": .string("Loading")]),
            ]),
            "timeout": .double(0.2),
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
        _ = try? await fence.execute(command: .waitForChange)
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

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .string("screen_changed"),
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
        let result = try parseTypedExpectation(nil)
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedObject() async throws {
        let result = try parseTypedExpectation(.object(["type": .string("screen_changed")]))
        XCTAssertEqual(result, .screenChanged)
    }

    func testNormalizeToolCallRoutesWithoutParsingRequestArguments() throws {
        let expectation: HeistValue = .object(["type": .string("screen_changed")])
        let result = FenceOperationCatalog.normalizeToolCall(
            name: "activate",
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "target": .object(["identifier": .string("submit")]),
                "expect": expectation,
                "timeout": .double(0.25),
            ])
        )

        guard case .success(let operation) = result else {
            return XCTFail("Expected successful operation, got \(result)")
        }

        XCTAssertEqual(operation.command, .activate)
        XCTAssertNil(operation.arguments.string("identifier"))
        XCTAssertEqual(operation.arguments.argumentValues["expect"], expectation)
        XCTAssertEqual(operation.arguments.argumentValues["timeout"], .double(0.25))
    }

    @ButtonHeistActor
    func testParseExpectationStringValuesThrowObjectRequired() async {
        for value in ["screen_changed", "elements_changed", "element_updated", "layout_changed", "bogus"] {
            XCTAssertThrowsError(try parseTypedExpectation(.string(value))) { error in
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
        XCTAssertThrowsError(try parseTypedExpectation(.object(["wrong": .string("key")]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("\"type\" discriminator"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.int(42))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid expectation type"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationTopLevelArrayThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.array([
            .object(["type": .string("screen_changed")]),
            .object(["type": .string("elements_changed")]),
        ]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("expected object"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationFromTypedPlaybackRequestArguments() async throws {
        let evidence = HeistEvidence(
            command: "activate",
            target: semanticTarget(identifier: "counter"),
            arguments: [
                "expect": .object([
                    "type": .string("element_updated"),
                    "heistId": .string("counter"),
                    "property": .string("value"),
                    "newValue": .string("5"),
                ]),
            ]
        )

        let (fence, _) = makeConnectedFence()
        let result = try parseTypedExpectation(
            try fence.parsePlaybackEvidence(evidence).arguments.argumentValues["expect"]
        )

        XCTAssertEqual(
            result,
            .elementUpdated(heistId: "counter", property: .value, newValue: "5")
        )
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorScreenChanged() async throws {
        let result = try parseTypedExpectation(.object(["type": .string("screen_changed")]))
        XCTAssertEqual(result, .screenChanged)
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_updated"),
            "heistId": .string("slider"),
            "property": .string("value"),
            "oldValue": .string("0"),
            "newValue": .string("50"),
        ]))
        XCTAssertEqual(
            result,
            .elementUpdated(heistId: "slider", property: .value, oldValue: "0", newValue: "50")
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedInvalidPropertyListsValidValues() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_updated"),
            "property": .string("bogus"),
        ]))) { error in
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
        let result = try parseTypedExpectation(.object(["type": .string("element_updated")]))
        XCTAssertEqual(result, .elementUpdated())
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithMatcher() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "matcher": .object(["label": .string("Cart"), "identifier": .string("cart.button")]),
        ]))
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
            XCTAssertEqual(message, #"Unknown element matcher field "unknown""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationMatcherRejectsHeistId() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "matcher": .object([
                "heistId": .string("button_save"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"Unknown element matcher field "heistId""#)
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
            XCTAssertTrue(message.contains("type: integer 7"))
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
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("element_appeared")]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "matcher")
            XCTAssertEqual(error.observed, "missing")
            XCTAssertEqual(error.expected, "present")
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorCompound() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("compound"),
            "expectations": .array([
                .object(["type": .string("screen_changed")]),
                .object(["type": .string("element_updated"), "heistId": .string("counter")]),
            ]),
        ]))
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
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("compound"),
            "expectations": .array([
                .string("screen_changed"),
                .object(["type": .string("elements_changed")]),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "expectations[0]")
            XCTAssertEqual(error.observed, #"string "screen_changed""#)
            XCTAssertEqual(error.expected, "object")
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorUnknownTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("bogus_type")]))) { error in
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
                batchStepValue(.activate, [
                    "target": targetValue(identifier: "save-button"),
                    "expect": .object(["type": .string("elements_changed")]),
                ]),
            ]
        )

        guard let step = batch.steps.first else {
            return XCTFail("Expected planned batch step")
        }
        XCTAssertEqual(step.originalIndex, 0)
        XCTAssertEqual(step.commandName, "activate")
        XCTAssertEqual(step.typedStep.expectation, .elementsChanged)

        let singleMessages = try fence.executableActionMessages(for: try fence.parseRequest(
            command: .activate,
            values: ["target": targetValue(identifier: "save-button")]
        ))
        XCTAssertEqual(singleMessages.count, 1)

        guard case .activate(let actionTarget) = step.typedStep.command else {
            return XCTFail("Expected activate command, got \(step.typedStep.command)")
        }
        XCTAssertEqual(actionTarget, .matcher(ElementMatcher(identifier: "save-button")))
        guard case .activate(let singleActionTarget)? = singleMessages.first else {
            return XCTFail("Expected single activate command, got \(String(describing: singleMessages.first))")
        }
        XCTAssertEqual(singleActionTarget, actionTarget)
    }

    @ButtonHeistActor
    func testBatchAndSingleCommandsUseSameClientMessageLowering() async throws {
        let (fence, _) = makeConnectedFence()
        let cases: [(command: TheFence.Command, arguments: [String: HeistValue])] = [
            (.oneFingerTap, ["x": .double(12.0), "y": .double(34.0)]),
            (.scroll, ["direction": .string("up")]),
            (.activate, ["target": targetValue(identifier: "save-button")]),
            (.waitFor, ["target": targetValue(identifier: "toast")]),
            (.setPasteboard, ["text": .string("copied")]),
        ]

        for testCase in cases {
            let batch = try decodedRunBatch(fence, steps: [batchStepValue(testCase.command, testCase.arguments)])
            guard let plannedStep = plannedBatchSteps(from: batch).first else {
                return XCTFail("Expected planned batch step for \(testCase.command.rawValue)")
            }
            let singleRequest = try fence.parseRequest(command: testCase.command, values: testCase.arguments)
            let singleMessages = try fence.executableActionMessages(for: singleRequest)
            XCTAssertEqual(
                String(reflecting: singleMessages),
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
                    batchStepValue(.activate, ["target": targetValue(label: "Save")]),
                    batchStepValue(.getScreen),
                ]
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
                batchStepValue(.activate, ["target": targetValue(label: "Save")]),
                batchStepValue(.waitFor, ["target": targetValue(identifier: "toast")]),
                batchStepValue(.waitForChange, ["expect": .object(["type": .string("screen_changed")])]),
            ]
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
                batchStepValue(.waitFor, ["target": targetValue(identifier: "toast")]),
                batchStepValue(.waitForChange),
            ]
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
                batchStepValue(.activate, ["target": heistTargetValue("leaf-123")]),
                batchStepValue(.waitFor, ["target": heistTargetValue("leaf-456")]),
            ]
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
                batchStepValue(.activate, [
                    "target": targetValue(
                        traits: ["button"],
                        excludeTraits: ["header"],
                        ordinal: 1
                    ),
                ]),
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
                batchStepValue(.activate, [
                    "target": .object(["traits": .array([.string("notATrait")])]),
                ]),
            ],
            contains: "schema validation failed for steps[0].target.traits[0]: observed string \"notATrait\"; expected"
        )
    }

    @ButtonHeistActor
    func testBatchRoutedTargetRejectsNonIntegerOrdinal() async {
        await assertRunBatchDecodeError(
            steps: [
                batchStepValue(.activate, [
                    "target": .object([
                        "label": .string("Save"),
                        "ordinal": .string("first"),
                    ]),
                ]),
            ],
            contains: "schema validation failed for steps[0].target.ordinal: observed string \"first\"; expected integer"
        )
    }

    @ButtonHeistActor
    func testBatchRoutingReportsNonStringCommandClearly() async {
        await assertRunBatchDecodeError(
            steps: [
                .object([
                    "command": .int(7),
                    "target": targetValue(identifier: "btn"),
                ]),
            ],
            contains: "run_batch step 0: schema validation failed for steps[0].command: observed integer 7; expected string"
        )
    }

    @ButtonHeistActor
    func testBatchRoutedTargetRejectsNegativeOrdinal() async {
        await assertRunBatchDecodeError(
            steps: [
                batchStepValue(.activate, [
                    "target": .object([
                        "label": .string("Save"),
                        "ordinal": .int(-1),
                    ]),
                ]),
            ],
            contains: "schema validation failed for steps[0].target.ordinal: observed integer -1; expected ordinal must be non-negative, got -1"
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
        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, [
                "target": targetValue(identifier: "btn1"),
                "expect": .object(["type": .string("elements_changed")]),
            ]),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn2")]),
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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, [
                "target": targetValue(identifier: "btn1"),
                "expect": .object(["type": .string("screen_changed")]),
            ]),
            batchStepValue(.activate, [
                "target": targetValue(identifier: "btn2"),
                "expect": .object(["type": .string("elements_changed")]),
            ]),
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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "first")]),
            batchStepValue(.activate, ["target": targetValue(identifier: "second")]),
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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "first")]),
            batchStepValue(.activate, ["target": targetValue(identifier: "second")]),
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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue("not_a_real_command"),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn1")]),
        ], policy: "stop_on_error")

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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "stale-button")]),
            batchStepValue(.activate, ["target": targetValue(identifier: "later-button")]),
        ], policy: "stop_on_error")

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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "btn1")]),
            batchStepValue("not_a_real_command"),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn2")]),
        ], policy: "stop_on_error")

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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, [
                "target": targetValue(identifier: "btn1"),
                "expect": .object(["type": .string("screen_changed")]),
            ]),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn2")]),
        ], policy: "stop_on_error")

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
        await assertValidationError(
            command: .runBatch,
            arguments: ["steps": .array([
                batchStepValue(.scroll, [
                    "unexpected": .string("value"),
                    "target": targetValue(label: "Done"),
                ]),
            ])],
            contains: #"schema validation failed for unexpected: observed string "value"; expected valid scroll parameter"#
        )
    }

    @ButtonHeistActor
    func testBatchAllowsContainerTargetedScrollThroughNormalCommandPath() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .scroll))
        }

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.scroll, [
                "container": .object(["stableId": .string("main_scroll")]),
                "direction": .string("down"),
            ]),
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
            repeating: batchStepValue(.activate, ["target": targetValue(identifier: "btn")]),
            count: TheFence.DecodeLimits.maxRunBatchSteps + 1
        )
        await assertValidationError(
            command: .runBatch,
            arguments: ["steps": .array(steps)],
            equals: "schema validation failed for steps: observed array count 101; expected array count 1...100"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsTooDeepRequestBeforeExecution() async {
        func nested(_ depth: Int) -> HeistValue {
            depth == 0
                ? .object(["type": .string("screen_changed")])
                : .object(["expectations": .array([nested(depth - 1)])])
        }
        await assertValidationError(
            command: .runBatch,
            arguments: ["steps": .array([
                batchStepValue(.activate, [
                    "target": targetValue(identifier: "btn"),
                    "expect": nested(TheFence.DecodeLimits.maxRunBatchNestingDepth),
                ]),
            ])],
            contains: "expected nesting depth <= 32"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsOversizedRequestBeforeExecution() async {
        let payload = String(repeating: "x", count: TheFence.DecodeLimits.maxRunBatchRequestBytes)
        await assertValidationError(
            command: .runBatch,
            arguments: ["steps": .array([
                batchStepValue(.activate, ["target": targetValue(identifier: payload)]),
            ])],
            contains: "expected JSON request <= \(TheFence.DecodeLimits.maxRunBatchRequestBytes) bytes"
        )
    }

    @ButtonHeistActor
    func testBatchRejectsNonBatchExecutableCommandsBeforeExecution() async {
        let nonBatchCommands = TheFence.Command.descriptors
            .filter { !$0.isBatchExecutable }
            .map(\.command)

        for command in nonBatchCommands {
            await assertValidationError(
                command: .runBatch,
                arguments: ["steps": .array([batchStepValue(command)])],
                contains: "run_batch step command \"\(command.rawValue)\" is not supported"
            )
        }
    }

    @ButtonHeistActor
    func testBatchRejectsGetScreenBeforePayloadValidation() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.getScreen, ["inlineData": .bool(true)]),
            batchStepValue(.activate, ["target": targetValue(identifier: "skipped")]),
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
    func testBatchStillAcceptsCanonicalTypedCommandShapes() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.swipe, ["target": heistTargetValue("row_1"), "direction": .string("left")]),
            batchStepValue(.scrollToVisible, ["target": targetValue(label: "Done")]),
            batchStepValue(.dismissKeyboard),
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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.typeText, ["text": .string("")]),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn")]),
        ], policy: "continue_on_error")

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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "first")]),
            batchStepValue("unknown_command"),
            batchStepValue(.activate, ["target": targetValue(identifier: "skipped")]),
        ], policy: "stop_on_error")

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

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.waitFor),
            batchStepValue(.activate, ["target": targetValue(identifier: "skipped")]),
        ], policy: "stop_on_error")

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
        _ = try? await fence.execute(command: .getInterface)
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
            command: .activate,
            arguments: ["target": targetValue(identifier: "save"), "mode": .string("tap")],
            equals: "schema validation failed for mode: observed string \"tap\"; expected valid activate parameter"
        )
    }

    @ButtonHeistActor
    func testTypedElementTargetIsRejectedForCommandWithoutTargetParameter() async throws {
        let (fence, _) = makeConnectedFence()
        let operation = NormalizedOperation(
            command: TheFence.Command.getScreen,
            arguments: TheFence.CommandArgumentEnvelope(
                values: [:],
                elementTarget: ElementTarget.heistId("button_save")
            )
        )

        let response = try await fence.execute(operation: operation)
        guard case .error(let message, _) = response else {
            return XCTFail("Expected typed element target to be rejected")
        }
        XCTAssertEqual(
            message,
            #"schema validation failed for target: observed target(heistId="button_save"); expected get_screen command without element target"#
        )
    }

    @ButtonHeistActor
    func testTimeoutIsRejectedWhenCommandDoesNotConsumeIt() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["timeout": .int(15)],
            equals: "schema validation failed for timeout: observed integer 15; expected valid get_interface parameter"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceFullAliasUsesCommandContractRejection() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["full": .bool(false)],
            equals: "schema validation failed for full: observed boolean false; expected valid get_interface parameter"
        )
        await assertValidationError(
            command: .getInterface,
            arguments: ["full": .bool(true)],
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

        let response = try await fence.execute(command: .getInterface)

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

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "container": .object(["stableId": .string("semantic_actions__actions")]),
            ]),
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

    @ButtonHeistActor
    func testGetInterfaceSubtreeElementRejectsHeistIdAndOrdinal() async {
        await assertOperationValidationError(
            command: .getInterface,
            arguments: [
                "subtree": .object([
                    "element": .object(["heistId": .string("button_save")]),
                    "ordinal": .int(1),
                ]),
            ],
            contains: "ElementTarget heistId cannot be combined with matcher fields or ordinal"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceSubtreeElementRejectsUnknownTargetField() async {
        await assertOperationValidationError(
            command: .getInterface,
            arguments: [
                "subtree": .object([
                    "element": .object([
                        "label": .string("Save"),
                        "unexpectedTargetField": .string("button_save"),
                    ]),
                ]),
            ],
            contains: "unexpectedTargetField"
        )
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

        let response = try await fence.execute(command: .getInterface, values: ["label": .string("Submit")])

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
        _ = try? await fullFence.execute(command: .getInterface, values: ["detail": .string("full")])
        guard let (fullMessage, _) = fullMock.sent.last,
              case .requestInterface = fullMessage else {
            XCTFail("Expected detail=full on get_interface to send requestInterface, got \(String(describing: fullMock.sent.last))")
            return
        }
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsScopeParameter() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["scope": .string("current")],
            equals: "schema validation failed for scope: observed string \"current\"; expected valid get_interface parameter"
        )
    }

    @ButtonHeistActor
    func testBatchWithNoExpectationsShowsZeroCounts() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let response = try await executeRunBatch(fence, steps: [
            batchStepValue(.activate, ["target": targetValue(identifier: "btn1")]),
            batchStepValue(.activate, ["target": targetValue(identifier: "btn2")]),
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
            let response = try await fence.execute(command: .playHeist)
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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string("/tmp/../etc/passwd")])
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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string("")])
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

        let response = try await fence.execute(command: .stopHeist)
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
            _ = try await fence.execute(command: .stopHeist, values: ["output": .string("/tmp/../invalid.heist")])
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
        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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
        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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
    func testPlaybackScriptValidationBindsFixtureStepsToTypedCommands() async throws {
        let playback = HeistPlayback(
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
        let (fence, _) = makeConnectedFence()
        try fence.validateHeistPlayback(playback)
        let operation = playback.steps[0]

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.steps.count, 2)
        XCTAssertEqual(operation.command, "type_text")
        XCTAssertEqual(playback.steps[1].command, "activate")
        XCTAssertEqual(operation.target?.matcher.identifier, "email")
        XCTAssertEqual(operation.target?.ordinal, 1)

        let parsed = try fence.parsePlaybackEvidence(operation)
        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertNil(parsed.arguments.string("identifier"))
        XCTAssertEqual(parsed.arguments.string("text"), "user@example.com")
        XCTAssertNil(parsed.arguments.string("_recorded"))
        guard case .matcher(let matcher, let ordinal)? = parsed.arguments.elementTarget else {
            return XCTFail("Expected playback target to bind as typed matcher")
        }
        XCTAssertEqual(matcher.identifier, "email")
        XCTAssertEqual(ordinal, 1)
    }

    @ButtonHeistActor
    func testPlaybackScriptLoadsHeistFileAtFileEdge() async throws {
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

        let (fence, _) = makeConnectedFence()
        let playback = try fence.readHeistPlayback(contentsOf: heistURL)

        XCTAssertEqual(playback.app, "com.test.mock")
        XCTAssertEqual(playback.steps.map(\.command), ["activate"])
        XCTAssertEqual(playback.steps.first?.target?.matcher.identifier, "submit")
        let step = try XCTUnwrap(playback.steps.first)
        let expect = try fence.parsePlaybackEvidence(step).arguments.argumentValues["expect"]
        XCTAssertEqual(expect, .object(["type": .string("screen_changed")]))
    }

    @ButtonHeistActor
    func testPlaybackScriptFileEdgeRejectsUnsupportedVersion() async throws {
        let heist = HeistPlayback(
            version: HeistPlayback.currentVersion + 1,
            app: "com.test.mock",
            steps: [HeistEvidence(command: "activate", target: semanticTarget(identifier: "submit"))]
        )
        let heistURL = try writeTemporaryHeist(heist)
        defer { try? FileManager.default.removeItem(at: heistURL) }

        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(try fence.readHeistPlayback(contentsOf: heistURL)) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported heist file version \(HeistPlayback.currentVersion + 1)"))
            XCTAssertTrue(message.contains("supports version \(HeistPlayback.currentVersion)"))
        }
    }

    @ButtonHeistActor
    func testHeistEvidencePreservesCanonicalExpectationPayload() async throws {
        let evidence = HeistEvidence(
            command: "type_text",
            target: semanticTarget(identifier: "email"),
            arguments: [
                "text": .string("user@example.com"),
                "expect": .object(["type": .string("screen_changed")]),
            ]
        )

        let (fence, _) = makeConnectedFence()
        let expect = try fence.parsePlaybackEvidence(evidence).arguments.argumentValues["expect"]
        XCTAssertEqual(expect, .object(["type": .string("screen_changed")]))
    }

    @ButtonHeistActor
    func testPlaybackScriptValidationAcceptsCanonicalPlaybackExecutableCommands() async throws {
        let playback = HeistPlayback(
            app: "com.test.mock",
            steps: TheFence.Command.playbackExecutableCases.map { command in
                HeistEvidence(command: command.rawValue)
            }
        )
        let (fence, _) = makeConnectedFence()
        try fence.validateHeistPlayback(playback)

        XCTAssertEqual(playback.steps.map(\.command), TheFence.Command.playbackExecutableCases.map(\.rawValue))
    }

    @ButtonHeistActor
    func testPlaybackScriptValidationRejectsUnknownCommandName() async throws {
        let (fence, _) = makeConnectedFence()
        XCTAssertThrowsError(
            try fence.validateHeistPlayback(
                HeistPlayback(
                    app: "com.test.mock",
                    steps: [HeistEvidence(command: "unknown_command", arguments: [:])]
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
        let cases: [(name: String, evidence: HeistEvidence, message: String)] = [
            (
                "unknown scroll parameter",
                HeistEvidence(
                    command: "scroll",
                    arguments: ["unexpected": .string("value")]
                ),
                "schema validation failed for unexpected: observed string \"value\"; expected valid scroll playback argument"
            ),
            (
                "unknown activate parameter",
                HeistEvidence(
                    command: "activate",
                    arguments: ["heistId": .string("stale_button")]
                ),
                "schema validation failed for heistId: observed string \"stale_button\"; expected valid activate playback argument"
            ),
            (
                "request target object is not playback identity",
                HeistEvidence(
                    command: "activate",
                    arguments: ["target": targetValue(identifier: "argument_button")]
                ),
                "schema validation failed for target: observed object; expected valid activate playback argument"
            ),
            (
                "edit_action invalid action type",
                HeistEvidence(
                    command: "edit_action",
                    arguments: ["action": .int(7)]
                ),
                "schema validation failed for action: observed integer 7; expected string"
            ),
            (
                "non-target command carries playback target",
                HeistEvidence(
                    command: "edit_action",
                    target: semanticTarget(identifier: "ignored"),
                    arguments: ["action": .string("copy")]
                ),
                "schema validation failed for target: observed target(matcher(identifier=\"ignored\")); "
                    + "expected edit_action command without element target"
            ),
        ]

        let (fence, _) = makeConnectedFence()
        for testCase in cases {
            let response = try await fence.execute(playback: testCase.evidence)
            guard case .error(let message, _) = response else {
                XCTFail("Expected playback validation error for \(testCase.name), got \(response)")
                continue
            }
            XCTAssertEqual(message, testCase.message)
        }
    }

    @ButtonHeistActor
    func testPlaybackScriptValidationRejectsNonExecutableCommands() async throws {
        let (fence, _) = makeConnectedFence()
        for command in TheFence.Command.allCases where !command.isPlaybackExecutable {
            XCTAssertThrowsError(
                try fence.validateHeistPlayback(
                    HeistPlayback(app: "com.test.mock", steps: [HeistEvidence(command: command.rawValue)])
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
    func testExecutePlaybackEvidenceUsesTypedCommand() async throws {
        let evidence = HeistEvidence(command: "activate", target: semanticTarget(identifier: "btn1"))

        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(playback: evidence)

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

        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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

        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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

        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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
        let evidence = HeistEvidence(
            command: "activate",
            target: semanticTarget(identifier: "btn1"),
            recorded: RecordedMetadata(heistId: "stale_debug_id")
        )

        let (fence, mockConn) = makeConnectedFence()
        let parsed = try fence.parsePlaybackEvidence(evidence)
        guard case .matcher(let matcher, nil)? = parsed.arguments.elementTarget else {
            return XCTFail("Expected playback target to bind as typed matcher")
        }
        XCTAssertEqual(matcher.identifier, "btn1")
        XCTAssertNil(parsed.arguments.argumentValues["heistId"])
        XCTAssertNil(parsed.arguments.argumentValues["target"])

        let response = try await fence.execute(playback: evidence)

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
        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])
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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])
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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])
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
            _ = try await fence.execute(command: .playHeist, values: ["input": .string("../bad.heist")])
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
        let response = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])

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
        let firstResponse = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])
        guard case .heistPlayback = firstResponse else {
            return XCTFail("Expected heistPlayback response")
        }

        // Second playback should also succeed (phase reset to idle)
        let secondResponse = try await fence.execute(command: .playHeist, values: ["input": .string(heistURL.path)])
        guard case .heistPlayback(let completedSteps, let failedIndex, _, let failure, _) = secondResponse else {
            return XCTFail("Expected heistPlayback response")
        }
        XCTAssertEqual(completedSteps, 1)
        XCTAssertNil(failedIndex)
        XCTAssertNil(failure)
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

private func heistTargetValue(_ heistId: String) -> HeistValue {
    elementTargetValue(["heistId": .string(heistId)])
}

private func targetValue(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    excludeTraits: [String]? = nil,
    ordinal: Int? = nil
) -> HeistValue {
    var target: [String: HeistValue] = [:]
    if let label { target["label"] = .string(label) }
    if let identifier { target["identifier"] = .string(identifier) }
    if let value { target["value"] = .string(value) }
    if let traits { target["traits"] = .array(traits.map { .string($0) }) }
    if let excludeTraits { target["excludeTraits"] = .array(excludeTraits.map { .string($0) }) }
    if let ordinal { target["ordinal"] = .int(ordinal) }
    return elementTargetValue(target)
}

private func elementTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
    .object(fields)
}

private func batchStepValue(
    _ command: TheFence.Command,
    _ fields: [String: HeistValue] = [:]
) -> HeistValue {
    batchStepValue(command.rawValue, fields)
}

private func batchStepValue(
    _ commandName: String,
    _ fields: [String: HeistValue] = [:]
) -> HeistValue {
    var values = fields
    values["command"] = .string(commandName)
    return .object(values)
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
