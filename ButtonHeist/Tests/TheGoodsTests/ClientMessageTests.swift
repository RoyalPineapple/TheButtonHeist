import XCTest
 import TheGoods

final class ClientMessageTests: XCTestCase {

    func testRequestSnapshotEncodeDecode() throws {
        let message = ClientMessage.requestSnapshot
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestSnapshot = decoded {
            // Success
        } else {
            XCTFail("Expected requestSnapshot, got \(decoded)")
        }
    }

    func testSubscribeEncodeDecode() throws {
        let message = ClientMessage.subscribe
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .subscribe = decoded {
            // Success
        } else {
            XCTFail("Expected subscribe, got \(decoded)")
        }
    }

    func testUnsubscribeEncodeDecode() throws {
        let message = ClientMessage.unsubscribe
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .unsubscribe = decoded {
            // Success
        } else {
            XCTFail("Expected unsubscribe, got \(decoded)")
        }
    }

    func testPingEncodeDecode() throws {
        let message = ClientMessage.ping
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .ping = decoded {
            // Success
        } else {
            XCTFail("Expected ping, got \(decoded)")
        }
    }

    func testRequestScreenshotEncodeDecode() throws {
        let message = ClientMessage.requestScreenshot
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestScreenshot = decoded {
            // Success
        } else {
            XCTFail("Expected requestScreenshot, got \(decoded)")
        }
    }
}
