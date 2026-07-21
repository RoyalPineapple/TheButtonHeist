import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct EvidenceContinuityCompatibilityTests {
    @Test func `tokenless source calls preserve legacy request result and wait evidence bytes`() throws {
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "legacy")),
        ])
        let request = HeistPlanRun(plan: plan)
        let result = try HeistResult(steps: [], durationMs: 3)
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(payload: .wait),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let waitEvidence = HeistWaitEvidence.matched(check)

        let requestGolden = LegacyHeistPlanRun(plan: plan, argument: .none)
        let resultGolden = LegacyHeistResult(steps: [], durationMs: 3)
        let waitEvidenceGolden = LegacyHeistWaitEvidence(
            outcome: .matched,
            actionResult: check.actionResult,
            expectation: check.expectation.result
        )

        #expect(try canonicalJSON(request) == canonicalJSON(requestGolden))
        #expect(try canonicalJSON(result) == canonicalJSON(resultGolden))
        #expect(try canonicalJSON(waitEvidence) == canonicalJSON(waitEvidenceGolden))
    }

    @Test func `legacy tokenless payloads decode without continuity`() throws {
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "legacy")),
        ])
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(payload: .wait),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))

        let request = try JSONDecoder().decode(
            HeistPlanRun.self,
            from: canonicalJSON(LegacyHeistPlanRun(plan: plan, argument: .none))
        )
        let result = try JSONDecoder().decode(
            HeistResult.self,
            from: canonicalJSON(LegacyHeistResult(steps: [], durationMs: 3))
        )
        let waitEvidence = try JSONDecoder().decode(
            HeistWaitEvidence.self,
            from: canonicalJSON(LegacyHeistWaitEvidence(
                outcome: .matched,
                actionResult: check.actionResult,
                expectation: check.expectation.result
            ))
        )

        #expect(request.continuity == nil)
        #expect(result.evidenceContinuity == nil)
        #expect(waitEvidence.continuity == nil)
    }

    @Test func `continuity remains execution context outside durable plan artifacts`() throws {
        let plan = try HeistPlan(
            name: "legacy",
            body: [.warn(WarnStep(message: "legacy"))]
        )
        let tokenless = HeistPlanRun(plan: plan)
        let supplied = HeistPlanRun(
            plan: plan,
            continuity: EvidenceContinuity.Reference()
        )

        #expect(try planJSON(in: tokenless) == planJSON(in: supplied))
        #expect(try planJSON(in: tokenless) == canonicalJSON(plan))
    }

    private func canonicalJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func planJSON(in request: HeistPlanRun) throws -> Data {
        let data = try canonicalJSON(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plan = try #require(object["plan"])
        return try JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys])
    }
}

private struct LegacyHeistPlanRun: Encodable {
    let plan: HeistPlan
    let argument: HeistArgument
}

private struct LegacyHeistResult: Encodable {
    let steps: [HeistExecutionStepResult]
    let durationMs: Int
}

private struct LegacyHeistWaitEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let actionResult: ActionResult
    let expectation: ExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(
        outcome: HeistPredicateEvidenceOutcome,
        actionResult: ActionResult,
        expectation: ExpectationResult,
        baselineSummary: String? = nil,
        finalSummary: String? = nil
    ) {
        self.outcome = outcome
        self.actionResult = actionResult
        self.expectation = expectation
        self.baselineSummary = baselineSummary
        self.finalSummary = finalSummary
    }
}
