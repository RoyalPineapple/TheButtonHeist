import XCTest
@testable import AccraClient

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(AccraClient.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(AccraClient.ConnectionState.connecting, .connecting)
        XCTAssertEqual(AccraClient.ConnectionState.connected, .connected)
        XCTAssertEqual(AccraClient.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(AccraClient.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(AccraClient.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [AccraClient.ConnectionState] = [
            .disconnected,
            .connecting,
            .connected,
            .failed("error")
        ]

        for i in 0..<states.count {
            for j in 0..<states.count {
                if i == j {
                    XCTAssertEqual(states[i], states[j])
                } else {
                    XCTAssertNotEqual(states[i], states[j])
                }
            }
        }
    }

    func testFailedStateWithDifferentMessages() {
        let error1 = AccraClient.ConnectionState.failed("Connection refused")
        let error2 = AccraClient.ConnectionState.failed("Timeout")
        let error3 = AccraClient.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
