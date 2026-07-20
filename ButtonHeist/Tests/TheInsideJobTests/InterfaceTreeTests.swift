#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class InterfaceTreeTests: XCTestCase {
    func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        shape: AccessibilityElement.Shape = .frame(AccessibilityRect.zero)
    ) -> AccessibilityElement {
        .make(label: label, value: value, identifier: identifier, traits: traits, shape: shape)
    }

    func makeEntry(
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

    func updateViewport(
        of tree: InterfaceTree,
        with observation: InterfaceObservation
    ) -> InterfaceTree {
        tree.updatingViewport(with: observation)
    }

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
}

#endif // canImport(UIKit)
