import XCTest
@testable import ButtonHeist

final class ConnectionPhaseTests: XCTestCase {

    func testConnectionFailureAsConnectionError() {
        let errorFailure = TheHandoff.ConnectionFailure.error("boom")
        let authFailure = TheHandoff.ConnectionFailure.authFailed("bad token")
        let lockFailure = TheHandoff.ConnectionFailure.sessionLocked("in use")

        XCTAssertEqual(errorFailure.asConnectionError.errorDescription,
                       TheHandoff.ConnectionError.connectionFailed("boom").errorDescription)
        XCTAssertEqual(authFailure.asConnectionError.errorDescription,
                       TheHandoff.ConnectionError.authFailed("bad token").errorDescription)
        XCTAssertEqual(lockFailure.asConnectionError.errorDescription,
                       TheHandoff.ConnectionError.sessionLocked("in use").errorDescription)
    }
}
