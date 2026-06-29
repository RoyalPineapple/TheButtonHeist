import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import XCTest
@testable import TheScore

/// Wire-shape tests for the public `Interface` tree.
///
/// The canonical wire payload is the parser's full-fidelity hierarchy plus
/// Button Heist annotations. These tests pin the accepted public shape.
final class AccessibilityHierarchyWireShapeTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testElementLeafCarriesParserElementAndTraversalIndex() throws {
        let element = sampleElement(label: "OK")
        let interface = makeTestInterface(nodes: [testElement(element)])

        let payload = try encodeInterfacePayload(interface)

        let tree = try payload.array("tree")
        let elementPayload = try XCTUnwrap(tree.first).object("element")
        XCTAssertEqual(try elementPayload.string("description"), "Button")
        XCTAssertEqual(try elementPayload.string("label"), "OK")
        XCTAssertEqual(try elementPayload.int("traversalIndex"), 0)
        try payload.assertMissing("elements")
    }

    func testPathIndexedElementsReturnNamedRecords() {
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(type: .list),
                children: [
                    testElement(sampleElement(label: "First")),
                    testElement(sampleElement(label: "Second")),
                ]
            ),
        ])

        let indexed: [PathIndexedAccessibilityElement] = interface.tree.pathIndexedElements

        XCTAssertEqual(indexed.map(\.path), [TreePath([0, 0]), TreePath([0, 1])])
        XCTAssertEqual(indexed.map(\.traversalIndex), [0, 1])
        XCTAssertEqual(indexed.map(\.element.label), ["First", "Second"])
    }

    func testContainerCarriesParserContainerAndChildren() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameWidth: 320, frameHeight: 200),
                children: [testElement(sampleElement())]
            ),
        ])

        let payload = try encodeInterfacePayload(interface)

        let tree = try payload.array("tree")
        let containerPayload = try XCTUnwrap(tree.first).object("container")
        let type = try containerPayload.object("type")
        try type.assertPresent("list")
        let size = try containerPayload.object("frame").object("size")
        XCTAssertEqual(try size.double("width"), 320)
        XCTAssertEqual(try size.double("height"), 200)
        let children = try containerPayload.array("children")
        XCTAssertEqual(children.count, 1)
    }

    func testInterfaceCarriesTreePlusAnnotations() throws {
        let header = sampleElement(label: "Header")
        let row = sampleElement(label: "Row 0")
        let interface = makeTestInterface(nodes: [
            testElement(header),
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameY: 50, frameWidth: 320, frameHeight: 400),
                containerName: "list_0",
                children: [testElement(row)]
            ),
        ])

        let payload = try encodeInterfacePayload(interface)

        let tree = try payload.array("tree")
        XCTAssertEqual(tree.count, 2)
        try tree[0].assertPresent("element")
        try tree[1].assertPresent("container")
        try payload.assertMissing("elements")

        let annotations = try payload.object("annotations")
        let elements = try annotations.array("elements")
        XCTAssertEqual(elements.count, 2)
        try XCTUnwrap(elements.first).assertMissing("heistId")
        let containers = try annotations.array("containers")
        XCTAssertEqual(try XCTUnwrap(containers.first).string("containerName"), "list_0")
    }

    func testNestedInterfaceRoundTripsThroughCanonicalHierarchy() throws {
        let element = sampleElement(label: "Row")
        let original = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(
                    type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
                    frameWidth: 320,
                    frameHeight: 480
                ),
                containerName: "scroll",
                children: [
                    testContainer(
                        makeTestAccessibilityContainer(type: .landmark, frameWidth: 320, frameHeight: 100),
                        containerName: "landmark",
                        children: [testElement(element)]
                    ),
                ]
            ),
        ])

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Interface.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.projectedElements, [element])
    }

    func testNodeLookupHandlesRootAndInvalidPaths() {
        let leaf = AccessibilityHierarchy.element(
            makeTestAccessibilityElement(sampleElement(label: "Leaf")),
            traversalIndex: 7
        )
        let root = AccessibilityHierarchy.container(
            makeTestAccessibilityContainer(type: .list),
            children: [leaf]
        )

        XCTAssertEqual(root.node(at: .root), root)
        XCTAssertEqual(root.node(at: TreePath([0])), leaf)
        XCTAssertNil(root.node(at: TreePath([1])))
        XCTAssertNil(leaf.node(at: TreePath([0])))
    }

    func testForestNodeLookupHandlesRootsNestedPathsAndInvalidRootPath() {
        let standalone = AccessibilityHierarchy.element(
            makeTestAccessibilityElement(sampleElement(label: "Standalone")),
            traversalIndex: 0
        )
        let nestedLeaf = AccessibilityHierarchy.element(
            makeTestAccessibilityElement(sampleElement(label: "Nested")),
            traversalIndex: 1
        )
        let container = AccessibilityHierarchy.container(
            makeTestAccessibilityContainer(type: .landmark),
            children: [nestedLeaf]
        )
        let forest = [standalone, container]

        XCTAssertNil(forest.node(at: .root))
        XCTAssertEqual(forest.node(at: TreePath([0])), standalone)
        XCTAssertEqual(forest.node(at: TreePath([1])), container)
        XCTAssertEqual(forest.node(at: TreePath([1, 0])), nestedLeaf)
        XCTAssertNil(forest.node(at: TreePath([2])))
        XCTAssertNil(forest.node(at: TreePath([1, 1])))
    }

    func testInterfaceDiagnosticsRoundTripThroughCanonicalWireShape() throws {
        let diagnostics = InterfaceDiagnostics(discovery: InterfaceDiscoveryDiagnostics(
            state: .limited,
            reasonCodes: [.discoveryScrollLimit],
            includedElementCount: 3,
            scrollAttempts: 5,
            maxScrollsPerDiscovery: 5,
            maxScrollsPerContainer: 3,
            exploredScrollableContainerCount: 1,
            omittedScrollableContainerCount: 1,
            omittedContainers: [
                InterfaceDiscoveryOmittedContainer(
                    containerName: "main_scroll",
                    type: .scrollable,
                    reasonCodes: [.discoveryScrollLimit],
                    scrollAxis: .vertical,
                    viewportWidth: 320,
                    viewportHeight: 400,
                    contentWidth: 320,
                    contentHeight: 1_200
                ),
            ],
            nextAction: "Retry get_interface with a higher maxScrollsPerDiscovery."
        ))
        let original = makeTestInterface(elements: [sampleElement(label: "Row")])
            .withDiagnostics(diagnostics)

        let payload = try encodeInterfacePayload(original)
        let encodedDiscovery = try payload.object("diagnostics").object("discovery")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Interface.self, from: data)

        XCTAssertEqual(try encodedDiscovery.string("state"), "limited")
        XCTAssertEqual(try encodedDiscovery.strings("reasonCodes"), ["scroll-attempt-budget"])
        XCTAssertEqual(decoded, original)
    }

    func testOmittedContainerDiagnosticsUseCanonicalSortOrder() {
        let unnamed = InterfaceDiscoveryOmittedContainer(
            type: .scrollable,
            reasonCodes: [],
            viewportWidth: 320,
            viewportHeight: 400
        )
        let namedList = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: .list,
            reasonCodes: [],
            viewportWidth: 500,
            viewportHeight: 400
        )
        let namedScrollableNarrow = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: .scrollable,
            reasonCodes: [],
            viewportWidth: 320,
            viewportHeight: 400
        )
        let namedScrollableWide = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: .scrollable,
            reasonCodes: [],
            viewportWidth: 500,
            viewportHeight: 400
        )
        let laterName = InterfaceDiscoveryOmittedContainer(
            containerName: "secondary",
            type: .scrollable,
            reasonCodes: [],
            viewportWidth: 100,
            viewportHeight: 100
        )

        XCTAssertEqual(
            [namedScrollableWide, laterName, namedScrollableNarrow, unnamed, namedList].sorted(),
            [unnamed, namedList, namedScrollableNarrow, namedScrollableWide, laterName]
        )
    }

    private func encodeInterfacePayload(_ interface: Interface) throws -> JSONProbe {
        let envelope = ResponseEnvelope(message: .interface(interface))
        let data = try encoder.encode(envelope)
        return try JSONProbe(data: data).object("payload")
    }

    private func sampleElement(
        label: String? = "OK"
    ) -> HeistElement {
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
