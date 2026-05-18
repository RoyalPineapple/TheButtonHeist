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
        .make(label: label, value: value, identifier: identifier, traits: traits)
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

    func testEmptyKnownIdsIsEmpty() {
        XCTAssertTrue(Screen.empty.knownIds.isEmpty)
    }

    func testEmptyVisibleIdsIsEmpty() {
        XCTAssertTrue(Screen.empty.visibleIds.isEmpty)
    }

    // MARK: - KnownInterface / InteractionSnapshot

    func testKnownInterfaceIncludesKnownEntriesOutsideLatestParse() {
        let visible = makeElement(label: "Visible", traits: .button)
        let knownOnly = makeElement(label: "Known", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownOnly,
                    heistId: "button_known",
                    contentSpaceOrigin: CGPoint(x: 0, y: 2_000)
                )
            ]
        )

        XCTAssertEqual(screen.knownInterface.heistIds, ["button_visible", "button_known"])
        XCTAssertEqual(screen.interactionSnapshot.heistIds, ["button_visible"])
        XCTAssertEqual(screen.knownInterface.findElement(heistId: "button_known")?.element.label, "Known")
        XCTAssertFalse(screen.interactionSnapshot.contains(heistId: "button_known"))
    }

    func testMergingUnionsKnownInterfaceButTakesLatestInteractionSnapshot() {
        let first = makeElement(label: "First", traits: .button)
        let second = makeElement(label: "Second", traits: .button)
        let oldPage = Screen.makeForTests(elements: [(first, "button_first")])
        let newPage = Screen.makeForTests(elements: [(second, "button_second")])

        let merged = oldPage.merging(newPage)

        XCTAssertEqual(merged.knownInterface.heistIds, ["button_first", "button_second"])
        XCTAssertEqual(merged.interactionSnapshot.heistIds, ["button_second"])
        XCTAssertNil(merged.interactionSnapshot.heistId(for: first))
        XCTAssertEqual(merged.interactionSnapshot.heistId(for: second), "button_second")
    }

    func testVisibleOnlyFiltersKnownEntriesOutsideLatestParse() {
        let visible = makeElement(label: "Visible", traits: .button)
        let knownOnly = makeElement(label: "Known", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownOnly,
                    heistId: "button_known",
                    contentSpaceOrigin: CGPoint(x: 0, y: 2_000)
                )
            ],
            firstResponderHeistId: "button_visible"
        )

        let visibleOnly = screen.visibleOnly

        XCTAssertEqual(visibleOnly.knownIds, ["button_visible"])
        XCTAssertEqual(visibleOnly.visibleIds, ["button_visible"])
        XCTAssertEqual(visibleOnly.hierarchy, screen.hierarchy)
        XCTAssertEqual(visibleOnly.firstResponderHeistId, "button_visible")
        XCTAssertNil(visibleOnly.findElement(heistId: "button_known"))
    }

    func testOrderedElementsReturnsLiveOrderThenKnownOnlySortedByHeistId() {
        let firstLive = makeElement(label: "First", traits: .button)
        let secondLive = makeElement(label: "Second", traits: .button)
        let aKnown = makeElement(label: "A Known", traits: .button)
        let zKnown = makeElement(label: "Z Known", traits: .button)
        let screen = Screen.makeForTests(
            elements: [
                (secondLive, "button_second"),
                (firstLive, "button_first"),
            ],
            offViewport: [
                Screen.OffViewportEntry(zKnown, heistId: "z_known"),
                Screen.OffViewportEntry(aKnown, heistId: "a_known"),
            ]
        )

        XCTAssertEqual(
            screen.orderedElements.map(\.heistId),
            ["button_second", "button_first", "a_known", "z_known"]
        )
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

        XCTAssertEqual(merged.knownIds, ["a_button", "b_button", "c_button", "d_button"])
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

    // MARK: - refreshingVisibleState

    func testRefreshingVisibleStatePreservesKnownElementsWhenVisibleIdsAreKnown() {
        let visible = makeElement(label: "Visible", traits: .button)
        let knownOnly = makeElement(label: "Known", traits: .button)
        let refreshedVisible = makeElement(label: "Visible", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownOnly,
                    heistId: "button_known",
                    contentSpaceOrigin: CGPoint(x: 0, y: 2_000)
                )
            ]
        )
        let refresh = Screen.makeForTests(
            elements: [(refreshedVisible, "button_visible")],
            firstResponderHeistId: "button_visible"
        )

        let updated = screen.refreshingVisibleState(with: refresh)

        XCTAssertEqual(updated.knownIds, ["button_visible", "button_known"])
        XCTAssertEqual(updated.visibleIds, ["button_visible"])
        XCTAssertEqual(updated.firstResponderHeistId, "button_visible")
        XCTAssertEqual(updated.findElement(heistId: "button_known")?.element.label, "Known")
    }

    func testRefreshingVisibleStateDropsDisappearedVisibleNonScrollElements() {
        let disappearing = makeElement(label: "Disappearing", traits: .staticText)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = Screen.makeForTests(
            elements: [
                (disappearing, "disappearing_staticText"),
                (visible, "button_visible")
            ]
        )
        let refresh = Screen.makeForTests(elements: [(visible, "button_visible")])

        let updated = screen.refreshingVisibleState(with: refresh)

        XCTAssertEqual(updated.knownIds, ["button_visible"])
        XCTAssertNil(updated.findElement(heistId: "disappearing_staticText"))
    }

    func testRefreshingVisibleStatePreservesDisappearedVisibleScrollElements() {
        let scrolledAway = makeElement(label: "Scrolled Away", traits: .button)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = Screen(
            elements: [
                "button_scrolled_away": Screen.ScreenElement(
                    heistId: "button_scrolled_away",
                    contentSpaceOrigin: CGPoint(x: 0, y: 1_000),
                    element: scrolledAway,
                    object: nil,
                    scrollView: nil
                ),
                "button_visible": Screen.ScreenElement(
                    heistId: "button_visible",
                    contentSpaceOrigin: nil,
                    element: visible,
                    object: nil,
                    scrollView: nil
                )
            ],
            hierarchy: [
                .element(scrolledAway, traversalIndex: 0),
                .element(visible, traversalIndex: 1)
            ],
            containerStableIds: [:],
            heistIdByElement: [
                scrolledAway: "button_scrolled_away",
                visible: "button_visible"
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let refresh = Screen.makeForTests(elements: [(visible, "button_visible")])

        let updated = screen.refreshingVisibleState(with: refresh)

        XCTAssertEqual(updated.knownIds, ["button_scrolled_away", "button_visible"])
        XCTAssertEqual(updated.visibleIds, ["button_visible"])
        XCTAssertEqual(updated.findElement(heistId: "button_scrolled_away")?.element.label, "Scrolled Away")
    }

    func testRefreshingVisibleStateReplacesKnownElementsWhenVisibleIdsAreUnknown() {
        let old = makeElement(label: "Old", traits: .button)
        let knownOnly = makeElement(label: "Known", traits: .button)
        let replacement = makeElement(label: "Replacement", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(old, "button_old")],
            offViewport: [
                Screen.OffViewportEntry(knownOnly, heistId: "button_known")
            ]
        )
        let refresh = Screen.makeForTests(elements: [(replacement, "button_replacement")])

        let updated = screen.refreshingVisibleState(with: refresh)

        XCTAssertEqual(updated.knownIds, ["button_replacement"])
        XCTAssertNil(updated.findElement(heistId: "button_known"))
    }

    func testRefreshingVisibleStateReplacesKnownElementsForEmptyRefresh() {
        let old = makeElement(label: "Old", traits: .button)
        let screen = Screen.makeForTests(elements: [(old, "button_old")])

        let updated = screen.refreshingVisibleState(with: .empty)

        XCTAssertTrue(updated.knownIds.isEmpty)
        XCTAssertTrue(updated.visibleIds.isEmpty)
    }
}

#endif // canImport(UIKit)
