#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class AccessibilityHierarchyFilterTests: XCTestCase {

    // MARK: - Fixtures

    private func el(
        label: String,
        traits: UIAccessibilityTraits = .none,
        index: Int = 0
    ) -> AccessibilityHierarchy {
        .element(
            AccessibilityElement(
                description: label,
                label: label,
                value: nil,
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

    // MARK: - Element Filtering

    func testFilterKeepsMatchingElement() {
        let node = el(label: "Save", index: 0)
        let result = node.filtered { node in
            if case let .element(e, _) = node { return e.label == "Save" }
            return false
        }
        XCTAssertNotNil(result)
    }

    func testFilterRemovesNonMatchingElement() {
        let node = el(label: "Cancel", index: 0)
        let result = node.filtered { node in
            if case let .element(e, _) = node { return e.label == "Save" }
            return false
        }
        XCTAssertNil(result)
    }

    // MARK: - Container Filtering

    func testContainerKeptWhenChildMatches() {
        let tree = group(label: "Toolbar", children: [
            el(label: "Save", index: 0),
            el(label: "Cancel", index: 1),
        ])

        let result = tree.filtered { node in
            if case let .element(e, _) = node { return e.label == "Save" }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 1)
        if case let .element(e, _) = children[0] {
            XCTAssertEqual(e.label, "Save")
        } else {
            XCTFail("Expected element")
        }
    }

    func testContainerRemovedWhenNoChildMatches() {
        let tree = group(label: "Toolbar", children: [
            el(label: "Cancel", index: 0),
            el(label: "Delete", index: 1),
        ])

        let result = tree.filtered { node in
            if case let .element(e, _) = node { return e.label == "Save" }
            return false
        }
        XCTAssertNil(result)
    }

    func testEmptyContainerKeptWhenPredicateMatchesContainer() {
        let tree = scrollable(children: [
            el(label: "Item", index: 0),
        ])

        let result = tree.filtered { node in
            if case let .container(c, _) = node {
                if case .scrollable = c.type { return true }
            }
            return false
        }

        guard case let .container(c, children) = result else {
            return XCTFail("Expected container")
        }
        if case .scrollable = c.type {} else {
            XCTFail("Expected scrollable container")
        }
        // Child didn't match predicate but container did — children still filtered
        XCTAssertEqual(children.count, 0)
    }

    // MARK: - Nested Filtering

    func testDeepNestedElementSurvives() {
        let tree = group(label: "Root", children: [
            group(label: "Section A", children: [
                el(label: "Nope", index: 0),
            ]),
            group(label: "Section B", children: [
                group(label: "Subsection", children: [
                    el(label: "Target", index: 1),
                ]),
            ]),
        ])

        let result = tree.filtered { node in
            if case let .element(e, _) = node { return e.label == "Target" }
            return false
        }

        guard case let .container(_, rootChildren) = result else {
            return XCTFail("Expected root container")
        }
        // Section A pruned (no matches), Section B kept
        XCTAssertEqual(rootChildren.count, 1)

        guard case let .container(_, sectionBChildren) = rootChildren[0] else {
            return XCTFail("Expected Section B container")
        }
        XCTAssertEqual(sectionBChildren.count, 1)

        guard case let .container(_, subChildren) = sectionBChildren[0] else {
            return XCTFail("Expected Subsection container")
        }
        XCTAssertEqual(subChildren.count, 1)

        if case let .element(e, _) = subChildren[0] {
            XCTAssertEqual(e.label, "Target")
        } else {
            XCTFail("Expected Target element")
        }
    }

    // MARK: - Trait Filtering

    func testFilterByTrait() {
        let tree = group(children: [
            el(label: "Title", traits: .header, index: 0),
            el(label: "Body", index: 1),
            el(label: "Subtitle", traits: .header, index: 2),
        ])

        let result = tree.filtered { node in
            if case let .element(e, _) = node {
                return e.traits.contains(.header)
            }
            return false
        }

        guard case let .container(_, children) = result else {
            return XCTFail("Expected container")
        }
        XCTAssertEqual(children.count, 2)
    }

    // MARK: - Array Extension

    func testFilteredHierarchyOnArray() {
        let roots: [AccessibilityHierarchy] = [
            el(label: "A", index: 0),
            el(label: "B", index: 1),
            el(label: "C", index: 2),
        ]

        let result = roots.filteredHierarchy { node in
            if case let .element(e, _) = node { return e.label != "B" }
            return false
        }
        XCTAssertEqual(result.count, 2)
    }

    func testFilteredHierarchyPrunesEmptyContainers() {
        let roots: [AccessibilityHierarchy] = [
            group(label: "Has Match", children: [
                el(label: "Keep", index: 0),
            ]),
            group(label: "No Match", children: [
                el(label: "Drop", index: 1),
            ]),
        ]

        let result = roots.filteredHierarchy { node in
            if case let .element(e, _) = node { return e.label == "Keep" }
            return false
        }
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Edge Cases

    func testFilterOnEmptyArray() {
        let roots: [AccessibilityHierarchy] = []
        let result = roots.filteredHierarchy { _ in true }
        XCTAssertTrue(result.isEmpty)
    }

    func testAlwaysTruePredicatePreservesTree() {
        let tree = group(label: "Root", children: [
            el(label: "A", index: 0),
            group(label: "Inner", children: [
                el(label: "B", index: 1),
            ]),
        ])

        let result = tree.filtered { _ in true }
        XCTAssertEqual(result, tree)
    }

    func testAlwaysFalsePredicateReturnsNil() {
        let tree = group(label: "Root", children: [
            el(label: "A", index: 0),
        ])

        let result = tree.filtered { _ in false }
        XCTAssertNil(result)
    }
}
#endif
