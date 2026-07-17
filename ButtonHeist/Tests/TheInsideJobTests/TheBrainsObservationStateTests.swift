#if canImport(UIKit)
#if DEBUG
import XCTest
@testable import TheInsideJob

@MainActor
final class TheBrainsObservationStateTests: XCTestCase {

    func testChangedWaitLeaseRequiresActiveObservationAndRejectsReentry() {
        let brains = TheBrains(tripwire: TheTripwire())

        XCTAssertFalse(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())

        brains.startSemanticObservation()
        defer {
            brains.finishChangedWait()
            brains.stopSemanticObservation()
        }

        XCTAssertTrue(brains.semanticObservationIsActive)
        XCTAssertTrue(brains.beginChangedWait())
        XCTAssertTrue(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())

        brains.finishChangedWait()

        XCTAssertTrue(brains.beginChangedWait())
    }

    func testStoppingObservationDuringChangedWaitIsNotReactivatedByWaitFinish() {
        let brains = TheBrains(tripwire: TheTripwire())
        brains.startSemanticObservation()

        XCTAssertTrue(brains.beginChangedWait())

        brains.stopSemanticObservation()
        brains.finishChangedWait()

        XCTAssertFalse(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
