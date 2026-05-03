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
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: nil,
            traits: [],
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

        let idA = TheStash.ElementRegistry.stableId(for: containerA, scrollableViews: [:], firstChildHeistId: nil)
        let idB = TheStash.ElementRegistry.stableId(for: containerB, scrollableViews: [:], firstChildHeistId: nil)

        XCTAssertEqual(idA, idB, "Same semantic group metadata yields same stableId across frame drift")
    }

    func testScrollableStableIdHoldsAcrossFrameDrift() {
        let view = UIScrollView()
        let containerV1 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let containerV2 = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 100, width: 320, height: 480)
        )

        let idV1 = TheStash.ElementRegistry.stableId(
            for: containerV1, scrollableViews: [containerV1: view], firstChildHeistId: nil
        )
        let idV2 = TheStash.ElementRegistry.stableId(
            for: containerV2, scrollableViews: [containerV2: view], firstChildHeistId: nil
        )

        XCTAssertEqual(idV1, idV2, "Same UIScrollView yields same stableId regardless of frame or content size")
    }

    func testListStableIdUsesFrameAndFirstChild() {
        let container = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 100, width: 320, height: 400)
        )
        let id1 = TheStash.ElementRegistry.stableId(for: container, scrollableViews: [:], firstChildHeistId: "row_0")
        let id2 = TheStash.ElementRegistry.stableId(for: container, scrollableViews: [:], firstChildHeistId: "row_0")
        let id3 = TheStash.ElementRegistry.stableId(for: container, scrollableViews: [:], firstChildHeistId: "row_99")

        XCTAssertEqual(id1, id2, "Identical inputs yield identical ids")
        XCTAssertNotEqual(id1, id3, "Different first-child anchors yield different ids")
    }

    // MARK: - Merge

    func testMergeEmptyHierarchyLeavesEmptyTree() {
        var registry = TheStash.ElementRegistry()
        registry.merge(hierarchy: [], heistIds: [:], contexts: [:], scrollableViews: [:])
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
            scrollableViews: [:]
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

        registry.merge(hierarchy: hierarchy, heistIds: heistIds, contexts: [:], scrollableViews: [:])
        let firstRoots = registry.roots.count
        registry.merge(hierarchy: hierarchy, heistIds: heistIds, contexts: [:], scrollableViews: [:])

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
            scrollableViews: [:]
        )

        // Second parse: only B is live. A scrolled out.
        registry.merge(
            hierarchy: leaves([elementB]),
            heistIds: heistIdMap([(elementB, "id-b")]),
            contexts: [:],
            scrollableViews: [:]
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
            scrollableViews: [:]
        )

        // Second parse: B is new. A is still present.
        registry.merge(
            hierarchy: leaves([elementA, elementB]),
            heistIds: heistIdMap([(elementA, "id-a"), (elementB, "id-b")]),
            contexts: [:],
            scrollableViews: [:]
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
            scrollableViews: [:]
        )
        registry.merge(
            hierarchy: leaves([newElement]),
            heistIds: heistIdMap([(newElement, "id-a")]),
            contexts: [:],
            scrollableViews: [:]
        )

        XCTAssertEqual(registry.flattenElements().count, 1)
        XCTAssertEqual(registry.findElement(heistId: "id-a")?.element.label, "New")
    }

    /// Non-scrollable containers (list/landmark/tabBar/dataTable) currently
    /// derive their `stableId` partly from `firstChildHeistId`. When the first
    /// child changes between parses (deletion, scroll-out, hide), the
    /// container's stableId changes, so orphans collected under the old
    /// stableId can no longer reattach and surface at root level. This test
    /// pins that documented limitation — when retention beyond the scrollable
    /// case is required, fix the heuristic and update this test to assert
    /// the orphan stays nested.
    func testNonScrollableContainerLosesIdentityWhenFirstChildChanges() {
        var registry = TheStash.ElementRegistry()
        let rowA = makeElement(label: "Row A")
        let rowB = makeElement(label: "Row B")
        let listContainer = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        // First parse: list contains both rows; rowA is first.
        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowA, traversalIndex: 0),
                    .element(rowB, traversalIndex: 1),
                ])
            ],
            heistIds: heistIdMap([(rowA, "row_a"), (rowB, "row_b")]),
            contexts: [:],
            scrollableViews: [:]
        )

        // Second parse: rowA is gone; rowB is now first. The list container
        // looks the same to the parser (same type, same frame) but its
        // stableId now anchors on rowB, not rowA. The orphan rowA can't
        // reattach to the rebuilt list.
        registry.merge(
            hierarchy: [
                .container(listContainer, children: [
                    .element(rowB, traversalIndex: 0),
                ])
            ],
            heistIds: heistIdMap([(rowB, "row_b")]),
            contexts: [:],
            scrollableViews: [:]
        )

        XCTAssertNotNil(
            registry.findElement(heistId: "row_a"),
            "rowA must still be retained somewhere in the registry"
        )

        // Pin the current behavior: rowA surfaces at the root level, not
        // under the list. Update this assertion if/when the stableId
        // heuristic is replaced with something more durable.
        let topLevel = registry.roots.compactMap { node -> String? in
            if case .element(let element) = node { return element.heistId }
            return nil
        }
        XCTAssertTrue(
            topLevel.contains("row_a"),
            "Known limitation: orphans of a non-scrollable container surface " +
            "at root when the container's first-child anchor changes"
        )
    }

    func testMergeContainerSurvivesAcrossParses() {
        var registry = TheStash.ElementRegistry()
        let row = makeElement(label: "Row 0")
        let scrollView = UIScrollView()
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
            scrollableViews: [container: scrollView]
        )

        // Reparse: same scroll view but row scrolled out (no live children).
        registry.merge(
            hierarchy: [],
            heistIds: [:],
            contexts: [:],
            scrollableViews: [:]
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
            scrollableViews: [scrollContainer: UIScrollView()]
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
            scrollableViews: [scrollContainer: UIScrollView()]
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
            scrollableViews: [:]
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
            scrollableViews: [scrollContainer: UIScrollView()]
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
        let scrollView = UIScrollView()
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
            scrollableViews: [:]
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
            scrollableViews: [scrollContainer: scrollView]
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
            scrollableViews: [scrollContainer: scrollView]
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
            scrollableViews: [scrollContainer: UIScrollView()]
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
        let scrollView = UIScrollView()

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
            scrollableViews: [scrollContainer: scrollView]
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
            scrollableViews: [scrollContainer: scrollView]
        )

        let ids = registry.flattenElements().map(\.heistId)
        XCTAssertTrue(ids.contains("search_items_searchField"),
                      "Search field absent from current parse must still be in the registry tree")
    }
}

#endif
