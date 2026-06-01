import XCTest
@testable import ButtonHeist
import TheScore

final class WireCommandParityTests: XCTestCase {

    func testEveryCommandHasExactlyOneDescriptor() {
        let descriptorCommands = TheFence.Command.descriptors.map(\.command)
        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
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
            let playback = try fence.validateHeistPlayback(HeistPlan(steps: [sourceStep]))
            let playbackMessages = playback.plan.steps.flatMap(clientMessages(for:))

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
            return ["x": .double(12), "y": .double(34)]
        case .longPress:
            return ["x": .double(12), "y": .double(34)]
        case .swipe:
            return ["target": target, "direction": .string(SwipeDirection.left.rawValue)]
        case .drag:
            return ["target": target, "endX": .double(120), "endY": .double(240)]
        case .scroll:
            return ["direction": .string(ScrollDirection.down.rawValue)]
        case .scrollToVisible, .elementSearch, .activate:
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
                "steps": .array([heistStepValue(
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
            .elementSearch(ElementSearchTarget(elementTarget: target)),
            .scrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
            .wait(WaitTarget(predicate: .changed(.elements), timeout: 1)),
            .heistPlan(HeistPlan(steps: [
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
            return [action.command]
        case .wait(let wait):
            return [.wait(WaitTarget(predicate: wait.predicate, timeout: wait.timeout))]
        case .warn, .fail:
            return []
        }
    }
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
