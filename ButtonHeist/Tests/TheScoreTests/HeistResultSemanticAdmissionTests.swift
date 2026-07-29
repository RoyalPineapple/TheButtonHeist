import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
@testable import TheScore

@Suite struct HeistResultSemanticAdmissionTests {
    @Test func `passed wait evidence admits only the replayed decision`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let unmatched = expectationEvidence(predicate: predicate, elements: [])
        let matched = expectationEvidence(
            predicate: predicate,
            elements: [makeTestHeistElement(label: "Done")]
        )
        let incomplete = expectationEvidence(
            predicate: predicate,
            elements: [],
            coverage: .incomplete(.captureUnavailable)
        )

        #expect(HeistPassedWaitEvidence.matched(matched) != nil)
        #expect(HeistPassedWaitEvidence.matched(unmatched) == nil)
        #expect(HeistPassedWaitEvidence.matched(incomplete) == nil)
        #expect(HeistPassedWaitEvidence.fallback(unmatched) != nil)
        #expect(HeistPassedWaitEvidence.fallback(matched) == nil)
        #expect(HeistPassedWaitEvidence.fallback(incomplete) == nil)
    }

    @Test func `aggregate admission accepts an unmet wait proven for fallback`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let unmatched = expectationEvidence(predicate: predicate, elements: [])
        let fallback = try #require(HeistPassedWaitEvidence.fallback(unmatched))
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .passed(evidence: fallback)
        )

        let result = try HeistResult(steps: [step], durationMs: 1)

        #expect(result.steps.first?.status == .passed)
        #expect(try result.steps.first?.replayExpectation()?.met == false)
    }

    @Test func `passed action evidence requires expectation replay proof`() {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let matched = expectationEvidence(
            predicate: predicate,
            elements: [makeTestHeistElement(label: "Done")]
        )
        let unmatched = expectationEvidence(predicate: predicate, elements: [])
        let incomplete = expectationEvidence(
            predicate: predicate,
            elements: [],
            coverage: .incomplete(.captureUnavailable)
        )
        let action = HeistResultFixture.actionResult()

        #expect(HeistPassedActionEvidence(.completed(result: action, expectation: matched)) != nil)
        #expect(HeistPassedActionEvidence(.completed(result: action, expectation: unmatched)) == nil)
        #expect(HeistPassedActionEvidence(.completed(result: action, expectation: incomplete)) == nil)
    }

    @Test func `passed wait decoding cannot bypass replay proof`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let matched = expectationEvidence(
            predicate: predicate,
            elements: [makeTestHeistElement(label: "Done")]
        )
        let evidence = try #require(HeistPassedWaitEvidence.matched(matched))
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
                as? [String: Any]
        )
        object["decision"] = HeistWaitDecision.fallback.rawValue
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HeistPassedWaitEvidence.self, from: data)
        }
    }

    @Test func `aggregate admission still rejects a failed wait whose predicate was met`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let matched = expectationEvidence(
            predicate: predicate,
            elements: [makeTestHeistElement(label: "Done")]
        )
        let failure = HeistFailureDetail(
            category: .timeout,
            contract: "wait predicate is met",
            observed: "deadline expired"
        )
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .failed(evidence: .observed(matched), failure: failure)
        )
        let expected = HeistResultCodecError.incoherentExecutionEvidence(
            path: "$.body[0]",
            reason: "failed wait expectation must not replay as met"
        )

        #expect(throws: expected) {
            _ = try HeistResult(steps: [step], durationMs: 1)
        }
    }

    private func expectationEvidence(
        predicate: AccessibilityPredicate,
        elements: [HeistElement],
        coverage: Observation.Coverage = .complete
    ) -> HeistExpectationEvidence {
        let snapshot = makeTestObservationSnapshot(elements: elements)
        return HeistResultFixture.expectationEvidence(
            predicate: predicate,
            observation: Observation.Evidence(
                baseline: nil,
                events: [.elementsChanged(snapshot), .noChange],
                current: snapshot,
                coverage: coverage
            )
        )
    }
}
