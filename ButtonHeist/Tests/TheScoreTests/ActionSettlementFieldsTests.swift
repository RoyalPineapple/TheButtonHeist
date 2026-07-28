import ButtonHeistTestSupport
import XCTest
@testable import TheScore

final class ActionSettlementFieldsTests: XCTestCase {
    func testSuccessfulSettlementRoundTrips() throws {
        let result = ActionResult.success(
            payload: .activate,
            observation: .settled(
                stableEvidence(completeness: .incomplete),
                .settled(duration: 1234)
            )
        )

        let decoded = try roundTrip(result)

        XCTAssertEqual(decoded.settled, true)
        XCTAssertEqual(decoded.settleTimeMs, 1234)
    }

    func testTimedOutSettlementRoundTrips() throws {
        let result = ActionResult.failure(
            payload: .wait,
            failureKind: .timeout,
            message: "timed out",
            observation: .settled(
                stableEvidence(completeness: .incomplete),
                .timedOut(duration: 750)
            )
        )

        let decoded = try roundTrip(result)

        XCTAssertEqual(decoded.outcome.failureKind, .timeout)
        XCTAssertEqual(decoded.settled, false)
        XCTAssertEqual(decoded.settleTimeMs, 750)
    }

    func testSettlementAndPerformanceTimingRemainDistinct() throws {
        let result = ActionResult.success(
            payload: .activate,
            observation: .settled(
                stableEvidence(completeness: .incomplete),
                .settled(duration: 125)
            ),
            timing: ActionPerformanceTiming(actionDispatchMs: 4)
        )

        let decoded = try roundTrip(result)

        XCTAssertEqual(decoded.settleTimeMs, 125)
        XCTAssertEqual(decoded.timing?.actionDispatchMs, 4)
    }

    func testAnnouncementIsDerivedFromOrderedObservationEvents() throws {
        let notification = try XCTUnwrap(
            Observation.Notification(text: "Checkout", element: nil)
        )
        let evidence = makeTestObservationEvidence(
            current: makeTestObservationSnapshot(elements: []),
            events: [.notification(notification)],
            completeness: .incomplete
        )
        let result = ActionResult.success(
            payload: .activate,
            observation: .observed(evidence)
        )

        let decoded = try roundTrip(result)

        XCTAssertEqual(result.announcement, "Checkout")
        XCTAssertEqual(decoded.announcement, "Checkout")
        XCTAssertEqual(decoded.observationEvidence, evidence)
    }

    private func stableEvidence(
        completeness: Observation.Evidence.Completeness
    ) -> Observation.Evidence {
        let snapshot = makeTestObservationSnapshot(elements: [])
        return makeTestObservationEvidence(
            baseline: snapshot,
            current: snapshot,
            events: [.noChange],
            completeness: completeness
        )
    }

    private func roundTrip(_ result: ActionResult) throws -> ActionResult {
        try JSONDecoder().decode(ActionResult.self, from: JSONEncoder().encode(result))
    }
}
