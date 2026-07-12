import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistWaitEvidenceFactoryTests {
    @Test func `wait evidence factories bind outcome to result polarity`() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let met = ExpectationResult.Met(predicate: predicate)
        let unmet = ExpectationResult.Unmet(predicate: predicate, actual: "not found")
        let success = ActionResult.success(method: .wait, evidence: .none)
        let timeout = ActionResult.failure(method: .wait, errorKind: .timeout, evidence: .none)

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
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(method: .wait, evidence: .none),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let evidence = HeistWaitEvidence.matched(check)
        var invalidFixture = WaitEvidenceFixture(evidence)
        invalidFixture.expectation = ExpectationResult(
            met: false,
            predicate: invalidFixture.expectation.predicate,
            actual: "not found"
        )
        let invalidData = try JSONEncoder().encode(invalidFixture)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistWaitEvidence.self, from: invalidData)
        }
    }

    @Test func `decode rejects continued wait evidence`() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.UnmatchedCheck(
            actionResult: .success(method: .wait, evidence: .none),
            expectation: .unmet(ExpectationResult.Unmet(predicate: predicate, actual: "not found"))
        ))
        var invalidFixture = WaitEvidenceFixture(HeistWaitEvidence.failed(check))
        invalidFixture.outcome = .continued
        let invalidData = try JSONEncoder().encode(invalidFixture)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistWaitEvidence.self, from: invalidData)
        }
    }

    @Test func `decode rejects legacy wait warning`() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(method: .wait, evidence: .none),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let encoded = try JSONEncoder().encode(HeistWaitEvidence.matched(check))
        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject["warning"] = [
            "code": "transition_not_observed_final_state_satisfied",
            "predicate": predicate.description,
            "message": "final state was already satisfied",
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistWaitEvidence.self, from: legacyData)
        }
    }
}

private struct WaitEvidenceFixture: Codable {
    var outcome: HeistPredicateEvidenceOutcome
    var actionResult: ActionResult
    var expectation: ExpectationResult
    var baselineSummary: String?
    var finalSummary: String?

    init(_ evidence: HeistWaitEvidence) {
        outcome = evidence.outcome
        actionResult = evidence.actionResult
        expectation = evidence.expectation
        baselineSummary = evidence.baselineSummary
        finalSummary = evidence.finalSummary
    }
}
