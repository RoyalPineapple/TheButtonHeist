#if canImport(UIKit)
#if DEBUG
import XCTest
@testable import TheInsideJob

@MainActor
final class TheBrainsObservationStateTests: XCTestCase {

    func testChangedWaitLeaseRequiresActiveObservationAndRejectsReentry() async {
        let brains = TheBrains(tripwire: TheTripwire())

        XCTAssertFalse(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())

        await brains.startSemanticObservation()
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

    func testStoppingObservationDuringChangedWaitIsNotReactivatedByWaitFinish() async {
        let brains = TheBrains(tripwire: TheTripwire())
        await brains.startSemanticObservation()

        XCTAssertTrue(brains.beginChangedWait())

        brains.stopSemanticObservation()
        brains.finishChangedWait()

        XCTAssertFalse(brains.semanticObservationIsActive)
        XCTAssertFalse(brains.beginChangedWait())
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
