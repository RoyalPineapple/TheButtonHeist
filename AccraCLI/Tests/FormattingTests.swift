import XCTest
import AccraCore

// We can't directly import the executable, so we'll duplicate the formatting functions for testing
// This tests the same logic that's in the CLI

final class FormattingTests: XCTestCase {

    func testFormatElementBasic() {
        let element = makeElement(label: "Submit", index: 0, traits: ["button"])
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("[ 0] Submit (button)"))
        XCTAssertTrue(output.contains("Frame: (10, 20) 100x44"))
        XCTAssertFalse(output.hasPrefix("*"))
    }

    func testFormatElementChanged() {
        let element = makeElement(label: "Submit", index: 0, traits: ["button"])
        let output = formatElement(element, changed: true)

        XCTAssertTrue(output.hasPrefix("*"))
    }

    func testFormatElementWithValue() {
        let element = AccessibilityElementData(
            traversalIndex: 1,
            description: "Slider",
            label: "Volume",
            value: "50%",
            traits: ["adjustable"],
            identifier: nil,
            hint: "Swipe up or down to adjust",
            frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 30,
            activationPointX: 100, activationPointY: 15,
            customActions: []
        )
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("Value: 50%"))
        XCTAssertTrue(output.contains("Hint: Swipe up or down to adjust"))
    }

    func testFormatElementWithIdentifier() {
        let element = AccessibilityElementData(
            traversalIndex: 2,
            description: "Button",
            label: "Login",
            value: nil,
            traits: ["button"],
            identifier: "login_button",
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            activationPointX: 50, activationPointY: 22,
            customActions: []
        )
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("ID: login_button"))
    }

    func testFormatElementWithCustomActions() {
        let element = AccessibilityElementData(
            traversalIndex: 3,
            description: "Cell",
            label: "Item",
            value: nil,
            traits: [],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 300, frameHeight: 60,
            activationPointX: 150, activationPointY: 30,
            customActions: ["Delete", "Archive"]
        )
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("Actions: Delete, Archive"))
    }

    func testFormatHierarchyJSON() {
        let element = makeElement(label: "Test", index: 0, traits: [])
        let payload = HierarchyPayload(timestamp: Date(), elements: [element])

        let json = formatHierarchyJSON(payload)

        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"elements\""))
        XCTAssertTrue(json!.contains("\"timestamp\""))
    }

    func testFormatMultipleTraits() {
        let element = makeElement(label: "Link", index: 0, traits: ["link", "button", "header"])
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("(link, button, header)"))
    }

    func testFormatElementNoTraits() {
        let element = makeElement(label: "Text", index: 5, traits: [])
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("[ 5] Text\n"))
        XCTAssertFalse(output.contains("()"))
    }

    func testFormatElementLargeIndex() {
        let element = makeElement(label: "Item", index: 99, traits: [])
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("[99]"))
    }

    func testFormatElementUsesLabelOverDescription() {
        let element = AccessibilityElementData(
            traversalIndex: 0,
            description: "Description text",
            label: "Label text",
            value: nil,
            traits: [],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            activationPointX: 50, activationPointY: 22,
            customActions: []
        )
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("Label text"))
        XCTAssertFalse(output.contains("Description text"))
    }

    func testFormatElementFallsBackToDescription() {
        let element = AccessibilityElementData(
            traversalIndex: 0,
            description: "Description text",
            label: nil,
            value: nil,
            traits: [],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            activationPointX: 50, activationPointY: 22,
            customActions: []
        )
        let output = formatElement(element, changed: false)

        XCTAssertTrue(output.contains("Description text"))
    }

    // MARK: - Helpers

    private func makeElement(label: String, index: Int, traits: [String]) -> AccessibilityElementData {
        AccessibilityElementData(
            traversalIndex: index,
            description: label,
            label: label,
            value: nil,
            traits: traits,
            identifier: nil,
            hint: nil,
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            activationPointX: 60, activationPointY: 42,
            customActions: []
        )
    }
}

// MARK: - Formatting Functions (copied from CLI for testing)

func formatElement(_ element: AccessibilityElementData, changed: Bool) -> String {
    var output = ""
    let prefix = changed ? "* " : "  "
    let index = String(format: "[%2d]", element.traversalIndex)
    let traits = element.traits.isEmpty ? "" : " (\(element.traits.joined(separator: ", ")))"
    let label = element.label ?? element.description

    output += "\(prefix)\(index) \(label)\(traits)\n"

    if let value = element.value, !value.isEmpty {
        output += "       Value: \(value)\n"
    }
    if let hint = element.hint, !hint.isEmpty {
        output += "       Hint: \(hint)\n"
    }
    if let id = element.identifier, !id.isEmpty {
        output += "       ID: \(id)\n"
    }
    if !element.customActions.isEmpty {
        output += "       Actions: \(element.customActions.joined(separator: ", "))\n"
    }

    let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))x\(Int(element.frameHeight))"
    output += "       Frame: \(frame)\n"

    return output
}

func formatHierarchyJSON(_ payload: HierarchyPayload) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(payload),
          let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return json
}
