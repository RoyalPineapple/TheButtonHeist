#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class InterfaceTreeTests: XCTestCase {

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
        scrollContainerPath: TreePath? = nil,
        scrollIndex: Int? = nil
    ) -> InterfaceTree.Element {
        InterfaceTree.Element(
            heistId: heistId,
            scrollMembership: scrollContainerPath.map {
                InterfaceTree.ScrollMembership(containerPath: $0, index: scrollIndex)
            },
            element: makeElement(label: label ?? heistId.description)
        )
    }

    private func updateViewport(
        of tree: InterfaceTree,
        with observation: InterfaceObservation
    ) -> InterfaceTree {
        tree.updatingViewport(with: observation)
    }

    // MARK: - .empty

    func testEmptyHasNoElements() {
        XCTAssertTrue(InterfaceObservation.empty.tree.elements.isEmpty)
    }

    func testEmptyHasNoHierarchy() {
        XCTAssertTrue(InterfaceObservation.empty.liveCapture.hierarchy.isEmpty)
    }

    func testEmptyHasNoFirstResponder() {
        XCTAssertNil(InterfaceObservation.empty.liveCapture.firstResponderHeistId)
    }

    func testEmptyHasNoName() {
        XCTAssertNil(InterfaceObservation.empty.tree.name)
        XCTAssertNil(InterfaceObservation.empty.tree.id)
    }

    func testEmptyInterfaceIdsIsEmpty() {
        XCTAssertTrue(InterfaceObservation.empty.tree.elementIDs.isEmpty)
    }

    func testEmptyViewportIdsIsEmpty() {
        XCTAssertTrue(InterfaceObservation.empty.tree.viewportElementIDs.isEmpty)
    }

    // MARK: - InterfaceTree / LiveInterface

    func testInterfaceTreeIncludesOffViewportEntriesOutsideLatestParse() {
        let visible = makeElement(label: "Visible", traits: .button)
        let offViewport = makeElement(label: "Known", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    offViewport,
                    heistId: "button_known",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )

        XCTAssertEqual(screen.tree.elementIDs, ["button_visible", "button_known"])
        XCTAssertEqual(screen.liveCapture.heistIds, ["button_visible"])
        XCTAssertEqual(screen.tree.findElement(heistId: "button_known")?.element.label, "Known")
        XCTAssertFalse(screen.liveCapture.contains(heistId: "button_known"))
    }

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

    func testViewportUpdateRetainsElementsThatMoveOffscreenInFullTreeCapture() throws {
        let visibleTarget = makeElement(label: "Target", traits: .button)
        let anchor = makeElement(label: "Anchor", traits: .staticText)
        let initial = InterfaceObservation.makeForTests(elements: [
            (visibleTarget, "target"),
            (anchor, "anchor"),
        ])
        let refreshed = InterfaceObservation.makeForTests(elements: [
            (.make(label: "Target", traits: .button, visibility: .offscreen), "target"),
            (anchor, "anchor"),
        ])

        let updated = initial.tree.updatingViewport(with: refreshed)

        XCTAssertEqual(updated.viewportElementIDs, ["anchor"])
        XCTAssertEqual(updated.elementIDs, ["anchor", "target"])
        XCTAssertEqual(updated.findElement(heistId: "target")?.element.visibility, .offscreen)
        XCTAssertNoThrow(try InterfaceObservation.build(tree: updated))
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
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
        )
        let keptObject = NSObject()
        let containerObject = NSObject()
        let scrollView = UIScrollView()
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "old": InterfaceTree.Element(
                    heistId: "old",
                    scrollMembership: nil,
                    element: removed
                ),
                "kept": InterfaceTree.Element(
                    heistId: "kept",
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([1]), index: nil),
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
            elementRefs: [
                "kept": LiveCapture.ElementRef(object: keptObject, scrollView: scrollView),
            ],
            containerRefsByPath: [
                TreePath([1]): LiveCapture.ContainerRef(object: containerObject),
            ],
            firstResponderHeistId: "kept",
            scrollableContainerViewsByPath: [
                TreePath([1]): LiveCapture.ScrollableViewRef(view: scrollView),
            ]
        )

        let pruned = screen.removingElements(withIds: ["old"])
        let interface = TheVault.WireConversion.toSemanticInterface(from: pruned.tree)

        XCTAssertEqual(pruned.liveCapture.heistId(forPath: TreePath([0, 0])), "kept")
        XCTAssertNil(pruned.liveCapture.heistId(forPath: TreePath([1, 0])))
        XCTAssertEqual(pruned.tree.containers[TreePath([0])]?.containerName, "feed")
        XCTAssertNil(pruned.tree.containers[TreePath([1])])
        XCTAssertEqual(pruned.tree.elements["kept"]?.scrollMembership?.containerPath, TreePath([0]))
        XCTAssertEqual(pruned.liveCapture.firstResponderHeistId, "kept")
        XCTAssertTrue(pruned.liveCapture.object(for: "kept") === keptObject)
        XCTAssertTrue(pruned.liveCapture.containerObject(forPath: TreePath([0])) === containerObject)
        XCTAssertTrue(pruned.liveCapture.scrollView(forContainerPath: TreePath([0])) === scrollView)
        XCTAssertEqual(interface.annotations.containerByPath[TreePath([0])]?.containerName, "feed")
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 0])])
        XCTAssertNil(interface.annotations.elementByPath[TreePath([1, 0])])
    }

    func testViewportOnlyFiltersOffViewportEntriesOutsideLatestParse() {
        let visible = makeElement(label: "Visible", traits: .button)
        let offViewport = makeElement(label: "Known", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    offViewport,
                    heistId: "button_known",
                    scrollContainerPath: TreePath([0])
                )
            ],
            firstResponderHeistId: "button_visible"
        )

        let visibleOnly = screen.viewportOnly

        XCTAssertEqual(visibleOnly.tree.elementIDs, ["button_visible"])
        XCTAssertEqual(visibleOnly.tree.viewportElementIDs, ["button_visible"])
        XCTAssertEqual(visibleOnly.liveCapture.hierarchy, screen.liveCapture.hierarchy)
        XCTAssertEqual(visibleOnly.liveCapture.firstResponderHeistId, "button_visible")
        XCTAssertNil(visibleOnly.tree.findElement(heistId: "button_known"))
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

    func testOrderedElementsReturnsViewportOrderThenOffViewportSortedByHeistId() {
        let firstLive = makeElement(label: "First", traits: .button)
        let secondLive = makeElement(label: "Second", traits: .button)
        let aKnown = makeElement(label: "A Known", traits: .button)
        let zKnown = makeElement(label: "Z Known", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (secondLive, "button_second"),
                (firstLive, "button_first"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(zKnown, heistId: "z_known"),
                InterfaceObservation.OffViewportEntry(aKnown, heistId: "a_known"),
            ]
        )

        XCTAssertEqual(
            screen.tree.orderedElements.map(\.heistId),
            ["button_second", "button_first", "a_known", "z_known"]
        )
    }

    // MARK: - findElement

    func testFindElementReturnsNilForUnknownId() {
        let screen = InterfaceObservation.makeForTests(
            elements: ["a_button": makeEntry(heistId: "a_button")],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        XCTAssertNil(screen.tree.findElement(heistId: "missing"))
    }

    func testFindElementReturnsEntryForExistingId() {
        let entry = makeEntry(heistId: "save_button")
        let screen = InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [],
            firstResponderHeistId: nil,
        )
        XCTAssertEqual(screen.tree.findElement(heistId: "save_button")?.heistId, "save_button")
    }

    // MARK: - name / id

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

    // MARK: - merging — disjoint sets

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

    // MARK: - merging — conflict rule

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

    // MARK: - merging — hierarchy / first responder

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

    // MARK: - InterfaceTree viewport updates

    func testInterfaceTreeViewportUpdatePreservesDiscoveryMemoryWhenVisibleIdsAreKnown() {
        let visible = makeElement(label: "Visible", traits: .button)
        let offViewport = makeElement(label: "Known", traits: .button)
        let refreshedVisible = makeElement(label: "Visible", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    offViewport,
                    heistId: "button_known",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        let refresh = InterfaceObservation.makeForTests(
            elements: [(refreshedVisible, "button_visible")],
            firstResponderHeistId: "button_visible"
        )

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.elementIDs, ["button_visible", "button_known"])
        XCTAssertEqual(updated.viewportElementIDs, ["button_visible"])
        XCTAssertEqual(refresh.liveCapture.firstResponderHeistId, "button_visible")
        XCTAssertEqual(
            LiveCapture.makeForTests(snapshot: updated.viewportCapture).firstResponderHeistId,
            "button_visible"
        )
        XCTAssertEqual(updated.findElement(heistId: "button_known")?.element.label, "Known")
    }

    func testInterfaceTreeViewportUpdateSlotsVisibleUpdatesWithoutTouchingDiscoveryMemory() {
        let counter = makeElement(label: "Total", value: "$4.00", traits: .staticText)
        let offViewport = makeElement(label: "Below Fold", value: "old", traits: .button)
        let updatedCounter = makeElement(label: "Total", value: "$8.00", traits: .staticText)
        let screen = InterfaceObservation.makeForTests(
            elements: [(counter, "total_staticText")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    offViewport,
                    heistId: "below_fold_button",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(updatedCounter, "total_staticText")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.findElement(heistId: "total_staticText")?.element.value, "$8.00")
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.value, "old")
        XCTAssertEqual(updated.viewportElementIDs, ["total_staticText"])
        XCTAssertEqual(updated.elementIDs, ["below_fold_button", "total_staticText"])
    }

    func testInterfaceTreeViewportUpdateDoesNotPreserveDiscoveryMemoryForDisjointCommittedViewport() {
        let oldVisible = makeElement(label: "Old Visible", traits: .button)
        let staleOffViewport = makeElement(label: "Stale Below Fold", traits: .button)
        let freshVisible = makeElement(label: "Fresh Visible", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(oldVisible, "old_visible")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleOffViewport,
                    heistId: "stale_below_fold",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(freshVisible, "stale_below_fold")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.viewportElementIDs, ["stale_below_fold"])
        XCTAssertEqual(updated.elementIDs, ["stale_below_fold"])
        XCTAssertEqual(updated.findElement(heistId: "stale_below_fold")?.element.label, "Fresh Visible")
    }

    func testInterfaceTreeViewportUpdatePreservesDiscoveryMemoryFromOffViewportBaseline() {
        let offViewport = makeElement(label: "Below Fold", traits: .button)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            offViewport: [InterfaceObservation.OffViewportEntry(offViewport, heistId: "below_fold_button")]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(visible, "button_visible")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.viewportElementIDs, ["button_visible"])
        XCTAssertEqual(updated.elementIDs, ["below_fold_button", "button_visible"])
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.label, "Below Fold")
    }

    func testInterfaceTreeViewportUpdatePreservesDiscoveryMemoryWhenCommittedViewportAddsElement() {
        let visible = makeElement(label: "Visible", traits: .button)
        let added = makeElement(label: "Added", traits: .button)
        let offViewport = makeElement(label: "Below Fold", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [InterfaceObservation.OffViewportEntry(offViewport, heistId: "below_fold_button")]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [
            (visible, "button_visible"),
            (added, "button_added")
        ])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.viewportElementIDs, ["button_added", "button_visible"])
        XCTAssertEqual(updated.elementIDs, ["below_fold_button", "button_added", "button_visible"])
        XCTAssertEqual(updated.findElement(heistId: "below_fold_button")?.element.label, "Below Fold")
    }

    func testInterfaceTreeViewportUpdateDropsDisappearedVisibleNonScrollElements() {
        let disappearing = makeElement(label: "Disappearing", traits: .staticText)
        let visible = makeElement(label: "Visible", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [
                (disappearing, "disappearing_staticText"),
                (visible, "button_visible")
            ]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(visible, "button_visible")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.elementIDs, ["button_visible"])
        XCTAssertNil(updated.findElement(heistId: "disappearing_staticText"))
    }

    func testInterfaceTreeViewportUpdateDropsDisappearedVisibleScrollElements() {
        let scrolledAway = makeElement(label: "Scrolled Away", traits: .button)
        let visible = makeElement(label: "Visible", traits: .button)
        let scrollContainer = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "button_scrolled_away": InterfaceTree.Element(
                    heistId: "button_scrolled_away",
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
                    element: scrolledAway
                ),
                "button_visible": InterfaceTree.Element(
                    heistId: "button_visible",
                    scrollMembership: nil,
                    element: visible
                )
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(scrolledAway, traversalIndex: 0),
                ]),
                .element(visible, traversalIndex: 1)
            ],
            heistIdsByPath: [
                TreePath([0, 0]): "button_scrolled_away",
                TreePath([1]): "button_visible"
            ],
            firstResponderHeistId: nil,
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(visible, "button_visible")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.elementIDs, ["button_visible"])
        XCTAssertEqual(updated.viewportElementIDs, ["button_visible"])
        XCTAssertNil(updated.findElement(heistId: "button_scrolled_away"))
    }

    func testInterfaceTreeViewportUpdatePreservesOffViewportMemoryForUnrelatedVisibleRefresh() {
        let old = makeElement(label: "Old", traits: .button)
        let offViewport = makeElement(label: "Known", traits: .button)
        let replacement = makeElement(label: "Replacement", traits: .button)
        let screen = InterfaceObservation.makeForTests(
            elements: [(old, "button_old")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(offViewport, heistId: "button_known")
            ]
        )
        let refresh = InterfaceObservation.makeForTests(elements: [(replacement, "button_replacement")])

        let updated = updateViewport(of: screen.tree, with: refresh)

        XCTAssertEqual(updated.elementIDs, ["button_known", "button_replacement"])
        XCTAssertEqual(updated.findElement(heistId: "button_known")?.element.label, "Known")
    }

    func testInterfaceTreeViewportUpdateReplacesInterfaceTreeForEmptyRefresh() {
        let old = makeElement(label: "Old", traits: .button)
        let screen = InterfaceObservation.makeForTests(elements: [(old, "button_old")])

        let updated = updateViewport(of: screen.tree, with: .empty)

        XCTAssertTrue(updated.elementIDs.isEmpty)
        XCTAssertTrue(updated.viewportElementIDs.isEmpty)
    }

    // MARK: - InterfaceObservation Capture Plan

    func testCapturePlanUsesLandscapeFrameForRotatedWindow() throws {
        let window = TheVault.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 0, y: 0, width: 200, height: 100),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 100, y: 50),
            transform: CGAffineTransform(rotationAngle: .pi / 2)
        )

        let captureBounds = try XCTUnwrap(TheVault.screenCaptureBounds(for: [window]))
        let transform = TheVault.screenCaptureTransform(for: window, relativeTo: captureBounds)
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
        let window = TheVault.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 20, y: 30, width: 100, height: 200),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 70, y: 130),
            transform: .identity
        )

        let captureBounds = try XCTUnwrap(TheVault.screenCaptureBounds(for: [window]))
        let transform = TheVault.screenCaptureTransform(for: window, relativeTo: captureBounds)
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
