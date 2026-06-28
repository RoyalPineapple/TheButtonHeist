import XCTest
import ThePlans
@testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class WireCommandParityTests: XCTestCase {

    func testEveryCommandHasExactlyOneDescriptor() {
        let descriptorCommands = TheFence.Command.descriptors.map(\.command)
        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
    }

    func testCommandFamiliesHaveNoDuplicateRawValuesAndCoverEveryCommand() {
        let familyDescriptors = FenceCommandRegistry.families.flatMap(\.descriptors)
        let familyCommands = familyDescriptors.map(\.command)

        XCTAssertEqual(familyCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(familyCommands), Set(TheFence.Command.allCases))
        XCTAssertEqual(familyCommands.count, Set(familyCommands).count)
        XCTAssertEqual(
            familyDescriptors.map(\.family),
            familyDescriptors.map { $0.command.family }
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

        XCTAssertNil(ObservationCommand(rawValue: TheFence.Command.wait.rawValue))
        XCTAssertEqual(AssertionCommand.wait.command, .wait)
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
        XCTAssertNotNil(TheFence.Command.scroll.viewportDebugCommand)
        XCTAssertFalse(TheFence.Command.scroll.lowersToHeistPrimitive)
        XCTAssertFalse(TheFence.Command.scroll.usesPayloadCheckedHeistPrimitive)
    }

    func testDescriptorDoesNotExposeBehaviorCapabilityFlags() throws {
        let catalogSource = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift")
        )
        for removedFlag in [
            "isNormalRecordable",
            "recordsHeistStep",
            "isDurableHeistPrimitive",
            "isObservation",
            "isViewportDebug",
            "isSemanticAction",
            "isSpatialAction",
            "FenceCommandCapabilities",
            "RecordableCommand",
            "AppInteractionCommand",
            "HeistPrimitiveCommand",
            "PayloadCheckedHeistPrimitiveCommand",
        ] {
            XCTAssertFalse(catalogSource.contains(removedFlag), removedFlag)
        }
    }

    func testGeneratedCommandReferenceDisplaysFamilyGrouping() {
        let reference = FenceCommandReference.commandMarkdown()

        XCTAssertTrue(reference.contains("| Command | Family | CLI | MCP | Description |"), reference)
        XCTAssertTrue(reference.contains("| `wait` | `assertion` |"), reference)
        XCTAssertTrue(reference.contains("| `scroll` | `viewportDebug` |"), reference)
        XCTAssertFalse(reference.contains("Recordable"), reference)
        XCTAssertFalse(reference.contains("Durable"), reference)
    }

    func testCommittedCommandReferenceDocsMatchDescriptorProjection() throws {
        try assertReferenceDocInSync(
            relativePath: "docs/reference/commands.md",
            generated: FenceCommandReference.commandMarkdown()
        )
        try assertReferenceDocInSync(
            relativePath: "docs/reference/mcp-tools.md",
            generated: FenceCommandReference.mcpMarkdown()
        )
    }

    private func assertReferenceDocInSync(
        relativePath: String,
        generated: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let committed = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(
            committed,
            generated,
            "\(relativePath) is stale. Regenerate with scripts/render-command-reference.sh.",
            file: file,
            line: line
        )
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
            TheFence.Command.scroll.descriptor.requiredDefaultEnumValue(for: .direction, as: ScrollDirection.self),
            .down
        )
        XCTAssertEqual(
            TheFence.Command.scrollToEdge.descriptor.requiredDefaultEnumValue(for: .edge, as: ScrollEdge.self),
            .top
        )
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.requiredDefaultEnumValue(for: .direction, as: RotorDirection.self),
            .next
        )
        XCTAssertEqual(
            TheFence.Command.listHeists.descriptor.requiredDefaultEnumValue(for: .detail, as: HeistCatalogDetail.self),
            .summary
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
    func testEveryExecutableSingleCommandLowersToTheSameRuntimeActionAsSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.allCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)
            let singleStepPlan = try fence.singleStepHeistPlan(for: singleRequest)

            guard let singleMessages = singleRequest.runtimeActionMessages, !singleMessages.isEmpty else {
                XCTAssertNil(singleStepPlan, command.rawValue)
                continue
            }

            let plan = try XCTUnwrap(singleStepPlan, command.rawValue)
            let heistMessages = plan.body.flatMap(runtimeActions(for:))

            XCTAssertEqual(
                String(reflecting: heistMessages),
                String(reflecting: singleMessages),
                command.rawValue
            )
        }
    }

    @ButtonHeistActor
    func testViewportDebugCommandsAreCLIDirectOnlyAndRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in [TheFence.Command.scroll, .scrollToVisible, .scrollToEdge] {
            let descriptor = command.descriptor
            XCTAssertEqual(descriptor.family, .viewportDebug, command.rawValue)
            XCTAssertEqual(descriptor.cliExposure, .directCommand, command.rawValue)
            XCTAssertEqual(descriptor.mcpExposure, .notExposed, command.rawValue)
            XCTAssertTrue(command.dispatchesAppInteraction, command.rawValue)
            XCTAssertNotNil(command.viewportDebugCommand, command.rawValue)
            XCTAssertFalse(command.lowersToHeistPrimitive, command.rawValue)
            XCTAssertFalse(command.usesPayloadCheckedHeistPrimitive, command.rawValue)

            let request = try fence.parseRequest(command: command, values: sampleArguments(for: command))
            let singleMessages = try fence.executableRuntimeActions(for: request)
            XCTAssertFalse(singleMessages.isEmpty, command.rawValue)

            let plan = try XCTUnwrap(fence.singleStepHeistPlan(for: request), command.rawValue)
            let heistMessages = plan.body.flatMap(runtimeActions(for:))
            XCTAssertEqual(String(reflecting: heistMessages), String(reflecting: singleMessages), command.rawValue)
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
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getSessionState,
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
                    "type": .string("change"),
                    "scopes": .array([.object(["type": .string("elements")])]),
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
            .requestScreen,
            .heistPlan(HeistPlanRun(plan: try HeistPlan(body: [
                .action(try ActionStep(command: .activate(.identifier(.literal("target"))))),
            ]))),
        ]
    }

    private func encodedWireType(for message: ClientMessage) throws -> ClientWireMessageType {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(EncodedClientType.self, from: data).type
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryRoot() -> URL {
        packageRoot().deletingLastPathComponent()
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
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
