#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class ContainerFingerprintTests: XCTestCase {

    // MARK: - Fixtures

    private func makeElement(
        label: String,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        identifier: String? = nil,
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        .make(label: label, value: value, identifier: identifier, traits: traits, frame: frame)
    }

    private func element(
        label: String,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        identifier: String? = nil,
        frame: CGRect = .zero,
        index: Int = 0
    ) -> AccessibilityHierarchy {
        .element(
            makeElement(label: label, value: value, traits: traits, identifier: identifier, frame: frame),
            traversalIndex: index
        )
    }

    private func scrollable(
        contentSize: CGSize = CGSize(width: 320, height: 1000),
        frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 500),
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .scrollable(contentSize: AccessibilitySize(contentSize)),
                frame: frame
            ),
            children: children
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

    private func tabBar(
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .tabBar, frame: .zero),
            children: children
        )
    }

    // MARK: - containerFingerprints: Stability

    func testIdenticalTreesProduceSameFingerprints() {
        let tree1: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2", index: 1),
            ]),
        ]
        let tree2: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2", index: 1),
            ]),
        ]

        let fingerprints1 = tree1.containerFingerprints
        let fingerprints2 = tree2.containerFingerprints

        XCTAssertEqual(fingerprints1.count, 1)
        XCTAssertEqual(fingerprints2.count, 1)

        let fp1 = fingerprints1.values.first
        let fp2 = fingerprints2.values.first
        XCTAssertNotNil(fp1)
        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprintChangesWhenChildLabelChanges() {
        let before: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2", index: 1),
            ]),
        ]
        let after: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2 Updated", index: 1),
            ]),
        ]

        let fpBefore = before.containerFingerprints.values.first
        let fpAfter = after.containerFingerprints.values.first
        XCTAssertNotNil(fpBefore)
        XCTAssertNotNil(fpAfter)
        XCTAssertNotEqual(fpBefore, fpAfter)
    }

    func testFingerprintChangesWhenChildAdded() {
        let before: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
            ]),
        ]
        let after: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2", index: 1),
            ]),
        ]

        let fpBefore = before.containerFingerprints.values.first
        let fpAfter = after.containerFingerprints.values.first
        XCTAssertNotEqual(fpBefore, fpAfter)
    }

    func testFingerprintChangesWhenChildRemoved() {
        let before: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
                element(label: "Row 2", index: 1),
            ]),
        ]
        let after: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row 1", index: 0),
            ]),
        ]

        let fpBefore = before.containerFingerprints.values.first
        let fpAfter = after.containerFingerprints.values.first
        XCTAssertNotEqual(fpBefore, fpAfter)
    }

    func testFingerprintChangesWhenChildValueChanges() {
        let before: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Slider", value: "50%", index: 0),
            ]),
        ]
        let after: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Slider", value: "75%", index: 0),
            ]),
        ]

        let fpBefore = before.containerFingerprints.values.first
        let fpAfter = after.containerFingerprints.values.first
        XCTAssertNotEqual(fpBefore, fpAfter)
    }

    func testFingerprintStableWhenTraversalIndexChanges() {
        // Traversal index should not affect content fingerprint —
        // only content properties matter.
        let tree1: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row", index: 0),
            ]),
        ]
        let tree2: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "Row", index: 99),
            ]),
        ]

        let fp1 = tree1.containerFingerprints.values.first
        let fp2 = tree2.containerFingerprints.values.first
        XCTAssertEqual(fp1, fp2)
    }

    // MARK: - containerFingerprints: Per-Container Granularity

    func testMultipleContainersGetIndependentFingerprints() {
        let container1 = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 250)
        )
        let container2 = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 800)),
            frame: CGRect(x: 0, y: 250, width: 320, height: 250)
        )

        let tree: [AccessibilityHierarchy] = [
            .container(container1, children: [
                element(label: "List A Row", index: 0),
            ]),
            .container(container2, children: [
                element(label: "List B Row", index: 1),
            ]),
        ]

        let fingerprints = tree.containerFingerprints
        XCTAssertEqual(fingerprints.count, 2)

        let fp1 = fingerprints[container1]
        let fp2 = fingerprints[container2]
        XCTAssertNotNil(fp1)
        XCTAssertNotNil(fp2)
        XCTAssertNotEqual(fp1, fp2, "Different content should yield different fingerprints")
    }

    func testNestedContainersAllGetFingerprints() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                scrollable(children: [
                    element(label: "Nested Row", index: 0),
                ]),
            ]),
        ]

        let fingerprints = tree.containerFingerprints
        // Group container + scrollable container = 2
        XCTAssertEqual(fingerprints.count, 2)
    }

    func testOnlyChangedContainerFingerprintChanges() {
        let container1 = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 250)
        )
        let container2 = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 800)),
            frame: CGRect(x: 0, y: 250, width: 320, height: 250)
        )

        let before: [AccessibilityHierarchy] = [
            .container(container1, children: [
                element(label: "Stable Row", index: 0),
            ]),
            .container(container2, children: [
                element(label: "Changing Row", index: 1),
            ]),
        ]

        let after: [AccessibilityHierarchy] = [
            .container(container1, children: [
                element(label: "Stable Row", index: 0),
            ]),
            .container(container2, children: [
                element(label: "Changed Row", index: 1),
            ]),
        ]

        let fpBefore = before.containerFingerprints
        let fpAfter = after.containerFingerprints

        XCTAssertEqual(fpBefore[container1], fpAfter[container1], "Unchanged container should keep its fingerprint")
        XCTAssertNotEqual(fpBefore[container2], fpAfter[container2], "Changed container should have a new fingerprint")
    }

    func testEmptyContainerHasFingerprint() {
        let tree: [AccessibilityHierarchy] = [
            scrollable(children: []),
        ]

        let fingerprints = tree.containerFingerprints
        XCTAssertEqual(fingerprints.count, 1)
        XCTAssertNotNil(fingerprints.values.first)
    }

    func testNonContainerTreeHasNoFingerprints() {
        let tree: [AccessibilityHierarchy] = [
            element(label: "Just an element", index: 0),
        ]

        let fingerprints = tree.containerFingerprints
        XCTAssertTrue(fingerprints.isEmpty)
    }

    func testEmptyHierarchyHasNoFingerprints() {
        let tree: [AccessibilityHierarchy] = []
        let fingerprints = tree.containerFingerprints
        XCTAssertTrue(fingerprints.isEmpty)
    }

    // MARK: - containerFingerprints: Order Sensitivity

    func testFingerprintChangesWhenChildOrderChanges() {
        let tree1: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "A", index: 0),
                element(label: "B", index: 1),
            ]),
        ]
        let tree2: [AccessibilityHierarchy] = [
            scrollable(children: [
                element(label: "B", index: 0),
                element(label: "A", index: 1),
            ]),
        ]

        let fp1 = tree1.containerFingerprints.values.first
        let fp2 = tree2.containerFingerprints.values.first
        XCTAssertNotEqual(fp1, fp2, "Child order should affect the fingerprint (Merkle property)")
    }

    // MARK: - scrollableContainers

    func testScrollableContainersFindsScrollViews() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                scrollable(children: [element(label: "Row", index: 0)]),
                group(children: [element(label: "Other", index: 1)]),
            ]),
        ]

        let containers = tree.scrollableContainers
        XCTAssertEqual(containers.count, 1)
        if case .scrollable = containers.first?.type {} else {
            XCTFail("Expected scrollable container")
        }
    }

    func testScrollableContainersPreservesPreOrder() {
        let outerContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 2000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 500)
        )
        let innerContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 800)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        let tree: [AccessibilityHierarchy] = [
            .container(outerContainer, children: [
                .container(innerContainer, children: [
                    element(label: "Nested", index: 0),
                ]),
            ]),
        ]

        let containers = tree.scrollableContainers
        XCTAssertEqual(containers.count, 2)
        XCTAssertEqual(containers[0], outerContainer, "Outer should come first (pre-order)")
        XCTAssertEqual(containers[1], innerContainer)
    }

    func testScrollableContainersEmptyWhenNoScrollViews() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                element(label: "Static", index: 0),
                tabBar(children: [element(label: "Home", index: 1)]),
            ]),
        ]

        XCTAssertTrue(tree.scrollableContainers.isEmpty)
    }

    // MARK: - ScreenManifest

    func testMarkExploredMovesFromPending() {
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
            frame: .zero
        )

        var manifest = Navigation.ScreenManifest()
        manifest.addPendingContainers([container])
        XCTAssertTrue(manifest.pendingContainers.contains(container))

        manifest.markExplored(container)
        XCTAssertFalse(manifest.pendingContainers.contains(container))
        XCTAssertTrue(manifest.exploredContainers.contains(container))
        XCTAssertTrue(manifest.pendingContainers.isEmpty)
    }

    func testAddPendingSkipsExplored() {
        let container = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
            frame: .zero
        )

        var manifest = Navigation.ScreenManifest()
        manifest.markExplored(container)
        manifest.addPendingContainers([container])

        XCTAssertTrue(manifest.pendingContainers.isEmpty, "Already-explored container should not be re-added to pending")
    }

}
#endif
