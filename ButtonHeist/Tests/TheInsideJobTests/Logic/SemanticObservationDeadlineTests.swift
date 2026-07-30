#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

final class SemanticObservationDeadlineTests: XCTestCase {
    func testLargeFiniteTimeoutRemainsLiveAndProducesRepresentableSleep() {
        let now = RuntimeElapsed.now
        let deadline = SemanticObservationDeadline(
            start: now,
            timeoutSeconds: Double.greatestFiniteMagnitude
        )

        XCTAssertTrue(deadline.hasTimeRemaining(at: now))
        XCTAssertEqual(
            deadline.remainingSeconds(at: now),
            Double.greatestFiniteMagnitude
        )
        XCTAssertGreaterThan(deadline.remainingDuration(at: now), .zero)
    }
}
#endif
