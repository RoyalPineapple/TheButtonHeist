import Foundation
import XCTest
@testable import TheScore

final class ActionSettlementEvidenceContractTests: XCTestCase {
    func testObservationHandoffTimedOutPreservesReadyPredicateEvidence() throws {
        let evidence = ActionSettlementEvidence.observationHandoffTimedOut(duration: 125)

        XCTAssertFalse(evidence.settled)
        XCTAssertTrue(evidence.readinessEstablished)
        XCTAssertFalse(evidence.observationHandoffCompleted)
        XCTAssertEqual(
            try encodedString(evidence),
            #"{"durationMs":125,"kind":"observationHandoffTimedOut"}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(
            ActionSettlementEvidence.self,
            from: JSONEncoder().encode(evidence)
        ), evidence)
    }

    /// `kind` is the whole discriminator now. The `path` key is gone: once
    /// settlement unified onto a single comparison it only ever encoded one
    /// string, which `kind` already implied.
    func testExistingSettlementEncodingsRemainStable() throws {
        XCTAssertEqual(
            try encodedString(ActionSettlementEvidence.settled(duration: 12)),
            #"{"durationMs":12,"kind":"settled"}"#
        )
        XCTAssertEqual(
            try encodedString(ActionSettlementEvidence.timedOut(duration: 12)),
            #"{"durationMs":12,"kind":"timedOut"}"#
        )
    }

    func testSettlementFactsAreExhaustive() {
        let rows: [(ActionSettlementEvidence, Bool, Bool, Bool)] = [
            (.settled(duration: 1), true, true, true),
            (.timedOut(duration: 1), false, false, false),
            (.observationHandoffTimedOut(duration: 1), false, true, false),
        ]

        for (evidence, settled, ready, handedOff) in rows {
            XCTAssertEqual(evidence.settled, settled)
            XCTAssertEqual(evidence.readinessEstablished, ready)
            XCTAssertEqual(evidence.observationHandoffCompleted, handedOff)
        }
    }

    private func encodedString(_ evidence: ActionSettlementEvidence) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(evidence), encoding: .utf8))
    }
}
