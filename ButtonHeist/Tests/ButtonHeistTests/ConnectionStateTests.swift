import XCTest
@testable import ButtonHeist

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(HeistClient.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(HeistClient.ConnectionState.connecting, .connecting)
        XCTAssertEqual(HeistClient.ConnectionState.connected, .connected)
        XCTAssertEqual(HeistClient.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(HeistClient.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(HeistClient.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [HeistClient.ConnectionState] = [
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
        let error1 = HeistClient.ConnectionState.failed("Connection refused")
        let error2 = HeistClient.ConnectionState.failed("Timeout")
        let error3 = HeistClient.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
