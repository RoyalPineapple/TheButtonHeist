import XCTest
 import TheGoods

final class SnapshotTests: XCTestCase {

    func testEmptyPayload() throws {
        let payload = Snapshot(timestamp: Date(), elements: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Snapshot.self, from: data)

        XCTAssertTrue(decoded.elements.isEmpty)
    }

    func testPayloadWithMultipleElements() throws {
        let elements = (0..<10).map { i in
            UIElement(
                order: i,
                description: "Element \(i)",
                label: "Label \(i)",
                value: nil,
                identifier: "id_\(i)",
                frameX: Double(i * 10), frameY: 0,
                frameWidth: 100, frameHeight: 44,
                actions: []
            )
        }

        let payload = Snapshot(timestamp: Date(), elements: elements)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Snapshot.self, from: data)

        XCTAssertEqual(decoded.elements.count, 10)
        for i in 0..<10 {
            XCTAssertEqual(decoded.elements[i].order, i)
            XCTAssertEqual(decoded.elements[i].label, "Label \(i)")
        }
    }

    func testTimestampPreservation() throws {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let payload = Snapshot(timestamp: timestamp, elements: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Snapshot.self, from: data)

        // ISO8601 preserves to second precision
        XCTAssertEqual(
            Int(decoded.timestamp.timeIntervalSince1970),
            Int(timestamp.timeIntervalSince1970)
        )
    }
}
