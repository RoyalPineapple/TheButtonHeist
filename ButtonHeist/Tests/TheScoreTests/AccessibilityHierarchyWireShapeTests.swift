import AccessibilitySnapshotModel
import XCTest
@testable import TheScore

/// Wire-shape tests for the public `Interface` tree.
///
/// The canonical wire payload is the parser's full-fidelity hierarchy plus
/// Button Heist annotations. These tests pin the explicit public shape so
/// compiler-derived enum payloads cannot drift into the protocol.
final class AccessibilityHierarchyWireShapeTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testElementLeafCarriesParserElementAndTraversalIndexWithoutCompilerPayload() throws {
        let element = sampleElement(heistId: "btn", label: "OK")
        let interface = makeTestInterface(nodes: [testElement(element)])

        let payload = try encodeInterfacePayload(interface)

        let tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        let elementPayload = try XCTUnwrap(tree.first?["element"] as? [String: Any])
        XCTAssertNil(elementPayload["_0"])
        XCTAssertEqual(elementPayload["description"] as? String, "Button")
        XCTAssertEqual(elementPayload["label"] as? String, "OK")
        XCTAssertEqual(elementPayload["traversalIndex"] as? Int, 0)
        XCTAssertNil(payload["elements"])
    }

    func testContainerCarriesParserContainerAndChildrenWithoutCompilerPayload() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameWidth: 320, frameHeight: 200),
                children: [testElement(sampleElement())]
            ),
        ])

        let payload = try encodeInterfacePayload(interface)

        let tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        let containerPayload = try XCTUnwrap(tree.first?["container"] as? [String: Any])
        XCTAssertNil(containerPayload["_0"])
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
        let header = sampleElement(heistId: "header", label: "Header")
        let row = sampleElement(heistId: "row_0", label: "Row 0")
        let interface = makeTestInterface(nodes: [
            testElement(header),
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameY: 50, frameWidth: 320, frameHeight: 400),
                stableId: "list_0",
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
        XCTAssertEqual(elements.map { $0["heistId"] as? String }, ["header", "row_0"])
        let containers = try XCTUnwrap(annotations["containers"] as? [[String: Any]])
        XCTAssertEqual(containers.first?["stableId"] as? String, "list_0")

        XCTAssertEqual(interface.elements.map(\.heistId), ["header", "row_0"])
    }

    func testNestedInterfaceRoundTripsThroughCanonicalHierarchy() throws {
        let element = sampleElement(heistId: "row", label: "Row")
        let original = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(
                    type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1000)),
                    frameWidth: 320,
                    frameHeight: 480
                ),
                stableId: "scroll",
                children: [
                    testContainer(
                        makeTestAccessibilityContainer(type: .landmark, frameWidth: 320, frameHeight: 100),
                        stableId: "landmark",
                        children: [testElement(element)]
                    ),
                ]
            ),
        ])

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Interface.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.elements, [element])
    }

    func testInterfaceRejectsCompilerDerivedElementTreePayload() throws {
        let interface = makeTestInterface(nodes: [testElement(sampleElement())])
        var payload = try encodeJSON(interface)
        var tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        var node = try XCTUnwrap(tree.first)
        let element = try XCTUnwrap(node["element"] as? [String: Any])
        node["element"] = [
            "_0": element.filter { $0.key != "traversalIndex" },
            "traversalIndex": try XCTUnwrap(element["traversalIndex"]),
        ]
        tree[0] = node
        payload["tree"] = tree

        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try decoder.decode(Interface.self, from: data)) { error in
            XCTAssertTrue(String(describing: error).contains("_0"))
        }
    }

    func testInterfaceRejectsCompilerDerivedContainerTreePayload() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(type: .list, frameWidth: 320, frameHeight: 200),
                children: [testElement(sampleElement())]
            ),
        ])
        var payload = try encodeJSON(interface)
        var tree = try XCTUnwrap(payload["tree"] as? [[String: Any]])
        var node = try XCTUnwrap(tree.first)
        let container = try XCTUnwrap(node["container"] as? [String: Any])
        node["container"] = [
            "_0": container.filter { $0.key != "children" },
            "children": try XCTUnwrap(container["children"]),
        ]
        tree[0] = node
        payload["tree"] = tree

        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try decoder.decode(Interface.self, from: data)) { error in
            XCTAssertTrue(String(describing: error).contains("_0"))
        }
    }

    private func encodeInterfacePayload(_ interface: Interface) throws -> [String: Any] {
        let envelope = ResponseEnvelope(message: .interface(interface))
        let data = try encoder.encode(envelope)
        let dict = try jsonObject(data)
        return try XCTUnwrap(dict["payload"] as? [String: Any])
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try jsonObject(data)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func sampleElement(
        heistId: HeistId = "btn",
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
            heistId: heistId,
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
