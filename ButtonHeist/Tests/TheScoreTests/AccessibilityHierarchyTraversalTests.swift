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

    @Test func `forest and subtree traversal agree on preorder paths`() {
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                testElement(label: "First", traversalIndex: 0),
                .container(nested, children: [
                    testElement(label: "Nested", traversalIndex: 1),
                ]),
            ]),
            testElement(label: "Second root", traversalIndex: 2),
        ]

        let forestPaths = tree.compactMapSubtrees { _, path in path }
        let subtreePaths = tree.enumerated().flatMap { index, hierarchy in
            hierarchy.compactMapSubtrees(path: TreePath([index])) { _, path in path }
        }

        #expect(forestPaths == subtreePaths)
        #expect(forestPaths == [
            TreePath([0]),
            TreePath([0, 0]),
            TreePath([0, 1]),
            TreePath([0, 1, 0]),
            TreePath([1]),
        ])
    }

    @Test func `fold and compaction preserve canonical child order`() {
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let hierarchy = AccessibilityHierarchy.container(root, children: [
            testElement(label: "First", traversalIndex: 0),
            testElement(label: "Drop", traversalIndex: 1),
            .container(nested, children: [
                testElement(label: "Nested", traversalIndex: 2),
            ]),
        ])

        let foldedLabels = hierarchy.folded(
            onElement: { element, _ -> [String] in [element.label ?? ""] },
            onContainer: { _, children -> [String] in Array(children.joined()) }
        )
        var retainedPaths: [String: TreePath] = [:]
        let compacted = hierarchy.compactingElements(
            context: TreePath.root,
            into: &retainedPaths,
            onElement: { element, traversalIndex, path, retainedPaths in
                guard element.label != "Drop" else { return nil }
                retainedPaths[element.label ?? ""] = path
                return .element(element, traversalIndex: traversalIndex)
            },
            onContainer: { _, path, _ in path },
            childContext: { path, _, newIndex in path.appending(newIndex) }
        )
        let compactedLabels = compacted?.compactMapSubtrees { hierarchy, _ -> String? in
            guard case .element(let element, _) = hierarchy else { return nil }
            return element.label
        }

        #expect(foldedLabels == ["First", "Drop", "Nested"])
        #expect(compactedLabels == ["First", "Nested"])
        #expect(retainedPaths == [
            "First": TreePath([0]),
            "Nested": TreePath([1, 0]),
        ])
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
