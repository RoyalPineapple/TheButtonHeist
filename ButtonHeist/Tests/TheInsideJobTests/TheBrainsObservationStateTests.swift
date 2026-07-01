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

        brains.semanticObservationIsActive = true

        XCTAssertTrue(brains.semanticObservationIsActive)
        XCTAssertTrue(brains.beginChangedWait())
        XCTAssertTrue(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())

        brains.finishChangedWait()

        XCTAssertTrue(brains.beginChangedWait())
    }

    func testStoppingObservationDuringChangedWaitIsNotReactivatedByWaitFinish() {
        let brains = TheBrains(tripwire: TheTripwire())
        brains.semanticObservationIsActive = true

        XCTAssertTrue(brains.beginChangedWait())

        brains.stopSemanticObservation()
        brains.finishChangedWait()

        XCTAssertFalse(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
