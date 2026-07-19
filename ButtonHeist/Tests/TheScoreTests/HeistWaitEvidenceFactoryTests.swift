import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistWaitEvidenceFactoryTests {
    @Test func `wait evidence factories bind outcome to result polarity`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = ExpectationResult.Met(predicate: predicate)
        let unmet = ExpectationResult.Unmet(predicate: predicate, actual: "not found")
        let success = ActionResult.success(payload: .wait)
        let timeout = ActionResult.failure(payload: .wait, failureKind: .timeout)

        let matchedCheck = try #require(HeistWaitEvidence.MatchedCheck(actionResult: success, expectation: met))
        let matched = HeistWaitEvidence.matched(matchedCheck)
        #expect(matched.outcome == .matched)
        #expect(matched.actionResult.outcome.isSuccess)
        #expect(matched.expectation.met)

        let failedCheck = try #require(HeistWaitEvidence.UnmatchedCheck(
            actionResult: success,
            expectation: .unmet(unmet)
        ))
        let failed = HeistWaitEvidence.failed(
            failedCheck,
            finalSummary: "not found"
        )
        #expect(failed.outcome == .failed)
        #expect(failed.actionResult.outcome.isSuccess)
        #expect(!failed.expectation.met)
        #expect(failed.finalSummary == "not found")

        let handledElseCheck = try #require(HeistWaitEvidence.UnmatchedCheck(
            actionResult: timeout,
            expectation: .unmet(unmet)
        ))
        let handledElse = HeistWaitEvidence.handledElse(handledElseCheck)
        #expect(handledElse.outcome == .handledElse)
        #expect(!handledElse.actionResult.outcome.isSuccess)
    }

    @Test func `decode rejects invalid wait evidence polarity at boundary`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(payload: .wait),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let evidence = HeistWaitEvidence.matched(check)
        let invalidExpectation = ExpectationResult(
            met: false,
            predicate: evidence.expectation.predicate,
            actual: "not found"
        )
        let invalidData = try mutatedTestJSONData(evidence) { object in
            object["expectation"] = try testJSONObject(invalidExpectation)
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistWaitEvidence.self, from: invalidData)
        }
    }

}
