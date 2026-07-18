import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class WireCommandParityTests: XCTestCase {

    func testCommandDefinitionsOwnUniqueCanonicalNames() {
        let commands = TheFence.Command.allCases
        let names = commands.map(\.rawValue)

        XCTAssertEqual(names.count, Set(names).count)
        for command in commands {
            XCTAssertEqual(TheFence.Command(rawValue: command.rawValue), command)
        }
    }

    func testCommandFamilyMembership() {
        XCTAssertEqual(TheFence.Command.ping.descriptor.family, .session)
        XCTAssertEqual(TheFence.Command.getInterface.descriptor.family, .observation)
        XCTAssertEqual(TheFence.Command.wait.descriptor.family, .assertion)
        XCTAssertEqual(TheFence.Command.activate.descriptor.family, .semanticAction)
        XCTAssertEqual(TheFence.Command.oneFingerTap.descriptor.family, .spatialAction)
        XCTAssertEqual(TheFence.Command.scroll.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToVisible.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToEdge.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.perform.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.runHeist.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.validateHeist.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.listHeists.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.describeHeist.descriptor.family, .heistRuntime)

        XCTAssertEqual(TheFence.Command.wait.descriptor.command, .wait)
        XCTAssertEqual(TheFence.Command.wait.descriptor.family, .assertion)
    }

    func testDescriptorBackedCLIHelpDisplaysFamilyGrouping() {
        let help = TheFence.Command.cliJSONLinesHelp

        XCTAssertTrue(help.contains("wait"), help)
        XCTAssertTrue(help.contains("[assertion]"), help)
        XCTAssertTrue(help.contains("scroll"), help)
        XCTAssertTrue(help.contains("[viewportDebug]"), help)
        XCTAssertFalse(help.contains("Recordable"), help)
        XCTAssertFalse(help.contains("Durable"), help)
    }

    func testRunHeistDescriptorDoesNotAdvertiseRawJSONIRFields() {
        let descriptor = TheFence.Command.runHeist.descriptor
        let keys = Set(descriptor.parameters.map(\.key))

        XCTAssertTrue(keys.isSuperset(of: Set([
            FenceParameterKey.path,
            .plan,
            .argument,
        ].map(\.rawValue))))
        XCTAssertTrue(keys.isDisjoint(with: Set([
            FenceParameterKey.version,
            .name,
            .parameter,
            .definitions,
            .body,
        ].map(\.rawValue))))
    }

    func testValidateHeistDescriptorIsOfflineAndUsesCanonicalPlanSources() {
        let descriptor = TheFence.Command.validateHeist.descriptor
        let keys = Set(descriptor.parameters.map(\.key))

        XCTAssertFalse(descriptor.requiresConnectionBeforeDispatch)
        XCTAssertTrue(keys.isSuperset(of: Set([
            FenceParameterKey.path,
            .plan,
            .argument,
            .lint,
        ].map(\.rawValue))))
        XCTAssertFalse(keys.contains(FenceParameterKey.body.rawValue))
        XCTAssertEqual(
            descriptor.defaultValue(for: FenceParameters.heistValidationLint),
            .compositionQuality
        )
    }

    func testDescriptorLookupFindsEquivalentNestedParameters() {
        let direction = TheFence.Command.swipe.descriptor.parameter(named: .direction)

        XCTAssertEqual(direction?.enumValues, fenceEnumValues(SwipeDirection.self))
    }

    func testDescriptorDefaultsOwnCommandDefaultValues() {
        XCTAssertEqual(
            TheFence.Command.scroll.descriptor.defaultValue(for: FenceParameters.scrollDirection),
            .down
        )
        XCTAssertEqual(
            TheFence.Command.scrollToEdge.descriptor.defaultValue(for: FenceParameters.scrollEdge),
            .top
        )
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.defaultValue(for: FenceParameters.rotorDirection),
            .next
        )
        XCTAssertEqual(
            TheFence.Command.listHeists.descriptor.defaultValue(for: FenceParameters.heistCatalogDetail),
            .summary
        )
    }

    func testDescriptorTimeoutSemanticsOwnCommandTimeouts() {
        XCTAssertEqual(TheFence.Command.ping.descriptor.timeout, .fixed(.health))
        XCTAssertEqual(TheFence.Command.getInterface.descriptor.timeout, .fixed(.explore))
        XCTAssertEqual(TheFence.Command.getScreen.descriptor.timeout, .fixed(.screenCapture))
        XCTAssertEqual(TheFence.Command.runHeist.descriptor.timeout, .fixed(.longAction))
        XCTAssertEqual(TheFence.Command.wait.descriptor.timeout, .wait)
        XCTAssertEqual(TheFence.Command.activate.descriptor.timeout, .singleStepAction(base: .standardAction))
        XCTAssertEqual(TheFence.Command.typeText.descriptor.timeout, .singleStepAction(base: .longAction))
        XCTAssertEqual(TheFence.Command.perform.descriptor.timeout, .performStep)
    }

    @ButtonHeistActor
    func testTransientSingleStepDirectActionsUseDescriptorDispatchTimeout() async throws {
        let (fence, _) = makeConnectedFence()
        let request = try fence.parseRequest(command: .rotor, values: [
            FenceParameterKey.target.rawValue: targetArgumentValue(identifier: "target"),
            FenceParameterKey.rotorIndex.rawValue: .int(0),
        ])

        guard case .directAction(let directAction) = request.dispatch else {
            return XCTFail("Indexed rotor should decode as transient direct action")
        }
        XCTAssertNotNil(directAction.action.durableHeistActionFailure)
        XCTAssertEqual(directAction.timeout, FenceCommandFixedTimeout.standardAction.seconds)
    }

    func testCommandHelpKeepsAccessibilitySemanticAndMechanicalBoundaries() {
        let activate = TheFence.Command.activate.descriptor.description
        let tap = TheFence.Command.oneFingerTap.descriptor.description
        let scroll = TheFence.Command.scroll.descriptor.description
        let scrollToVisible = TheFence.Command.scrollToVisible.descriptor.description
        let scrollToEdge = TheFence.Command.scrollToEdge.descriptor.description

        XCTAssertTrue(activate.localizedCaseInsensitiveContains("primary accessibility activation"), activate)
        XCTAssertTrue(activate.localizedCaseInsensitiveContains("semantic UI element"), activate)
        XCTAssertFalse(activate.localizedCaseInsensitiveContains("tap"), activate)

        XCTAssertTrue(tap.localizedCaseInsensitiveContains("explicit mechanical/spatial tap"), tap)
        XCTAssertTrue(tap.localizedCaseInsensitiveContains("ordinary accessible controls should use the semantic command path"), tap)

        XCTAssertTrue(scroll.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scroll)
        XCTAssertTrue(scrollToVisible.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scrollToVisible)
        XCTAssertTrue(scrollToEdge.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scrollToEdge)
    }

    @ButtonHeistActor
    func testCLIAndMCPAdaptersPreserveRepresentativeAdmissionFailures() async throws {
        let (fence, _) = makeConnectedFence()
        let missingStep = try TheFence.Command.routeToolRequest(
            named: TheFence.Command.perform.rawValue,
            arguments: .init(values: [:])
        ).get()
        XCTAssertThrowsError(try fence.admit(missingStep)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, FenceParameterKey.step.rawValue)
        }

        let malformedDirection = try TheFence.Command.routeCLICommandEnvelope(
            .init(values: [
                FenceParameterKey.command.rawValue: .string(TheFence.Command.scroll.rawValue),
                FenceParameterKey.direction.rawValue: .string("sideways"),
            ]),
            context: "test"
        ).get()
        XCTAssertThrowsError(try fence.admit(malformedDirection)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, FenceParameterKey.direction.rawValue)
        }

        let unknownKey = "__unknown_parameter__"
        let unknownParameter = try TheFence.Command.routeCLICommandEnvelope(
            .init(values: [
                FenceParameterKey.command.rawValue: .string(TheFence.Command.ping.rawValue),
                unknownKey: .bool(true),
            ]),
            context: "test"
        ).get()
        XCTAssertThrowsError(try fence.admit(unknownParameter)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, unknownKey)
        }
    }

    @ButtonHeistActor
    func testAdmissionRejectsMissingSemanticRequirements() async throws {
        let (fence, _) = makeConnectedFence()

        XCTAssertThrowsError(try fence.admit(FenceCommandInput(
            command: .activate,
            arguments: .init(values: [:])
        ))) { error in
            XCTAssertEqual((error as? TheFence.MissingAccessibilityTarget)?.command, .activate)
        }
    }

    @ButtonHeistActor
    func testViewportDebugCommandsAreCLIDirectOnlyAndDoNotRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.scroll, [FenceParameterKey.direction.rawValue: .string(ScrollDirection.down.rawValue)]),
            (.scrollToVisible, [FenceParameterKey.target.rawValue: targetArgumentValue(identifier: "target")]),
            (.scrollToEdge, [FenceParameterKey.edge.rawValue: .string(ScrollEdge.bottom.rawValue)]),
        ]
        for (command, arguments) in cases {
            let descriptor = command.descriptor
            XCTAssertEqual(descriptor.family, .viewportDebug, command.rawValue)
            XCTAssertEqual(descriptor.cliExposure, .directCommand, command.rawValue)
            XCTAssertEqual(descriptor.mcpExposure, .notExposed, command.rawValue)

            let request = try fence.parseRequest(command: command, values: arguments)
            guard case .directAction(let directAction) = request.dispatch else {
                return XCTFail("\(command.rawValue) should decode as direct action")
            }
            XCTAssertNotNil(directAction.action.durableHeistActionFailure, command.rawValue)
        }
    }

    @ButtonHeistActor
    func testDurableRuntimeActionCommandsRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.activate, [FenceParameterKey.target.rawValue: targetArgumentValue(identifier: "target")]),
            (.oneFingerTap, [
                FenceParameterKey.point.rawValue: .object([
                    FenceParameterKey.x.rawValue: .double(12),
                    FenceParameterKey.y.rawValue: .double(34),
                ]),
            ]),
            (.typeText, [FenceParameterKey.text.rawValue: .string("hello")]),
            (.setPasteboard, [FenceParameterKey.text.rawValue: .string("clipboard")]),
        ]
        for (command, arguments) in cases {
            let request = try fence.parseRequest(command: command, values: arguments)
            guard case .singleStepHeist(let heistRequest) = request.dispatch,
                  case .actions(let actions, _, _) = heistRequest else {
                return XCTFail("\(command.rawValue) should decode as single-step action command")
            }
            let singleCommands = actions.values
            let plan = try fence.singleStepHeistPlan(for: heistRequest)
            let heistCommands = plan.body.flatMap(actionCommands(for:))

            XCTAssertEqual(String(reflecting: heistCommands), String(reflecting: singleCommands), command.rawValue)
        }
    }

    func testEveryPublicTypedClientMessageOwnsItsWireIdentity() throws {
        let samples = try sampleClientMessages()
        XCTAssertEqual(
            Set(samples.map(\.wireType)),
            Set(ClientWireMessageType.allCases)
        )

        for message in samples {
            XCTAssertEqual(try encodedWireType(for: message), message.wireType, "\(message)")
        }
    }

    private func sampleClientMessages() throws -> [ClientMessage] {
        return [
            .clientHello,
            .authenticate(AuthenticatePayload(token: "token")),
            .requestInterface(InterfaceQuery()),
            .ping,
            .status,
            .getPasteboard,
            .getAnnouncements,
            .requestScreen(),
            .runtimeAction(.viewportScroll(ScrollTarget(direction: .down))),
            .heistPlan(HeistPlanRun(plan: try HeistPlan(body: [
                .action(ActionStep(command: .activate(.identifier("target")))),
            ]))),
        ]
    }

    private func encodedWireType(for message: ClientMessage) throws -> ClientWireMessageType {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(EncodedClientType.self, from: data).type
    }

    private func actionCommands(for step: HeistStep) -> [HeistActionCommand] {
        switch step {
        case .action(let action):
            return [action.command]
        case .wait, .conditional, .forEachElement, .forEachString, .repeatUntil, .warn, .fail, .heist, .invoke:
            return []
        }
    }
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
