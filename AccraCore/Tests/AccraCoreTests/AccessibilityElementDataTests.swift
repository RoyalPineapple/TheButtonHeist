import XCTest
@testable import AccraCore

final class AccessibilityElementDataTests: XCTestCase {

    func testEquality() {
        let element1 = makeElement(label: "Button1", index: 0)
        let element2 = makeElement(label: "Button1", index: 0)
        let element3 = makeElement(label: "Button2", index: 1)

        XCTAssertEqual(element1, element2)
        XCTAssertNotEqual(element1, element3)
    }

    func testHashable() {
        let element1 = makeElement(label: "Button1", index: 0)
        let element2 = makeElement(label: "Button1", index: 0)

        var set = Set<AccessibilityElementData>()
        set.insert(element1)
        set.insert(element2)

        XCTAssertEqual(set.count, 1)
    }

    func testFrameComputed() {
        let element = makeElement(label: "Test", index: 0)
        let frame = element.frame

        XCTAssertEqual(frame.origin.x, 10)
        XCTAssertEqual(frame.origin.y, 20)
        XCTAssertEqual(frame.size.width, 100)
        XCTAssertEqual(frame.size.height, 44)
    }

    func testActivationPointComputed() {
        let element = makeElement(label: "Test", index: 0)
        let point = element.activationPoint

        XCTAssertEqual(point.x, 60)
        XCTAssertEqual(point.y, 42)
    }

    func testEncodingRoundTrip() throws {
        let element = makeElement(label: "RoundTrip", index: 5)

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(AccessibilityElementData.self, from: data)

        XCTAssertEqual(element, decoded)
    }

    func testElementWithAllFields() throws {
        let element = AccessibilityElementData(
            traversalIndex: 10,
            description: "A complex button",
            label: "Submit Form",
            value: "Enabled",
            traits: ["button", "staticText"],
            identifier: "submit_button_id",
            hint: "Double tap to submit the form",
            frameX: 50, frameY: 100, frameWidth: 200, frameHeight: 60,
            activationPointX: 150, activationPointY: 130,
            customActions: ["Delete", "Edit", "Share"]
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(AccessibilityElementData.self, from: data)

        XCTAssertEqual(decoded.traversalIndex, 10)
        XCTAssertEqual(decoded.description, "A complex button")
        XCTAssertEqual(decoded.label, "Submit Form")
        XCTAssertEqual(decoded.value, "Enabled")
        XCTAssertEqual(decoded.traits, ["button", "staticText"])
        XCTAssertEqual(decoded.identifier, "submit_button_id")
        XCTAssertEqual(decoded.hint, "Double tap to submit the form")
        XCTAssertEqual(decoded.customActions, ["Delete", "Edit", "Share"])
    }

    func testElementWithNilOptionals() throws {
        let element = AccessibilityElementData(
            traversalIndex: 0,
            description: "Minimal",
            label: nil,
            value: nil,
            traits: [],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            activationPointX: 0, activationPointY: 0,
            customActions: []
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(AccessibilityElementData.self, from: data)

        XCTAssertEqual(element, decoded)
        XCTAssertNil(decoded.label)
        XCTAssertNil(decoded.value)
        XCTAssertNil(decoded.identifier)
        XCTAssertNil(decoded.hint)
    }

    // MARK: - Helpers

    private func makeElement(label: String, index: Int) -> AccessibilityElementData {
        AccessibilityElementData(
            traversalIndex: index,
            description: label,
            label: label,
            value: nil,
            traits: ["button"],
            identifier: nil,
            hint: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            activationPointX: 60, activationPointY: 42,
            customActions: []
        )
    }
}
