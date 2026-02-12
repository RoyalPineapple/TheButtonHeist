import XCTest
import Foundation
 import TheGoods

final class ScreenshotCommandTests: XCTestCase {

    // MARK: - Message Encoding Tests

    func testRequestScreenshotMessageEncoding() throws {
        let message = ClientMessage.requestScreenshot
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestScreenshot = decoded {
            // Success
        } else {
            XCTFail("Expected requestScreenshot, got \(decoded)")
        }
    }

    func testScreenshotPayloadEncoding() throws {
        let payload = ScreenshotPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 390,
            height: 844
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScreenshotPayload.self, from: data)

        XCTAssertEqual(decoded.pngData, payload.pngData)
        XCTAssertEqual(decoded.width, 390)
        XCTAssertEqual(decoded.height, 844)
    }

    func testServerMessageScreenshotEncoding() throws {
        let payload = ScreenshotPayload(
            pngData: "base64data",
            width: 1206,
            height: 2622
        )
        let message = ServerMessage.screenshot(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .screenshot(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.pngData, "base64data")
            XCTAssertEqual(decodedPayload.width, 1206)
            XCTAssertEqual(decodedPayload.height, 2622)
        } else {
            XCTFail("Expected screenshot message, got \(decoded)")
        }
    }

    func testBase64Decoding() throws {
        // 1x1 red pixel PNG in base64
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

        let payload = ScreenshotPayload(
            pngData: base64PNG,
            width: 1,
            height: 1
        )

        // Verify base64 can be decoded to Data
        let imageData = Data(base64Encoded: payload.pngData)
        XCTAssertNotNil(imageData)
        XCTAssertGreaterThan(imageData!.count, 0)

        // Verify PNG magic bytes
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let firstFourBytes = Array(imageData!.prefix(4))
        XCTAssertEqual(firstFourBytes, pngMagic)
    }

    func testScreenshotPayloadTimestamp() throws {
        let fixedDate = Date(timeIntervalSince1970: 1706900000)
        let payload = ScreenshotPayload(
            pngData: "data",
            width: 100,
            height: 200,
            timestamp: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScreenshotPayload.self, from: data)

        // ISO8601 may lose sub-second precision, so compare within 1 second
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, fixedDate.timeIntervalSince1970, accuracy: 1.0)
    }
}
