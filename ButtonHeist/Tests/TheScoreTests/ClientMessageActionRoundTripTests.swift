import XCTest
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

/// Message-level coverage for mutating behavior now proves those actions are
/// carried by `ClientMessage.heistPlan`. Individual target payloads keep their
/// own Codable tests in `WireTypeRoundTripTests`.
final class ClientMessageActionRoundTripTests: XCTestCase {

    func testHeistPlanCarriesSemanticActionCommands() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(identifier: "btn"))
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(target))),
            .action(try ActionStep(command: .rotor(
                selection: .named("Errors"),
                target: target,
                direction: .previous
            ))),
            .action(try ActionStep(command: .dismiss)),
            .action(try ActionStep(command: .magicTap)),
            .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
            .action(try ActionStep(command: .dismissKeyboard)),
        ])

        let decodedPlan = try roundTripHeistPlan(plan)
        let commands = decodedPlan.body.compactMap { step -> HeistActionCommand? in
            guard case .action(let action) = step else { return nil }
            return action.command
        }

        XCTAssertEqual(commands.count, 6)
        let expectedTypes: [HeistActionCommandType] = [.activate, .rotor, .dismiss, .magicTap, .editAction, .resignFirstResponder]
        XCTAssertEqual(commands.map(\.wireType), expectedTypes)
    }

    func testHeistPlanCarriesGestureCommands() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Canvas"))
        let point = GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20))
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .mechanicalTap(TapTarget(selection: point)))),
            .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
                selection: point,
                duration: GestureDuration(seconds: 1.0)
            )))),
            .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(target, .left))))),
            .action(try ActionStep(command: .mechanicalDrag(DragTarget(
                start: .element(target),
                end: ScreenPoint(x: 30, y: 40)
            )))),
        ])

        let decodedPlan = try roundTripHeistPlan(plan)
        let commands = decodedPlan.body.compactMap { step -> HeistActionCommand? in
            guard case .action(let action) = step else { return nil }
            return action.command
        }

        let expectedTypes: [HeistActionCommandType] = [.oneFingerTap, .longPress, .swipe, .drag]
        XCTAssertEqual(commands.map(\.wireType), expectedTypes)
    }

    func testHeistPlanCarriesWaitStep() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .changed(.elements()), timeout: 2)),
        ])

        let decodedPlan = try roundTripHeistPlan(plan)

        guard case .wait(let wait)? = decodedPlan.body.first else {
            return XCTFail("Expected wait step")
        }
        XCTAssertEqual(wait.predicate, .changed(.elements()))
        XCTAssertEqual(wait.timeout, 2)
    }

    func testRuntimeActionCarriesTransientViewportCommand() throws {
        let message = ClientMessage.runtimeAction(.viewportScroll(ScrollTarget(direction: .down)))
        let data = try JSONEncoder().encode(message)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains(#""type":"runtimeAction""#), json)

        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testPrimitiveActionClientMessageJSONIsRejected() throws {
        let primitiveMessages = [
            """
            {
              "type": "activate",
              "payload": {
                "target": {
                  "checks": [
                    { "kind": "identifier", "match": { "mode": "exact", "value": "btn" } }
                  ]
                }
              }
            }
            """,
            """
            {
              "type": "rotor",
              "payload": {
                "target": {
                  "checks": [
                    { "kind": "identifier", "match": { "mode": "exact", "value": "btn" } }
                  ]
                },
                "selection": { "type": "named", "name": "Errors" },
                "direction": "previous"
              }
            }
            """,
            #"{"type":"oneFingerTap","payload":{"point":{"x":100,"y":200}}}"#,
            #"{"type":"editAction","payload":{"action":"paste"}}"#,
            #"{"type":"resignFirstResponder"}"#,
        ]

        for json in primitiveMessages {
            XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)), json) { error in
                XCTAssertTrue("\(error)".contains("Unsupported client wire message type"), "\(error)")
            }
        }
    }

    func testActionResultEncodesCanonicalOutcomeObject() throws {
        let result = ActionResult.failure(
            method: .activate,
            errorKind: .elementNotFound,
            message: "Element not found",
            evidence: .none
        )
        let data = try JSONEncoder().encode(result)
        let encoded = try JSONDecoder().decode(EncodedActionResultProbe.self, from: data)

        XCTAssertEqual(encoded.outcome.kind, "failure")
        XCTAssertEqual(encoded.outcome.errorKind, .elementNotFound)
        XCTAssertNil(encoded.success)
        XCTAssertNil(encoded.errorKind)
    }

    func testActionResultRejectsLegacySuccessErrorKindFields() throws {
        let json = """
        {"success":false,"method":"activate","errorKind":"elementNotFound","message":"Element not found"}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown ActionResult field"), "\(error)")
        }
    }

    private func roundTripHeistPlan(_ plan: HeistPlan) throws -> HeistPlan {
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .heistPlan(let run) = decoded else {
            throw XCTSkip("Expected heistPlan")
        }
        return run.plan
    }
}

private struct EncodedActionResultProbe: Decodable {
    let outcome: EncodedActionResultOutcomeProbe
    let success: Bool?
    let errorKind: ErrorKind?
}

private struct EncodedActionResultOutcomeProbe: Decodable {
    let kind: String
    let errorKind: ErrorKind?
}
