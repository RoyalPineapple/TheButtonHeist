import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist

final class ConnectionPhaseTests: XCTestCase {

    func testConnectionErrorTaxonomy() {
        let cases: [(HandoffConnectionError, KnownFailureCode, FailurePhase, Bool)] = [
            (.connectionFailed("refused"), .connectionFailed, .transport, true),
            (.disconnected(.missingToken), .tlsMissingToken, .tls, false),
            (.disconnected(.serverClosed), .transportServerClosed, .transport, true),
            (.disconnected(.authFailed("bad token")), .authFailed, .authentication, false),
            (.disconnected(.sessionLocked("busy")), .sessionLocked, .session, true),
            (.timeout, .setupTimeout, .setup, true),
            (.noDeviceFound, .discoveryNoDeviceFound, .discovery, true),
            (.noMatchingDevice(filter: "Demo", available: ["Other"]), .discoveryNoMatchingDevice, .discovery, false),
            (.ambiguousDeviceTarget(filter: "Demo", matches: ["Demo#one", "Demo#two"]), .discoveryAmbiguousDeviceTarget, .discovery, false),
        ]

        for (error, knownCode, phase, retryable) in cases {
            XCTAssertEqual(error.diagnostic.details.code, knownCode)
            XCTAssertEqual(error.failureCode, knownCode.rawValue)
            XCTAssertEqual(error.phase, phase)
            XCTAssertEqual(error.retryable, retryable)
            if knownCode != .authFailed {
                XCTAssertNotNil(error.hint, "Expected hint for \(error)")
            }
        }
    }
}
