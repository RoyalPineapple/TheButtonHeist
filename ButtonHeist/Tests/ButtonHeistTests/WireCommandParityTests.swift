import XCTest
@testable import ButtonHeist
import TheScore

final class WireCommandParityTests: XCTestCase {

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
        case .oneFingerTap:
            return ["x": .double(12), "y": .double(34)]
        case .longPress:
            return ["x": .double(12), "y": .double(34)]
        case .swipe:
            return ["target": target, "direction": .string(SwipeDirection.left.rawValue)]
        case .drag:
            return ["target": target, "endX": .double(120), "endY": .double(240)]
        case .pinch:
            return ["centerX": .double(50), "centerY": .double(60), "scale": .double(1.25)]
        case .rotate:
            return ["centerX": .double(50), "centerY": .double(60), "angle": .double(0.5)]
        case .twoFingerTap:
            return ["centerX": .double(50), "centerY": .double(60)]
        case .drawPath:
            return ["points": .array([
                .object(["x": .double(0), "y": .double(0)]),
                .object(["x": .double(10), "y": .double(10)]),
            ])]
        case .drawBezier:
            return [
                "startX": .double(0),
                "startY": .double(0),
                "segments": .array([
                    .object([
                        "cp1X": .double(10),
                        "cp1Y": .double(0),
                        "cp2X": .double(10),
                        "cp2Y": .double(10),
                        "endX": .double(20),
                        "endY": .double(20),
                    ]),
                ]),
            ]
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
        case .waitForChange, .dismissKeyboard:
            return [:]
        case .help, .ping, .quit, .listDevices, .getInterface, .getScreen, .getPasteboard,
             .startRecording, .stopRecording, .runBatch, .getSessionState, .connect,
             .listTargets, .getSessionLog, .archiveSession, .startHeist, .stopHeist,
             .playHeist:
            XCTFail("Unexpected non-batch command \(command.rawValue)")
            return [:]
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
            .explore,
            .stopRecording,
            .activate(target),
            .increment(target),
            .decrement(target),
            .performCustomAction(CustomActionTarget(elementTarget: target, actionName: "Open")),
            .rotor(RotorTarget(elementTarget: target, selection: .named("Headings"))),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .oneFingerTap(TapTarget(selection: point)),
            .longPress(LongPressTarget(selection: point)),
            .swipe(SwipeTarget(selection: .unitElement(
                target,
                start: SwipeDirection.left.defaultStart,
                end: SwipeDirection.left.defaultEnd,
                direction: .left
            ))),
            .drag(DragTarget(start: .element(target), end: ScreenPoint(x: 30, y: 40))),
            .pinch(PinchTarget(center: point, scale: 1.25)),
            .rotate(RotateTarget(center: point, angle: 0.5)),
            .twoFingerTap(TwoFingerTapTarget(center: point)),
            .drawPath(DrawPathTarget(points: [PathPoint(x: 0, y: 0), PathPoint(x: 10, y: 10)])),
            .drawBezier(DrawBezierTarget(
                startX: 0,
                startY: 0,
                segments: [BezierSegment(cp1X: 10, cp1Y: 0, cp2X: 10, cp2Y: 10, endX: 20, endY: 20)]
            )),
            .typeText(TypeTextTarget(text: "hello")),
            .scroll(ScrollTarget(direction: .down)),
            .scrollToVisible(ScrollToVisibleTarget(elementTarget: target)),
            .elementSearch(ElementSearchTarget(elementTarget: target)),
            .scrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
            .waitForIdle(WaitForIdleTarget(timeout: 1)),
            .waitFor(WaitForTarget(elementTarget: target)),
            .waitForChange(WaitForChangeTarget(timeout: 1)),
            .batchExecutionPlan(BatchPlan(steps: [
                BatchStep(command: .activate(target), expectation: .delivery, deadline: Deadline()),
            ])),
            .startRecording(RecordingConfig(fps: 8, scale: 1)),
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
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}
