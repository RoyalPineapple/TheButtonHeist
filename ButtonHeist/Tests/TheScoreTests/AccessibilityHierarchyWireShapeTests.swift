import AccessibilitySnapshotModel
import XCTest
@testable import TheScore

/// Wire-shape tests for the public `Interface` tree.
///
/// The canonical wire payload is the parser's full-fidelity
/// `AccessibilityHierarchy` plus Button Heist annotations. These tests pin
/// that shape so the old lossy converted tree payload
/// payload cannot drift back into the protocol.
final class AccessibilityHierarchyWireShapeTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testElementLeafCarriesParserElementAndTraversalIndex() throws {
        let element = sampleElement(heistId: "btn", label: "OK")
        let node = AccessibilityHierarchy.element(makeTestAccessibilityElement(element), traversalIndex: 7)

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["element"] as? [String: Any])
        let accessibilityElement = try XCTUnwrap(payload["_0"] as? [String: Any])
        XCTAssertEqual(accessibilityElement["description"] as? String, "Button")
        XCTAssertEqual(accessibilityElement["label"] as? String, "OK")
        XCTAssertEqual(payload["traversalIndex"] as? Int, 7)
    }

    func testContainerCarriesParserContainerAndChildren() throws {
        let node = AccessibilityHierarchy.container(
            makeTestAccessibilityContainer(type: .list, frameWidth: 320, frameHeight: 200),
            children: [.element(makeTestAccessibilityElement(sampleElement()), traversalIndex: 0)]
        )

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        let accessibilityContainer = try XCTUnwrap(payload["_0"] as? [String: Any])
        let type = try XCTUnwrap(accessibilityContainer["type"] as? [String: Any])
        XCTAssertNotNil(type["list"])
        let frame = try XCTUnwrap(accessibilityContainer["frame"] as? [String: Any])
        let size = try XCTUnwrap(frame["size"] as? [String: Any])
        XCTAssertEqual(size["width"] as? Double, 320)
        XCTAssertEqual(size["height"] as? Double, 200)
        let children = try XCTUnwrap(payload["children"] as? [[String: Any]])
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

        let dict = try encodeJSON(interface)

        let tree = try XCTUnwrap(dict["tree"] as? [[String: Any]])
        XCTAssertEqual(tree.count, 2)
        XCTAssertNotNil(tree[0]["element"])
        XCTAssertNotNil(tree[1]["container"])

        let annotations = try XCTUnwrap(dict["annotations"] as? [String: Any])
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

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
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
