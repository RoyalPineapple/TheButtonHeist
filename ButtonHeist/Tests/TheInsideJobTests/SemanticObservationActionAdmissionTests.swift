#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationActionAdmissionTests: SemanticObservationStreamTestCase {
    func testActionAdmissionRejectsSupersededSettledCapture() async {
        let stale = observation(label: "Same Tree", heistId: "same")
        let current = observation(label: "Same Tree", heistId: "same")
        vault.observeInterface(stale)
        vault.observeInterface(current)

        let result = await vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleResult: settleResult(
                .settled(timeMs: 1),
                observation: stale,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .unavailable = result.commitOutcome else {
            return XCTFail("A superseded settled capture must not commit")
        }
        XCTAssertEqual(vault.latestObservation.captureID, current.captureID)
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureID, stale.captureID)
    }

    func testPostActionAdmissionReturnsExactTimedOutObservationAsUnsettledEvidence() async {
        let screen = observation(label: "Unstable", heistId: "unstable")
        vault.observeInterface(screen)

        let result = await vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleResult: settleResult(
                .timedOut(timeMs: 1),
                observation: screen,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .observedUnsettled(let observation, _) = result.commitOutcome else {
            return XCTFail("A timeout with a final observation should return diagnostic unsettled evidence")
        }
        XCTAssertEqual(observation.captureID, screen.captureID)
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureID, screen.captureID)
    }

    func testPostActionAdmissionNeverReturnsCancelledObservationAsUsableEvidence() async {
        let screen = observation(label: "Cancelled", heistId: "cancelled")
        vault.observeInterface(screen)

        let result = await vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleResult: settleResult(
                .cancelled(timeMs: 1),
                observation: screen,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .unavailable = result.commitOutcome else {
            return XCTFail("Cancellation must not expose its last tree as usable action evidence")
        }
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureID, screen.captureID)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
