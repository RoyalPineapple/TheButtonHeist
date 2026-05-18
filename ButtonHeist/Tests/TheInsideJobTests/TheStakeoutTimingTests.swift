import XCTest

@testable import TheInsideJob
import TheScore

final class TheStakeoutTimingTests: XCTestCase {

    func testOmittedInactivityTimeoutDisablesInactivityAutoStop() {
        let timing = resolvedStakeoutTiming(for: RecordingConfig(maxDuration: 42.0))

        XCTAssertEqual(timing.maxDuration, 42.0)
        XCTAssertNil(timing.inactivityTimeout)
    }

    func testExplicitInactivityTimeoutIsPreservedAsEarlyStop() {
        let timing = resolvedStakeoutTiming(for: RecordingConfig(inactivityTimeout: 3.0, maxDuration: 42.0))

        XCTAssertEqual(timing.maxDuration, 42.0)
        XCTAssertEqual(timing.inactivityTimeout, 3.0)
    }
}
