#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

extension InterfaceTreeTests {
    func testMergingUnionsElementsAndTakesLatestViewport() {
        let first = makeElement(label: "First", traits: .button)
        let second = makeElement(label: "Second", traits: .button)
        let oldPage = InterfaceObservation.makeForTests(elements: [(first, "button_first")])
        let newPage = InterfaceObservation.makeForTests(elements: [(second, "button_second")])

        let merged = oldPage.tree.merging(newPage.tree)

        XCTAssertEqual(merged.elementIDs, ["button_first", "button_second"])
        XCTAssertEqual(merged.viewportElementIDs, ["button_second"])
        XCTAssertFalse(merged.viewportCapture.heistIdsByPath.values.contains("button_first"))
        XCTAssertTrue(merged.viewportCapture.heistIdsByPath.values.contains("button_second"))
        XCTAssertEqual(merged.findElement(heistId: "button_second")?.element, second)
    }

    func testMergingDisjointSetsProducesUnion() {
        let lhs = InterfaceObservation.makeForTests(
            elements: [
                "a_button": makeEntry(heistId: "a_button"),
                "b_button": makeEntry(heistId: "b_button"),
            ],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        let rhs = InterfaceObservation.makeForTests(
            elements: [
                "c_button": makeEntry(heistId: "c_button"),
                "d_button": makeEntry(heistId: "d_button"),
            ],
            hierarchy: [],
            firstResponderHeistId: nil,
        )

        let merged = lhs.tree.merging(rhs.tree)

        XCTAssertEqual(merged.elementIDs, ["a_button", "b_button", "c_button", "d_button"])
    }

    func testMergingTakesOtherElementOnConflict() {
        let oldEntry = InterfaceTree.Element(
            heistId: "save_button",
            scrollMembership: nil,
            element: makeElement(label: "Save", traits: .button)
        )
        let newEntry = InterfaceTree.Element(
            heistId: "save_button",
            scrollMembership: nil,
            element: makeElement(label: "Save Changes", traits: .button)
        )
        let lhs = InterfaceObservation.makeForTests(
            elements: ["save_button": oldEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        let rhs = InterfaceObservation.makeForTests(
            elements: ["save_button": newEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )

        let merged = lhs.tree.merging(rhs.tree)

        XCTAssertEqual(merged.findElement(heistId: "save_button")?.element.label, "Save Changes",
                       "Conflict resolver should take `other`'s element payload")
    }

    func testMergingTakesOtherScrollMembershipEvenWhenOtherIsNil() {
        // Last-read-always-wins: no field-level preservation. If `other`
        // reports nil scroll membership for this heistId, that's the new truth.
        let lhsEntry = makeEntry(
            heistId: "scrolled_row",
            scrollContainerPath: TreePath([0])
        )
        let rhsEntry = makeEntry(
            heistId: "scrolled_row"
        )
        let lhs = InterfaceObservation.makeForTests(
            elements: ["scrolled_row": lhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        let rhs = InterfaceObservation.makeForTests(
            elements: ["scrolled_row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )

        let merged = lhs.tree.merging(rhs.tree)

        XCTAssertNil(merged.findElement(heistId: "scrolled_row")?.scrollMembership,
                     "Last-read-wins: `other`'s nil membership replaces `self`'s value")
    }

    func testMergingTakesOtherScrollMembershipWhenBothPresent() {
        let lhsEntry = makeEntry(
            heistId: "row",
            scrollContainerPath: TreePath([0]),
            scrollIndex: 100
        )
        let rhsEntry = makeEntry(
            heistId: "row",
            scrollContainerPath: TreePath([0]),
            scrollIndex: 500
        )
        let lhs = InterfaceObservation.makeForTests(
            elements: ["row": lhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        let rhs = InterfaceObservation.makeForTests(
            elements: ["row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )

        let merged = lhs.tree.merging(rhs.tree)

        XCTAssertEqual(merged.findElement(heistId: "row")?.scrollMembership?.index, 500,
                       "When both screens have membership, `other`'s wins (newer parse)")
    }

    func testMergingTakesOtherHierarchy() {
        let lhs = InterfaceObservation.makeForTests(
            elements: [(makeElement(label: "Old"), "old")]
        )
        let rhs = InterfaceObservation.makeForTests(
            elements: [(makeElement(label: "New"), "new")]
        )

        let merged = lhs.tree.merging(rhs.tree)

        XCTAssertEqual(merged.viewportCapture.hierarchy.count, 1)
        if case .element(let element, _) = merged.viewportCapture.hierarchy[0] {
            XCTAssertEqual(element.label, "New")
        } else {
            XCTFail("Expected element node")
        }
    }
}

#endif // canImport(UIKit)
