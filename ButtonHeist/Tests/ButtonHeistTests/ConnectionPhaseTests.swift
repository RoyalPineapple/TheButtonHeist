import XCTest
@testable import ButtonHeist

final class ConnectionPhaseTests: XCTestCase {

    func testConnectionErrorIsEquatable() {
        // HandoffConnectionError is used as the associated value in
        // HandoffConnectionPhase.failed, so Equatable conformance is load-bearing
        // for phase comparison in tests and assertions.
        XCTAssertEqual(
            HandoffConnectionError.connectionFailed("boom"),
            HandoffConnectionError.connectionFailed("boom")
        )
        XCTAssertNotEqual(
            HandoffConnectionError.connectionFailed("boom"),
            HandoffConnectionError.connectionFailed("other")
        )
        XCTAssertNotEqual(
            HandoffConnectionError.disconnected(.authFailed("bad token")),
            HandoffConnectionError.disconnected(.sessionLocked("bad token"))
        )
        XCTAssertEqual(
            HandoffConnectionError.disconnected(.missingFingerprint),
            HandoffConnectionError.disconnected(.missingFingerprint)
        )
    }

    func testConnectionErrorTaxonomy() {
        let cases: [(HandoffConnectionError, String, FailurePhase, Bool)] = [
            (.connectionFailed("refused"), "connection.failed", .transport, true),
            (.disconnected(.missingFingerprint), "tls.missing_fingerprint", .tls, false),
            (.disconnected(.serverClosed), "transport.server_closed", .transport, true),
            (.disconnected(.authFailed("bad token")), "auth.failed", .authentication, false),
            (
                .disconnected(.authApprovalPending("Legacy server is waiting for UI approval.")),
                "auth.approval_pending",
                .authentication,
                true
            ),
            (.disconnected(.sessionLocked("busy")), "session.locked", .session, true),
            (.timeout, "setup.timeout", .setup, true),
            (.noDeviceFound, "discovery.no_device_found", .discovery, true),
            (.noMatchingDevice(filter: "Demo", available: ["Other"]), "discovery.no_matching_device", .discovery, false),
            (.ambiguousDeviceTarget(filter: "Demo", matches: ["Demo#one", "Demo#two"]), "discovery.ambiguous_device_target", .discovery, false),
        ]

        for (error, code, phase, retryable) in cases {
            XCTAssertEqual(error.failureCode, code)
            XCTAssertEqual(error.phase, phase)
            XCTAssertEqual(error.retryable, retryable)
            if code != "auth.failed" {
                XCTAssertNotNil(error.hint, "Expected hint for \(error)")
            }
        }
    }
}
