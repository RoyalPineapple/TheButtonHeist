#if canImport(UIKit)
import Testing
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
import TheScore

@MainActor
@Suite("LiveCapture")
struct LiveCaptureTests {

    @Test func `rejects duplicate live HeistIds before indexing`() {
        let first = AccessibilityElement.make(label: "First", traits: .button)
        let second = AccessibilityElement.make(label: "Second", traits: .button)
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): "shared_button",
                TreePath([1]): "shared_button",
            ]
        )

        expectValidationError(
            .duplicateHeistId(
                heistId: "shared_button",
                firstPath: TreePath([0]),
                duplicatePath: TreePath([1])
            ),
            tree: makeTree(snapshot: snapshot)
        )
    }

    @Test func `rejects semantic viewport elements without HeistIds`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)]
        )
        let tree = InterfaceTree(
            elements: [
                "save_button": InterfaceTree.Element(
                    heistId: "save_button",
                    path: path,
                    scrollMembership: nil,
                    element: element
                )
            ],
            viewportCapture: snapshot
        )

        expectValidationError(
            .missingHeistId(path: path),
            tree: tree
        )
    }

    @Test func `rejects viewport elements without HeistIds when absent from semantic tree`() {
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .element(
                    AccessibilityElement.make(label: "Unindexed", traits: .button),
                    traversalIndex: 0
                )
            ]
        )

        expectValidationError(
            .missingHeistId(path: path),
            tree: InterfaceTree(elements: [:], viewportCapture: snapshot)
        )
    }

    @Test func `rejects container metadata for missing paths`() {
        let path = TreePath([4])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [],
            containerNamesByPath: [path: ContainerName(rawValue: "missing")]
        )

        expectValidationError(
            .containerMetadataForMissingPath(path: path),
            tree: makeTree(snapshot: snapshot)
        )
    }

    @Test func `rejects semantic containers that mismatch the viewport capture`() {
        let path = TreePath([0])
        let container = makeTestAccessibilityContainer()
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.container(container, children: [])]
        )
        let tree = InterfaceTree(
            elements: [:],
            containers: [
                path: InterfaceTree.Container(
                    container: container,
                    path: path,
                    containerName: ContainerName(rawValue: "wrong"),
                    contentFrame: nil
                )
            ],
            viewportCapture: snapshot
        )

        expectValidationError(
            .treeContainerMismatch(path: path),
            tree: tree
        )
    }

    @Test func `rejects visible scroll membership outside the capture`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let path = TreePath([0])
        let missingContainerPath = TreePath([9])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [path: "save_button"]
        )
        let tree = InterfaceTree(
            elements: [
                "save_button": InterfaceTree.Element(
                    heistId: "save_button",
                    path: path,
                    scrollMembership: InterfaceTree.ScrollMembership(
                        containerPath: missingContainerPath,
                        index: 0
                    ),
                    element: element
                )
            ],
            viewportCapture: snapshot
        )

        expectValidationError(
            .invalidScrollMembership(path: path, containerPath: missingContainerPath),
            tree: tree
        )
    }

    @Test func `rejects visible scroll membership in an unrelated container`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let elementPath = TreePath([1])
        let containerPath = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .container(
                    makeTestAccessibilityContainer(
                        type: .none,
                        scrollableContentSize: AccessibilitySize(width: 320, height: 1_000)
                    ),
                    children: []
                ),
                .element(element, traversalIndex: 0),
            ],
            heistIdsByPath: [elementPath: "save_button"]
        )

        expectValidationError(
            .invalidScrollMembership(path: elementPath, containerPath: containerPath),
            tree: makeTree(
                snapshot: snapshot,
                scrollMembershipsByHeistId: [
                    "save_button": InterfaceTree.ScrollMembership(
                        containerPath: containerPath,
                        index: 0
                    )
                ]
            )
        )
    }

    @Test func `rejects self-referential container scroll membership`() {
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .container(
                    makeTestAccessibilityContainer(
                        type: .none,
                        scrollableContentSize: AccessibilitySize(width: 320, height: 1_000)
                    ),
                    children: []
                )
            ],
            containerScrollMembershipsByPath: [
                path: InterfaceTree.ScrollMembership(containerPath: path, index: nil)
            ]
        )

        expectValidationError(
            .invalidScrollMembership(path: path, containerPath: path),
            tree: makeTree(snapshot: snapshot)
        )
    }

    @Test func `rejects stray element refs`() {
        let tree = makeSingleElementTree()
        expectValidationError(
            .strayElementRef(heistId: "missing_button"),
            tree: tree,
            dispatchReferences: LiveCapture.DispatchReferences(
                elementRefs: [
                    "missing_button": LiveCapture.ElementRef(
                        object: NSObject(),
                        scrollView: nil
                    )
                ]
            )
        )
    }

    @Test func `rejects first responder id outside viewport entries`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "save_button"],
            firstResponderHeistId: "missing_button"
        )

        expectValidationError(
            .invalidFirstResponderHeistId(heistId: "missing_button"),
            tree: makeTree(snapshot: snapshot)
        )
    }

    @Test func `rejects container refs for missing paths`() {
        let path = TreePath([9])
        expectValidationError(
            .containerRefForMissingPath(path: path),
            tree: makeSingleElementTree(),
            dispatchReferences: LiveCapture.DispatchReferences(
                containerRefsByPath: [path: LiveCapture.ContainerRef(object: NSObject())]
            )
        )
    }

    @Test func `rejects container refs on element paths`() {
        let path = TreePath([0])
        expectValidationError(
            .containerRefForElementPath(path: path),
            tree: makeSingleElementTree(),
            dispatchReferences: LiveCapture.DispatchReferences(
                containerRefsByPath: [path: LiveCapture.ContainerRef(object: NSObject())]
            )
        )
    }

    @Test func `rejects scroll view refs for missing paths`() {
        let path = TreePath([9])
        expectValidationError(
            .scrollableViewForMissingPath(path: path),
            tree: makeSingleElementTree(),
            dispatchReferences: LiveCapture.DispatchReferences(
                scrollableContainerViewsByPath: [
                    path: LiveCapture.ScrollableViewRef(view: UIScrollView())
                ]
            )
        )
    }

    @Test func `rejects scroll view refs on element paths`() {
        let path = TreePath([0])
        expectValidationError(
            .scrollableViewForElementPath(path: path),
            tree: makeSingleElementTree(),
            dispatchReferences: LiveCapture.DispatchReferences(
                scrollableContainerViewsByPath: [
                    path: LiveCapture.ScrollableViewRef(view: UIScrollView())
                ]
            )
        )
    }

    @Test func `rejects scroll view refs on non-scrollable containers`() {
        let path = TreePath([0])
        let container = makeTestAccessibilityContainer()
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.container(container, children: [])]
        )
        expectValidationError(
            .scrollableViewForNonScrollablePath(path: path),
            tree: makeTree(snapshot: snapshot),
            dispatchReferences: LiveCapture.DispatchReferences(
                scrollableContainerViewsByPath: [
                    path: LiveCapture.ScrollableViewRef(view: UIScrollView())
                ]
            )
        )
    }

    @Test func `rejects viewport snapshots with missing semantic elements`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [path: "save_button"]
        )
        expectValidationError(
            .missingTreeElement(heistId: "save_button", path: path),
            tree: InterfaceTree(elements: [:], viewportCapture: snapshot)
        )
    }

    @Test func `rejects mismatched viewport snapshot and semantic element path`() {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let snapshotPath = TreePath([0])
        let treePath = TreePath([1])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [snapshotPath: "save_button"]
        )
        let tree = InterfaceTree(
            elements: [
                "save_button": InterfaceTree.Element(
                    heistId: "save_button",
                    path: treePath,
                    scrollMembership: nil,
                    element: element
                )
            ],
            viewportCapture: snapshot
        )

        expectValidationError(
            .treeElementPathMismatch(
                heistId: "save_button",
                snapshotPath: snapshotPath,
                treePath: treePath
            ),
            tree: tree
        )
    }

    @Test func `rejects mismatched viewport snapshot and semantic element content`() {
        let snapshotElement = AccessibilityElement.make(label: "Save", traits: .button)
        let treeElement = AccessibilityElement.make(label: "Delete", traits: .button)
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(snapshotElement, traversalIndex: 0)],
            heistIdsByPath: [path: "save_button"]
        )
        let tree = InterfaceTree(
            elements: [
                "save_button": InterfaceTree.Element(
                    heistId: "save_button",
                    path: path,
                    scrollMembership: nil,
                    element: treeElement
                )
            ],
            viewportCapture: snapshot
        )

        expectValidationError(
            .treeElementMismatch(heistId: "save_button", path: path),
            tree: tree
        )
    }

    @Test func `accepts identical nonfinite viewport geometry`() throws {
        let element = AccessibilityElement.make(
            label: "Loading",
            traits: .button,
            shape: .frame(AccessibilityRect(x: Double.nan, y: 0, width: 10, height: 10)),
            activationPoint: CGPoint(x: CGFloat.nan, y: 5)
        )
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [path: "loading_button"]
        )

        _ = try LiveCapture.build(
            validating: makeTree(snapshot: snapshot),
            dispatchReferences: .empty
        )
    }

    @Test func `valid builder keeps live lookup behavior`() throws {
        let save = AccessibilityElement.make(label: "Save", traits: .button)
        let cancel = AccessibilityElement.make(label: "Cancel", traits: .button)
        let saveObject = NSObject()
        let saveScrollView = UIScrollView()
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .element(save, traversalIndex: 10),
                .element(cancel, traversalIndex: 0),
            ],
            heistIdsByPath: [
                TreePath([0]): "save_button",
                TreePath([1]): "cancel_button",
            ],
            firstResponderHeistId: "save_button"
        )
        let observation = try InterfaceObservation.build(
            tree: makeTree(snapshot: snapshot),
            dispatchReferences: LiveCapture.DispatchReferences(
                elementRefs: [
                    "save_button": LiveCapture.ElementRef(
                        object: saveObject,
                        scrollView: saveScrollView
                    )
                ]
            )
        )
        let capture = observation.liveCapture

        #expect(capture.heistIds == ["cancel_button", "save_button"])
        #expect(capture.contains(heistId: "save_button"))
        #expect(capture.heistId(forPath: TreePath([0])) == "save_button")
        #expect(capture.heistId(forPath: TreePath([1])) == "cancel_button")
        #expect(capture.element(for: "cancel_button") == cancel)
        #expect(capture.object(for: "save_button") === saveObject)
        #expect(capture.heistId(matching: saveObject) == "save_button")
        #expect(capture.scrollView(for: "save_button") === saveScrollView)
        #expect(capture.orderedElementEntries().map(\.heistId) == ["cancel_button", "save_button"])
        #expect(capture.firstResponderHeistId == "save_button")
    }

    @Test func `duplicate equal elements keep separate live entries by path`() throws {
        let repeated = AccessibilityElement.make(label: "Repeat", traits: .button)
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .element(repeated, traversalIndex: 0),
                .element(repeated, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): "repeat_button_1",
                TreePath([1]): "repeat_button_2",
            ]
        )
        let capture = try InterfaceObservation.build(
            tree: makeTree(snapshot: snapshot)
        ).liveCapture

        #expect(capture.heistId(forPath: TreePath([0])) == "repeat_button_1")
        #expect(capture.heistId(forPath: TreePath([1])) == "repeat_button_2")
        #expect(capture.orderedElementEntries().map(\.heistId) == ["repeat_button_1", "repeat_button_2"])
    }

    private func expectValidationError(
        _ expected: LiveCapture.ValidationError,
        tree: InterfaceTree,
        dispatchReferences: LiveCapture.DispatchReferences = .empty
    ) {
        do {
            _ = try InterfaceObservation.build(
                tree: tree,
                dispatchReferences: dispatchReferences
            )
            Issue.record("Expected live capture validation to fail")
        } catch let error as LiveCapture.ValidationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected LiveCapture.ValidationError, got \(error)")
        }
    }

    private func makeSingleElementTree() -> InterfaceTree {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "save_button"]
        )
        return makeTree(snapshot: snapshot)
    }

    private func makeTree(
        snapshot: LiveCapture.Snapshot,
        scrollMembershipsByHeistId: [HeistId: InterfaceTree.ScrollMembership] = [:]
    ) -> InterfaceTree {
        let elements = snapshot.hierarchy.pathIndexedElements.reduce(
            into: [HeistId: InterfaceTree.Element]()
        ) { result, item in
            guard let heistId = snapshot.heistIdsByPath[item.path] else { return }
            result[heistId] = InterfaceTree.Element(
                heistId: heistId,
                path: item.path,
                scrollMembership: scrollMembershipsByHeistId[heistId],
                element: item.element
            )
        }
        let containers = Dictionary(
            uniqueKeysWithValues: snapshot.hierarchy.pathIndexedContainers.map { item in
                (
                    item.path,
                    InterfaceTree.Container(
                        container: item.container,
                        path: item.path,
                        containerName: snapshot.containerNamesByPath[item.path],
                        contentRect: snapshot.containerContentFramesByPath[item.path],
                        scrollMembership: snapshot.containerScrollMembershipsByPath[item.path],
                        observedScrollContentActivationPoint: snapshot
                            .containerObservedScrollContentActivationPointsByPath[item.path],
                        scrollInventory: snapshot.scrollInventoriesByPath[item.path]
                    )
                )
            }
        )
        return InterfaceTree(
            elements: elements,
            containers: containers,
            viewportCapture: snapshot
        )
    }
}

#endif
