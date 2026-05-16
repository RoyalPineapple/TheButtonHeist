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
        XCTAssertEqual(
            TheHandoff.ConnectionError.disconnected(.missingFingerprint),
            TheHandoff.ConnectionError.disconnected(.missingFingerprint)
        )
    }

    func testConnectionErrorTaxonomy() {
        let cases: [(TheHandoff.ConnectionError, String, FailurePhase, Bool)] = [
            (.connectionFailed("refused"), "connection.failed", .transport, true),
            (.disconnected(.missingFingerprint), "tls.missing_fingerprint", .tls, false),
            (.disconnected(.serverClosed), "transport.server_closed", .transport, true),
            (.authFailed("bad token"), "auth.failed", .authentication, false),
            (.sessionLocked("busy"), "session.locked", .session, true),
            (.timeout, "setup.timeout", .setup, true),
            (.noDeviceFound, "discovery.no_device_found", .discovery, true),
            (.noMatchingDevice(filter: "Demo", available: ["Other"]), "discovery.no_matching_device", .discovery, false),
        ]

        for (error, code, phase, retryable) in cases {
            XCTAssertEqual(error.failureCode, code)
            XCTAssertEqual(error.phase, phase)
            XCTAssertEqual(error.retryable, retryable)
            XCTAssertNotNil(error.hint, "Expected hint for \(error)")
        }
    }
}
