import Foundation
import XCTest
@testable import TheScore

final class ActionSettlementEvidenceContractTests: XCTestCase {
    func testObservationHandoffTimedOutPreservesReadyPredicateEvidence() throws {
        let evidence = ActionSettlementEvidence.observationHandoffTimedOut(
            duration: 125,
            path: .uikitIdle
        )

        XCTAssertFalse(evidence.settled)
        XCTAssertTrue(evidence.readinessEstablished)
        XCTAssertFalse(evidence.observationHandoffCompleted)
        XCTAssertEqual(evidence.path, .uikitIdle)
        XCTAssertEqual(
            try encodedString(evidence),
            #"{"durationMs":125,"kind":"observationHandoffTimedOut","path":"uikitIdle"}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(
            ActionSettlementEvidence.self,
            from: JSONEncoder().encode(evidence)
        ), evidence)
    }

    func testExistingSettlementEncodingsRemainStable() throws {
        XCTAssertEqual(
            try encodedString(ActionSettlementEvidence.settled(duration: 12, path: .semanticStability)),
            #"{"durationMs":12,"kind":"settled","path":"semanticStability"}"#
        )
        XCTAssertEqual(
            try encodedString(ActionSettlementEvidence.timedOut(duration: 12)),
            #"{"durationMs":12,"kind":"timedOut"}"#
        )
    }

    func testSettlementFactsAreExhaustive() {
        let rows: [(ActionSettlementEvidence, Bool, Bool, Bool)] = [
            (.settled(duration: 1, path: .uikitIdle), true, true, true),
            (.timedOut(duration: 1), false, false, false),
            (.observationHandoffTimedOut(duration: 1, path: .uikitIdle), false, true, false),
        ]

        for (evidence, settled, ready, handedOff) in rows {
            XCTAssertEqual(evidence.settled, settled)
            XCTAssertEqual(evidence.readinessEstablished, ready)
            XCTAssertEqual(evidence.observationHandoffCompleted, handedOff)
        }
    }

    func testStrictLegacyDecoderRequiresCoordinatedVersionForNewDiscriminator() throws {
        let data = try JSONEncoder().encode(ActionSettlementEvidence.observationHandoffTimedOut(
            duration: 1,
            path: .uikitIdle
        ))

        XCTAssertThrowsError(try JSONDecoder().decode(LegacySettlementEvidence.self, from: data))
        XCTAssertNoThrow(try JSONDecoder().decode(ActionSettlementEvidence.self, from: data))
    }

    func testObservationHandoffTimeoutRequiresReadinessPath() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ActionSettlementEvidence.self,
            from: Data(#"{"durationMs":1,"kind":"observationHandoffTimedOut"}"#.utf8)
        ))
    }

    private func encodedString(_ evidence: ActionSettlementEvidence) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(evidence), encoding: .utf8))
    }
}

private struct LegacySettlementEvidence: Decodable {
    private enum Kind: String, Decodable {
        case settled
        case timedOut
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Kind.self, forKey: .kind)
    }
}
