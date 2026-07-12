import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class WireCommandParityTests: XCTestCase {

    func testEveryCommandHasExactlyOneDescriptor() {
        let descriptorCommands = TheFence.Command.descriptors.map(\.command)
        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
    }

    func testCommandFamiliesHaveNoDuplicateRawValuesAndCoverEveryCommand() {
        let descriptors = TheFence.Command.descriptors
        let descriptorCommands = descriptors.map(\.command)

        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
        XCTAssertEqual(descriptorCommands.count, Set(descriptorCommands).count)
        XCTAssertEqual(
            descriptors.map(\.family),
            descriptors.map { $0.command.family }
        )
    }

    func testCommandFamilyMembershipAndTypedGates() {
        XCTAssertEqual(TheFence.Command.ping.family, .session)
        XCTAssertEqual(TheFence.Command.getInterface.family, .observation)
        XCTAssertEqual(TheFence.Command.wait.family, .assertion)
        XCTAssertEqual(TheFence.Command.activate.family, .semanticAction)
        XCTAssertEqual(TheFence.Command.oneFingerTap.family, .spatialAction)
        XCTAssertEqual(TheFence.Command.scroll.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToVisible.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToEdge.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.perform.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.runHeist.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.listHeists.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.describeHeist.family, .heistRuntime)

        XCTAssertEqual(TheFence.Command.wait.descriptor.command, .wait)
        XCTAssertEqual(TheFence.Command.wait.descriptor.family, .assertion)
        XCTAssertTrue(TheFence.Command.wait.lowersToHeistPrimitive)
        XCTAssertFalse(TheFence.Command.wait.dispatchesAppInteraction)
        XCTAssertFalse(TheFence.Command.wait.usesPayloadCheckedHeistPrimitive)

        XCTAssertTrue(TheFence.Command.activate.dispatchesAppInteraction)
        XCTAssertTrue(TheFence.Command.activate.lowersToHeistPrimitive)
        XCTAssertFalse(TheFence.Command.activate.usesPayloadCheckedHeistPrimitive)

        XCTAssertTrue(TheFence.Command.oneFingerTap.dispatchesAppInteraction)
        XCTAssertTrue(TheFence.Command.oneFingerTap.lowersToHeistPrimitive)
        XCTAssertTrue(TheFence.Command.oneFingerTap.usesPayloadCheckedHeistPrimitive)

        XCTAssertTrue(TheFence.Command.scroll.dispatchesAppInteraction)
        XCTAssertTrue(TheFence.Command.scroll.isViewportDebugCommand)
        XCTAssertFalse(TheFence.Command.scroll.lowersToHeistPrimitive)
        XCTAssertFalse(TheFence.Command.scroll.usesPayloadCheckedHeistPrimitive)
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
        let descriptor = TheFence.Command.descriptor(for: .runHeist)
        let keys = Set(descriptor.parameters.map(\.key))

        XCTAssertTrue(keys.contains("path"))
        XCTAssertTrue(keys.contains("plan"))
        XCTAssertTrue(keys.contains("argument"))
        XCTAssertFalse(keys.contains("version"))
        XCTAssertFalse(keys.contains("name"))
        XCTAssertFalse(keys.contains("parameter"))
        XCTAssertFalse(keys.contains("definitions"))
        XCTAssertFalse(keys.contains("body"))
    }

    func testDescriptorLookupFindsEquivalentNestedParameters() {
        let direction = TheFence.Command.swipe.descriptor.parameter(named: .direction)

        XCTAssertEqual(direction?.enumValues, fenceEnumValues(SwipeDirection.self))
    }

    func testDescriptorDefaultsOwnCommandDefaultValues() {
        XCTAssertEqual(
            TheFence.Command.scroll.descriptor.requiredDefaultValue(for: FenceParameters.scrollDirection),
            .down
        )
        XCTAssertEqual(
            TheFence.Command.scrollToEdge.descriptor.requiredDefaultValue(for: FenceParameters.scrollEdge),
            .top
        )
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.requiredDefaultValue(for: FenceParameters.rotorDirection),
            .next
        )
        XCTAssertEqual(
            TheFence.Command.listHeists.descriptor.requiredDefaultValue(for: FenceParameters.heistCatalogDetail),
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

    func testDescriptorResponseAndFailureProjectionMetadata() {
        XCTAssertEqual(TheFence.Command.ping.descriptor.responseProjection, .pong)
        XCTAssertEqual(TheFence.Command.getInterface.descriptor.responseProjection, .interface)
        XCTAssertEqual(TheFence.Command.getScreen.descriptor.responseProjection, .screenshot)
        XCTAssertEqual(TheFence.Command.activate.descriptor.responseProjection, .heistExecution)
        XCTAssertEqual(TheFence.Command.scroll.descriptor.responseProjection, .action)
        XCTAssertEqual(TheFence.Command.listHeists.descriptor.responseProjection, .heistCatalog)
        XCTAssertEqual(TheFence.Command.describeHeist.descriptor.responseProjection, .heistDescription)
        XCTAssertTrue(TheFence.Command.descriptors.allSatisfy { $0.failureProjection == .diagnosticFailure })
    }

    @ButtonHeistActor
    func testTransientSingleStepDirectActionsUseDescriptorDispatchTimeout() async throws {
        let (fence, _) = makeConnectedFence()
        let request = try fence.parseRequest(command: .rotor, values: [
            "target": targetArgumentValue(identifier: "target"),
            "rotorIndex": .int(0),
        ])

        guard case .directAction(let directAction) = request.dispatch else {
            return XCTFail("Indexed rotor should decode as transient direct action")
        }
        XCTAssertEqual(directAction.command, .rotor)
        XCTAssertNotNil(directAction.action.durableHeistActionFailure)
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.timeout.requiredDirectDispatchSeconds,
            FenceCommandFixedTimeout.standardAction.seconds
        )
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
    func testEveryPublicCommandRoutesThroughDescriptorOwnedDecoder() async throws {
        let (fence, _) = makeConnectedFence()

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            XCTAssertNoThrow(
                try fence.parseRequest(command: descriptor.command, values: sampleArguments(for: descriptor.command)),
                descriptor.command.rawValue
            )
        }
    }

    @ButtonHeistActor
    func testDurableExecutableSingleCommandsLowerToTheSameRuntimeActionAsSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.allCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)

            switch singleRequest.dispatch {
            case .singleStepHeist(let heistRequest):
                let plan = try fence.singleStepHeistPlan(for: heistRequest)
                if case .wait(_, let wait) = heistRequest {
                    XCTAssertEqual(plan.body, [.wait(wait)], command.rawValue)
                    continue
                }

                guard case .actions(_, let actions, _) = heistRequest else {
                    XCTFail("Unknown single-step request for \(command.rawValue)")
                    continue
                }
                let singleCommands = actions.values
                let heistCommands = plan.body.flatMap(actionCommands(for:))

                XCTAssertEqual(
                    String(reflecting: heistCommands),
                    String(reflecting: singleCommands),
                    command.rawValue
                )
            case .directAction(let directAction):
                XCTAssertNotNil(directAction.action.durableHeistActionFailure, command.rawValue)
            case .handler:
                continue
            }
        }
    }

    @ButtonHeistActor
    func testViewportDebugCommandsAreCLIDirectOnlyAndDoNotRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in [TheFence.Command.scroll, .scrollToVisible, .scrollToEdge] {
            let descriptor = command.descriptor
            XCTAssertEqual(descriptor.family, .viewportDebug, command.rawValue)
            XCTAssertEqual(descriptor.cliExposure, .directCommand, command.rawValue)
            XCTAssertEqual(descriptor.mcpExposure, .notExposed, command.rawValue)
            XCTAssertTrue(command.dispatchesAppInteraction, command.rawValue)
            XCTAssertTrue(command.isViewportDebugCommand, command.rawValue)
            XCTAssertFalse(command.lowersToHeistPrimitive, command.rawValue)
            XCTAssertFalse(command.usesPayloadCheckedHeistPrimitive, command.rawValue)

            let request = try fence.parseRequest(command: command, values: sampleArguments(for: command))
            guard case .directAction(let directAction) = request.dispatch else {
                return XCTFail("\(command.rawValue) should decode as direct action")
            }
            XCTAssertNotNil(directAction.action.durableHeistActionFailure, command.rawValue)
        }
    }

    @ButtonHeistActor
    func testDurableRuntimeActionCommandsRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in [TheFence.Command.activate, .oneFingerTap, .typeText, .setPasteboard] {
            let request = try fence.parseRequest(command: command, values: sampleArguments(for: command))
            guard case .singleStepHeist(.actions(_, let actions, _)) = request.dispatch else {
                return XCTFail("\(command.rawValue) should decode as single-step action command")
            }
            let singleCommands = actions.values
            let plan = try fence.singleStepHeistPlan(for: try XCTUnwrap(request.singleStepHeistRequest))
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

    @ButtonHeistActor
    private func sampleArguments(for command: TheFence.Command) -> [String: HeistValue] {
        let target = targetArgumentValue(identifier: "target")
        switch command {
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements, .getSessionState,
             .listTargets, .dismissKeyboard:
            return [:]
        case .perform:
            return ["step": .string(#"Activate(.label("Pay"))"#)]
        case .oneFingerTap:
            return ["point": .object(["x": .double(12), "y": .double(34)])]
        case .longPress:
            return ["point": .object(["x": .double(12), "y": .double(34)])]
        case .swipe:
            return [
                "elementDirection": .object([
                    "element": target,
                    "direction": .string(SwipeDirection.left.rawValue),
                ]),
            ]
        case .drag:
            return [
                "elementToPoint": .object([
                    "element": target,
                    "end": .object(["x": .double(120), "y": .double(240)]),
                ]),
            ]
        case .scroll:
            return ["direction": .string(ScrollDirection.down.rawValue)]
        case .scrollToVisible, .activate:
            return ["target": target]
        case .wait:
            return [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .double(10),
            ]
        case .scrollToEdge:
            return ["edge": .string(ScrollEdge.bottom.rawValue)]
        case .rotor:
            return ["target": target, "rotor": .string("Headings")]
        case .typeText:
            return ["text": .string("hello")]
        case .editAction:
            return ["action": .string(EditAction.paste.rawValue)]
        case .setPasteboard:
            return ["text": .string("clipboard")]
        case .runHeist, .listHeists:
            return [
                "plan": .string("""
                HeistPlan("entry") {
                    Warn("ready")
                }
                """),
            ]
        case .describeHeist:
            return [
                "heist": .string("entry"),
                "plan": .string("""
                HeistPlan("entry") {
                    Warn("ready")
                }
                """),
            ]
        case .connect:
            return ["target": .string("default")]
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
                .action(try ActionStep(command: .activate(.identifier(.literal("target"))))),
            ]))),
        ]
    }

    private func encodedWireType(for message: ClientMessage) throws -> ClientWireMessageType {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(EncodedClientType.self, from: data).type
    }

    private func heistStepValue(type: String, payload: [String: HeistValue]) -> HeistValue {
        .object([
            "type": .string(type),
            type: .object(payload),
        ])
    }

    private func runtimeActions(for step: HeistStep) -> [RuntimeActionMessage] {
        switch step {
        case .action(let action):
            guard let command = try? action.command.resolveForRuntimeDispatch(in: .empty) else { return [] }
            return [command]
        case .wait(let wait):
            let waitActions: [RuntimeActionMessage]
            if let resolved = try? wait.resolve(in: .empty) {
                waitActions = [.wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout))]
            } else {
                waitActions = []
            }
            return waitActions + (wait.elseBody ?? []).flatMap(runtimeActions)
        case .conditional(let conditional):
            return conditional.cases.flatMap { $0.body.flatMap(runtimeActions) }
                + (conditional.elseBody ?? []).flatMap(runtimeActions)
        case .forEachElement, .forEachString, .repeatUntil, .heist, .invoke:
            return []
        case .warn, .fail:
            return []
        }
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
