import XCTest
import ThePlans
import TheScore

final class HeistElementTests: XCTestCase {

    func testEquality() {
        let element1 = makeElement(label: "Button1")
        let element2 = makeElement(label: "Button1")
        let element3 = makeElement(label: "Button2")

        XCTAssertEqual(element1, element2)
        XCTAssertNotEqual(element1, element3)
    }

    func testHashable() {
        let element1 = makeElement(label: "Button1")
        let element2 = makeElement(label: "Button1")

        var set = Set<HeistElement>()
        set.insert(element1)
        set.insert(element2)

        XCTAssertEqual(set.count, 1)
    }

    func testEncodingRoundTrip() throws {
        let element = makeElement(label: "RoundTrip")

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(element, decoded)
    }

    func testElementWithAllFields() throws {
        let element = HeistElement(
            description: "A complex button",
            label: "Submit Form",
            value: "Enabled",
            identifier: "submit_button_id",
            frameX: 50, frameY: 100, frameWidth: 200, frameHeight: 60,
            actions: [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")]
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(decoded.description, "A complex button")
        XCTAssertEqual(decoded.label, "Submit Form")
        XCTAssertEqual(decoded.value, "Enabled")
        XCTAssertEqual(decoded.identifier, "submit_button_id")
        XCTAssertEqual(decoded.actions, [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")])
    }

    func testElementWithNilOptionals() throws {
        let element = HeistElement(
            description: "Minimal",
            label: nil,
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(element, decoded)
        XCTAssertNil(decoded.label)
        XCTAssertNil(decoded.value)
        XCTAssertNil(decoded.identifier)
    }

    func testElementWithRotorsRoundTrips() throws {
        let element = HeistElement(
            description: "Validation Results",
            label: "Validation Results",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 400,
            rotors: [HeistRotor(name: "Errors"), HeistRotor(name: "Warnings")],
            actions: []
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(decoded.rotors, element.rotors)
    }

    func testActionsCanonicalizeAtConstructionBoundary() {
        let element = HeistElement(
            description: "Actions",
            label: "Actions",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.custom("Share"), .activate, .custom("Delete"), .activate, .typeText, .decrement, .increment]
        )

        XCTAssertEqual(element.actions, [.activate, .typeText, .increment, .decrement, .custom("Delete"), .custom("Share")])
    }

    func testActionsCanonicalizeAtDecodeBoundaryAndEncodeDeterministically() throws {
        let json = """
        {
          "description": "Actions",
          "label": "Actions",
          "traits": [],
          "frameX": 0,
          "frameY": 0,
          "frameWidth": 100,
          "frameHeight": 44,
          "activationPointX": 50,
          "activationPointY": 22,
          "respondsToUserInteraction": true,
          "actions": [
            {"custom": "Share"},
            "activate",
            "typeText",
            {"custom": "Delete"},
            "activate"
          ]
        }
        """
        let decoded = try JSONDecoder().decode(HeistElement.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(decoded)
        let encodedProjection = try JSONDecoder().decode(EncodedElementActionsProjection.self, from: encoded)

        XCTAssertEqual(decoded.actions, [.activate, .typeText, .custom("Delete"), .custom("Share")])
        XCTAssertEqual(encodedProjection.actions, [.activate, .typeText, .custom("Delete"), .custom("Share")])
    }

    // MARK: - Helpers

    private func makeElement(label: String) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
    }

    private struct EncodedElementActionsProjection: Decodable {
        let actions: [ElementAction]
    }
}
