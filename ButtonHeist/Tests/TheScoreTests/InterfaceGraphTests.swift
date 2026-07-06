import AccessibilitySnapshotModel
import Foundation
import XCTest
@testable import TheScore

final class InterfaceGraphTests: XCTestCase {

    func testStableTraversalAndPathLookup() throws {
        let first = makeElement(label: "First")
        let second = makeElement(label: "Second")
        let third = makeElement(label: "Third")
        let tree: [AccessibilityHierarchy] = [
            .container(makeTestAccessibilityContainer(type: .list), children: [
                .element(makeTestAccessibilityElement(second), traversalIndex: 2),
                .container(makeTestAccessibilityContainer(type: .landmark), children: [
                    .element(makeTestAccessibilityElement(first), traversalIndex: 0),
                ]),
            ]),
            .element(makeTestAccessibilityElement(third), traversalIndex: 1),
        ]

        let graph = try InterfaceGraph(tree: tree)

        XCTAssertEqual(graph.elementsInTraversalOrder.map(\.path), [
            TreePath([0, 1, 0]),
            TreePath([1]),
            TreePath([0, 0]),
        ])
        XCTAssertEqual(graph.elementsInTraversalOrder.map(\.projectedElement.label), [
            "First",
            "Third",
            "Second",
        ])
        let containerPaths = graph.nodesInPathOrder.compactMap { record -> TreePath? in
            guard case .container = record.kind else { return nil }
            return record.path
        }
        XCTAssertEqual(containerPaths, [
            TreePath([0]),
            TreePath([0, 1]),
        ])
        XCTAssertEqual(graph.node(at: TreePath([0, 1, 0])), tree[0].node(at: TreePath([1, 0])))
        XCTAssertNil(graph.node(at: TreePath([9])))
    }

    func testDuplicateAnnotationPathsRejected() {
        let annotation = InterfaceElementAnnotation(path: TreePath([0]), actions: [.activate])
        XCTAssertThrowsError(try InterfaceGraph(
            tree: [.element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0)],
            annotations: InterfaceAnnotations(elements: [annotation, annotation])
        )) { error in
            XCTAssertEqual(error as? InterfaceGraphValidationError, .duplicateElementAnnotationPath(TreePath([0])))
        }
    }

    func testAnnotationPathWithoutNodeRejected() {
        XCTAssertThrowsError(try InterfaceGraph(
            tree: [.element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0)],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: TreePath([1]), actions: [.activate]),
            ])
        )) { error in
            XCTAssertEqual(error as? InterfaceGraphValidationError, .elementAnnotationForMissingPath(TreePath([1])))
        }
    }

    func testAnnotationAndTraceIdentityLookupByPath() throws {
        let save = makeElement(label: "Save")
        let cancel = makeElement(label: "Cancel")
        let savePath = TreePath([0])
        let cancelPath = TreePath([1])
        let saveIdentity = TraceElementIdentity("save_button")
        let cancelIdentity = TraceElementIdentity("cancel_button")

        let graph = try InterfaceGraph(
            tree: [
                .element(makeTestAccessibilityElement(save), traversalIndex: 0),
                .element(makeTestAccessibilityElement(cancel), traversalIndex: 1),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: savePath, actions: [.activate]),
                InterfaceElementAnnotation(path: cancelPath, actions: []),
            ]),
            traceIdentities: InterfaceTraceIdentities([
                savePath: saveIdentity,
                cancelPath: cancelIdentity,
            ])
        )

        let saveRecord = graph.elementsInTraversalOrder.first { $0.path == savePath }
        let cancelRecord = graph.elementsInTraversalOrder.first { $0.path == cancelPath }
        XCTAssertEqual(saveRecord?.annotation?.actions, [.activate])
        XCTAssertEqual(saveRecord?.traceIdentity, saveIdentity)
        XCTAssertEqual(cancelRecord?.traceIdentity, cancelIdentity)
    }

    func testTraceIdentityPathWithoutElementRejected() {
        XCTAssertThrowsError(try InterfaceGraph(
            tree: [
                .container(makeTestAccessibilityContainer(type: .list), children: []),
            ],
            traceIdentities: InterfaceTraceIdentities([
                TreePath([0]): TraceElementIdentity("container_identity"),
            ])
        )) { error in
            XCTAssertEqual(error as? InterfaceGraphValidationError, .traceIdentityForContainerPath(TreePath([0])))
        }
    }

    func testGraphCoreTypesRemainValueContracts() {
        assertValueContract(AccessibilityNodeRecord.self)
        assertValueContract(AccessibilityElementNodeRecord.self)
        assertValueContract(AccessibilityHierarchyGraph.self)
        assertValueContract(InterfaceGraphElementRecord.self)
        assertValueContract(InterfaceGraphContainerRecord.self)
        assertValueContract(InterfaceGraphNodeKind.self)
        assertValueContract(InterfaceGraphNodeRecord.self)
        assertValueContract(InterfaceGraph.self)
    }

    private func makeElement(label: String) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }

    private func assertValueContract<T: Equatable & Sendable>(_: T.Type) {}
}
