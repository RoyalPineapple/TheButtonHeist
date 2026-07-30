import Foundation
import Testing
import TheScore

@Suite struct HeistRepeatUntilEvidenceFactoryTests {
    @Test func aggregateEvidenceStoresOnlyLoopFacts() throws {
        let evidence = try #require(HeistRepeatUntilEvidence.failed(
            iterationCount: 1,
            iterationOrdinal: 0,
            lastObservedSummary: "Cart",
            failureReason: "child failed"
        ))
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
                as? [String: Any]
        )

        #expect(evidence.outcome == .failed)
        #expect(Set(object.keys) == [
            "outcome",
            "iterationCount",
            "iterationOrdinal",
            "lastObservedSummary",
            "failureReason",
        ])
        #expect(object["expectation"] == nil)
        #expect(object["actionResult"] == nil)
    }

    @Test func factoriesAdmitOnlyValidIterationRelationships() {
        #expect(HeistRepeatUntilEvidence.matched(iterationCount: 0) != nil)
        #expect(HeistRepeatUntilEvidence.continued(
            iterationCount: 1,
            iterationOrdinal: 0
        ) != nil)
        #expect(HeistRepeatUntilEvidence.continued(
            iterationCount: 0,
            iterationOrdinal: 0
        ) == nil)
        #expect(HeistRepeatUntilEvidence.failed(
            iterationCount: 1,
            lastObservedSummary: nil,
            failureReason: "timed out"
        ) != nil)
    }

    @Test func decodeRejectsHandledElseOutcome() {
        let json = """
        {
          "outcome": "handled_else",
          "iterationCount": 1,
          "iterationOrdinal": 0
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistRepeatUntilEvidence.self, from: Data(json.utf8))
        }
    }
}
