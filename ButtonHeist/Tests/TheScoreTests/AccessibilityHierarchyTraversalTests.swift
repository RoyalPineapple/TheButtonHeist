import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Testing
import ThePlans
@testable import TheScore

@Suite struct AccessibilityHierarchyTraversalTests {

    @Test func `preorder traversal includes empty nested and duplicate semantic nodes`() {
        let duplicate = makeTestAccessibilityElement(makeTestHeistElement(label: "Duplicate"))
        let empty = makeTestAccessibilityContainer(type: .semanticGroup(label: "Empty", value: nil))
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let trailing = makeTestAccessibilityElement(makeTestHeistElement(label: "Trailing"))
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                .container(empty, children: []),
                .element(duplicate, traversalIndex: 4),
                .container(nested, children: [
                    .element(duplicate, traversalIndex: 4),
                ]),
            ]),
            .element(trailing, traversalIndex: 1),
        ]

        let paths = tree.compactMapSubtrees { _, path in path }

        #expect(paths == [
            TreePath([0]),
            TreePath([0, 0]),
            TreePath([0, 1]),
            TreePath([0, 2]),
            TreePath([0, 2, 0]),
            TreePath([1]),
        ])
        #expect(tree.node(at: TreePath([0, 0])) == .container(empty, children: []))
        #expect(tree.pathIndexedElements.filter { $0.element == duplicate }.map(\.path) == [
            TreePath([0, 1]),
            TreePath([0, 2, 0]),
        ])
    }

    @Test func `canonical tree operations agree on order and inclusion`() {
        let first = makeTestAccessibilityElement(makeTestHeistElement(label: "First"))
        let duplicate = makeTestAccessibilityElement(makeTestHeistElement(label: "Duplicate"))
        let empty = makeTestAccessibilityContainer(type: .semanticGroup(label: "Empty", value: nil))
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                .element(duplicate, traversalIndex: 4),
                .container(empty, children: []),
                .container(nested, children: [
                    .element(duplicate, traversalIndex: 4),
                ]),
            ]),
            .element(first, traversalIndex: 1),
        ]

        let indexedElements = tree.pathIndexedElements

        #expect(indexedElements.map(\.path) == [
            TreePath([1]),
            TreePath([0, 0]),
            TreePath([0, 2, 0]),
        ])
        #expect(tree.elements.map(\.element) == indexedElements.map(\.element))
        #expect(tree.elements.map(\.traversalIndex) == indexedElements.map(\.traversalIndex))
        #expect(tree.sortedElements == indexedElements.map(\.element))
        #expect(tree.containers == tree.pathIndexedContainers.map(\.container))
        #expect(tree.containers == [root, empty, nested])

        let containerFingerprints = tree.containerFingerprints
        #expect(containerFingerprints[root] == tree[0].contentFingerprint)
        #expect(
            containerFingerprints[empty]
                == AccessibilityHierarchy.container(empty, children: []).contentFingerprint
        )
    }

    @Test func `context traversal preserves order context and early exit`() {
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                testElement(label: "First", traversalIndex: 0),
                .container(nested, children: [
                    testElement(label: "Second", traversalIndex: 1),
                ]),
                testElement(label: "Third", traversalIndex: 2),
                testElement(label: "Skipped", traversalIndex: 3),
            ]),
        ]
        var visitedLabels: [String] = []

        let results: [String] = tree.compactMap(
            first: 3,
            context: 0,
            container: { depth, _ in depth + 1 },
            element: { element, _, depth in
                let label = element.label ?? ""
                visitedLabels.append(label)
                return "\(label):\(depth)"
            }
        )

        #expect(results == ["First:1", "Second:2", "Third:1"])
        #expect(visitedLabels == ["First", "Second", "Third"])
    }

    @Test func `context traversal limits emitted results rather than visited leaves`() {
        let root = makeTestAccessibilityContainer(type: .list)
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                testElement(label: "Filtered", traversalIndex: 0),
                testElement(label: "First", traversalIndex: 1),
                testElement(label: "Second", traversalIndex: 2),
                testElement(label: "Unvisited", traversalIndex: 3),
            ]),
        ]
        var visitedLabels: [String] = []

        let results: [String] = tree.compactMap(
            first: 2,
            context: (),
            container: { _, _ in () },
            element: { element, _, _ in
                let label = element.label ?? ""
                visitedLabels.append(label)
                return label == "Filtered" ? nil : label
            }
        )

        #expect(results == ["First", "Second"])
        #expect(visitedLabels == ["Filtered", "First", "Second"])
    }

    @Test func `deep traversal preserves preorder path shape`() {
        let depth = 256
        let container = makeTestAccessibilityContainer(type: .landmark)
        let leaf = testElement(label: "Leaf", traversalIndex: 0)
        let hierarchy = (0..<depth).reduce(leaf) { child, _ in
            AccessibilityHierarchy.container(container, children: [child])
        }

        let paths = [hierarchy].compactMapSubtrees { _, path in path }
        let leafPaths = [hierarchy].compactMapSubtrees { node, path -> TreePath? in
            guard case .element = node else { return nil }
            return path
        }
        let foldedDepth = hierarchy.folded(
            onElement: { _, _ in 0 },
            onContainer: { _, children in (children.max() ?? -1) + 1 }
        )

        #expect(paths.count == depth + 1)
        #expect(paths.map { $0.indices.count } == Array(1...(depth + 1)))
        #expect(paths.allSatisfy { $0.indices.allSatisfy { $0 == 0 } })
        #expect(leafPaths == [TreePath(Array(repeating: 0, count: depth + 1))])
        #expect(foldedDepth == depth)
    }

    private func testElement(label: String, traversalIndex: Int) -> AccessibilityHierarchy {
        .element(
            makeTestAccessibilityElement(makeTestHeistElement(label: label)),
            traversalIndex: traversalIndex
        )
    }
}
