import XCTest
import ButtonHeist

// We can't directly import the executable, so we'll duplicate the formatting functions for testing
// This tests the same logic that's in the CLI

final class FormattingTests: XCTestCase {

    func testFormatElementBasic() {
        let element = makeElement(label: "Submit", index: 0, actions: [.activate])
        let output = formatElement(element, index: 0, changed: false)

        XCTAssertTrue(output.contains("[ 0] Submit"))
        XCTAssertTrue(output.contains("Frame: (10, 20) 100x44"))
        XCTAssertFalse(output.hasPrefix("*"))
    }

    func testFormatElementChanged() {
        let element = makeElement(label: "Submit", index: 0, actions: [.activate])
        let output = formatElement(element, index: 0, changed: true)

        XCTAssertTrue(output.hasPrefix("*"))
    }

    func testFormatElementWithValue() {
        let element = HeistElement(
            description: "Slider",
            label: "Volume",
            value: "50%",
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 30,
            actions: [.increment, .decrement]
        )
        let output = formatElement(element, index: 1, changed: false)

        XCTAssertTrue(output.contains("Value: 50%"))
    }

    func testFormatElementWithIdentifier() {
        let element = HeistElement(
            description: "Button",
            label: "Login",
            value: nil,
            identifier: "login_button",
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let output = formatElement(element, index: 2, changed: false)

        XCTAssertTrue(output.contains("ID: login_button"))
    }

    func testFormatElementWithActions() {
        let element = HeistElement(
            description: "Cell",
            label: "Item",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 300, frameHeight: 60,
            actions: [.activate, .custom("Delete"), .custom("Archive")]
        )
        let output = formatElement(element, index: 3, changed: false)

        XCTAssertTrue(output.contains("Actions: activate, Delete, Archive"))
    }

    func testFormatSnapshotJSON() {
        let element = makeElement(label: "Test", index: 0, actions: [])
        let payload = Interface(timestamp: Date(), tree: [.element(element)])

        let json = formatInterfaceJSON(payload)

        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"tree\""))
        XCTAssertTrue(json!.contains("\"timestamp\""))
    }

    func testFormatElementNoActions() {
        let element = makeElement(label: "Text", index: 5, actions: [])
        let output = formatElement(element, index: 5, changed: false)

        XCTAssertTrue(output.contains("[ 5] Text\n"))
        XCTAssertFalse(output.contains("Actions:"))
    }

    func testFormatElementLargeIndex() {
        let element = makeElement(label: "Item", index: 99, actions: [])
        let output = formatElement(element, index: 99, changed: false)

        XCTAssertTrue(output.contains("[99]"))
    }

    func testFormatElementUsesLabelOverDescription() {
        let element = HeistElement(
            description: "Description text",
            label: "Label text",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
        let output = formatElement(element, index: 0, changed: false)

        XCTAssertTrue(output.contains("Label text"))
        XCTAssertFalse(output.contains("Description text"))
    }

    func testFormatElementFallsBackToDescription() {
        let element = HeistElement(
            description: "Description text",
            label: nil,
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
        let output = formatElement(element, index: 0, changed: false)

        XCTAssertTrue(output.contains("Description text"))
    }

    // MARK: - Helpers

    private func makeElement(label: String, index: Int, actions: [ElementAction]) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: actions
        )
    }
}

// MARK: - Formatting Functions (copied from CLI for testing)

func formatElement(_ element: HeistElement, index elementIndex: Int = 0, changed: Bool) -> String {
    var output = ""
    let prefix = changed ? "* " : "  "
    let index = String(format: "[%2d]", elementIndex)
    let label = element.label ?? element.description

    output += "\(prefix)\(index) \(label)\n"

    if let value = element.value, !value.isEmpty {
        output += "       Value: \(value)\n"
    }
    if let id = element.identifier, !id.isEmpty {
        output += "       ID: \(id)\n"
    }
    if !element.actions.isEmpty {
        output += "       Actions: \(element.actions.map { $0.description }.joined(separator: ", "))\n"
    }

    let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))x\(Int(element.frameHeight))"
    output += "       Frame: \(frame)\n"

    return output
}

func formatInterfaceJSON(_ payload: Interface) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(payload),
          let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return json
}
