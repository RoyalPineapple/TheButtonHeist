import AccessibilitySnapshotModel
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

        let tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        let elementPayload = try XCTUnwrap(tree.first?["element"] as? [String: Any])
        XCTAssertEqual(elementPayload["description"] as? String, "Button")
        XCTAssertEqual(elementPayload["label"] as? String, "OK")
        XCTAssertEqual(elementPayload["traversalIndex"] as? Int, 0)
        XCTAssertNil(payload["elements"])
    }

    func testContainerCarriesParserContainerAndChildren() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameWidth: 320, frameHeight: 200),
                children: [testElement(sampleElement())]
            ),
        ])

        let payload = try encodeInterfacePayload(interface)

        let tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        let containerPayload = try XCTUnwrap(tree.first?["container"] as? [String: Any])
        let type = try XCTUnwrap(containerPayload["type"] as? [String: Any])
        XCTAssertNotNil(type["list"])
        let frame = try XCTUnwrap(containerPayload["frame"] as? [String: Any])
        let size = try XCTUnwrap(frame["size"] as? [String: Any])
        XCTAssertEqual(size["width"] as? Double, 320)
        XCTAssertEqual(size["height"] as? Double, 200)
        let children = try XCTUnwrap(containerPayload["children"] as? [[String: Any]])
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

        let tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        XCTAssertEqual(tree.count, 2)
        XCTAssertNotNil(tree[0]["element"])
        XCTAssertNotNil(tree[1]["container"])
        XCTAssertNil(payload["elements"])

        let annotations = try XCTUnwrap(payload["annotations"] as? [String: Any])
        let elements = try XCTUnwrap(annotations["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.count, 2)
        XCTAssertNil(elements.first?["heistId"], "heistId must never appear on the wire")
        let containers = try XCTUnwrap(annotations["containers"] as? [[String: Any]])
        XCTAssertEqual(containers.first?["containerName"] as? String, "list_0")
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
                    type: "scrollable",
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
        let encodedDiagnostics = try XCTUnwrap(payload["diagnostics"] as? [String: Any])
        let encodedDiscovery = try XCTUnwrap(encodedDiagnostics["discovery"] as? [String: Any])
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Interface.self, from: data)

        XCTAssertEqual(encodedDiscovery["state"] as? String, "limited")
        XCTAssertEqual(encodedDiscovery["reasonCodes"] as? [String], ["scroll-attempt-budget"])
        XCTAssertEqual(decoded, original)
    }

    func testOmittedContainerDiagnosticsUseCanonicalSortOrder() {
        let unnamed = InterfaceDiscoveryOmittedContainer(
            type: "scrollable",
            reasonCodes: [],
            viewportWidth: 320,
            viewportHeight: 400
        )
        let namedList = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: "list",
            reasonCodes: [],
            viewportWidth: 500,
            viewportHeight: 400
        )
        let namedScrollableNarrow = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: "scrollable",
            reasonCodes: [],
            viewportWidth: 320,
            viewportHeight: 400
        )
        let namedScrollableWide = InterfaceDiscoveryOmittedContainer(
            containerName: "main",
            type: "scrollable",
            reasonCodes: [],
            viewportWidth: 500,
            viewportHeight: 400
        )
        let laterName = InterfaceDiscoveryOmittedContainer(
            containerName: "secondary",
            type: "scrollable",
            reasonCodes: [],
            viewportWidth: 100,
            viewportHeight: 100
        )

        XCTAssertEqual(
            [namedScrollableWide, laterName, namedScrollableNarrow, unnamed, namedList].sorted(),
            [unnamed, namedList, namedScrollableNarrow, namedScrollableWide, laterName]
        )
    }

    private func encodeInterfacePayload(_ interface: Interface) throws -> [String: Any] {
        let envelope = ResponseEnvelope(message: .interface(interface))
        let data = try encoder.encode(envelope)
        let dict = try jsonObject(data)
        return try XCTUnwrap(dict["payload"] as? [String: Any])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
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
