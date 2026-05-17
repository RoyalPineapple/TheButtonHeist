import XCTest
@testable import TheScore

/// Wire-shape tests for the public `Interface` / `InterfaceNode` /
/// `ContainerInfo` JSON encoding. The synthesized `Codable` derived from
/// associated-value enums emits Swift-internal keys like `_0` and wraps each
/// case in a singleton dictionary; that does not match the documented
/// protocol shape and would break non-Swift clients. These tests pin the
/// canonical wire shape so it can't regress.
final class InterfaceNodeWireShapeTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Helpers

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            XCTFail("Expected top-level JSON object, got \(type(of: object))")
            return [:]
        }
        return dict
    }

    private func sampleElement(
        heistId: String = "btn",
        label: String? = "OK"
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: "Button",
            label: label,
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
    }

    // MARK: - Leaf shape

    func testElementLeafEncodesAsDirectHeistElementPayload() throws {
        let node = InterfaceNode.element(sampleElement(heistId: "btn", label: "OK"))

        let dict = try encodeJSON(node)

        XCTAssertEqual(Array(dict.keys), ["element"])
        let payload = try XCTUnwrap(dict["element"] as? [String: Any])
        XCTAssertNil(payload["_0"], "Leaf payload must not be wrapped under '_0'")
        XCTAssertEqual(payload["heistId"] as? String, "btn")
        XCTAssertEqual(payload["label"] as? String, "OK")
    }

    // MARK: - Container shape

    func testListContainerEncodesTypeStringInline() throws {
        let info = ContainerInfo(
            type: .list, frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 200
        )
        let node = InterfaceNode.container(info, children: [.element(sampleElement())])

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        XCTAssertNil(payload["_0"], "Container payload must not be wrapped under '_0'")
        XCTAssertEqual(payload["type"] as? String, "list")
        XCTAssertNil(payload["isModalBoundary"], "False modal boundary should preserve existing wire shape")
        XCTAssertEqual(payload["frameX"] as? Double, 0)
        XCTAssertEqual(payload["frameWidth"] as? Double, 320)
        XCTAssertNotNil(payload["children"])
    }

    func testModalBoundaryContainerEncodesOnlyWhenTrue() throws {
        let info = ContainerInfo(
            type: .semanticGroup(label: "Alert", value: nil, identifier: nil),
            isModalBoundary: true,
            frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 200
        )
        let node = InterfaceNode.container(info, children: [])

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "semanticGroup")
        XCTAssertEqual(payload["isModalBoundary"] as? Bool, true)
    }

    func testScrollableContainerEncodesContentSize() throws {
        let info = ContainerInfo(
            type: .scrollable(contentWidth: 390, contentHeight: 1200),
            frameX: 0, frameY: 44, frameWidth: 390, frameHeight: 600
        )
        let node = InterfaceNode.container(info, children: [])

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "scrollable")
        XCTAssertEqual(payload["contentWidth"] as? Double, 390)
        XCTAssertEqual(payload["contentHeight"] as? Double, 1200)
    }

    func testSemanticGroupContainerEncodesNamedFields() throws {
        let info = ContainerInfo(
            type: .semanticGroup(label: "Settings", value: nil, identifier: "settings"),
            frameX: 0, frameY: 0, frameWidth: 390, frameHeight: 100
        )
        let node = InterfaceNode.container(info, children: [])

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "semanticGroup")
        XCTAssertEqual(payload["label"] as? String, "Settings")
        XCTAssertEqual(payload["identifier"] as? String, "settings")
        XCTAssertNil(payload["value"], "Optional value should be omitted when nil")
    }

    func testDataTableContainerEncodesRowAndColumnCount() throws {
        let info = ContainerInfo(
            type: .dataTable(rowCount: 4, columnCount: 3),
            frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 200
        )
        let node = InterfaceNode.container(info, children: [])

        let dict = try encodeJSON(node)

        let payload = try XCTUnwrap(dict["container"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "dataTable")
        XCTAssertEqual(payload["rowCount"] as? Int, 4)
        XCTAssertEqual(payload["columnCount"] as? Int, 3)
    }

    // MARK: - Round-trip

    func testNestedTreeRoundTrips() throws {
        let element = sampleElement(heistId: "row", label: "Row")
        let scrollable = ContainerInfo(
            type: .scrollable(contentWidth: 320, contentHeight: 1000),
            frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 480
        )
        let landmark = ContainerInfo(
            type: .landmark, frameX: 0, frameY: 0, frameWidth: 320, frameHeight: 100
        )
        let original = InterfaceNode.container(scrollable, children: [
            .container(landmark, children: [.element(element)])
        ])

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(InterfaceNode.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testInterfaceWireShapeMatchesDocumentedProtocol() throws {
        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(sampleElement(heistId: "header", label: "Header")),
                .container(
                    ContainerInfo(
                        type: .list, frameX: 0, frameY: 50, frameWidth: 320, frameHeight: 400
                    ),
                    children: [.element(sampleElement(heistId: "row_0", label: "Row 0"))]
                ),
            ]
        )

        let dict = try encodeJSON(interface)

        let tree = try XCTUnwrap(dict["tree"] as? [[String: Any]])
        XCTAssertEqual(tree.count, 2)

        let first = try XCTUnwrap(tree[0]["element"] as? [String: Any])
        XCTAssertEqual(first["heistId"] as? String, "header")

        let second = try XCTUnwrap(tree[1]["container"] as? [String: Any])
        XCTAssertEqual(second["type"] as? String, "list")
        let nested = try XCTUnwrap(second["children"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 1)
        let nestedElement = try XCTUnwrap(nested[0]["element"] as? [String: Any])
        XCTAssertEqual(nestedElement["heistId"] as? String, "row_0")
    }

    // MARK: - Decoding rejects malformed input

    func testDecodingFailsForUnknownContainerType() {
        let json = Data("""
        {"container": {
          "type": "futureContainerType",
          "frameX": 0, "frameY": 0, "frameWidth": 0, "frameHeight": 0,
          "children": []
        }}
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(InterfaceNode.self, from: json))
    }

    func testDecodingFailsForMissingDiscriminator() {
        let json = Data("{}".utf8)
        XCTAssertThrowsError(try decoder.decode(InterfaceNode.self, from: json))
    }
}
