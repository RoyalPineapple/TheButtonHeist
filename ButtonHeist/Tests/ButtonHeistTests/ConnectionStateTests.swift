import XCTest
@testable import ButtonHeist

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(TheClient.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(TheClient.ConnectionState.connecting, .connecting)
        XCTAssertEqual(TheClient.ConnectionState.connected, .connected)
        XCTAssertEqual(TheClient.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(TheClient.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(TheClient.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [TheClient.ConnectionState] = [
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
        let error1 = TheClient.ConnectionState.failed("Connection refused")
        let error2 = TheClient.ConnectionState.failed("Timeout")
        let error3 = TheClient.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
