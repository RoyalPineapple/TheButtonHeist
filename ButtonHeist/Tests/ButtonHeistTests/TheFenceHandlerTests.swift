import XCTest
import Network
@testable import ButtonHeist
import TheScore

private extension AccessibilityTrace.Delta {
    var testKind: String {
        switch self {
        case .noChange:
            return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged:
            return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged:
            return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
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
            let response = try await fence.execute(command: command, values: arguments)
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
    private func assertOperationPassesValidation(
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
    private func decodedElementTarget(
        target: HeistValue? = nil
    ) throws -> ElementTarget? {
        var arguments: [String: HeistValue] = [:]
        if let target {
            arguments["target"] = target
        }
        return try TheFence.CommandArgumentEnvelope(values: arguments).decodedElementTarget()
    }

    private func testElement(
        label: String,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
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

    private func selectionTestInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = testElement(label: "Menu", traits: [.header])
        let submit = testElement(label: "Submit", traits: [.button])
        let cancel = testElement(label: "Cancel", traits: [.button])
        let footer = testElement(label: "Footer")
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
                containerName: "semantic_actions__actions",
                children: [.element(submit), .element(cancel)]
            ),
            .element(footer),
        ]
        if includeDuplicateGroup {
            let archive = testElement(label: "Archive", traits: [.button])
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
                    containerName: "semantic_actions__secondary_actions",
                    children: [.element(archive)]
                ),
                at: 2
            )
        }
        return makeReceiptTestInterface(nodes: nodes)
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
        fence.handoff.makeConnection = { _ in mockConn }

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
            case .requestInterface:
                XCTFail("connect must not send UI observation message \(message)")
            default:
                break
            }
        }
    }

    // MARK: - Run Heist Input Loading

    @ButtonHeistActor
    func testRunHeistReadsPlanFromArtifactPathIntoSwiftObjects() async throws {
        let fence = TheFence(configuration: .init())
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fence-runheist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // A hyphenated file name is NOT a valid Swift-style identifier. The fence
        // must run the plan exactly as authored — stamping the file name into the
        // plan's `name` would fail runtime admission and silently reduce the run
        // to zero steps (the run_heist replay no-op regression).
        let heistURL = temp.appendingPathComponent("bh-demo-smoke.heist")
        let plan = HeistPlan(body: [.warn(WarnStep(message: "from artifact"))])
        try HeistArtifactCodec.writePlan(plan, to: heistURL)

        let request = try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["path": .string(heistURL.path)])
        )

        // The fence reads the file into a HeistPlan directly — no parameter
        // round-trip — and does not invent a name from the file.
        XCTAssertEqual(request.plan.body, plan.body)
        XCTAssertNil(request.plan.name)
        XCTAssertTrue(
            request.plan.runtimeAdmissionFailures().isEmpty,
            "loaded plan must be runtime-admissible: \(request.plan.runtimeAdmissionFailures())"
        )
    }

    @ButtonHeistActor
    func testRunHeistRejectsPathCombinedWithAnyInlinePlanField() async {
        let fence = TheFence(configuration: .init())
        // Every canonical inline plan field combined with `path` must fail,
        // before the artifact is touched. Values are irrelevant — key presence
        // alone is the conflict.
        let inlineFields: [String: HeistValue] = [
            "version": .int(1),
            "name": .string("flow"),
            "parameter": .object(["type": .string("none")]),
            "definitions": .array([]),
            "body": .array([.object(["type": .string("warn")])]),
        ]
        for (field, value) in inlineFields {
            XCTAssertThrowsError(try fence.decodeRunHeistRequest(
                TheFence.CommandArgumentEnvelope(values: [
                    "path": .string("/tmp/Flow.heist"),
                    field: value,
                ])
            ), "path + \(field) must fail") { error in
                XCTAssertTrue(
                    String(describing: error).contains("run_heist accepts either a path or an inline plan, not both"),
                    "path + \(field): \(error)"
                )
            }
        }
    }

    @ButtonHeistActor
    func testRunHeistRejectsNonHeistAndEmptyInput() async {
        let fence = TheFence(configuration: .init())
        // Standalone .json is internal to the package; .swift is compiled by the
        // CLI authoring path, never inspected or compiled at the fence boundary.
        for path in ["Flow.txt", "Flow.json", "Flow.swift"] {
            XCTAssertThrowsError(try fence.decodeRunHeistRequest(
                TheFence.CommandArgumentEnvelope(values: ["path": .string(path)])
            )) { error in
                XCTAssertTrue(String(describing: error).contains(".heist package artifact"), "\(path): \(error)")
            }
        }
        // Empty path fails.
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["path": .string("   ")])
        )) { error in
            XCTAssertTrue(String(describing: error).contains("path must not be empty"), "\(error)")
        }
    }

    @ButtonHeistActor
    func testRunHeistDecodesComposableInlinePlan() async throws {
        let fence = TheFence(configuration: .init())
        // Nested definitions + invoke + a string parameter all round-trip.
        let definition = HeistPlan(
            name: "addToCart",
            parameter: .strings(name: "item"),
            body: [.action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .ref("item"))))))]
        )
        let plan = HeistPlan(definitions: [definition], body: [
            .invoke(HeistInvocationStep(path: ["addToCart"], argument: .strings([.literal("Milk")]))),
        ])

        let request = try fence.decodeRunHeistRequest(try Self.inlineArguments(for: plan))
        XCTAssertEqual(request.plan, plan)
    }

    @ButtonHeistActor
    func testRunHeistDecodesInlinePlanWithElementTargetParameter() async throws {
        let fence = TheFence(configuration: .init())
        let definition = HeistPlan(
            name: "tapEach",
            parameter: .elementTargets(name: "input"),
            body: [.action(try ActionStep(command: .activate(.ref("input"))))]
        )
        let plan = HeistPlan(
            definitions: [definition],
            body: [.warn(WarnStep(message: "namespace"))]
        )

        let request = try fence.decodeRunHeistRequest(try Self.inlineArguments(for: plan))
        XCTAssertEqual(request.plan, plan)
    }

    @ButtonHeistActor
    func testRunHeistRejectsUnsupportedInlineVersionAndEmptyPlan() async throws {
        let fence = TheFence(configuration: .init())
        // Unsupported plan version fails.
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: [
                "version": .int(999),
                "body": .array([.object(["type": .string("warn"), "warn": .object(["message": .string("x")])])]),
            ])
        ))
        // Empty inline plan (no body, no definitions) fails.
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["version": .int(1), "body": .array([])])
        ))
    }

    @ButtonHeistActor
    func testRunHeistDescriptorAcceptsComposableInlinePlanKeys() async throws {
        // The descriptor must declare the canonical plan fields so an inline
        // plan with definitions/parameter/name survives request-key validation
        // (the path that MCP and CLI inline plans travel).
        let fence = TheFence(configuration: .init())
        let definition = HeistPlan(
            name: "addToCart",
            parameter: .strings(name: "item"),
            body: [.warn(WarnStep(message: "x"))]
        )
        let plan = HeistPlan(
            name: "flow",
            definitions: [definition],
            body: [.invoke(HeistInvocationStep(path: ["addToCart"], argument: .strings([.literal("Milk")])))]
        )
        XCTAssertNoThrow(try fence.parseRequest(command: .runHeist, arguments: try Self.inlineArguments(for: plan)))
    }

    func testHeistExecutionResponseFailureDrivenByFailedStepNotFailedIndex() {
        // A failed child with nil failedIndex must mark the response as failure —
        // this is what drives CLI non-zero exit and MCP isError.
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .heist,
                    durationMs: 5,
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(
                                success: false,
                                method: .activate,
                                message: "boom",
                                errorKind: .actionFailed
                            ),
                            durationMs: 5
                        ),
                    ]
                ),
            ],
            totalTimingMs: 5,
            failedIndex: nil
        )
        let response = FenceResponse.heistExecution(
            plan: HeistPlan(body: [.warn(WarnStep(message: "x"))]),
            result: result,
            accessibilityTrace: nil
        )
        XCTAssertTrue(response.isFailure)
    }

    /// Build a run_heist argument envelope from a plan the way an inline
    /// `--plan` / MCP request would: the plan's canonical JSON object fields.
    private static func inlineArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        guard case .object(let fields) = try JSONDecoder().decode(HeistValue.self, from: data) else {
            throw XCTSkip("plan did not encode to a JSON object")
        }
        return TheFence.CommandArgumentEnvelope(values: fields)
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
        let first = TheFence.CommandArgumentEnvelope(values: firstObject, fieldPrefix: "array[0]")
        XCTAssertEqual(try first.schemaNumber("x"), 0.25)
        XCTAssertEqual(try first.schemaNumber("y"), 0.75)
        guard case .object(let secondObject) = array[1] else {
            return XCTFail("Expected typed object")
        }
        let second = TheFence.CommandArgumentEnvelope(values: secondObject, fieldPrefix: "array[1]")
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
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.identifier, "myButton")
    }

    @ButtonHeistActor
    func testElementTargetRejectsHeistIdField() async throws {
        // heistId is no longer a targeting field — it is rejected as unknown.
        XCTAssertThrowsError(try decodedElementTarget(target: legacyHeistIdTargetValue("button_save")))
    }

    @ButtonHeistActor
    func testElementTargetWithMatcherFields() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save", traits: ["button"])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
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
              case .predicate(let matcher, let ordinal) = target else {
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
              case .predicate(_, let ordinal) = target else {
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
            command: .wait,
            arguments: ["timeout": .string("forever")],
            equals: "schema validation failed for timeout: observed string \"forever\"; expected number"
        )
    }

    // MARK: - Gesture Validation

    @ButtonHeistActor
    func testOneFingerTapMissingTarget() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            contains: "Must specify element or point"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(100.0), "y": .double(200.0)])]
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsPartialCoordinates() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(100.0)])],
            equals: "schema validation failed for point.y: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsNaNCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(Double.nan), "y": .double(200.0)])],
            equals: "schema validation failed for point.x: observed number nan; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsInfiniteCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(Double.infinity), "y": .double(200.0)])],
            equals: "schema validation failed for point.x: observed number inf; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithIdentifierPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["element": targetValue(identifier: "myButton")]
        )
    }

    @ButtonHeistActor
    func testGestureTargetRejectsHeistIdAndMatcher() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: [
                "element": elementTargetValue([
                    "heistId": .string("button_save"),
                    "label": .string("Save"),
                ]),
            ],
            contains: "Unknown element target field \"heistId\""
        )
    }

    @ButtonHeistActor
    func testLongPressMissingTarget() async {
        await assertOperationValidationError(
            command: .longPress,
            contains: "Must specify element or point"
        )
    }

    @ButtonHeistActor
    func testLongPressWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .longPress,
            arguments: ["point": .object(["x": .double(50.0), "y": .double(50.0)])]
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsNegativeDuration() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: [
                "point": .object(["x": .double(50.0), "y": .double(50.0)]),
                "duration": .double(-1.0),
            ],
            equals: "schema validation failed for duration: observed number -1.0; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsOversizedDurationBeforeExecution() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: [
                "point": .object(["x": .double(50.0), "y": .double(50.0)]),
                "duration": .double(61.0),
            ],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
        )
    }

    @ButtonHeistActor
    func testSwipeInvalidDirection() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "direction": .string("diagonal"),
                ]),
            ],
            equals: "schema validation failed for pointDirection.direction: observed string \"diagonal\"; " +
                "expected enum one of up, down, left, right"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithoutTargetOrCoordinatesIsRejected() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object(["direction": .string("up")]),
            ],
            equals: "schema validation failed for pointDirection.start: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testSwipeRejectsPartialStartCoordinates() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0)]),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.start.y: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testSwipeWithUnitPointsPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: [
                "elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(0.8), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ]),
            ]
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsRejectOutOfRangeCoordinate() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(1.2), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ]),
            ],
            equals: "schema validation failed for elementUnitPoints.start.x: observed number 1.2; expected number in 0...1"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: [
                "elementDirection": .object([
                    "element": targetValue(identifier: "row_5"),
                    "direction": .string("left"),
                ]),
            ]
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementDispatchesElementDirectionPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .swipe, values: [
            "elementDirection": .object([
                "element": targetValue(identifier: "row_5"),
                "direction": .string("left"),
            ]),
        ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .swipe(let target) = message,
              case .elementDirection(let elementTarget, let direction) = target.selection else {
            XCTFail("Expected element direction swipe to lower to element direction swipe")
            return
        }
        XCTAssertEqual(elementTarget, .predicate(ElementPredicate(identifier: "row_5")))
        XCTAssertEqual(direction, .left)
    }

    @ButtonHeistActor
    func testSwipeRejectsMixedIntentObjects() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "direction": .string("down"),
                ]),
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "end": .object(["x": .double(30.0), "y": .double(40.0)]),
                ]),
            ],
            equals: "schema validation failed for swipe: observed mixed or missing gesture intent; expected exactly one swipe intent"
        )
    }

    @ButtonHeistActor
    func testDragMissingEndCoordinates() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(10.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.end: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testDragWithoutStartTargetIsRejected() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "pointToPoint": .object([
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.start: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testDragWithElementTargetAndEndCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ]
        )
    }

    @ButtonHeistActor
    func testDragWithStartCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .drag, values: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(100.0), "y": .double(300.0)]),
                    "end": .object(["x": .double(300.0), "y": .double(600.0)]),
                ]),
            ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .drag(let target) = message else {
            XCTFail("Expected drag message")
            return
        }
        XCTAssertEqual(target.start, .coordinate(ScreenPoint(x: 100.0, y: 300.0)))
        XCTAssertEqual(target.end, ScreenPoint(x: 300.0, y: 600.0))
    }

    @ButtonHeistActor
    func testDragRejectsMixedIntentObjects() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "schema validation failed for drag: observed mixed or missing gesture intent; expected exactly one drag intent"
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
    func testScrollRejectsContainerObject() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["container": .object(["unexpected": .string("main_scroll")])],
            contains: "schema validation failed for container"
        )
    }

    @ButtonHeistActor
    func testScrollRejectsPublicContainerName() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["containerName": .string("main_scroll")],
            contains: "schema validation failed for containerName"
        )
    }

    @ButtonHeistActor
    func testScrollAllowsContainerArgument() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down"), "container": .string("main_scroll")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeRejectsPublicContainerName() async {
        await assertValidationError(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "containerName": .string("main_scroll")],
            contains: "schema validation failed for containerName"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeAllowsContainerArgument() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "container": .string("main_scroll")]
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
    func testScrollToVisibleIdentifierTargetPassesValidation() async {
        await assertPassesValidation(
            command: .scrollToVisible,
            arguments: ["target": targetValue(identifier: "targetElement")]
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
    func testRotorRejectsLegacyLooseContinuationFields() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "currentTextStartOffset": .int(4)],
            contains: "schema validation failed for currentTextStartOffset:"
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
    func testActivateActionIncrementDispatchesSingleIncrementStep() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        let commands = mockConn.sent.sentHeistActionCommands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.wireType, .increment)
    }

    @ButtonHeistActor
    func testActivateRejectsEmptyActionNameAtRequestBoundary() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("")],
            equals: "schema validation failed for action: observed string \"\"; expected non-empty string"
        )
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
            "target": targetValue(identifier: "search_field"),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .typeText(let target) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.sentPlanMessages.last))")
        }
        XCTAssertEqual(target.text, "hello")
        XCTAssertEqual(target.elementTarget, .predicate(ElementPredicate(identifier: "search_field")))
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
        fence.handoff.makeConnection = { _ in mockConn }

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

    // MARK: - Wait Validation

    @ButtonHeistActor
    func testWaitMissingPredicate() async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: .wait, values: [:])
            if case .error(let message, _) = response {
                XCTAssertTrue(message.contains("predicate"), "Expected predicate error, got: \(message)")
            } else {
                XCTFail("Expected error response, got \(response)")
            }
        } catch let error as FenceError {
            XCTAssertTrue("\(error)".contains("predicate"), "Expected predicate error, got: \(error)")
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    @ButtonHeistActor
    func testWaitPresentWithLabelPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("present"),
                "element": .object(["label": .string("Loading")]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitAbsentWithLabelPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("absent"),
                "element": .object(["label": .string("Loading")]),
            ]), "timeout": .double(5.0)]
        )
    }

    @ButtonHeistActor
    func testWaitChangedScreenPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object(["type": .string("screen_changed")])]
        )
    }

    @ButtonHeistActor
    func testWaitChangedWithTimeoutPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object(["type": .string("elements_changed")]), "timeout": .double(5.0)]
        )
    }

    @ButtonHeistActor
    func testWaitAllStatesPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("all"),
                "states": .array([
                    .object(["type": .string("present"), "element": .object(["label": .string("Done")])]),
                    .object(["type": .string("absent"), "element": .object(["label": .string("Loading")])]),
                ]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitScreenChangedWhereClausePassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("screen_changed"),
                "where": .object(["type": .string("present"), "element": .object(["label": .string("Home")])]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitSendsCorrectMessage() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .wait, values: [
            "predicate": .object(["type": .string("screen_changed")]),
            "timeout": .double(8.0),
        ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .wait(let target) = message else {
            return XCTFail("Expected wait message")
        }
        XCTAssertEqual(target.predicate, .changed(.screen()))
        XCTAssertEqual(target.timeout, 8.0)
    }

    @ButtonHeistActor
    func testWaitChangedRequiresTraceDerivedExpectationMatch() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            guard case .wait = message else {
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return .actionResult(ActionResult(
                success: true,
                method: .wait,
                message: "expectation met after observed change",
                accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
            ))
        }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("element_disappeared"),
                "element": .object(["label": .string("Loading")]),
            ]),
        ])

        guard let leaf = response.leafAction else {
            return XCTFail("Expected single-step action response, got \(response)")
        }
        XCTAssertEqual(leaf.expectation?.met, false)
        XCTAssertEqual(leaf.expectation?.actual, "no elements removed")
    }

    @ButtonHeistActor
    func testWaitChangedTimeoutDoesNotClaimExpectationMet() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            guard case .wait = message else {
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return .actionResult(ActionResult(
                success: false,
                method: .wait,
                message: "timed out after 0.2s — expectation not met",
                errorKind: .timeout,
                accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
            ))
        }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("element_disappeared"),
                "element": .object(["label": .string("Loading")]),
            ]),
            "timeout": .double(0.2),
        ])

        guard let leaf = response.leafAction else {
            return XCTFail("Expected single-step action response, got \(response)")
        }
        XCTAssertEqual(leaf.expectation?.met, false)
        XCTAssertEqual(leaf.result.message, "timed out after 0.2s — expectation not met")
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
        XCTAssertEqual(message, "Invalid predicate type: expected object with a \"type\" discriminator")
        XCTAssertEqual(details?.errorCode, "request.invalid")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testActionExpectationExecutesAsServerSideExpectationStep() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "Home")))
        let interface = makeReceiptTestInterface([
            testElement(label: "Home", traits: [.staticText]),
        ])
        let trace = AccessibilityTrace.projectingForTests(.screenChanged(.init(
            elementCount: 1,
            newInterface: interface
        )))

        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: trace
                ))
            case .wait:
                return .actionResult(ActionResult(
                    success: true,
                    method: .wait,
                    message: "expectation met after observed change",
                    accessibilityTrace: trace
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .object([
                "type": .string("element_appeared"),
                "element": .object(["label": .string("Home")]),
            ]),
        ])

        // The action and its expectation cross the wire as one heist plan; the
        // expectation is a server-side step on the action, not a separate
        // client-issued wait round-trip.
        XCTAssertEqual(mockConn.sent.count, 1)
        guard case .action(let step)? = mockConn.sent.sentHeistPlan?.body.first else {
            return XCTFail("Expected a single action step, got \(String(describing: mockConn.sent.sentHeistPlan))")
        }
        XCTAssertEqual(step.expectation?.predicate, .predicate(predicate))

        guard let leaf = response.leafAction else {
            return XCTFail("Expected single-step action response, got \(response)")
        }
        XCTAssertEqual(leaf.expectation?.met, true)
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
        XCTAssertEqual(result, .changed(.screen()))
    }

    func testNormalizeToolCallRoutesWithoutParsingRequestArguments() throws {
        let result = TheFence.Command.routeToolCall(named: "activate")

        guard case .success(let command) = result else {
            return XCTFail("Expected successful command, got \(result)")
        }

        XCTAssertEqual(command, .activate)
    }

    func testNormalizeToolCallRejectsNonMCPCommands() {
        let result = TheFence.Command.routeToolCall(named: "help")

        guard case .failure(let error) = result else {
            return XCTFail("Expected non-MCP command rejection, got \(result)")
        }

        XCTAssertEqual(error.message, "Unknown tool: help")
    }

    func testRemovedProductCommandsAreUnknown() {
        let removedCommands = [
            "start_recording",
            "stop_recording",
            "archive_session",
            "get_session_log",
            "quit",
            "pinch",
            "rotate",
            "two_finger_tap",
        ]

        for commandName in removedCommands {
            XCTAssertNil(TheFence.Command(rawValue: commandName), commandName)

            let routed = TheFence.Command.routeCommandEnvelope(
                .init(values: [
                    "command": .string(commandName),
                ]),
                context: "direct command"
            )
            guard case .failure(let error) = routed else {
                return XCTFail("Expected \(commandName) to be rejected")
            }
            XCTAssertTrue(error.message.contains("unknown command \"\(commandName)\""), error.message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationStringValuesThrowObjectRequired() async {
        for value in ["screen_changed", "elements_changed", "element_updated", "layout_changed", "bogus"] {
            XCTAssertThrowsError(try parseTypedExpectation(.string(value))) { error in
                guard case FenceError.invalidRequest(let msg) = error else {
                    XCTFail("Expected FenceError.invalidRequest, got \(error)")
                    return
                }
                XCTAssertEqual(msg, "Invalid predicate type: expected object with a \"type\" discriminator")
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
            XCTAssertTrue(msg.contains("Invalid predicate type"))
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
    func testHeistPlanCarriesTypedActionExpectation() async throws {
        let expectation = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(
            element: ElementPredicate(identifier: "counter"), property: .value, to: "5"
        )))
        let sourceStep = HeistStep.action(try ActionStep(
            command: .activate(.predicate(ElementPredicate(identifier: "counter"))),
            expectation: WaitStep(predicate: expectation, timeout: 10)
        ))
        let plan = HeistPlan(body: [sourceStep])
        guard case .action(let action)? = plan.body.first else {
            return XCTFail("Expected action step")
        }

        XCTAssertEqual(action.expectation?.predicate, .predicate(expectation))
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorScreenChanged() async throws {
        let result = try parseTypedExpectation(.object(["type": .string("screen_changed")]))
        XCTAssertEqual(result, .changed(.screen()))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_updated"),
            "element": .object(["identifier": .string("slider")]),
            "property": .string("value"),
            "from": .string("0"),
            "to": .string("50"),
        ]))
        XCTAssertEqual(
            result,
            .changed(.updated(ElementUpdatePredicate(
            element: ElementPredicate(identifier: "slider"), property: .value, from: "0", to: "50"
            )))
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
        XCTAssertEqual(result, .changed(.updated(.any)))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementAppearedWithElement() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "element": .object(["label": .string("Cart"), "identifier": .string("cart.button")]),
        ]))
        XCTAssertEqual(
            result,
            .changed(.appeared(ElementPredicate(label: "Cart", identifier: "cart.button")))
        )
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadPreservesElementTraits() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("element_disappeared"),
            "element": .object([
                "label": .string("Spinner"),
                "traits": .array([.string("button")]),
                "excludeTraits": .array([.string("selected")]),
            ]),
        ]))

        XCTAssertEqual(
            result,
            .changed(.disappeared(
                ElementPredicate(label: "Spinner", traits: [.button], excludeTraits: [.selected])
            ))
        )
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadBadElementFieldNamesField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "element": .object([
                "traits": .array([.int(7)]),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "element.traits[0]")
            XCTAssertEqual(error.expected, "string")
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsDeletedDeliveryType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("delivery"),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains(#"Unknown predicate type: "delivery""#), message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsExtraElementKeys() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "element": .object([
                "label": .string("Done"),
                "unknown": .string("ignored before"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"Unknown element predicate field "unknown""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationElementRejectsHeistId() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("element_appeared"),
            "element": .object([
                "heistId": .string("button_save"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"Unknown element predicate field "heistId""#)
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
    func testParseExpectationDiscriminatorElementAppearedWithoutElementThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("element_appeared")]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "element")
            XCTAssertEqual(error.observed, "missing")
            XCTAssertEqual(error.expected, "present")
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsCompoundType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("compound"),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains(#"Unknown predicate type: "compound""#), message)
            XCTAssertTrue(message.contains("screen_changed"), message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorUnknownTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("bogus_type")]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown predicate type"))
        }
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
        let response = try await fence.execute(
            command: .getScreen,
            arguments: TheFence.CommandArgumentEnvelope(
                values: [:],
                elementTarget: ElementTarget.predicate(ElementPredicate(label: "Save"))
            )
        )

        guard case .error(let message, _) = response else {
            return XCTFail("Expected typed element target to be rejected")
        }
        XCTAssertEqual(
            message,
            #"schema validation failed for target: observed target(predicate(label="Save")); expected get_screen command without element target"#
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
        XCTAssertEqual(interface["screenDescription"] as? String, "Menu — 2 buttons")
        XCTAssertEqual(interface["screenId"] as? String, "menu")
        let navigation = interface["navigation"] as! [String: Any]
        XCTAssertEqual(navigation["screenTitle"] as? String, "Menu")
        XCTAssertNil(navigation["backButton"])
        XCTAssertNil(navigation["tabBarItems"])
        let tree = interface["tree"] as! [[String: Any]]
        XCTAssertEqual(tree.count, 3)
        let container = tree[1]["container"] as! [String: Any]
        XCTAssertEqual(container["containerName"] as? String, "semantic_actions__actions")
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
                "container": .object(["containerName": .string("semantic_actions__actions")]),
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
        XCTAssertEqual(container["containerName"] as? String, "semantic_actions__actions")
        let children = container["children"] as! [[String: Any]]
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual((children[0]["element"] as? [String: Any])?["label"] as? String, "Submit")
        XCTAssertNil((children[0]["element"] as? [String: Any])?["heistId"])
        XCTAssertEqual((children[1]["element"] as? [String: Any])?["label"] as? String, "Cancel")
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
            contains: "Unknown element target field \"heistId\""
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

    func testContainerNameAppearsInSummaryJsonAndCompactOutput() {
        let response = FenceResponse.interface(selectionTestInterface(), detail: .summary)

        let json = publicJSONObject(response)
        let interface = json["interface"] as! [String: Any]
        let tree = interface["tree"] as! [[String: Any]]
        let container = tree[1]["container"] as! [String: Any]
        XCTAssertEqual(container["containerName"] as? String, "semantic_actions__actions")
        XCTAssertEqual(container["containerName"] as? String, "semantic_actions__actions")
        XCTAssertNil(container["frameX"], "summary should expose identity, not geometry")

        let compact = response.compactFormatted()
        XCTAssertTrue(
            compact.contains(#"group label="Actions" id="actions" containerName="semantic_actions__actions""#),
            compact
        )
        XCTAssertFalse(compact.contains("stableId"), compact)
    }

    @ButtonHeistActor
    func testGetInterfaceSendsMatcherInObservationQuery() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let submit = testElement(label: "Submit", traits: [.button])
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
        XCTAssertEqual(element["label"] as? String, "Submit")
        XCTAssertNil(element["heistId"])
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

}

private func legacyHeistIdTargetValue(_ legacyHeistId: String) -> HeistValue {
    elementTargetValue(["heistId": .string(legacyHeistId)])
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

private func parseTypedExpectation(_ expectation: HeistValue?) throws -> AccessibilityPredicate? {
    var values: [String: HeistValue] = [:]
    if let expectation {
        values["expect"] = expectation
    }
    return try TheFence.ExpectationPayload(
        arguments: TheFence.CommandArgumentEnvelope(values: values)
    ).expectation
}
