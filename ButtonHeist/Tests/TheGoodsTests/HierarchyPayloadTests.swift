import XCTest
 import TheGoods

final class HierarchyPayloadTests: XCTestCase {

    func testEmptyPayload() throws {
        let payload = HierarchyPayload(timestamp: Date(), elements: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HierarchyPayload.self, from: data)

        XCTAssertTrue(decoded.elements.isEmpty)
    }

    func testPayloadWithMultipleElements() throws {
        let elements = (0..<10).map { i in
            AccessibilityElementData(
                traversalIndex: i,
                description: "Element \(i)",
                label: "Label \(i)",
                value: nil,
                traits: [],
                identifier: "id_\(i)",
                hint: nil,
                frameX: Double(i * 10), frameY: 0,
                frameWidth: 100, frameHeight: 44,
                activationPointX: Double(i * 10 + 50), activationPointY: 22,
                customActions: []
            )
        }

        let payload = HierarchyPayload(timestamp: Date(), elements: elements)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HierarchyPayload.self, from: data)

        XCTAssertEqual(decoded.elements.count, 10)
        for i in 0..<10 {
            XCTAssertEqual(decoded.elements[i].traversalIndex, i)
            XCTAssertEqual(decoded.elements[i].label, "Label \(i)")
        }
    }

    func testTimestampPreservation() throws {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let payload = HierarchyPayload(timestamp: timestamp, elements: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HierarchyPayload.self, from: data)

        // ISO8601 preserves to second precision
        XCTAssertEqual(
            Int(decoded.timestamp.timeIntervalSince1970),
            Int(timestamp.timeIntervalSince1970)
        )
    }
}
