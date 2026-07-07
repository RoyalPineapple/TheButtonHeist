import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import XCTest
@testable import TheScore

final class AccessibilityHierarchyRemovalTests: XCTestCase {

    func testRemovingElementProducesFilteredHierarchyIdsAndPathMap() {
        let removed = makeTestAccessibilityElement(element(label: "Old"))
        let keptInContainer = makeTestAccessibilityElement(element(label: "Kept"))
        let keptNested = makeTestAccessibilityElement(element(label: "Nested"))
        let keptRoot = makeTestAccessibilityElement(element(label: "Root"))
        let list = makeTestAccessibilityContainer(type: .list)
        let group = makeTestAccessibilityContainer(type: .semanticGroup(label: "Group", value: nil, identifier: nil))
        let tree: [AccessibilityHierarchy] = [
            .element(removed, traversalIndex: 0),
            .container(list, children: [
                .element(keptInContainer, traversalIndex: 1),
                .container(group, children: [
                    .element(keptNested, traversalIndex: 2),
                ]),
            ]),
            .element(keptRoot, traversalIndex: 3),
        ]
        let idsByPath = [
            TreePath([0]): "old",
            TreePath([1, 0]): "kept",
            TreePath([1, 1, 0]): "nested",
            TreePath([2]): "root",
        ]

        let removal = tree.removingElements(
            withIds: Set(["old"]),
            idsByPath: idsByPath
        )

        XCTAssertNil(removal.pathMap[TreePath([0])])
        XCTAssertEqual(removal.pathMap[TreePath([1])], TreePath([0]))
        XCTAssertEqual(removal.pathMap[TreePath([1, 0])], TreePath([0, 0]))
        XCTAssertEqual(removal.pathMap[TreePath([1, 1])], TreePath([0, 1]))
        XCTAssertEqual(removal.pathMap[TreePath([1, 1, 0])], TreePath([0, 1, 0]))
        XCTAssertEqual(removal.pathMap[TreePath([2])], TreePath([1]))

        XCTAssertEqual(removal.idsByPath, [
            TreePath([0, 0]): "kept",
            TreePath([0, 1, 0]): "nested",
            TreePath([1]): "root",
        ])
        XCTAssertEqual(removal.hierarchy.node(at: TreePath([0, 0])), .element(keptInContainer, traversalIndex: 1))
        XCTAssertEqual(removal.hierarchy.node(at: TreePath([0, 1, 0])), .element(keptNested, traversalIndex: 2))
        XCTAssertEqual(removal.hierarchy.node(at: TreePath([1])), .element(keptRoot, traversalIndex: 3))
    }

    func testElementWithoutIdIsRetainedAndMapped() {
        let unknown = makeTestAccessibilityElement(element(label: "Unknown"))
        let removed = makeTestAccessibilityElement(element(label: "Old"))
        let tree: [AccessibilityHierarchy] = [
            .element(unknown, traversalIndex: 0),
            .element(removed, traversalIndex: 1),
        ]

        let removal = tree.removingElements(
            withIds: Set(["old"]),
            idsByPath: [TreePath([1]): "old"]
        )

        XCTAssertEqual(removal.pathMap[TreePath([0])], TreePath([0]))
        XCTAssertNil(removal.pathMap[TreePath([1])])
        XCTAssertTrue(removal.idsByPath.isEmpty)
        XCTAssertEqual(removal.hierarchy, [.element(unknown, traversalIndex: 0)])
    }

    private func element(label: String) -> HeistElement {
        let frameX = 0.0
        let frameY = 0.0
        let frameWidth = 100.0
        let frameHeight = 44.0
        let activationPoint = defaultActivationPoint(
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        return HeistElement(
            description: "Button",
            label: label,
            value: nil,
            identifier: nil,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPoint.x,
            activationPointY: activationPoint.y,
            actions: [.activate]
        )
    }
}
