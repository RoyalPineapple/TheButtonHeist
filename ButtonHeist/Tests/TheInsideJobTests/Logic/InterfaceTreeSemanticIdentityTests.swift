#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

extension InterfaceTreeTests {
    func testCanonicalElementIdentityIgnoresViewportGeometry() {
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

        XCTAssertEqual(before.tree.elementIDs, after.tree.elementIDs)
        XCTAssertEqual(
            before.tree.findElement(heistId: "chicken_tikka_button").map {
                TheVault.WireConversion.semantics($0.element)
            },
            after.tree.findElement(heistId: "chicken_tikka_button").map {
                TheVault.WireConversion.semantics($0.element)
            }
        )
    }

    func testCanonicalElementSemanticsChangeWithAccessibilityState() {
        let oldTotal = makeElement(label: "Total", value: "$4.00", traits: .staticText)
        let newTotal = makeElement(label: "Total", value: "$8.00", traits: .staticText)
        let before = InterfaceObservation.makeForTests(elements: [(oldTotal, "total_staticText")])
        let after = InterfaceObservation.makeForTests(elements: [(newTotal, "total_staticText")])

        XCTAssertEqual(before.tree.elementIDs, after.tree.elementIDs)
        XCTAssertNotEqual(
            before.tree.findElement(heistId: "total_staticText").map {
                TheVault.WireConversion.semantics($0.element)
            },
            after.tree.findElement(heistId: "total_staticText").map {
                TheVault.WireConversion.semantics($0.element)
            }
        )
    }

}

#endif // canImport(UIKit)
