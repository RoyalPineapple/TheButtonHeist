#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ScreenTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    private func makeEntry(
        heistId: String,
        label: String? = nil,
        contentSpaceOrigin: CGPoint? = nil
    ) -> Screen.ScreenElement {
        Screen.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: contentSpaceOrigin,
            element: makeElement(label: label ?? heistId),
            object: nil,
            scrollView: nil
        )
    }

    // MARK: - .empty

    func testEmptyHasNoElements() {
        XCTAssertTrue(Screen.empty.elements.isEmpty)
    }

    func testEmptyHasNoHierarchy() {
        XCTAssertTrue(Screen.empty.hierarchy.isEmpty)
    }

    func testEmptyHasNoFirstResponder() {
        XCTAssertNil(Screen.empty.firstResponderHeistId)
    }

    func testEmptyHasNoName() {
        XCTAssertNil(Screen.empty.name)
        XCTAssertNil(Screen.empty.id)
    }

    func testEmptyHeistIdsIsEmpty() {
        XCTAssertTrue(Screen.empty.heistIds.isEmpty)
    }

    // MARK: - findElement

    func testFindElementReturnsNilForUnknownId() {
        let screen = Screen(
            elements: ["a_button": makeEntry(heistId: "a_button")],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        XCTAssertNil(screen.findElement(heistId: "missing"))
    }

    func testFindElementReturnsEntryForKnownId() {
        let entry = makeEntry(heistId: "save_button")
        let screen = Screen(
            elements: [entry.heistId: entry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        XCTAssertEqual(screen.findElement(heistId: "save_button")?.heistId, "save_button")
    }

    // MARK: - name / id

    func testNameDerivesFromFirstHeaderInHierarchy() {
        let header = makeElement(label: "Controls Demo", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let screen = Screen(
            elements: [:],
            hierarchy: [
                .element(header, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        XCTAssertEqual(screen.name, "Controls Demo")
        XCTAssertEqual(screen.id, "controls_demo")
    }

    func testNameIgnoresHeaderWithoutLabel() {
        let nilHeader = makeElement(label: nil, traits: .header)
        let realHeader = makeElement(label: "Page Title", traits: .header)
        let screen = Screen(
            elements: [:],
            hierarchy: [
                .element(nilHeader, traversalIndex: 0),
                .element(realHeader, traversalIndex: 1),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        XCTAssertEqual(screen.name, "Page Title")
    }

    func testNameNilWhenNoHeader() {
        let screen = Screen(
            elements: [:],
            hierarchy: [.element(makeElement(label: "Body"), traversalIndex: 0)],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        XCTAssertNil(screen.name)
        XCTAssertNil(screen.id)
    }

    // MARK: - merging — disjoint sets

    func testMergingDisjointSetsProducesUnion() {
        let lhs = Screen(
            elements: [
                "a_button": makeEntry(heistId: "a_button"),
                "b_button": makeEntry(heistId: "b_button"),
            ],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: [
                "c_button": makeEntry(heistId: "c_button"),
                "d_button": makeEntry(heistId: "d_button"),
            ],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.heistIds, ["a_button", "b_button", "c_button", "d_button"])
    }

    // MARK: - merging — conflict rule

    func testMergingTakesOtherElementOnConflict() {
        let oldEntry = Screen.ScreenElement(
            heistId: "save_button",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Save", traits: .button),
            object: nil,
            scrollView: nil
        )
        let newEntry = Screen.ScreenElement(
            heistId: "save_button",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Save Changes", traits: .button),
            object: nil,
            scrollView: nil
        )
        let lhs = Screen(
            elements: ["save_button": oldEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: ["save_button": newEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.findElement(heistId: "save_button")?.element.label, "Save Changes",
                       "Conflict resolver should take `other`'s element payload")
    }

    func testMergingTakesOtherOriginEvenWhenOtherIsNil() {
        // Last-read-always-wins: no field-level preservation. If `other`
        // reports nil contentSpaceOrigin for this heistId, that's the new
        // truth, even if `self` had a non-nil value previously.
        let lhsEntry = makeEntry(
            heistId: "scrolled_row",
            contentSpaceOrigin: CGPoint(x: 0, y: 400)
        )
        let rhsEntry = makeEntry(
            heistId: "scrolled_row",
            contentSpaceOrigin: nil
        )
        let lhs = Screen(
            elements: ["scrolled_row": lhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: ["scrolled_row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let merged = lhs.merging(rhs)

        XCTAssertNil(merged.findElement(heistId: "scrolled_row")?.contentSpaceOrigin,
                     "Last-read-wins: `other`'s nil origin replaces `self`'s value")
    }

    func testMergingTakesOtherOriginWhenBothPresent() {
        let lhsEntry = makeEntry(
            heistId: "row",
            contentSpaceOrigin: CGPoint(x: 0, y: 100)
        )
        let rhsEntry = makeEntry(
            heistId: "row",
            contentSpaceOrigin: CGPoint(x: 0, y: 500)
        )
        let lhs = Screen(
            elements: ["row": lhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: ["row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.findElement(heistId: "row")?.contentSpaceOrigin,
                       CGPoint(x: 0, y: 500),
                       "When both screens have an origin, `other`'s wins (newer parse)")
    }

    // MARK: - merging — hierarchy / first responder

    func testMergingTakesOtherHierarchy() {
        let oldHierarchy: [AccessibilityHierarchy] = [
            .element(makeElement(label: "Old"), traversalIndex: 0),
        ]
        let newHierarchy: [AccessibilityHierarchy] = [
            .element(makeElement(label: "New"), traversalIndex: 0),
        ]
        let lhs = Screen(
            elements: [:],
            hierarchy: oldHierarchy,
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: [:],
            hierarchy: newHierarchy,
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.hierarchy.count, 1)
        if case .element(let element, _) = merged.hierarchy[0] {
            XCTAssertEqual(element.label, "New")
        } else {
            XCTFail("Expected element node")
        }
    }

    func testMergingTakesOtherFirstResponder() {
        let lhs = Screen(
            elements: [:],
            hierarchy: [],
            firstResponderHeistId: "old_field",
            scrollableContainerViews: [:]
        )
        let rhs = Screen(
            elements: [:],
            hierarchy: [],
            firstResponderHeistId: "new_field",
            scrollableContainerViews: [:]
        )

        XCTAssertEqual(lhs.merging(rhs).firstResponderHeistId, "new_field")
    }
}

#endif // canImport(UIKit)
