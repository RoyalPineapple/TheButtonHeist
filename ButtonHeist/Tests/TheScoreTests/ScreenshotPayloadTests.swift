import XCTest
import ButtonHeistTestSupport
import ThePlans
import TheScore

final class ScreenshotPayloadTests: XCTestCase {

    func testDefaultTimestamp() {
        let before = Date()
        let payload = ScreenPayload(
            pngData: "data",
            width: 100,
            height: 200,
            interface: Interface(timestamp: Date(), tree: [])
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(payload.timestamp, before)
        XCTAssertLessThanOrEqual(payload.timestamp, after)
    }

    func testEncodingRoundTripWithInterfaceEvidence() throws {
        let element = HeistElement(
            description: "Total $12.34",
            label: "Total",
            value: "$12.34",
            identifier: "total",
            traits: [.staticText],
            frameX: 12,
            frameY: 680,
            frameWidth: 240,
            frameHeight: 32,
            activationPointEvidence: .explicit(ScreenPoint(x: 132, y: 696)),
            actions: []
        )
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 1206,
            height: 2622,
            interface: makeTestInterface(elements: [element], timestamp: Date(timeIntervalSince1970: 123))
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
        XCTAssertEqual(decoded.interface?.projectedElements, [element])
        XCTAssertEqual(decoded.interface?.projectedElements.first?.frameY, 680)
        XCTAssertEqual(decoded.interface?.projectedElements.first?.activationPointY, 696)
    }

    func testEncodingRoundTripWithoutInterfaceEvidence() throws {
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
        XCTAssertNil(decoded.interface)
    }

    func testLargeBase64Data() throws {
        // Simulate a large screenshot (~100KB base64)
        let largeData = String(repeating: "A", count: 100_000)
        let payload = ScreenPayload(
            pngData: largeData,
            width: 1206,
            height: 2622,
            interface: Interface(timestamp: Date(), tree: [])
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
            height: 874,
            interface: Interface(timestamp: Date(), tree: [])
        )

        XCTAssertEqual(payload.width, 402)
        XCTAssertEqual(payload.height, 874)
    }

    func testAdmissionRejectsInvalidDimensions() {
        for dimensions in [(0.0, 1.0), (-1, 1), (.nan, 1), (1, 0), (1, .infinity)] {
            XCTAssertNil(ScreenPayload.admit(pngData: "data", width: dimensions.0, height: dimensions.1))
        }
    }

    func testDecodingRejectsInvalidDimensions() {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let invalidDimensions = [
            ("0", "1"),
            ("-1", "1"),
            (#""NaN""#, "1"),
            ("1", #""Infinity""#),
        ]

        for dimensions in invalidDimensions {
            let json = """
            {
              "pngData":"data",
              "width":\(dimensions.0),
              "height":\(dimensions.1),
              "timestamp":0
            }
            """
            XCTAssertThrowsError(try decoder.decode(ScreenPayload.self, from: Data(json.utf8)))
        }
    }
}
