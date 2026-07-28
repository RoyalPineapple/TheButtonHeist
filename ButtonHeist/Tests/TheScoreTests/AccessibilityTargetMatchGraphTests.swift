import XCTest
import ThePlans
@testable import TheScore

final class AccessibilityTargetMatchGraphTests: XCTestCase {
    func testContainerResolutionRetainsFactsAndProjectsPaths() throws {
        let checkout = container(
            path: [0],
            facts: ContainerPredicateFacts(
                role: .list,
                identifier: "checkout",
                isModalBoundary: true
            )
        )
        let graph = matchGraph(containers: [
            checkout,
            container(path: [1], facts: ContainerPredicateFacts(role: .landmark, identifier: "account")),
        ])

        let matches = graph.resolve(
            try AccessibilityTarget.container(.identifier("checkout")).resolve(in: .empty)
        )

        XCTAssertEqual(matches.containers, [checkout])
        XCTAssertEqual(matches.containerPaths, [TreePath([0])])
        XCTAssertEqual(matches.paths, [TreePath([0])])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0])])
    }

    func testContainerOrdinalSelectsTheCompleteMatch() throws {
        let first = container(
            path: [0],
            facts: ContainerPredicateFacts(role: .list, identifier: "first", isScrollable: true)
        )
        let second = container(
            path: [1],
            facts: ContainerPredicateFacts(
                role: .semanticGroup(label: "Second", value: "Selected"),
                identifier: "second",
                isScrollable: true,
                actions: [.custom("Advance")]
            )
        )
        let graph = matchGraph(containers: [first, second])

        let matches = graph.resolve(
            try AccessibilityTarget.container(.scrollable(true), ordinal: 1).resolve(in: .empty)
        )

        XCTAssertEqual(matches.containers, [second])
        XCTAssertEqual(matches.containers.first?.facts, second.facts)
        XCTAssertEqual(matches.orderedPaths, [TreePath([1])])
    }

    func testScopedContainerResolutionRetainsNestedFacts() throws {
        let root = container(
            path: [0],
            facts: ContainerPredicateFacts(role: .list, identifier: "root")
        )
        let nested = container(
            path: [0, 0],
            parent: [0],
            facts: ContainerPredicateFacts(
                role: .semanticGroup(label: "Nested", value: "Ready"),
                identifier: "nested"
            )
        )
        let nestedLandmark = container(
            path: [0, 0, 0],
            parent: [0, 0],
            facts: ContainerPredicateFacts(
                role: .landmark,
                identifier: "inside",
                actions: [.custom("Open")]
            )
        )
        let outsideLandmark = container(
            path: [1],
            facts: ContainerPredicateFacts(role: .landmark, identifier: "outside")
        )
        let graph = matchGraph(containers: [root, nested, nestedLandmark, outsideLandmark])

        let matches = graph.resolve(
            try AccessibilityTarget.within(
                container: .identifier("root"),
                target: .container(.landmark)
            ).resolve(in: .empty)
        )

        XCTAssertEqual(matches.containers, [nestedLandmark])
        XCTAssertEqual(matches.containers.first?.facts, nestedLandmark.facts)
        XCTAssertEqual(matches.paths, [TreePath([0, 0, 0])])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0, 0, 0])])
    }

    private func matchGraph(
        containers: [AccessibilityTargetContainerMatch]
    ) -> AccessibilityTargetMatchGraph<HeistElement> {
        AccessibilityTargetMatchGraph(
            AccessibilityTargetMatchInput(elements: [], containers: containers)
        )
    }

    private func container(
        path: [Int],
        parent: [Int]? = nil,
        facts: ContainerPredicateFacts
    ) -> AccessibilityTargetContainerMatch {
        AccessibilityTargetContainerMatch(
            path: TreePath(path),
            parentContainerPath: parent.map(TreePath.init),
            facts: facts
        )
    }
}
