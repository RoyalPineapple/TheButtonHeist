import XCTest
@testable import ButtonHeist
import TheScore

final class WireCommandParityTests: XCTestCase {

    func testEveryCommandHasExactlyOneDescriptor() {
        let descriptorCommands = TheFence.Command.descriptors.map(\.command)
        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
    }

    func testRunHeistDescriptorAdvertisesPublicJSONPlanStepTypes() {
        let descriptor = TheFence.Command.descriptor(for: .runHeist)
        let body = descriptor.parameters.first { $0.key == "body" }
        let type = body?.arrayItemProperties.first { $0.key == "type" }

        XCTAssertEqual(
            type?.enumValues,
            ["action", "wait", "conditional", "wait_for_cases", "for_each_element", "for_each_string", "warn", "fail"]
        )
    }

    func testDescriptorLookupFindsEquivalentNestedParameters() {
        let direction = TheFence.Command.swipe.descriptor.parameter(named: .direction)

        XCTAssertEqual(direction?.enumValues, fenceEnumValues(SwipeDirection.self))
    }

    func testDescriptorDefaultsOwnCommandFallbackValues() {
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
        XCTAssertTrue(tap.localizedCaseInsensitiveContains("ordinary control activation should use activate"), tap)

        XCTAssertTrue(scroll.localizedCaseInsensitiveContains("explicit viewport operation"), scroll)
        XCTAssertTrue(scrollToVisible.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scrollToVisible)
        XCTAssertTrue(scrollToEdge.localizedCaseInsensitiveContains("explicit viewport operation"), scrollToEdge)
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
    func testEveryHeistExecutableCommandLowersToTheSameClientMessageAsSingleCommand() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.heistExecutableCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)
            let singleMessages = try fence.executableActionMessages(for: singleRequest)
            XCTAssertFalse(singleMessages.isEmpty, command.rawValue)

            let heistStep = try fence.heistStep(for: singleRequest)
            let heistMessages = clientMessages(for: heistStep)

            XCTAssertEqual(
                String(reflecting: heistMessages),
                String(reflecting: singleMessages),
                command.rawValue
            )
        }
    }

    @ButtonHeistActor
    func testEveryPlaybackStepLowersToTheSameClientMessageAsSingleCommand() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.heistExecutableCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)
            let singleMessages = try fence.executableActionMessages(for: singleRequest)
            XCTAssertFalse(singleMessages.isEmpty, command.rawValue)

            let sourceStep = try fence.heistStep(for: singleRequest)
            let playback = try fence.validateHeistPlayback(HeistPlan(body: [sourceStep]))
            let playbackMessages = playback.plan.body.flatMap(clientMessages(for:))

            XCTAssertEqual(
                String(reflecting: playbackMessages),
                String(reflecting: singleMessages),
                command.rawValue
            )
        }
    }

    func testEveryTypedClientMessageOwnsItsWireIdentity() throws {
        let samples = try sampleClientMessages()
        XCTAssertEqual(Set(samples.map(\.wireType)), Set(ClientWireMessageType.allCases))

        for message in samples {
            XCTAssertEqual(try encodedWireType(for: message), message.wireType, "\(message)")
        }
    }

    @ButtonHeistActor
    private func sampleArguments(for command: TheFence.Command) -> [String: HeistValue] {
        let target = targetArgumentValue(identifier: "target")
        switch command {
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getSessionState,
             .listTargets, .startHeist, .dismissKeyboard:
            return [:]
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
                "predicate": .object(["type": .string("elements_changed")]),
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
        case .runHeist:
            return [
                "version": .int(HeistPlan.currentVersion),
                "body": .array([heistStepValue(
                    type: "action",
                    payload: [
                        "command": .object([
                            "type": .string(ClientWireMessageType.activate.rawValue),
                            "payload": target,
                        ]),
                    ]
                )]),
            ]
        case .connect:
            return ["target": .string("default")]
        case .stopHeist:
            return ["output": .string("contract.heist")]
        case .playHeist:
            return ["input": .string("contract.heist")]
        }
    }

    private func sampleClientMessages() throws -> [ClientMessage] {
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        let point = GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20))
        return [
            .clientHello,
            .authenticate(AuthenticatePayload(token: "token")),
            .requestInterface(InterfaceQuery()),
            .ping,
            .status,
            .resignFirstResponder,
            .getPasteboard,
            .requestScreen,
            .activate(target),
            .increment(target),
            .decrement(target),
            .performCustomAction(CustomActionTarget(elementTarget: target, actionName: "Open")),
            .rotor(RotorTarget(elementTarget: target, selection: .named("Headings"))),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .oneFingerTap(TapTarget(selection: point)),
            .longPress(LongPressTarget(selection: point)),
            .swipe(SwipeTarget(selection: .elementDirection(target, .left))),
            .drag(DragTarget(start: .element(target), end: ScreenPoint(x: 30, y: 40))),
            .typeText(TypeTextTarget(text: "hello")),
            .scroll(ScrollTarget(direction: .down)),
            .scrollToVisible(ScrollToVisibleTarget(elementTarget: target)),
            .scrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
            .wait(WaitTarget(predicate: .changed(.elements), timeout: 1)),
            .heistPlan(HeistPlan(body: [
                .action(try ActionStep(command: .activate(target))),
            ])),
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

    private func clientMessages(for step: HeistStep) -> [ClientMessage] {
        switch step {
        case .action(let action):
            guard let command = try? action.command.resolve(in: .empty) else { return [] }
            return [command]
        case .wait(let wait):
            guard let resolved = try? wait.resolve(in: .empty) else { return [] }
            return [.wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout))]
        case .conditional(let conditional):
            return conditional.cases.flatMap { $0.body.flatMap(clientMessages) }
                + (conditional.elseBody ?? []).flatMap(clientMessages)
        case .waitForCases(let waitForCases):
            return waitForCases.cases.flatMap { $0.body.flatMap(clientMessages) }
                + (waitForCases.elseBody ?? []).flatMap(clientMessages)
        case .forEachElement, .forEachString, .heist, .invoke:
            return []
        case .warn, .fail:
            return []
        }
    }
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
