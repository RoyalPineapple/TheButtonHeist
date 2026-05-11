import XCTest
@testable import ButtonHeist

final class ConnectionPhaseTests: XCTestCase {

    func testConnectionErrorIsEquatable() {
        // ConnectionError is used as the associated value in
        // ConnectionPhase.failed, so Equatable conformance is load-bearing
        // for phase comparison in tests and assertions.
        XCTAssertEqual(
            TheHandoff.ConnectionError.connectionFailed("boom"),
            TheHandoff.ConnectionError.connectionFailed("boom")
        )
        XCTAssertNotEqual(
            TheHandoff.ConnectionError.connectionFailed("boom"),
            TheHandoff.ConnectionError.connectionFailed("other")
        )
        XCTAssertNotEqual(
            TheHandoff.ConnectionError.authFailed("bad token"),
            TheHandoff.ConnectionError.sessionLocked("bad token")
        )
    }
}
