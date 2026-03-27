import XCTest
@testable import ButtonHeist

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(TheHandoff.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(TheHandoff.ConnectionState.connecting, .connecting)
        XCTAssertEqual(TheHandoff.ConnectionState.connected, .connected)
        XCTAssertEqual(TheHandoff.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(TheHandoff.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(TheHandoff.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [TheHandoff.ConnectionState] = [
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
        let error1 = TheHandoff.ConnectionState.failed("Connection refused")
        let error2 = TheHandoff.ConnectionState.failed("Timeout")
        let error3 = TheHandoff.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
