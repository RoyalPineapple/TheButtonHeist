#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

extension InterfaceTreeTests {
    func testSemanticHashIgnoresViewportGeometry() {
        let top = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: 22)
        )
        let scrolled = AccessibilityElement.make(
            label: "Chicken Tikka",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: -300, width: 200, height: 44))),
            activationPoint: CGPoint(x: 100, y: -278)
        )
        let before = InterfaceObservation.makeForTests(elements: [(top, "chicken_tikka_button")])
        let after = InterfaceObservation.makeForTests(elements: [(scrolled, "chicken_tikka_button")])
        let beforeInterfaceHash = AccessibilityTrace.Capture.hash(
            TheVault.WireConversion.toSemanticInterface(from: before.tree)
        )
        let afterInterfaceHash = AccessibilityTrace.Capture.hash(
            TheVault.WireConversion.toSemanticInterface(from: after.tree)
        )

        XCTAssertEqual(beforeInterfaceHash, afterInterfaceHash)
        XCTAssertEqual(before.tree.interfaceHash, after.tree.interfaceHash)
    }

    func testSemanticHashChangesForAccessibilityState() {
        let oldTotal = makeElement(label: "Total", value: "$4.00", traits: .staticText)
        let newTotal = makeElement(label: "Total", value: "$8.00", traits: .staticText)
        let before = InterfaceObservation.makeForTests(elements: [(oldTotal, "total_staticText")])
        let after = InterfaceObservation.makeForTests(elements: [(newTotal, "total_staticText")])

        XCTAssertNotEqual(before.tree.interfaceHash, after.tree.interfaceHash)
    }

    func testNameDerivesFromFirstHeaderInHierarchy() {
        let header = makeElement(label: "Controls Demo", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (header, "controls_header"),
                (button, "save_button"),
            ]
        )
        XCTAssertEqual(screen.tree.name, "Controls Demo")
        XCTAssertEqual(screen.tree.id, "controls_demo")
    }

    func testNameDerivesFromTopmostHeaderInHierarchy() {
        let contentHeader = makeElement(
            label: "Section Header Style",
            traits: .header,
            shape: .frame(AccessibilityRect(CGRect(x: 20, y: 240, width: 200, height: 44)))
        )
        let navigationTitle = makeElement(
            label: "Display",
            traits: .header,
            shape: .frame(AccessibilityRect(CGRect(x: 120, y: 72, width: 100, height: 44)))
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (contentHeader, "content_header"),
                (navigationTitle, "navigation_title"),
            ]
        )
        XCTAssertEqual(screen.tree.name, "Display")
        XCTAssertEqual(screen.tree.id, "display")
        XCTAssertEqual(screen.tree.summaryElement, navigationTitle)
    }

    func testSummaryElementTraitTakesPrecedenceOverTopmostHeader() {
        let navigationTitle = makeElement(
            label: "Display",
            traits: .header,
            shape: .frame(AccessibilityRect(CGRect(x: 120, y: 72, width: 100, height: 44)))
        )
        let explicitSummary = makeElement(
            label: "Messages",
            traits: .summaryElement,
            shape: .frame(AccessibilityRect(CGRect(x: 20, y: 240, width: 200, height: 44)))
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (navigationTitle, "navigation_title"),
                (explicitSummary, "messages_summary"),
            ]
        )

        XCTAssertEqual(screen.tree.summaryElement, explicitSummary)
        XCTAssertEqual(screen.tree.name, "Messages")
        XCTAssertEqual(screen.tree.id, "messages")
    }

    func testNameIgnoresHeaderWithoutLabel() {
        let nilHeader = makeElement(label: nil, traits: .header)
        let realHeader = makeElement(label: "Page Title", traits: .header)
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (nilHeader, "unlabeled_header"),
                (realHeader, "page_title"),
            ]
        )
        XCTAssertEqual(screen.tree.name, "Page Title")
    }

    func testNameNilWhenNoHeader() {
        let screen = InterfaceObservation.makeForTests(
            elements: [(makeElement(label: "Body"), "body")]
        )
        XCTAssertNil(screen.tree.name)
        XCTAssertNil(screen.tree.id)
    }
}

#endif // canImport(UIKit)
