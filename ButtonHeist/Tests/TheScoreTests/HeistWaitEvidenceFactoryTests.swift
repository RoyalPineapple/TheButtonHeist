import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistWaitEvidenceFactoryTests {
    @Test func `wait evidence factories bind outcome to result polarity`() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let met = MetExpectationResult(predicate: predicate)
        let unmet = UnmetExpectationResult(predicate: predicate, actual: "not found")
        let success = ActionResult.success(method: .wait)
        let timeout = ActionResult.failure(method: .wait, errorKind: .timeout)

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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(method: .wait),
            expectation: MetExpectationResult(predicate: predicate)
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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let check = try #require(HeistWaitEvidence.UnmatchedCheck(
            actionResult: .success(method: .wait),
            expectation: .unmet(UnmetExpectationResult(predicate: predicate, actual: "not found"))
        ))
        var invalidFixture = WaitEvidenceFixture(HeistWaitEvidence.failed(check))
        invalidFixture.outcome = .continued
        let invalidData = try JSONEncoder().encode(invalidFixture)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistWaitEvidence.self, from: invalidData)
        }
    }
}

private struct WaitEvidenceFixture: Codable {
    var outcome: HeistPredicateEvidenceOutcome
    var actionResult: ActionResult
    var expectation: ExpectationResult
    var baselineSummary: String?
    var finalSummary: String?
    var warning: HeistPredicateWarning?

    init(_ evidence: HeistWaitEvidence) {
        outcome = evidence.outcome
        actionResult = evidence.actionResult
        expectation = evidence.expectation
        baselineSummary = evidence.baselineSummary
        finalSummary = evidence.finalSummary
        warning = evidence.warning
    }
}
