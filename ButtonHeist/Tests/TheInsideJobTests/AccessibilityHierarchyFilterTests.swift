#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class AccessibilityHierarchyFilterTests: XCTestCase {

    // MARK: - Fixtures

    private func element(
        label: String,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        index: Int = 0
    ) -> AccessibilityHierarchy {
        .element(
            AccessibilityElement(
                description: label,
                label: label,
                value: value,
                traits: traits,
                identifier: nil,
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
            ),
            traversalIndex: index
        )
    }

    private func group(
        label: String? = nil,
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil, identifier: nil),
                frame: .zero
            ),
            children: children
        )
    }

    private func scrollable(
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .scrollable(contentSize: CGSize(width: 320, height: 1000)),
                frame: .zero
            ),
            children: children
        )
    }

    private func tabBar(
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .tabBar, frame: .zero),
            children: children
        )
    }

    /// Extracts the label from an element node, nil for containers.
    private func label(of node: AccessibilityHierarchy) -> String? {
        if case let .element(e, _) = node { return e.label }
        return nil
    }

    // MARK: - Filter: Element

    func testFilterKeepsMatchingElement() {
        let node = element(label: "Save")
        let result = node.filtered { n in
            if case let .element(e, _) = n { return e.label == "Save" }
            return false
        }
        XCTAssertNotNil(result)
    }

    func testFilterRemovesNonMatchingElement() {
        let node = element(label: "Cancel")
        let result = node.filtered { n in
            if case let .element(e, _) = n { return e.label == "Save" }
            return false
        }
        XCTAssertNil(result)
    }

    func testFilterPreservesTraversalIndex() {
        let node = element(label: "X", index: 42)
        let result = node.filtered { _ in true }
        if case let .element(_, idx) = result {
            XCTAssertEqual(idx, 42)
        } else {
            XCTFail("Expected element")
        }
    }

    // MARK: - Filter: Container

    func testContainerKeptWhenChildMatches() {
        let tree = group(label: "Toolbar", children: [
            element(label: "Save", index: 0),
            element(label: "Cancel", index: 1),
        ])

        let result = tree.filtered { n in
            if case let .element(e, _) = n { return e.label == "Save" }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(label(of: children[0]), "Save")
    }

    func testContainerRemovedWhenNoChildMatches() {
        let tree = group(label: "Toolbar", children: [
            element(label: "Cancel", index: 0),
            element(label: "Delete", index: 1),
        ])

        let result = tree.filtered { n in
            if case let .element(e, _) = n { return e.label == "Save" }
            return false
        }
        XCTAssertNil(result)
    }

    func testEmptyContainerKeptWhenPredicateMatchesContainer() {
        let tree = scrollable(children: [
            element(label: "Item"),
        ])

        let result = tree.filtered { n in
            if case let .container(c, _) = n {
                if case .scrollable = c.type { return true }
            }
            return false
        }

        guard case let .container(c, children) = result else {
            return XCTFail("Expected container")
        }
        if case .scrollable = c.type {} else {
            XCTFail("Expected scrollable container type")
        }
        XCTAssertEqual(children.count, 0)
    }

    func testContainerPreservesMetadata() {
        let tree = group(label: "Settings", children: [
            element(label: "Volume", index: 0),
        ])

        let result = tree.filtered { _ in true }
        guard case let .container(c, _) = result else {
            return XCTFail("Expected container")
        }
        if case let .semanticGroup(label, _, _) = c.type {
            XCTAssertEqual(label, "Settings")
        } else {
            XCTFail("Expected semanticGroup")
        }
    }

    // MARK: - Filter: Nested

    func testDeepNestedElementSurvives() {
        let tree = group(label: "Root", children: [
            group(label: "Section A", children: [
                element(label: "Nope", index: 0),
            ]),
            group(label: "Section B", children: [
                group(label: "Subsection", children: [
                    element(label: "Target", index: 1),
                ]),
            ]),
        ])

        let result = tree.filtered { n in
            if case let .element(e, _) = n { return e.label == "Target" }
            return false
        }

        guard case let .container(_, rootChildren) = result else {
            return XCTFail("Expected root container")
        }
        XCTAssertEqual(rootChildren.count, 1, "Section A should be pruned")

        guard case let .container(_, sectionBChildren) = rootChildren[0] else {
            return XCTFail("Expected Section B")
        }
        guard case let .container(_, subChildren) = sectionBChildren[0] else {
            return XCTFail("Expected Subsection")
        }
        XCTAssertEqual(label(of: subChildren[0]), "Target")
    }

    func testMultipleMatchesAcrossBranches() {
        let tree = group(children: [
            group(children: [element(label: "A", traits: .button, index: 0)]),
            group(children: [element(label: "B", index: 1)]),
            group(children: [element(label: "C", traits: .button, index: 2)]),
        ])

        let result = tree.filtered { n in
            if case let .element(e, _) = n { return e.traits.contains(.button) }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 2, "Middle branch (no buttons) should be pruned")
    }

    // MARK: - Filter: Trait

    func testFilterByTrait() {
        let tree = group(children: [
            element(label: "Title", traits: .header, index: 0),
            element(label: "Body", index: 1),
            element(label: "Subtitle", traits: .header, index: 2),
        ])

        let result = tree.filtered { n in
            if case let .element(e, _) = n { return e.traits.contains(.header) }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 2)
    }

    func testFilterForContainerType() {
        let tree = group(children: [
            scrollable(children: [element(label: "Row 1", index: 0)]),
            tabBar(children: [element(label: "Home", index: 1)]),
            group(children: [element(label: "Other", index: 2)]),
        ])

        let result = tree.filtered { n in
            if case let .container(c, _) = n {
                if case .scrollable = c.type { return true }
            }
            if case .element = n { return true }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected root container")
        }
        // scrollable kept (matches + has matching children), tabBar's child is an element
        // so tabBar kept via child, group also kept via child — all three survive
        // But the predicate only matches scrollable containers and all elements
        XCTAssertEqual(children.count, 3)
    }

    // MARK: - Filter: Array

    func testFilteredHierarchyOnArray() {
        let roots: [AccessibilityHierarchy] = [
            element(label: "A", index: 0),
            element(label: "B", index: 1),
            element(label: "C", index: 2),
        ]

        let result = roots.filteredHierarchy { n in
            if case let .element(e, _) = n { return e.label != "B" }
            return false
        }
        XCTAssertEqual(result.count, 2)
    }

    func testFilteredHierarchyPrunesEmptyContainers() {
        let roots: [AccessibilityHierarchy] = [
            group(label: "Has Match", children: [element(label: "Keep")]),
            group(label: "No Match", children: [element(label: "Drop")]),
        ]

        let result = roots.filteredHierarchy { n in
            if case let .element(e, _) = n { return e.label == "Keep" }
            return false
        }
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Filter: Edge Cases

    func testFilterOnEmptyArray() {
        let roots: [AccessibilityHierarchy] = []
        let result = roots.filteredHierarchy { _ in true }
        XCTAssertTrue(result.isEmpty)
    }

    func testAlwaysTruePreservesTree() {
        let tree = group(label: "Root", children: [
            element(label: "A", index: 0),
            group(label: "Inner", children: [
                element(label: "B", index: 1),
            ]),
        ])
        XCTAssertEqual(tree.filtered { _ in true }, tree)
    }

    func testAlwaysFalseReturnsNil() {
        let tree = group(children: [element(label: "A")])
        XCTAssertNil(tree.filtered { _ in false })
    }

    func testFilterEmptyContainer() {
        let tree = group(label: "Empty", children: [])
        // No children, container doesn't match → nil
        XCTAssertNil(tree.filtered { _ in false })
        // Container matches predicate → kept empty
        let kept = tree.filtered { _ in true }
        XCTAssertNotNil(kept)
        if case let .container(_, children) = kept {
            XCTAssertTrue(children.isEmpty)
        }
    }

    // MARK: - Map: Element

    func testMapTransformsElementLabel() {
        let node = element(label: "hello", index: 5)
        let result = node.mapped { n in
            guard case let .element(e, idx) = n else { return n }
            return .element(
                AccessibilityElement(
                    description: e.description.uppercased(),
                    label: e.label?.uppercased(),
                    value: e.value,
                    traits: e.traits,
                    identifier: e.identifier,
                    hint: e.hint,
                    userInputLabels: e.userInputLabels,
                    shape: e.shape,
                    activationPoint: e.activationPoint,
                    usesDefaultActivationPoint: e.usesDefaultActivationPoint,
                    customActions: e.customActions,
                    customContent: e.customContent,
                    customRotors: e.customRotors,
                    accessibilityLanguage: e.accessibilityLanguage,
                    respondsToUserInteraction: e.respondsToUserInteraction
                ),
                traversalIndex: idx
            )
        }
        XCTAssertEqual(label(of: result), "HELLO")
        if case let .element(_, idx) = result {
            XCTAssertEqual(idx, 5, "Traversal index preserved")
        }
    }

    func testMapIdentityPreservesTree() {
        let tree = group(children: [
            element(label: "A", index: 0),
            group(children: [element(label: "B", index: 1)]),
        ])
        XCTAssertEqual(tree.mapped { $0 }, tree)
    }

    // MARK: - Map: Container

    func testMapTransformsContainerChildren() {
        let tree = group(children: [
            element(label: "A", index: 0),
            element(label: "B", index: 1),
        ])

        let result = tree.mapped { n in
            guard case let .element(e, idx) = n else { return n }
            return .element(
                AccessibilityElement(
                    description: e.description,
                    label: (e.label ?? "") + "!",
                    value: e.value,
                    traits: e.traits,
                    identifier: e.identifier,
                    hint: e.hint,
                    userInputLabels: e.userInputLabels,
                    shape: e.shape,
                    activationPoint: e.activationPoint,
                    usesDefaultActivationPoint: e.usesDefaultActivationPoint,
                    customActions: e.customActions,
                    customContent: e.customContent,
                    customRotors: e.customRotors,
                    accessibilityLanguage: e.accessibilityLanguage,
                    respondsToUserInteraction: e.respondsToUserInteraction
                ),
                traversalIndex: idx
            )
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(label(of: children[0]), "A!")
        XCTAssertEqual(label(of: children[1]), "B!")
    }

    func testMapIsBottomUp() {
        // Verify children are transformed before their parent container.
        // We track visit order by appending to an array.
        var visitOrder: [String] = []

        let tree = group(label: "Root", children: [
            element(label: "Child", index: 0),
        ])

        _ = tree.mapped { n in
            switch n {
            case let .element(e, _):
                visitOrder.append(e.label ?? "?")
            case let .container(c, _):
                if case let .semanticGroup(label, _, _) = c.type {
                    visitOrder.append(label ?? "?")
                }
            }
            return n
        }

        XCTAssertEqual(visitOrder, ["Child", "Root"], "Children visited before parent")
    }

    func testMapDeepNesting() {
        let tree = group(children: [
            group(children: [
                group(children: [
                    element(label: "deep", index: 0),
                ]),
            ]),
        ])

        let result = tree.mapped { n in
            guard case let .element(e, idx) = n else { return n }
            return .element(
                AccessibilityElement(
                    description: e.description,
                    label: "found",
                    value: e.value,
                    traits: e.traits,
                    identifier: e.identifier,
                    hint: e.hint,
                    userInputLabels: e.userInputLabels,
                    shape: e.shape,
                    activationPoint: e.activationPoint,
                    usesDefaultActivationPoint: e.usesDefaultActivationPoint,
                    customActions: e.customActions,
                    customContent: e.customContent,
                    customRotors: e.customRotors,
                    accessibilityLanguage: e.accessibilityLanguage,
                    respondsToUserInteraction: e.respondsToUserInteraction
                ),
                traversalIndex: idx
            )
        }

        // Dig down three levels
        guard case let .container(_, l1) = result,
              case let .container(_, l2) = l1[0],
              case let .container(_, l3) = l2[0] else {
            return XCTFail("Expected nested containers")
        }
        XCTAssertEqual(label(of: l3[0]), "found")
    }

    func testMapCanReplaceContainerType() {
        let tree = group(label: "Nav", children: [
            element(label: "Home", index: 0),
        ])

        let result = tree.mapped { n in
            guard case let .container(_, children) = n else { return n }
            return .container(
                AccessibilityContainer(type: .tabBar, frame: .zero),
                children: children
            )
        }

        guard case let .container(c, children) = result else {
            return XCTFail("Expected container")
        }
        if case .tabBar = c.type {} else {
            XCTFail("Expected tabBar type")
        }
        XCTAssertEqual(children.count, 1)
    }

    func testMapCanReindexTraversalOrder() {
        let roots: [AccessibilityHierarchy] = [
            element(label: "A", index: 0),
            element(label: "B", index: 1),
            element(label: "C", index: 2),
        ]

        var counter = 10
        let result = roots.mappedHierarchy { n in
            guard case let .element(e, _) = n else { return n }
            let newIndex = counter
            counter += 10
            return .element(e, traversalIndex: newIndex)
        }

        if case let .element(_, idx) = result[0] { XCTAssertEqual(idx, 10) }
        if case let .element(_, idx) = result[1] { XCTAssertEqual(idx, 20) }
        if case let .element(_, idx) = result[2] { XCTAssertEqual(idx, 30) }
    }

    // MARK: - Map: Array

    func testMappedHierarchyOnArray() {
        let roots: [AccessibilityHierarchy] = [
            element(label: "a", index: 0),
            element(label: "b", index: 1),
        ]

        let result = roots.mappedHierarchy { n in
            guard case let .element(e, idx) = n else { return n }
            return .element(
                AccessibilityElement(
                    description: e.description,
                    label: e.label?.uppercased(),
                    value: e.value,
                    traits: e.traits,
                    identifier: e.identifier,
                    hint: e.hint,
                    userInputLabels: e.userInputLabels,
                    shape: e.shape,
                    activationPoint: e.activationPoint,
                    usesDefaultActivationPoint: e.usesDefaultActivationPoint,
                    customActions: e.customActions,
                    customContent: e.customContent,
                    customRotors: e.customRotors,
                    accessibilityLanguage: e.accessibilityLanguage,
                    respondsToUserInteraction: e.respondsToUserInteraction
                ),
                traversalIndex: idx
            )
        }

        XCTAssertEqual(label(of: result[0]), "A")
        XCTAssertEqual(label(of: result[1]), "B")
    }

    func testMappedHierarchyEmptyArray() {
        let roots: [AccessibilityHierarchy] = []
        let result = roots.mappedHierarchy { $0 }
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Map: Edge Cases

    func testMapEmptyContainer() {
        let tree = group(label: "Empty", children: [])
        let result = tree.mapped { $0 }
        XCTAssertEqual(result, tree)
    }

    func testMapCanCollapseContainerToElement() {
        let tree = group(children: [element(label: "Only", index: 7)])

        let result = tree.mapped { n in
            if case let .container(_, children) = n, children.count == 1 {
                return children[0]
            }
            return n
        }

        // Container collapsed to its single child
        XCTAssertEqual(label(of: result), "Only")
    }

    // MARK: - Elements & Containers Extraction

    func testElementsCountsLeaves() {
        let tree = group(children: [
            element(label: "A", index: 0),
            group(children: [
                element(label: "B", index: 1),
                element(label: "C", index: 2),
            ]),
        ])

        XCTAssertEqual(tree.elements.count, 3)
    }

    func testContainersCountsAllContainers() {
        let tree = group(children: [
            group(children: [element(label: "A")]),
            group(children: []),
        ])

        XCTAssertEqual(tree.containers.count, 3, "Root + 2 inner containers")
    }

    func testElementsCollectsLabelsInTraversalOrder() {
        let tree = group(children: [
            element(label: "A", index: 0),
            element(label: "B", index: 1),
            group(children: [
                element(label: "C", index: 2),
            ]),
        ])

        let labels = tree.elements.compactMap(\.element.label)
        XCTAssertEqual(labels, ["A", "B", "C"])
    }

    func testFoldedComputesMaxTraversalIndex() {
        let tree = group(children: [
            element(label: "A", index: 3),
            group(children: [
                element(label: "B", index: 7),
                element(label: "C", index: 1),
            ]),
        ])

        let maxIndex = tree.folded(
            onElement: { _, traversalIndex in traversalIndex },
            onContainer: { _, childMaxes in childMaxes.max() ?? Int.min }
        )
        XCTAssertEqual(maxIndex, 7)
    }

    func testFoldedComputesTreeDepth() {
        let tree = group(children: [
            element(label: "shallow", index: 0),
            group(children: [
                group(children: [
                    element(label: "deep", index: 1),
                ]),
            ]),
        ])

        let depth: Int = tree.folded(
            onElement: { _, _ in 1 },
            onContainer: { _, childDepths in 1 + (childDepths.max() ?? 0) }
        )
        XCTAssertEqual(depth, 4, "Root > group > group > element")
    }

    func testFilteredElementsChecksAnyButton() {
        let tree = group(children: [
            element(label: "Title", traits: .header),
            element(label: "OK", traits: .button),
        ])

        let hasButton = tree.filtered { node in
            guard case .element(let element, _) = node else { return false }
            return element.traits.contains(.button)
        } != nil
        XCTAssertTrue(hasButton)
    }

    func testElementsChecksAllInteractive() {
        let tree = group(children: [
            element(label: "A"),
            element(label: "B"),
        ])

        let allInteractive = tree.elements.allSatisfy(\.element.respondsToUserInteraction)
        XCTAssertTrue(allInteractive)
    }

    func testElementsOnSingleElement() {
        let node = element(label: "Solo", index: 0)
        XCTAssertEqual(node.elements.count, 1)
    }

    func testElementsOnArray() {
        let roots: [AccessibilityHierarchy] = [
            element(label: "A", index: 0),
            group(children: [
                element(label: "B", index: 1),
            ]),
        ]

        XCTAssertEqual(roots.elements.count, 2)
    }

    func testElementsOnEmptyArray() {
        let roots: [AccessibilityHierarchy] = []
        XCTAssertEqual(roots.elements.count, 0)
    }

    func testElementsVisitsAllRoots() {
        let roots: [AccessibilityHierarchy] = [
            group(children: [element(label: "A")]),
            group(children: [element(label: "B")]),
            group(children: [element(label: "C")]),
        ]

        let labels = roots.elements.compactMap(\.element.label)
        XCTAssertEqual(labels, ["A", "B", "C"])
    }

    func testContainersOnEmptyContainer() {
        let tree = group(children: [])
        XCTAssertEqual(tree.containers.count, 1, "Just the container itself")
    }

    // MARK: - Composition: Filter + Map

    func testFilterThenMap() {
        let tree = group(children: [
            element(label: "Keep", traits: .button, index: 0),
            element(label: "Drop", index: 1),
            element(label: "Also Keep", traits: .button, index: 2),
        ])

        let result = tree
            .filtered { n in
                if case let .element(e, _) = n { return e.traits.contains(.button) }
                return true
            }?
            .mapped { n in
                guard case let .element(e, idx) = n else { return n }
                return .element(
                    AccessibilityElement(
                        description: e.description,
                        label: e.label?.uppercased(),
                        value: e.value,
                        traits: e.traits,
                        identifier: e.identifier,
                        hint: e.hint,
                        userInputLabels: e.userInputLabels,
                        shape: e.shape,
                        activationPoint: e.activationPoint,
                        usesDefaultActivationPoint: e.usesDefaultActivationPoint,
                        customActions: e.customActions,
                        customContent: e.customContent,
                        customRotors: e.customRotors,
                        accessibilityLanguage: e.accessibilityLanguage,
                        respondsToUserInteraction: e.respondsToUserInteraction
                    ),
                    traversalIndex: idx
                )
            }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(label(of: children[0]), "KEEP")
        XCTAssertEqual(label(of: children[1]), "ALSO KEEP")
    }

    // MARK: - Composition: Filter + Elements

    func testFilterThenElements() {
        let tree = group(children: [
            element(label: "Header", traits: .header, index: 0),
            element(label: "Body", index: 1),
            element(label: "Footer", traits: .header, index: 2),
        ])

        let headerLabels = tree
            .filtered { node in
                if case let .element(element, _) = node { return element.traits.contains(.header) }
                return false
            }?
            .elements
            .compactMap(\.element.label)

        XCTAssertEqual(headerLabels, ["Header", "Footer"])
    }

    // MARK: - Composition: Map + Elements

    func testMapThenElements() {
        let tree = group(children: [
            element(label: "a", index: 0),
            element(label: "b", index: 1),
        ])

        let uppercased = tree
            .mapped { node in
                guard case let .element(element, index) = node else { return node }
                return .element(
                    AccessibilityElement(
                        description: element.description,
                        label: element.label?.uppercased(),
                        value: element.value,
                        traits: element.traits,
                        identifier: element.identifier,
                        hint: element.hint,
                        userInputLabels: element.userInputLabels,
                        shape: element.shape,
                        activationPoint: element.activationPoint,
                        usesDefaultActivationPoint: element.usesDefaultActivationPoint,
                        customActions: element.customActions,
                        customContent: element.customContent,
                        customRotors: element.customRotors,
                        accessibilityLanguage: element.accessibilityLanguage,
                        respondsToUserInteraction: element.respondsToUserInteraction
                    ),
                    traversalIndex: index
                )
            }
            .elements
            .compactMap(\.element.label)
            .joined(separator: ",")

        XCTAssertEqual(uppercased, "A,B")
    }

    // MARK: - Composition: Filter + Map + Elements

    func testFilterMapElements() {
        let tree = group(children: [
            element(label: "Settings", traits: .button, index: 0),
            element(label: "Info", index: 1),
            element(label: "Profile", traits: .button, index: 2),
            element(label: "Help", index: 3),
        ])

        let count = tree
            .filtered { node in
                if case let .element(element, _) = node { return element.traits.contains(.button) }
                return false
            }?
            .mapped { node in
                guard case let .element(element, index) = node else { return node }
                return .element(
                    AccessibilityElement(
                        description: element.description,
                        label: "[" + (element.label ?? "") + "]",
                        value: element.value,
                        traits: element.traits,
                        identifier: element.identifier,
                        hint: element.hint,
                        userInputLabels: element.userInputLabels,
                        shape: element.shape,
                        activationPoint: element.activationPoint,
                        usesDefaultActivationPoint: element.usesDefaultActivationPoint,
                        customActions: element.customActions,
                        customContent: element.customContent,
                        customRotors: element.customRotors,
                        accessibilityLanguage: element.accessibilityLanguage,
                        respondsToUserInteraction: element.respondsToUserInteraction
                    ),
                    traversalIndex: index
                )
            }
            .elements
            .count

        XCTAssertEqual(count, 2)
    }
}
#endif
