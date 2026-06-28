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
        traits: UIAccessibilityTraits = .none,
        shape: AccessibilityElement.Shape = .frame(AccessibilityRect.zero)
    ) -> AccessibilityElement {
        .make(label: label, value: value, identifier: identifier, traits: traits, shape: shape)
    }

    private func makeEntry(
        heistId: HeistId,
        label: String? = nil,
        contentSpaceOrigin: CGPoint? = nil
    ) -> Screen.ScreenElement {
        Screen.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: contentSpaceOrigin,
            scrollContainerPath: contentSpaceOrigin.map { _ in TreePath([0]) },
            element: makeElement(label: label ?? heistId.description)
        )
    }

    private func commitVisibleRefresh(from settled: Screen, with refresh: Screen) -> WorldStore.CommitResult {
        var worldStore = WorldStore()
        worldStore.commitDiscovery(settled)
        return worldStore.commitVisible(refresh)
    }

    // MARK: - .empty

    func testEmptyHasNoElements() {
        XCTAssertTrue(Screen.empty.semantic.elements.isEmpty)
    }

    func testEmptyHasNoHierarchy() {
        XCTAssertTrue(Screen.empty.liveCapture.hierarchy.isEmpty)
    }

    func testEmptyHasNoFirstResponder() {
        XCTAssertNil(Screen.empty.liveCapture.firstResponderHeistId)
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

    // MARK: - KnownInterface / LiveInterface

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
        XCTAssertEqual(screen.liveCapture.heistIds, ["button_visible"])
        XCTAssertEqual(screen.knownInterface.findElement(heistId: "button_known")?.element.label, "Known")
        XCTAssertFalse(screen.liveCapture.contains(heistId: "button_known"))
    }

    func testMergingUnionsKnownInterfaceButTakesLatestLiveInterface() {
        let first = makeElement(label: "First", traits: .button)
        let second = makeElement(label: "Second", traits: .button)
        let oldPage = Screen.makeForTests(elements: [(first, "button_first")])
        let newPage = Screen.makeForTests(elements: [(second, "button_second")])

        let merged = oldPage.merging(newPage)

        XCTAssertEqual(merged.knownInterface.heistIds, ["button_first", "button_second"])
        XCTAssertEqual(merged.liveCapture.heistIds, ["button_second"])
        XCTAssertNil(merged.liveCapture.element(for: "button_first"))
        XCTAssertEqual(merged.liveCapture.heistId(forPath: TreePath([0])), "button_second")
        XCTAssertEqual(merged.liveCapture.element(for: "button_second"), second)
    }

    func testRemovingElementsRemapsLiveSemanticAndAnnotationPaths() {
        let removed = makeElement(
            label: "Old",
            traits: .button,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44))
        )
        let kept = makeElement(
            label: "Kept",
            traits: .button,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44))
        )
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1_200)),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
        )
        let keptOrigin = CGPoint(x: 0, y: 600)
        let screen = Screen(
            elements: [
                "old": Screen.ScreenElement(
                    heistId: "old",
                    contentSpaceOrigin: nil,
                    element: removed
                ),
                "kept": Screen.ScreenElement(
                    heistId: "kept",
                    contentSpaceOrigin: keptOrigin,
                    scrollContainerPath: TreePath([1]),
                    element: kept
                ),
            ],
            hierarchy: [
                .element(removed, traversalIndex: 0),
                .container(container, children: [
                    .element(kept, traversalIndex: 1),
                ]),
            ],
            containerNamesByPath: [TreePath([1]): "feed"],
            heistIdsByPath: [
                TreePath([0]): "old",
                TreePath([1, 0]): "kept",
            ],
            firstResponderHeistId: nil,
        )

        let pruned = screen.removingElements(withIds: ["old"])
        let interface = TheStash.WireConversion.toInterface(from: pruned)

        XCTAssertEqual(pruned.liveCapture.heistId(forPath: TreePath([0, 0])), "kept")
        XCTAssertNil(pruned.liveCapture.heistId(forPath: TreePath([1, 0])))
        XCTAssertEqual(pruned.liveCapture.containerNamesByPath[TreePath([0])], "feed")
        XCTAssertEqual(pruned.semantic.containers[TreePath([0])]?.containerName, "feed")
        XCTAssertNil(pruned.semantic.containers[TreePath([1])])
        XCTAssertEqual(pruned.semantic.elements["kept"]?.scrollContentLocation?.scrollContainerPath, TreePath([0]))
        XCTAssertEqual(interface.annotations.containerByPath[TreePath([0])]?.containerName, "feed")
        XCTAssertEqual(
            interface.annotations.elementByPath[TreePath([0, 0])]?.contentSpaceOrigin,
            AccessibilityPoint(x: Double(keptOrigin.x), y: Double(keptOrigin.y))
        )
        XCTAssertNil(interface.annotations.elementByPath[TreePath([1, 0])])
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
        XCTAssertEqual(visibleOnly.liveCapture.hierarchy, screen.liveCapture.hierarchy)
        XCTAssertEqual(visibleOnly.liveCapture.firstResponderHeistId, "button_visible")
        XCTAssertNil(visibleOnly.findElement(heistId: "button_known"))
    }

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
        let before = Screen.makeForTests(elements: [(top, "chicken_tikka_button")])
        let after = Screen.makeForTests(elements: [(scrolled, "chicken_tikka_button")])
        let beforeInterfaceHash = AccessibilityTrace.Capture.hash(TheStash.WireConversion.toInterface(from: before))
        let afterInterfaceHash = AccessibilityTrace.Capture.hash(TheStash.WireConversion.toInterface(from: after))

        XCTAssertNotEqual(beforeInterfaceHash, afterInterfaceHash)
        XCTAssertEqual(before.semanticHash, after.semanticHash)
    }

    func testSemanticHashChangesForAccessibilityState() {
        let oldTotal = makeElement(label: "Total", value: "$4.00", traits: .staticText)
        let newTotal = makeElement(label: "Total", value: "$8.00", traits: .staticText)
        let before = Screen.makeForTests(elements: [(oldTotal, "total_staticText")])
        let after = Screen.makeForTests(elements: [(newTotal, "total_staticText")])

        XCTAssertNotEqual(before.semanticHash, after.semanticHash)
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
        )
        XCTAssertNil(screen.findElement(heistId: "missing"))
    }

    func testFindElementReturnsEntryForKnownId() {
        let entry = makeEntry(heistId: "save_button")
        let screen = Screen(
            elements: [entry.heistId: entry],
            hierarchy: [],
            firstResponderHeistId: nil,
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
        )
        XCTAssertEqual(screen.name, "Controls Demo")
        XCTAssertEqual(screen.id, "controls_demo")
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
        let screen = Screen(
            elements: [:],
            hierarchy: [
                .element(contentHeader, traversalIndex: 0),
                .element(navigationTitle, traversalIndex: 1),
            ],
            firstResponderHeistId: nil,
        )
        XCTAssertEqual(screen.name, "Display")
        XCTAssertEqual(screen.id, "display")
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
        )
        XCTAssertEqual(screen.name, "Page Title")
    }

    func testNameNilWhenNoHeader() {
        let screen = Screen(
            elements: [:],
            hierarchy: [.element(makeElement(label: "Body"), traversalIndex: 0)],
            firstResponderHeistId: nil,
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
        )
        let rhs = Screen(
            elements: [
                "c_button": makeEntry(heistId: "c_button"),
                "d_button": makeEntry(heistId: "d_button"),
            ],
            hierarchy: [],
            firstResponderHeistId: nil,
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.knownIds, ["a_button", "b_button", "c_button", "d_button"])
    }

    // MARK: - merging — conflict rule

    func testMergingTakesOtherElementOnConflict() {
        let oldEntry = Screen.ScreenElement(
            heistId: "save_button",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Save", traits: .button)
        )
        let newEntry = Screen.ScreenElement(
            heistId: "save_button",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Save Changes", traits: .button)
        )
        let lhs = Screen(
            elements: ["save_button": oldEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        let rhs = Screen(
            elements: ["save_button": newEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
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
        )
        let rhs = Screen(
            elements: ["scrolled_row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
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
        )
        let rhs = Screen(
            elements: ["row": rhsEntry],
            hierarchy: [],
            firstResponderHeistId: nil,
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
        )
        let rhs = Screen(
            elements: [:],
            hierarchy: newHierarchy,
            firstResponderHeistId: nil,
        )

        let merged = lhs.merging(rhs)

        XCTAssertEqual(merged.liveCapture.hierarchy.count, 1)
        if case .element(let element, _) = merged.liveCapture.hierarchy[0] {
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
        )
        let rhs = Screen(
            elements: [:],
            hierarchy: [],
            firstResponderHeistId: "new_field",
        )

        XCTAssertEqual(lhs.merging(rhs).liveCapture.firstResponderHeistId, "new_field")
    }

    // MARK: - WorldStore visible commits

    func testWorldStoreVisibleCommitPreservesDiscoveryMemoryWhenVisibleIdsAreKnown() {
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

        let result = commitVisibleRefresh(from: screen, with: refresh)
        let updated = result.settledScreen

        XCTAssertEqual(updated.knownIds, ["button_visible", "button_known"])
        XCTAssertEqual(updated.visibleIds, ["button_visible"])
        XCTAssertEqual(result.observedEvidence.liveCapture.firstResponderHeistId, "button_visible")
        XCTAssertNil(updated.liveCapture.firstResponderHeistId)
        XCTAssertEqual(updated.findElement(heistId: "button_known")?.element.label, "Known")
    }

    func testWorldStoreVisibleCommitSlotsVisibleUpdatesWithoutTouchingDiscoveryMemory() {
        let counter = makeElement(label: "Total", value: "$4.00", traits: .staticText)
        let knownOnly = makeElement(label: "Below Fold", value: "old", traits: .button)
        let updatedCounter = makeElement(label: "Total", value: "$8.00", traits: .staticText)
        let screen = Screen.makeForTests(
            elements: [(counter, "total_staticText")],
            offViewport: [
                Screen.OffViewportEntry(
                    knownOnly,
                    heistId: "below_fold_button",
                    contentSpaceOrigin: CGPoint(x: 0, y: 2_000)
                )
            ]
        )
        let refresh = Screen.makeForTests(elements: [(updatedCounter, "total_staticText")])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.findElement(heistId: "total_staticText")?.element.value, "$8.00")
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.value, "old")
        XCTAssertEqual(updated.visibleIds, ["total_staticText"])
        XCTAssertEqual(updated.knownIds, ["below_fold_button", "total_staticText"])
    }

    func testWorldStoreVisibleCommitDoesNotPreserveDiscoveryMemoryForDisjointKnownViewport() {
        let oldVisible = makeElement(label: "Old Visible", traits: .button)
        let staleKnownOnly = makeElement(label: "Stale Below Fold", traits: .button)
        let freshVisible = makeElement(label: "Fresh Visible", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(oldVisible, "old_visible")],
            offViewport: [
                Screen.OffViewportEntry(
                    staleKnownOnly,
                    heistId: "stale_below_fold",
                    contentSpaceOrigin: CGPoint(x: 0, y: 2_000)
                ),
            ]
        )
        let refresh = Screen.makeForTests(elements: [(freshVisible, "stale_below_fold")])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.visibleIds, ["stale_below_fold"])
        XCTAssertEqual(updated.knownIds, ["stale_below_fold"])
        XCTAssertEqual(updated.findElement(heistId: "stale_below_fold")?.element.label, "Fresh Visible")
    }

    func testWorldStoreVisibleCommitPreservesDiscoveryMemoryFromKnownOnlyBaseline() {
        let knownOnly = makeElement(label: "Below Fold", traits: .button)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = Screen.makeForTests(
            offViewport: [Screen.OffViewportEntry(knownOnly, heistId: "below_fold_button")]
        )
        let refresh = Screen.makeForTests(elements: [(visible, "button_visible")])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.visibleIds, ["button_visible"])
        XCTAssertEqual(updated.knownIds, ["below_fold_button", "button_visible"])
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.label, "Below Fold")
    }

    func testWorldStoreVisibleCommitPreservesDiscoveryMemoryWhenKnownViewportAddsElement() {
        let visible = makeElement(label: "Visible", traits: .button)
        let added = makeElement(label: "Added", traits: .button)
        let knownOnly = makeElement(label: "Below Fold", traits: .button)
        let screen = Screen.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [Screen.OffViewportEntry(knownOnly, heistId: "below_fold_button")]
        )
        let refresh = Screen.makeForTests(elements: [
            (visible, "button_visible"),
            (added, "button_added")
        ])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.visibleIds, ["button_added", "button_visible"])
        XCTAssertEqual(updated.knownIds, ["below_fold_button", "button_added", "button_visible"])
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.label, "Below Fold")
    }

    func testWorldStoreVisibleCommitDropsDisappearedVisibleNonScrollElements() {
        let disappearing = makeElement(label: "Disappearing", traits: .staticText)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = Screen.makeForTests(
            elements: [
                (disappearing, "disappearing_staticText"),
                (visible, "button_visible")
            ]
        )
        let refresh = Screen.makeForTests(elements: [(visible, "button_visible")])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.knownIds, ["button_visible"])
        XCTAssertNil(updated.findElement(heistId: "disappearing_staticText"))
    }

    func testWorldStoreVisibleCommitDropsDisappearedVisibleScrollElements() {
        let scrolledAway = makeElement(label: "Scrolled Away", traits: .button)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = Screen(
            elements: [
                "button_scrolled_away": Screen.ScreenElement(
                    heistId: "button_scrolled_away",
                    contentSpaceOrigin: CGPoint(x: 0, y: 1_000),
                    scrollContainerPath: TreePath([0]),
                    element: scrolledAway
                ),
                "button_visible": Screen.ScreenElement(
                    heistId: "button_visible",
                    contentSpaceOrigin: nil,
                    element: visible
                )
            ],
            hierarchy: [
                .element(scrolledAway, traversalIndex: 0),
                .element(visible, traversalIndex: 1)
            ],
            heistIdsByPath: [
                TreePath([0]): "button_scrolled_away",
                TreePath([1]): "button_visible"
            ],
            firstResponderHeistId: nil,
        )
        let refresh = Screen.makeForTests(elements: [(visible, "button_visible")])

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.knownIds, ["button_visible"])
        XCTAssertEqual(updated.visibleIds, ["button_visible"])
        XCTAssertNil(updated.findElement(heistId: "button_scrolled_away"))
    }

    func testWorldStoreVisibleCommitReplacesWorldForUnrelatedVisibleRefresh() {
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

        let updated = commitVisibleRefresh(from: screen, with: refresh).settledScreen

        XCTAssertEqual(updated.knownIds, ["button_replacement"])
        XCTAssertNil(updated.findElement(heistId: "button_known"))
    }

    func testWorldStoreVisibleCommitReplacesWorldForEmptyRefresh() {
        let old = makeElement(label: "Old", traits: .button)
        let screen = Screen.makeForTests(elements: [(old, "button_old")])

        let updated = commitVisibleRefresh(from: screen, with: .empty).settledScreen

        XCTAssertTrue(updated.knownIds.isEmpty)
        XCTAssertTrue(updated.visibleIds.isEmpty)
    }

    // MARK: - Screen Capture Plan

    func testCapturePlanUsesLandscapeFrameForRotatedWindow() throws {
        let window = TheStash.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 0, y: 0, width: 200, height: 100),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 100, y: 50),
            transform: CGAffineTransform(rotationAngle: .pi / 2)
        )

        let captureBounds = try XCTUnwrap(TheStash.screenCaptureBounds(for: [window]))
        let transform = TheStash.screenCaptureTransform(for: window, relativeTo: captureBounds)
        let transformedBounds = window.bounds.applyingToCorners(transform)

        assertRect(
            CGRect(origin: .zero, size: captureBounds.size),
            equals: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
        assertRect(
            transformedBounds,
            equals: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
    }

    func testCapturePlanNormalizesNonZeroWindowOrigin() throws {
        let window = TheStash.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 20, y: 30, width: 100, height: 200),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 70, y: 130),
            transform: .identity
        )

        let captureBounds = try XCTUnwrap(TheStash.screenCaptureBounds(for: [window]))
        let transform = TheStash.screenCaptureTransform(for: window, relativeTo: captureBounds)
        let transformedBounds = window.bounds.applyingToCorners(transform)

        assertRect(
            CGRect(origin: .zero, size: captureBounds.size),
            equals: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
        assertRect(
            transformedBounds,
            equals: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

private extension CGRect {
    func applyingToCorners(_ transform: CGAffineTransform) -> CGRect {
        let transformedPoints = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
        ]
        .map { $0.applying(transform) }

        let xs = transformedPoints.map(\.x)
        let ys = transformedPoints.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return .null
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

#endif // canImport(UIKit)
