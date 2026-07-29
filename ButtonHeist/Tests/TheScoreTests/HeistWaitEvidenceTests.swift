import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
@testable import TheScore

@Suite struct HeistWaitEvidenceTests {
    @Test func matchedAndUnmatchedFactsRoundTripWithoutActionResultsOrSummaries() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let observation = makeTestObservationEvidence(
            current: makeTestObservationSnapshot(elements: []),
            events: [.noChange],
            completeness: .complete
        )
        let matched = HeistWaitMatchedEvidence(
            observation: observation,
            expectation: ExpectationResult.Met(predicate: predicate)
        )
        let unmatched = HeistWaitUnmatchedEvidence(
            observation: observation,
            expectation: ExpectationResult.Unmet(
                predicate: predicate,
                actual: "Done was absent"
            )
        )

        #expect(try roundTrip(matched) == matched)
        #expect(try roundTrip(unmatched) == unmatched)

        let matchedObject = try encodedObject(matched)
        #expect(Set(matchedObject.keys) == Set(["observation", "expectation"]))
        #expect(matchedObject["actionResult"] == nil)
        #expect(matchedObject["baselineSummary"] == nil)
        #expect(matchedObject["finalSummary"] == nil)
    }

    @Test func passedEvidenceHasOneCanonicalTaggedSpelling() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let observation = makeTestObservationEvidence(
            events: [.noChange],
            completeness: .complete
        )
        let matched = HeistPassedWaitEvidence.matched(HeistWaitMatchedEvidence(
            observation: observation,
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let handledElse = HeistPassedWaitEvidence.handledElse(
            HeistWaitUnmatchedEvidence(
                observation: observation,
                expectation: ExpectationResult.Unmet(
                    predicate: predicate,
                    actual: "Done was absent"
                )
            )
        )

        #expect(try roundTrip(matched) == matched)
        #expect(try roundTrip(handledElse) == handledElse)
        #expect(try encodedObject(matched)["type"] as? String == "matched")
        #expect(try encodedObject(handledElse)["type"] as? String == "handled_else")
    }

    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
