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
    func testEveryBatchExecutableCommandLowersToTheSameClientMessageAsSingleCommand() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.batchExecutableCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)
            let singleMessages = try fence.executableActionMessages(for: singleRequest)
            XCTAssertFalse(singleMessages.isEmpty, command.rawValue)

            let batchRequest = try fence.decodeRunBatchRequest(TheFence.CommandArgumentEnvelope(values: [
                "steps": .array([batchStep(command, arguments)]),
            ]))
            let batchMessages = batchRequest.steps.map(\.typedStep.command)

            XCTAssertEqual(
                String(reflecting: batchMessages),
                String(reflecting: singleMessages),
                command.rawValue
            )
        }
    }

    @ButtonHeistActor
    func testEveryPlaybackStepLowersToTheSameClientMessageAsSingleCommand() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.batchExecutableCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)
            let singleMessages = try fence.executableActionMessages(for: singleRequest)
            XCTAssertFalse(singleMessages.isEmpty, command.rawValue)

            let sourceStep = try heistStep(command: command, fields: arguments)
            let playback = try fence.validateHeistPlayback(
                HeistPlayback(app: "com.test.mock", steps: [sourceStep])
            )
            let playbackMessages = playback.batchRequest.steps.map(\.typedStep.command)

            XCTAssertEqual(
                String(reflecting: playbackMessages),
                String(reflecting: singleMessages),
                command.rawValue
            )
        }
    }

    func testEveryTypedClientMessageOwnsItsWireIdentity() throws {
        let samples = sampleClientMessages()
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
        case .scrollToVisible, .elementSearch, .activate, .waitFor:
            return ["target": target]
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
        case .waitForChange:
            return [:]
        case .runBatch:
            return ["steps": .array([batchStep(.activate, ["target": target])])]
        case .connect:
            return ["target": .string("default")]
        case .stopHeist:
            return ["output": .string("contract.heist")]
        case .playHeist:
            return ["input": .string("contract.heist")]
        }
    }

    private func sampleClientMessages() -> [ClientMessage] {
        let target = ElementTarget.matcher(ElementMatcher(identifier: "target"))
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
            .waitFor(WaitForTarget(elementTarget: target)),
            .waitForChange(WaitForChangeTarget(timeout: 1)),
            .batchExecutionPlan(BatchPlan(steps: [
                BatchStep(command: .activate(target), expectation: nil, deadline: Deadline()),
            ])),
        ]
    }

    private func encodedWireType(for message: ClientMessage) throws -> ClientWireMessageType {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(EncodedClientType.self, from: data).type
    }

    private func batchStep(
        _ command: TheFence.Command,
        _ fields: [String: HeistValue] = [:]
    ) -> HeistValue {
        var object = fields
        object["command"] = .string(command.rawValue)
        return .object(object)
    }

    @ButtonHeistActor
    private func heistStep(
        command: TheFence.Command,
        fields: [String: HeistValue]
    ) throws -> HeistStep {
        var arguments = fields
        let target = try playbackTarget(from: &arguments)
        return try HeistStep(command: command.rawValue, target: target, arguments: arguments)
    }

    @ButtonHeistActor
    private func playbackTarget(from fields: inout [String: HeistValue]) throws -> ElementTarget? {
        guard let targetValue = fields.removeValue(forKey: "target") else { return nil }
        return try TheFence.CommandArgumentEnvelope(values: ["target": targetValue])
            .decodedElementTarget()
    }
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
