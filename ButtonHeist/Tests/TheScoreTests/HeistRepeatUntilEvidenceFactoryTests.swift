import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistRepeatUntilEvidenceFactoryTests {
    @Test func `expectation result converts to typed predicate checks`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = ExpectationResult(met: true, predicate: predicate)
        let unmet = ExpectationResult(met: false, predicate: predicate, actual: "not found")

        switch met {
        case .met(let expectation):
            #expect(expectation.result == met)
        case .unmet:
            Issue.record("Expected met predicate check")
        }

        switch unmet {
        case .met:
            Issue.record("Expected unmet predicate check")
        case .unmet(let expectation):
            #expect(expectation.result == unmet)
        }

        #expect(ExpectationResult.Met(unmet) == nil)
        #expect(ExpectationResult.Unmet(met) == nil)
        let convertedMet = try #require(ExpectationResult.Met(met))
        let convertedUnmet = try #require(ExpectationResult.Unmet(unmet))
        #expect(convertedMet.result == met)
        #expect(convertedUnmet.result == unmet)
    }

    @Test func `evidence factories align with stored outcomes`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = try #require(ExpectationResult.Met(ExpectationResult(met: true, predicate: predicate)))
        let unmet = try #require(ExpectationResult.Unmet(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))

        let predicateMet = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            expectation: met
        ))
        #expect(predicateMet.outcome == .matched)
        #expect(predicateMet.expectation.met)

        let failed = try #require(HeistRepeatUntilEvidence.failed(
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "timed out"
        ))
        #expect(failed.outcome == .failed)
        #expect(!failed.expectation.met)
        #expect(failed.failureReason == "timed out")

        let handledElse = try #require(HeistRepeatUntilEvidence.handledElse(
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "Cart"
        ))
        #expect(handledElse.outcome == .handledElse)
    }

    @Test func `iteration evidence factories return evidence for typed polarity`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = try #require(ExpectationResult.Met(ExpectationResult(met: true, predicate: predicate)))
        let unmet = try #require(ExpectationResult.Unmet(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))

        let predicateMet = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: met
        ))
        #expect(predicateMet.outcome == .matched)
        #expect(predicateMet.iterationOrdinal == 0)

        let continued = try #require(HeistRepeatUntilEvidence.continued(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet
        ))
        #expect(continued.outcome == .continued)
        #expect(continued.iterationOrdinal == 0)

        let failed = try #require(HeistRepeatUntilEvidence.failed(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet,
            lastObservedSummary: "Cart",
            failureReason: "child failed"
        ))
        #expect(failed.outcome == .failed)
        #expect(failed.iterationOrdinal == 0)
    }

    @Test func `decode rejects invalid repeat until polarity at boundary`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let evidence = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let invalidExpectation = ExpectationResult(
            met: false,
            predicate: evidence.expectation.predicate,
            actual: evidence.expectation.actual
        )
        let invalidData = try mutatedTestJSONData(evidence) { object in
            object["expectation"] = try testJSONObject(invalidExpectation)
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistRepeatUntilEvidence.self, from: invalidData)
        }
    }
}
