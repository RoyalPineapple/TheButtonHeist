import XCTest
 import TheGoods

final class HeistElementTests: XCTestCase {

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

        var set = Set<HeistElement>()
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

    func testEncodingRoundTrip() throws {
        let element = makeElement(label: "RoundTrip", index: 5)

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(element, decoded)
    }

    func testElementWithAllFields() throws {
        let element = HeistElement(
            order: 10,
            description: "A complex button",
            label: "Submit Form",
            value: "Enabled",
            identifier: "submit_button_id",
            frameX: 50, frameY: 100, frameWidth: 200, frameHeight: 60,
            actions: [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")]
        )

        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(HeistElement.self, from: data)

        XCTAssertEqual(decoded.order, 10)
        XCTAssertEqual(decoded.description, "A complex button")
        XCTAssertEqual(decoded.label, "Submit Form")
        XCTAssertEqual(decoded.value, "Enabled")
        XCTAssertEqual(decoded.identifier, "submit_button_id")
        XCTAssertEqual(decoded.actions, [.activate, .custom("Delete"), .custom("Edit"), .custom("Share")])
    }

    func testElementWithNilOptionals() throws {
        let element = HeistElement(
            order: 0,
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

    // MARK: - Helpers

    private func makeElement(label: String, index: Int) -> HeistElement {
        HeistElement(
            order: index,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
    }
}
