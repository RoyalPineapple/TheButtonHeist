import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
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

    func testHierarchyGraphRetainsEmptyContainersAndDuplicateSemanticNodes() {
        let duplicate = makeTestAccessibilityElement(makeElement(label: "Duplicate"))
        let empty = makeTestAccessibilityContainer(type: .semanticGroup(label: "Empty", value: nil))
        let nested = makeTestAccessibilityContainer(type: .landmark)
        let root = makeTestAccessibilityContainer(type: .list)
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                .container(empty, children: []),
                .element(duplicate, traversalIndex: 2),
                .container(nested, children: [
                    .element(duplicate, traversalIndex: 2),
                ]),
            ]),
        ]

        let graph = AccessibilityHierarchyGraph(tree: tree)

        XCTAssertEqual(graph.nodesInPathOrder.map(\.path), [
            TreePath([0]),
            TreePath([0, 0]),
            TreePath([0, 1]),
            TreePath([0, 2]),
            TreePath([0, 2, 0]),
        ])
        XCTAssertEqual(graph.elementsInTraversalOrder.map(\.path), [
            TreePath([0, 1]),
            TreePath([0, 2, 0]),
        ])
        XCTAssertEqual(graph.node(at: TreePath([0, 0])), .container(empty, children: []))
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

    func testElementPathIndexReusesPathDistinctCanonicalRecords() throws {
        let duplicate = makeTestAccessibilityElement(makeElement(label: "Duplicate"))
        let firstPath = TreePath([0, 0])
        let secondPath = TreePath([0, 1])
        let graph = try InterfaceGraph(
            tree: [
                .container(makeTestAccessibilityContainer(type: .list), children: [
                    .element(duplicate, traversalIndex: 4),
                    .element(duplicate, traversalIndex: 4),
                ]),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: firstPath, actions: [.activate]),
                InterfaceElementAnnotation(path: secondPath, actions: [.custom("Archive")]),
            ]),
            traceIdentities: InterfaceTraceIdentities([
                firstPath: TraceElementIdentity("duplicate_first"),
                secondPath: TraceElementIdentity("duplicate_second"),
            ])
        )

        let first = try XCTUnwrap(graph.element(at: firstPath))
        let second = try XCTUnwrap(graph.element(at: secondPath))
        let indexedNodes = graph.nodesInPathOrder.compactMap { node -> InterfaceGraphElementRecord? in
            guard case .element(let element) = node.kind else { return nil }
            return element
        }

        XCTAssertEqual(graph.elementsInTraversalOrder, [first, second])
        XCTAssertEqual(indexedNodes, [first, second])
        XCTAssertEqual(first.annotation?.actions, [.activate])
        XCTAssertEqual(second.annotation?.actions, [.custom("Archive")])
        XCTAssertEqual(first.traceIdentity, TraceElementIdentity("duplicate_first"))
        XCTAssertEqual(second.traceIdentity, TraceElementIdentity("duplicate_second"))
        XCTAssertNil(graph.element(at: TreePath([9])))
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

    func testInterfaceDerivesCanonicalGraphProjection() throws {
        let path = TreePath([0])
        let interface = try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: [
                .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: path, actions: [.activate]),
            ])
        )

        let firstRead = interface.graph
        let secondRead = interface.graph

        XCTAssertEqual(firstRead, secondRead)
        XCTAssertEqual(firstRead.node(at: path), interface.tree[0])
        XCTAssertEqual(firstRead.elementsInTraversalOrder.first?.annotation?.actions, [.activate])
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Save"])
    }

    func testProjectedInterfaceDerivesMetadataPathsFromTreeNodes() {
        let tree: [AccessibilityHierarchy] = [
            .container(makeTestAccessibilityContainer(type: .list), children: [
                .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
            ]),
        ]

        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            projecting: tree,
            elementMetadata: { _, _, _ in
                InterfaceElementProjectionMetadata(
                    actions: [.activate],
                    traceIdentity: TraceElementIdentity("save_button")
                )
            },
            containerMetadata: { _, _ in
                InterfaceContainerProjectionMetadata(containerName: ContainerName("checkout"))
            }
        )

        let elementPath = TreePath([0, 0])
        let containerPath = TreePath([0])
        XCTAssertEqual(interface.annotations.elements.map(\.path), [elementPath])
        XCTAssertEqual(interface.annotations.containers.map(\.path), [containerPath])
        XCTAssertEqual(interface.graph.element(at: elementPath)?.traceIdentity, TraceElementIdentity("save_button"))
        XCTAssertEqual(interface.projectedElements.map(\.label), ["Save"])
    }

    func testDecodedInterfaceHasValidatedUsableGraph() throws {
        let path = TreePath([0])
        let original = try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: [
                .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: path, actions: [.activate]),
            ])
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Interface.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.graph.node(at: path), original.tree[0])
        XCTAssertEqual(decoded.graph.elementsInTraversalOrder.first?.annotation?.actions, [.activate])
        XCTAssertEqual(try jsonObject(decoded), try jsonObject(original))
    }

    func testInterfaceDecodeRejectsInvalidGraphInput() throws {
        let original = try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: [
                .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: TreePath([0]), actions: [.activate]),
            ])
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        var annotations = try XCTUnwrap(payload["annotations"] as? [String: Any])
        var elements = try XCTUnwrap(annotations["elements"] as? [[String: Any]])
        elements[0]["path"] = ["indices": [1]]
        annotations["elements"] = elements
        payload["annotations"] = annotations
        let invalidData = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try JSONDecoder().decode(Interface.self, from: invalidData)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(
                context.underlyingError as? InterfaceGraphValidationError,
                .elementAnnotationForMissingPath(TreePath([1]))
            )
        }
    }

    func testInterfaceConstructionValidatesPathIndexedEvidence() {
        let tree: [AccessibilityHierarchy] = [
            .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
        ]

        XCTAssertThrowsError(try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: tree,
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(path: TreePath([1]), actions: [.activate]),
            ])
        )) { error in
            XCTAssertEqual(
                error as? InterfaceGraphValidationError,
                .elementAnnotationForMissingPath(TreePath([1]))
            )
        }

        XCTAssertThrowsError(try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: tree,
            traceIdentities: InterfaceTraceIdentities([
                TreePath([1]): TraceElementIdentity("missing_element"),
            ])
        )) { error in
            XCTAssertEqual(
                error as? InterfaceGraphValidationError,
                .traceIdentityForMissingPath(TreePath([1]))
            )
        }
    }

    func testDerivedGraphAndTraceIdentityRemainOutsideWireAndEqualityContracts() throws {
        let path = TreePath([0])
        let tree: [AccessibilityHierarchy] = [
            .element(makeTestAccessibilityElement(makeElement(label: "Save")), traversalIndex: 0),
        ]
        let plain = Interface(timestamp: Date(timeIntervalSince1970: 1), tree: tree)
        let traced = try Interface(
            timestamp: Date(timeIntervalSince1970: 1),
            tree: tree,
            traceIdentities: InterfaceTraceIdentities([
                path: TraceElementIdentity("save_button"),
            ])
        )

        XCTAssertEqual(traced, plain)
        XCTAssertNotEqual(traced.graph, plain.graph)
        XCTAssertEqual(try jsonObject(traced), try jsonObject(plain))
        let payload = try jsonObject(traced)
        XCTAssertNil(payload["graph"])
        XCTAssertNil(payload["traceIdentities"])

        let decoded = try JSONDecoder().decode(Interface.self, from: JSONEncoder().encode(traced))
        XCTAssertEqual(decoded.graph, plain.graph)
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
            activationPointEvidence: .defaultCenter(ScreenPoint(x: 50, y: 22)),
            actions: []
        )
    }

    private func jsonObject(_ interface: Interface) throws -> NSDictionary {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(interface)) as? NSDictionary
        )
    }
}
