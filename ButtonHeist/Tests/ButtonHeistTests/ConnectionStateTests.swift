import XCTest
@testable import ButtonHeist

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(TheMastermind.ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(TheMastermind.ConnectionState.connecting, .connecting)
        XCTAssertEqual(TheMastermind.ConnectionState.connected, .connected)
        XCTAssertEqual(TheMastermind.ConnectionState.failed("error"), .failed("error"))

        XCTAssertNotEqual(TheMastermind.ConnectionState.disconnected, .connecting)
        XCTAssertNotEqual(TheMastermind.ConnectionState.failed("a"), .failed("b"))
    }

    func testAllStatesDifferent() {
        let states: [TheMastermind.ConnectionState] = [
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
        let error1 = TheMastermind.ConnectionState.failed("Connection refused")
        let error2 = TheMastermind.ConnectionState.failed("Timeout")
        let error3 = TheMastermind.ConnectionState.failed("Connection refused")

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }
}
