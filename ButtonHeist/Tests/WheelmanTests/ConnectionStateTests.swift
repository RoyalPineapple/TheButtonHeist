import XCTest
@testable import Wheelman

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(Wheelman.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(Wheelman.ConnectionState.connecting, .connecting)
        XCTAssertEqual(Wheelman.ConnectionState.connected, .connected)
        XCTAssertEqual(Wheelman.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(Wheelman.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(Wheelman.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [Wheelman.ConnectionState] = [
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
        let error1 = Wheelman.ConnectionState.failed("Connection refused")
        let error2 = Wheelman.ConnectionState.failed("Timeout")
        let error3 = Wheelman.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
