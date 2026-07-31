import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
@testable import TheScore

@Suite struct HeistResultSemanticAdmissionTests {
    @Test func `passed wait evidence projects replayed semantics`() throws {
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
        let matchedEvidence = try #require(HeistPassedWaitEvidence(matched))
        let fallbackEvidence = try #require(HeistPassedWaitEvidence(unmatched))

        #expect(matchedEvidence.matchesExpectation)
        #expect(!matchedEvidence.usesFallback)
        #expect(!fallbackEvidence.matchesExpectation)
        #expect(fallbackEvidence.usesFallback)
        #expect(HeistPassedWaitEvidence(incomplete) == nil)
    }

    @Test func `aggregate admission accepts an unmet wait proven for fallback`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let unmatched = expectationEvidence(predicate: predicate, elements: [])
        let fallback = try #require(HeistPassedWaitEvidence(unmatched))
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

    @Test func `passed wait decoding rejects unreplayable expectation evidence`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let incomplete = expectationEvidence(
            predicate: predicate,
            elements: [makeTestHeistElement(label: "Done")],
            coverage: .incomplete(.captureUnavailable)
        )
        let expectationObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(incomplete))
                as? [String: Any]
        )
        let data = try JSONSerialization.data(
            withJSONObject: ["expectation": expectationObject]
        )

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
            completion: .failed(evidence: matched, failure: failure)
        )
        let expected = HeistResultCodecError.incoherentExecutionEvidence(
            path: "$.body[0]",
            reason: "failed wait expectation must not replay as met"
        )

        #expect(throws: expected) {
            _ = try HeistResult(steps: [step], durationMs: 1)
        }
    }

    @Test func `aggregate admission rejects child-aborted wait with incomplete fallback evidence`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let incomplete = expectationEvidence(
            predicate: predicate,
            elements: [],
            coverage: .incomplete(.captureUnavailable)
        )
        let childPath: HeistExecutionPath = "$.body[0].wait.else_body[0]"
        let child = HeistResultFixture.explicitFailure(
            path: childPath.description,
            message: "stop"
        )
        let failure = HeistFailureDetail(
            category: .wait,
            contract: "wait fallback completes",
            observed: "fallback child failed"
        )
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .childAborted(
                evidence: incomplete,
                failure: failure,
                children: try #require(HeistAbortedChildren([child]))
            )
        )
        let expected = HeistResultCodecError.incoherentExecutionEvidence(
            path: "$.body[0]",
            reason: "child-aborted wait requires complete unmet fallback evidence"
        )

        #expect(throws: expected) {
            _ = try HeistResult(steps: [step], durationMs: 1)
        }
    }

    @Test func `aggregate admission accepts intrinsic failed wait with incomplete evidence`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let incomplete = expectationEvidence(
            predicate: predicate,
            elements: [],
            coverage: .incomplete(.captureUnavailable)
        )
        let failure = HeistFailureDetail(
            category: .timeout,
            contract: "wait predicate is met",
            observed: "observation capture unavailable"
        )
        let step = HeistExecutionStepResult.wait(
            path: "$.body[0]",
            predicate: predicate,
            timeout: 1,
            completion: .failed(
                evidence: incomplete,
                failure: failure
            )
        )

        let result = try HeistResult(steps: [step], durationMs: 1)

        #expect(result.steps == [step])
        #expect(throws: Observation.Gap.captureUnavailable) {
            _ = try result.steps[0].replayExpectation()
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
