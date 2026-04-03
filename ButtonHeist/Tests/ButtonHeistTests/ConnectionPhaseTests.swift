import XCTest
@testable import ButtonHeist

final class ConnectionPhaseTests: XCTestCase {

    func testPhaseEquality() {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let dummyTask = Task<Void, Never> {}

        XCTAssertEqual(TheHandoff.ConnectionPhase.disconnected, .disconnected)
        XCTAssertEqual(TheHandoff.ConnectionPhase.connecting(device: device), .connecting(device: device))
        XCTAssertEqual(TheHandoff.ConnectionPhase.connected(device: device, keepaliveTask: dummyTask), .connected(device: device, keepaliveTask: dummyTask))
        XCTAssertEqual(TheHandoff.ConnectionPhase.failed(.error("error")), .failed(.error("error")))

        XCTAssertNotEqual(TheHandoff.ConnectionPhase.disconnected, .connecting(device: device))
        XCTAssertNotEqual(TheHandoff.ConnectionPhase.failed(.error("a")), .failed(.error("b")))
    }

    func testAllPhasesDifferent() {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let dummyTask = Task<Void, Never> {}
        let phases: [TheHandoff.ConnectionPhase] = [
            .disconnected,
            .connecting(device: device),
            .connected(device: device, keepaliveTask: dummyTask),
            .failed(.error("error"))
        ]

        for index in 0..<phases.count {
            for other in 0..<phases.count {
                if index == other {
                    XCTAssertEqual(phases[index], phases[other])
                } else {
                    XCTAssertNotEqual(phases[index], phases[other])
                }
            }
        }
    }

    func testFailedPhaseWithDifferentMessages() {
        let error1 = TheHandoff.ConnectionPhase.failed(.error("Connection refused"))
        let error2 = TheHandoff.ConnectionPhase.failed(.error("Timeout"))
        let error3 = TheHandoff.ConnectionPhase.failed(.error("Connection refused"))

        XCTAssertNotEqual(error1, error2)
        XCTAssertEqual(error1, error3)
    }

    func testFailedPhaseDistinguishesFailureTypes() {
        let error = TheHandoff.ConnectionPhase.failed(.error("denied"))
        let authFailed = TheHandoff.ConnectionPhase.failed(.authFailed("denied"))
        let sessionLocked = TheHandoff.ConnectionPhase.failed(.sessionLocked("denied"))

        XCTAssertNotEqual(error, authFailed)
        XCTAssertNotEqual(error, sessionLocked)
        XCTAssertNotEqual(authFailed, sessionLocked)
    }

    func testConnectionFailureAsFenceError() {
        let errorFailure = TheHandoff.ConnectionFailure.error("boom")
        let authFailure = TheHandoff.ConnectionFailure.authFailed("bad token")
        let lockFailure = TheHandoff.ConnectionFailure.sessionLocked("in use")

        XCTAssertEqual(errorFailure.asFenceError.errorDescription,
                       FenceError.connectionFailed("boom").errorDescription)
        XCTAssertEqual(authFailure.asFenceError.errorDescription,
                       FenceError.authFailed("bad token").errorDescription)
        XCTAssertEqual(lockFailure.asFenceError.errorDescription,
                       FenceError.sessionLocked("in use").errorDescription)
    }
}
