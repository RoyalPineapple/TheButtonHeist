import ButtonHeistTestSupport
import XCTest
import TheScore

final class ActionResultPayloadWireTests: XCTestCase {
    func testActionResultWithValue() throws {
        let result = ActionResult.success(payload: .typeText("Hello World"))
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.outcome.isSuccess)
            XCTAssertEqual(decodedResult.method, .typeText)
            guard case .typeText(let string?) = decodedResult.payload else {
                XCTFail("Expected .typeText payload")
                return
            }
            XCTAssertEqual(string, "Hello World")
            XCTAssertNil(decodedResult.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithoutValue() throws {
        let result = ActionResult.success(payload: .oneFingerTap)
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.outcome.isSuccess)
            XCTAssertEqual(decodedResult.method, .oneFingerTap)
            XCTAssertEqual(decodedResult.payload, .oneFingerTap)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultValuePayloadWireShape() throws {
        let result = ActionResult.success(payload: .typeText("Hi"))
        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        XCTAssertEqual(try json.string("payload"), "Hi")
    }

    func testActionResultScreenshotPayloadWireShape() throws {
        let screen = ScreenPayload(
            pngData: "png",
            width: 390,
            height: 844,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )
        let result = ActionResult.success(payload: .screenshot(screen))

        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        let payload = try json.object("payload")
        XCTAssertEqual(try payload.string("pngData"), "png")
        XCTAssertEqual(try payload.double("width"), 390)
        XCTAssertEqual(try payload.double("height"), 844)
        _ = try payload.object("interface")

        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.payload, .screenshot(screen))
    }

    func testActionResultHeistPayloadWireShape() throws {
        let result = try HeistResult(steps: [], durationMs: 42)
        let actionResult = ActionResult.success(payload: .heist(result))

        let data = try JSONEncoder().encode(actionResult)
        let json = try JSONProbe(data: data)
        let payload = try json.object("payload")
        XCTAssertEqual(try payload.int("durationMs"), 42)

        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.payload, .heist(result))
    }

    func testActionResultRotorPayloadWireShape() throws {
        let rotor = RotorResult(
            rotor: "Errors",
            direction: .next,
            foundElement: HeistElement(
                description: "Email", label: "Email", value: nil, identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
            ),
            textRange: RotorTextRange(text: "@maria", startOffset: 10, endOffset: 16, rangeDescription: "[10..<16]")
        )
        let result = ActionResult.success(payload: .rotor(rotor))
        let data = try JSONEncoder().encode(result)
        let json = try JSONProbe(data: data)
        let payload = try json.object("payload")
        XCTAssertEqual(try payload.string("rotor"), "Errors")
        XCTAssertEqual(try payload.string("direction"), "next")
        let foundElement = try payload.object("foundElement")
        XCTAssertEqual(try foundElement.string("label"), "Email")
        XCTAssertNoThrow(try foundElement.assertMissing("heistId"), "heistId must never appear on the wire")
        let textRange = try payload.object("textRange")
        XCTAssertEqual(try textRange.string("text"), "@maria")
        XCTAssertEqual(try textRange.int("startOffset"), 10)
        XCTAssertEqual(try textRange.int("endOffset"), 16)
        XCTAssertEqual(try textRange.string("rangeDescription"), "[10..<16]")
    }

    func testRotorResultRejectsObsoleteFoundElementSnapshot() throws {
        let json = Data("""
        {"rotor":"Errors","direction":"next","foundElement":{"heistId":"old"}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(RotorResult.self, from: json))
    }
    func testActionResultPayloadDecodesFromExplicitJSON() throws {
        let json = """
        {
          "type": "actionResult",
          "payload": {
            "outcome": { "kind": "success" },
            "method": "typeText",
            "payload": "Hello",
            "evidence": { "observation": { "kind": "none" } }
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        guard case .actionResult(let result) = decoded,
              case .typeText(let string?) = result.payload else {
            XCTFail("Expected actionResult with .typeText payload, got \(decoded)")
            return
        }
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(string, "Hello")
    }

    func testActionResultWithoutOptionalFieldsFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"outcome":{"kind":"success"},"method":"oneFingerTap","evidence":{"observation":{"kind":"none"}}}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let result) = decoded {
            XCTAssertTrue(result.outcome.isSuccess)
            XCTAssertEqual(result.method, .oneFingerTap)
            XCTAssertEqual(result.payload, .oneFingerTap)
            XCTAssertNil(result.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }
}
