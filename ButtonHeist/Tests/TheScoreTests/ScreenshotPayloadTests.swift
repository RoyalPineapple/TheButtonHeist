import XCTest
 import TheScore

final class ScreenshotPayloadTests: XCTestCase {

    func testInitialization() {
        let timestamp = Date()
        let payload = ScreenPayload(
            pngData: "base64data",
            width: 390,
            height: 844,
            timestamp: timestamp
        )

        XCTAssertEqual(payload.pngData, "base64data")
        XCTAssertEqual(payload.width, 390)
        XCTAssertEqual(payload.height, 844)
        XCTAssertEqual(payload.timestamp, timestamp)
    }

    func testDefaultTimestamp() {
        let before = Date()
        let payload = ScreenPayload(
            pngData: "data",
            width: 100,
            height: 200
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(payload.timestamp, before)
        XCTAssertLessThanOrEqual(payload.timestamp, after)
    }

    func testEncodingRoundTrip() throws {
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 1206,
            height: 2622
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScreenPayload.self, from: data)

        XCTAssertEqual(payload.pngData, decoded.pngData)
        XCTAssertEqual(payload.width, decoded.width)
        XCTAssertEqual(payload.height, decoded.height)
    }

    func testLargeBase64Data() throws {
        // Simulate a large screenshot (~100KB base64)
        let largeData = String(repeating: "A", count: 100_000)
        let payload = ScreenPayload(
            pngData: largeData,
            width: 1206,
            height: 2622
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScreenPayload.self, from: data)

        XCTAssertEqual(decoded.pngData.count, 100_000)
    }

    func testRetinaScreenDimensions() {
        // iPhone 17 Pro @3x: 402x874 points = 1206x2622 pixels
        let payload = ScreenPayload(
            pngData: "data",
            width: 402,
            height: 874
        )

        XCTAssertEqual(payload.width, 402)
        XCTAssertEqual(payload.height, 874)
    }
}
