#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for the persistent registry tree introduced in the registry-tree
/// refactor. The merge algorithm, flattenElements, findElement, prune and
/// stable-container-identity all live in `ElementRegistry+Merge.swift`.
@MainActor
final class ElementRegistryTreeTests: XCTestCase {

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: UIAccessibilityTraits = [],
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(frame),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }

    /// Compute the heistId map for a list of (element, id) pairs.
    private func heistIdMap(_ pairs: [(AccessibilityElement, String)]) -> [AccessibilityElement: String] {
        Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    /// Wrap elements as leaf hierarchy nodes with sequential traversal indices.
    private func leaves(_ elements: [AccessibilityElement]) -> [AccessibilityHierarchy] {
        elements.enumerated().map { index, element in
            .element(element, traversalIndex: index)
        }
    }

    // MARK: - Stable Container Identity

    func testSemanticGroupStableIdDerivesFromMetadata() {
        let containerA = AccessibilityContainer(
            type: .semanticGroup(label: "Settings", value: nil, identifier: "settings-section"),
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        let containerB = AccessibilityContainer(
            type: .semanticGroup(label: "Settings", value: nil, identifier: "settings-section"),
            frame: CGRect(x: 50, y: 200, width: 100, height: 100)
        )

        let idA = TheStash.ElementRegistry.stableId(for: containerA, contentFrame: containerA.frame)
        let idB = TheStash.ElementRegistry.stableId(for: containerB, contentFrame: containerB.frame)

        XCTAssertEqual(idA, idB, "Same semantic group metadata yields same stableId across frame drift")
    }

    func testScrollableStableIdSurvivesContentSizeDrift() {
        // Same scrollable across parses (same content-frame) — contentSize
        // changing as rows are added shouldn't change identity.
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let containerV1 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: frame
        )
        let containerV2 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: frame
        )

        let idV1 = TheStash.ElementRegistry.stableId(for: containerV1, contentFrame: frame)
        let idV2 = TheStash.ElementRegistry.stableId(for: containerV2, contentFrame: frame)

        XCTAssertEqual(idV1, idV2, "Same content-frame yields same stableId regardless of contentSize")
    }

    func testTopLevelScrollableStableIdSurvivesFrameDrift() {
        let view = UIScrollView()
        let containerV1 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let containerV2 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 88, width: 320, height: 392)
        )

        let idV1 = TheStash.ElementRegistry.stableId(
            for: containerV1,
            contentFrame: containerV1.frame,
            isNestedInScrollView: false,
            scrollableView: view
        )
        let idV2 = TheStash.ElementRegistry.stableId(
            for: containerV2,
            contentFrame: containerV2.frame,
            isNestedInScrollView: false,
            scrollableView: view
        )

        XCTAssertEqual(idV1, idV2, "Same top-level UIScrollView should keep identity across frame drift")
    }

    func testScrollableStableIdDistinguishesContentSpacePosition() {
        // Two scrollables at different content-space positions (e.g. cell-embedded
        // carousels at different rows) get distinct ids — no collision via shared
        // UIView instance from a cell reuse pool.
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let id1 = TheStash.ElementRegistry.stableId(
            for: container, contentFrame: CGRect(x: 0, y: 500, width: 320, height: 480)
        )
        let id2 = TheStash.ElementRegistry.stableId(
            for: container, contentFrame: CGRect(x: 0, y: 5400, width: 320, height: 480)
        )
        XCTAssertNotEqual(id1, id2)
    }

    func testNestedScrollableStableIdUsesContentSpacePositionEvenWithSameView() {
        let reusedView = UIScrollView()
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 200, width: 320, height: 200)
        )

        let id1 = TheStash.ElementRegistry.stableId(
            for: container,
            contentFrame: CGRect(x: 0, y: 500, width: 320, height: 200),
            isNestedInScrollView: true,
            scrollableView: reusedView
        )
        let id2 = TheStash.ElementRegistry.stableId(
            for: container,
            contentFrame: CGRect(x: 0, y: 2700, width: 320, height: 200),
            isNestedInScrollView: true,
            scrollableView: reusedView
        )

        XCTAssertNotEqual(id1, id2, "Nested scrollables must not collapse by reused UIView identity")
    }

    func testListStableIdDerivesFromContentFrame() {
        let container = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 100, width: 320, height: 400)
        )
        let id1 = TheStash.ElementRegistry.stableId(
            for: container, contentFrame: container.frame
        )
        let id2 = TheStash.ElementRegistry.stableId(
            for: container, contentFrame: container.frame
        )
        let id3 = TheStash.ElementRegistry.stableId(
            for: container, contentFrame: CGRect(x: 0, y: 800, width: 320, height: 400)
        )

        XCTAssertEqual(id1, id2, "Identical content-frame yields identical id")
        XCTAssertNotEqual(id1, id3, "Different content-frame yields different id")
    }

    func testCoarseFrameHashSanitizesNonFiniteCoordinates() {
        // A list whose frame became NaN (e.g. UIPickerView 3D-transform corner case)
        // must still produce a usable stableId without trapping.
        let container = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let nanFrame = CGRect(x: CGFloat.nan, y: 0, width: 320, height: 400)
        _ = TheStash.ElementRegistry.stableId(for: container, contentFrame: nanFrame)
    }

    // MARK: - Merge

    func testMergeEmptyHierarchyLeavesEmptyTree() {
        var registry = TheStash.ElementRegistry()
        registry.merge(hierarchy: [], heistIds: [:], contexts: [:], containerContentFrames: [:])
        XCTAssertTrue(registry.roots.isEmpty)
        XCTAssertTrue(registry.elementByHeistId.isEmpty)
    }

    func testMergeSingleFlatHierarchyBuildsTree() {
        var registry = TheStash.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")
        registry.merge(
            hierarchy: leaves([elementA, elementB]),
            heistIds: heistIdMap([(elementA, "id-a"), (elementB, "id-b")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        let flat = registry.flattenElements()
        XCTAssertEqual(flat.map(\.heistId), ["id-a", "id-b"])
        XCTAssertNotNil(registry.elementByHeistId["id-a"])
        XCTAssertNotNil(registry.elementByHeistId["id-b"])
    }

    func testMergeSameHierarchyTwiceIsIdempotent() {
        var registry = TheStash.ElementRegistry()
        let elementA = makeElement(label: "A")
        let hierarchy = leaves([elementA])
        let heistIds = heistIdMap([(elementA, "id-a")])

        registry.merge(hierarchy: hierarchy, heistIds: heistIds, contexts: [:], containerContentFrames: [:])
        let firstRoots = registry.roots.count
        registry.merge(hierarchy: hierarchy, heistIds: heistIds, contexts: [:], containerContentFrames: [:])

        XCTAssertEqual(registry.roots.count, firstRoots, "Merging an identical parse is idempotent")
        XCTAssertEqual(registry.flattenElements().map(\.heistId), ["id-a"])
    }

    func testMergeRetainsScrolledOutElement() {
        var registry = TheStash.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")

        registry.merge(
            hierarchy: leaves([elementA, elementB]),
            heistIds: heistIdMap([(elementA, "id-a"), (elementB, "id-b")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        // Second parse: only B is live. A scrolled out.
        registry.merge(
            hierarchy: leaves([elementB]),
            heistIds: heistIdMap([(elementB, "id-b")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        let ids = registry.flattenElements().map(\.heistId)
        XCTAssertTrue(ids.contains("id-a"), "Scrolled-out element retained in registry tree")
        XCTAssertTrue(ids.contains("id-b"), "Live element still in tree")
    }

    func testMergeInsertsNovelElement() {
        var registry = TheStash.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")

        registry.merge(
            hierarchy: leaves([elementA]),
            heistIds: heistIdMap([(elementA, "id-a")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        // Second parse: B is new. A is still present.
        registry.merge(
            hierarchy: leaves([elementA, elementB]),
            heistIds: heistIdMap([(elementA, "id-a"), (elementB, "id-b")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        let ids = registry.flattenElements().map(\.heistId)
        XCTAssertEqual(Set(ids), ["id-a", "id-b"])
    }

    func testMergeUpdatesExistingElementInPlace() {
        var registry = TheStash.ElementRegistry()
        let oldElement = makeElement(label: "Old")
        let newElement = makeElement(label: "New")

        registry.merge(
            hierarchy: leaves([oldElement]),
            heistIds: heistIdMap([(oldElement, "id-a")]),
            contexts: [:],
            containerContentFrames: [:]
        )
        registry.merge(
            hierarchy: leaves([newElement]),
            heistIds: heistIdMap([(newElement, "id-a")]),
            contexts: [:],
            containerContentFrames: [:]
        )

        XCTAssertEqual(registry.flattenElements().count, 1)
        XCTAssertEqual(registry.findElement(heistId: "id-a")?.element.label, "New")
    }

    func testSameMinimumMatcherUsesContentPositionSuffixWhenPositionChanges() {
        var registry = TheStash.ElementRegistry()
        let initial = makeElement(label: "Song A")
        let duplicate = makeElement(label: "Song A")

        registry.register(
            parsedElements: [initial],
            heistIds: ["song_a_staticText"],
            contexts: [
                initial: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 100),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(initial, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        registry.register(
            parsedElements: [duplicate],
            heistIds: ["song_a_staticText"],
            contexts: [
                duplicate: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 200),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(duplicate, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        XCTAssertNotNil(registry.findElement(heistId: "song_a_staticText"))
        XCTAssertNotNil(registry.findElement(heistId: "song_a_staticText_at_0_200"))
        XCTAssertEqual(Set(registry.flattenElements().map(\.heistId)), ["song_a_staticText", "song_a_staticText_at_0_200"])
    }

    func testStateChangeKeepsHeistIdAtSameContentPosition() {
        var registry = TheStash.ElementRegistry()
        let initial = makeElement(label: "Favorite", value: "0", traits: [.button])
        let selected = makeElement(label: "Favorite", value: "1", traits: [.button, .selected])

        registry.register(
            parsedElements: [initial],
            heistIds: ["favorite_button"],
            contexts: [
                initial: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 100),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(initial, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        registry.register(
            parsedElements: [selected],
            heistIds: ["favorite_button"],
            contexts: [
                selected: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 100),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(selected, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        XCTAssertNotNil(registry.findElement(heistId: "favorite_button"))
        XCTAssertNil(registry.findElement(heistId: "favorite_button_at_0_200"))
        XCTAssertEqual(registry.flattenElements().map(\.heistId), ["favorite_button"])
    }

    func testStableTraitChangeUsesContentPositionSuffix() {
        var registry = TheStash.ElementRegistry()
        let button = makeElement(label: "Open", traits: [.button])
        let link = makeElement(label: "Open", traits: [.link])

        registry.register(
            parsedElements: [button],
            heistIds: ["open"],
            contexts: [
                button: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 100),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(button, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        registry.register(
            parsedElements: [link],
            heistIds: ["open"],
            contexts: [
                link: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 200),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(link, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        XCTAssertNotNil(registry.findElement(heistId: "open"))
        XCTAssertNotNil(registry.findElement(heistId: "open_at_0_200"))
        XCTAssertEqual(Set(registry.flattenElements().map(\.heistId)), ["open", "open_at_0_200"])
    }

    func testDifferentMinimumMatcherUsesContentPositionSuffix() {
        var registry = TheStash.ElementRegistry()
        let initial = makeElement(label: "Song A")
        let replacement = makeElement(label: "Song B")

        registry.register(
            parsedElements: [initial],
            heistIds: ["song_staticText"],
            contexts: [
                initial: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 100),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(initial, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        registry.register(
            parsedElements: [replacement],
            heistIds: ["song_staticText"],
            contexts: [
                replacement: TheStash.ElementContext(
                    contentSpaceOrigin: CGPoint(x: 0, y: 200),
                    scrollView: nil,
                    object: nil
                ),
            ],
            hierarchy: [.element(replacement, traversalIndex: 0)],
            containerContentFrames: [:]
        )

        XCTAssertNotNil(registry.findElement(heistId: "song_staticText"))
        XCTAssertNotNil(registry.findElement(heistId: "song_staticText_at_0_200"))
        XCTAssertEqual(Set(registry.flattenElements().map(\.heistId)), ["song_staticText", "song_staticText_at_0_200"])
    }

    /// Non-scrollable containers (list/landmark/tabBar/dataTable) derive
    /// their `stableId` from the container's content-space frame, so identity
    /// holds through child churn. An orphan whose siblings changed entirely
    /// still reattaches to the same list across parses.
    func testNonScrollableContainerKeepsIdentityWhenChildrenChurn() {
        var registry = TheStash.ElementRegistry()
        let rowA = makeElement(label: "Row A")
        let rowB = makeElement(label: "Row B")
        let listContainer = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        // First parse: list contains both rows.
        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowA, traversalIndex: 0),
                    .element(rowB, traversalIndex: 1),
                ])
            ],
            heistIds: heistIdMap([(rowA, "row_a"), (rowB, "row_b")]),
            contexts: [:],
            containerContentFrames: [listContainer: listContainer.frame]
        )

        // Second parse: rowA is gone; rowB is now the first child.
        // List identity is content-frame-based, so it survives.
        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowB, traversalIndex: 0),
                ])
            ],
            heistIds: heistIdMap([(rowB, "row_b")]),
            contexts: [:],
            containerContentFrames: [listContainer: listContainer.frame]
        )

        XCTAssertNotNil(
            registry.findElement(heistId: "row_a"),
            "rowA must be retained in the registry"
        )

        let topLevel = registry.roots.compactMap { node -> String? in
            if case .element(let element) = node { return element.heistId }
            return nil
        }
        XCTAssertFalse(
            topLevel.contains("row_a"),
            "rowA must NOT surface at root — list identity holds across child churn"
        )

        var foundUnderList = false
        for node in registry.roots {
            if case .container(let entry, let children) = node,
               case .list = entry.container.type {
                for child in children {
                    if case .element(let element) = child, element.heistId == "row_a" {
                        foundUnderList = true
                    }
                }
            }
        }
        XCTAssertTrue(foundUnderList, "rowA should be a child of the list container")
    }

    func testNonScrollableContainerInterleavesRetainedChildrenByScreenPosition() {
        var registry = TheStash.ElementRegistry()
        let rowA = makeElement(label: "Row A", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let rowB = makeElement(label: "Row B", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let listContainer = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowA, traversalIndex: 0),
                    .element(rowB, traversalIndex: 1),
                ])
            ],
            heistIds: heistIdMap([(rowA, "row_a"), (rowB, "row_b")]),
            contexts: [:],
            containerContentFrames: [listContainer: listContainer.frame]
        )

        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowB, traversalIndex: 0),
                ])
            ],
            heistIds: heistIdMap([(rowB, "row_b")]),
            contexts: [:],
            containerContentFrames: [listContainer: listContainer.frame]
        )

        XCTAssertEqual(registry.flattenElements().map(\.heistId), ["row_a", "row_b"])
    }

    func testMergeContainerSurvivesAcrossParses() {
        var registry = TheStash.ElementRegistry()
        let row = makeElement(label: "Row 0")
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [.element(row, traversalIndex: 0)])
        ]

        registry.merge(
            hierarchy: hierarchy,
            heistIds: heistIdMap([(row, "row_0")]),
            contexts: [:],
            containerContentFrames: [container: container.frame]
        )

        // Reparse: same scroll view but row scrolled out (no live children).
        registry.merge(
            hierarchy: [],
            heistIds: [:],
            contexts: [:],
            containerContentFrames: [:]
        )

        XCTAssertNotNil(registry.findElement(heistId: "row_0"),
                        "Element under the container should persist across an empty parse")
    }

    // MARK: - flattenElements

    func testFlattenElementsTraversalOrder() {
        var registry = TheStash.ElementRegistry()
        let header = makeElement(label: "Header")
        let row0 = makeElement(label: "Row 0")
        let row1 = makeElement(label: "Row 1")

        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 50, width: 320, height: 480)
        )

        let hierarchy: [AccessibilityHierarchy] = [
            .element(header, traversalIndex: 0),
            .container(scrollContainer, children: [
                .element(row0, traversalIndex: 1),
                .element(row1, traversalIndex: 2),
            ])
        ]

        registry.merge(
            hierarchy: hierarchy,
            heistIds: heistIdMap([
                (header, "header"),
                (row0, "row_0"),
                (row1, "row_1"),
            ]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        XCTAssertEqual(
            registry.flattenElements().map(\.heistId),
            ["header", "row_0", "row_1"]
        )
    }

    // MARK: - findElement

    func testFindElementReturnsNilForUnknown() {
        let registry = TheStash.ElementRegistry()
        XCTAssertNil(registry.findElement(heistId: "missing"))
    }

    func testFindElementResolvesNestedLeaf() {
        var registry = TheStash.ElementRegistry()
        let row = makeElement(label: "Row")
        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let hierarchy: [AccessibilityHierarchy] = [
            .container(scrollContainer, children: [.element(row, traversalIndex: 0)])
        ]

        registry.merge(
            hierarchy: hierarchy,
            heistIds: heistIdMap([(row, "row_0")]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        XCTAssertEqual(registry.findElement(heistId: "row_0")?.element.label, "Row")
    }

    // MARK: - prune

    func testPruneTreeRemovesUnreachableLeaves() {
        var registry = TheStash.ElementRegistry()
        let elementA = makeElement(label: "A")
        let elementB = makeElement(label: "B")
        let elementC = makeElement(label: "C")
        registry.merge(
            hierarchy: leaves([elementA, elementB, elementC]),
            heistIds: heistIdMap([
                (elementA, "id-a"),
                (elementB, "id-b"),
                (elementC, "id-c"),
            ]),
            contexts: [:],
            containerContentFrames: [:]
        )

        registry.pruneTree(keeping: ["id-a", "id-c"])

        let surviving = Set(registry.flattenElements().map(\.heistId))
        XCTAssertEqual(surviving, ["id-a", "id-c"])
    }

    func testPruneTreeRemovesEmptiedContainers() {
        var registry = TheStash.ElementRegistry()
        let row = makeElement(label: "Row")
        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        registry.merge(
            hierarchy: [.container(scrollContainer, children: [.element(row, traversalIndex: 0)])],
            heistIds: heistIdMap([(row, "row_0")]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        registry.pruneTree(keeping: [])

        XCTAssertTrue(registry.roots.isEmpty,
                      "Container with no surviving descendants should be pruned")
    }

    // MARK: - Invariants

    /// The merge implementation must leave the registry in a consistent state:
    /// elementByHeistId matches roots, every leaf is unique, no empty containers.
    /// This test exercises a sequence of merges and validates after every step.
    func testInvariantsHoldAcrossSequenceOfMerges() {
        var registry = TheStash.ElementRegistry()
        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )

        // Step 1: empty registry has no violations
        XCTAssertNil(registry.validateInvariants())

        // Step 2: insert a few elements at root
        let alpha = makeElement(label: "Alpha")
        let beta = makeElement(label: "Beta")
        registry.merge(
            hierarchy: leaves([alpha, beta]),
            heistIds: heistIdMap([(alpha, "id-alpha"), (beta, "id-beta")]),
            contexts: [:],
            containerContentFrames: [:]
        )
        XCTAssertNil(registry.validateInvariants())

        // Step 3: add a scrollable container with rows
        let row0 = makeElement(label: "Row 0")
        let row1 = makeElement(label: "Row 1")
        registry.merge(
            hierarchy: [
                .element(alpha, traversalIndex: 0),
                .element(beta, traversalIndex: 1),
                .container(scrollContainer, children: [
                    .element(row0, traversalIndex: 2),
                    .element(row1, traversalIndex: 3),
                ])
            ],
            heistIds: heistIdMap([
                (alpha, "id-alpha"),
                (beta, "id-beta"),
                (row0, "row-0"),
                (row1, "row-1"),
            ]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )
        XCTAssertNil(registry.validateInvariants())

        // Step 4: a row scrolls out — invariants still hold, row retained
        registry.merge(
            hierarchy: [
                .element(alpha, traversalIndex: 0),
                .element(beta, traversalIndex: 1),
                .container(scrollContainer, children: [
                    .element(row1, traversalIndex: 2),
                ])
            ],
            heistIds: heistIdMap([
                (alpha, "id-alpha"),
                (beta, "id-beta"),
                (row1, "row-1"),
            ]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )
        XCTAssertNil(registry.validateInvariants())
        XCTAssertNotNil(registry.findElement(heistId: "row-0"))

        // Step 5: prune to keep only the alpha — invariants still hold
        registry.pruneTree(keeping: ["id-alpha"])
        XCTAssertNil(registry.validateInvariants())
        XCTAssertEqual(Set(registry.elementByHeistId.keys), ["id-alpha"])
    }

    /// flattenElements yields every leaf exactly once, in tree (DFS) order.
    func testFlattenIsBijectionWithLeaves() {
        var registry = TheStash.ElementRegistry()
        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let header = makeElement(label: "Header")
        let row0 = makeElement(label: "Row 0")
        let row1 = makeElement(label: "Row 1")
        let footer = makeElement(label: "Footer")

        registry.merge(
            hierarchy: [
                .element(header, traversalIndex: 0),
                .container(scrollContainer, children: [
                    .element(row0, traversalIndex: 1),
                    .element(row1, traversalIndex: 2),
                ]),
                .element(footer, traversalIndex: 3),
            ],
            heistIds: heistIdMap([
                (header, "header"),
                (row0, "row-0"),
                (row1, "row-1"),
                (footer, "footer"),
            ]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        let flat = registry.flattenElements().map(\.heistId)
        XCTAssertEqual(flat, ["header", "row-0", "row-1", "footer"])
        XCTAssertEqual(flat.count, registry.elementByHeistId.count)
    }

    // MARK: - T12 regression

    func testT12SearchFieldRegression() {
        // T12 shape: registry knows about a search field, but the live parse
        // doesn't include it (e.g. it scrolled out of the visible region or
        // the overlay-trim filter excluded it). The flat element list and
        // tree walk must still surface the search field.
        var registry = TheStash.ElementRegistry()
        let searchField = makeElement(label: "Search items", identifier: "search")
        let row0 = makeElement(label: "Row 0")
        let row1 = makeElement(label: "Row 1")

        let scrollContainer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 402, height: 5311)),
            frame: CGRect(x: 0, y: 0, width: 402, height: 800)
        )

        // First parse includes search field + rows.
        registry.merge(
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(searchField, traversalIndex: 0),
                    .element(row0, traversalIndex: 1),
                    .element(row1, traversalIndex: 2),
                ])
            ],
            heistIds: heistIdMap([
                (searchField, "search_items_searchField"),
                (row0, "row_0"),
                (row1, "row_1"),
            ]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        // Second parse: scrolled past the search field. It's no longer live,
        // but the registry remembers it.
        registry.merge(
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(row0, traversalIndex: 0),
                    .element(row1, traversalIndex: 1),
                ])
            ],
            heistIds: heistIdMap([(row0, "row_0"), (row1, "row_1")]),
            contexts: [:],
            containerContentFrames: [scrollContainer: scrollContainer.frame]
        )

        let ids = registry.flattenElements().map(\.heistId)
        XCTAssertTrue(ids.contains("search_items_searchField"),
                      "Search field absent from current parse must still be in the registry tree")
    }

    // MARK: - Cell Reuse Safety

    /// End-to-end property test for the cell-reuse hazard the content-frame
    /// identity model is designed to prevent.
    ///
    /// Scenario: a UICollectionView (or UITableView) reuses a cell whose
    /// inner UIScrollView (a horizontal carousel) was previously bound to row
    /// 5's data and is now bound to row 27's data. Under an `ObjectIdentifier`-
    /// based identity, both carousels would share a stableId and an orphan
    /// from row 5's carousel would attach as a sibling of row 27's content —
    /// cross-contamination. Under content-space-frame identity, the two
    /// carousels live at distinct logical positions (content-y = 500 vs 2700)
    /// and so receive distinct stableIds.
    ///
    /// The property under test: row 5's orphan element MUST NOT end up
    /// nested as a sibling of row 27's content under any single container.
    func testCellReusedScrollableDoesNotCrossContaminateContents() {
        var registry = TheStash.ElementRegistry()
        let carousel = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 200, width: 320, height: 200)
        )
        let row5Item = makeElement(label: "Row 5 Item")
        let row27Item = makeElement(label: "Row 27 Item")

        // Parse 1: row 5's carousel at content-y = 500.
        registry.merge(
            hierarchy: [.container(carousel, children: [.element(row5Item, traversalIndex: 0)])],
            heistIds: heistIdMap([(row5Item, "row5_item")]),
            contexts: [:],
            containerContentFrames: [carousel: CGRect(x: 0, y: 500, width: 320, height: 200)]
        )

        // Parse 2: cell reuse — same AccessibilityContainer value (and possibly the
        // same backing UIView from the cell pool), but at content-y = 2700.
        registry.merge(
            hierarchy: [.container(carousel, children: [.element(row27Item, traversalIndex: 0)])],
            heistIds: heistIdMap([(row27Item, "row27_item")]),
            contexts: [:],
            containerContentFrames: [carousel: CGRect(x: 0, y: 2700, width: 320, height: 200)]
        )

        XCTAssertNotNil(registry.findElement(heistId: "row5_item"),
                        "row 5's element retained in the registry")
        XCTAssertNotNil(registry.findElement(heistId: "row27_item"),
                        "row 27's element present from the live parse")

        var crossContamination = false
        for node in registry.roots {
            if case .container(_, let children) = node {
                let ids = children.compactMap { node -> String? in
                    if case .element(let element) = node { return element.heistId }
                    return nil
                }
                if ids.contains("row5_item") && ids.contains("row27_item") {
                    crossContamination = true
                }
            }
        }
        XCTAssertFalse(
            crossContamination,
            "A cell-reused scrollable at a different content-position must not adopt orphans from its previous logical content"
        )
    }
}

#endif
