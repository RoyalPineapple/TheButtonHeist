#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ActionTimingTests: XCTestCase {
    func testRecordedPhasesFreezeIntoOneTimingValue() {
        let base = ContinuousClock.now
        func instant(_ seconds: Int) -> RuntimeElapsed.Instant {
            base.advanced(by: .seconds(seconds))
        }
        var timing = ActionTiming(startedAt: instant(1))
        timing.record(.targetResolution, since: instant(2), endedAt: instant(4))
        timing.record(.actionDispatch, since: instant(4), endedAt: instant(7))
        timing.record(.interaction, since: instant(1), endedAt: instant(8))

        XCTAssertEqual(timing.freeze(endedAt: instant(11)), ActionPerformanceTiming(
            targetResolutionMs: 2_000,
            actionDispatchMs: 3_000,
            interactionMs: 7_000,
            totalMs: 10_000
        ))
    }
}
#endif
