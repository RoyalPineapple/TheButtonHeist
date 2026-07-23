import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistResultPublicAPIContractTests {
    @Test func `evidence admission permits only its legal completion polarity`() {
        let passedAction = HeistActionEvidence.dispatch(
            dispatchResult: .success(payload: .dismiss)
        )
        let failedAction = HeistActionEvidence.dispatch(
            dispatchResult: .failure(payload: .dismiss, failureKind: .actionFailed)
        )

        #expect(HeistPassedActionEvidence(passedAction) != nil)
        #expect(HeistFailedActionEvidence(passedAction) == nil)
        #expect(HeistPassedActionEvidence(failedAction) == nil)
        #expect(HeistFailedActionEvidence(failedAction) != nil)
    }

    @Test func `wait completion round trips with matched evidence`() throws {
        let step = HeistResultFixture.wait()
        let data = try JSONEncoder().encode(step)

        #expect(try JSONDecoder().decode(HeistExecutionStepResult.self, from: data) == step)
        #expect(step.kind == .wait)
        #expect(step.status == .passed)
    }

    @Test func `met predicate with incomplete settlement is failed action evidence`() {
        let settlement = ActionSettlementEvidence.observationHandoffTimedOut(
            duration: 10,
            path: .uikitIdle
        )
        let trace = AccessibilityTrace.noChangeForTests(elementCount: 0)
        let traceEvidence = makeTestTraceEvidence(trace, completeness: .incomplete)
        let expectationResult = ActionResult.failure(
            payload: .wait,
            failureKind: .timeout,
            observation: .settledTrace(traceEvidence, settlement)
        )
        let evidence = HeistActionEvidence.expectation(
            dispatchResult: .success(payload: .dismiss),
            expectationResult: expectationResult,
            expectation: ExpectationResult(met: true, predicate: .announcement("Saved"))
        )

        #expect(HeistPassedActionEvidence(evidence) == nil)
        #expect(HeistFailedActionEvidence(evidence) != nil)
    }

    @Test func `matched announcement is authoritative over unrelated trace announcement`() {
        let expectationResult = ActionResult.success(
            payload: .wait,
            observation: .announcement("AXPerformElementUpdateImmediatelyToken")
        )
        let evidence = HeistActionEvidence.expectation(
            dispatchResult: .success(payload: .activate),
            expectationResult: expectationResult,
            expectation: ExpectationResult(
                met: true,
                predicate: .announcement("Ticket saved."),
                actual: "Ticket saved."
            )
        )

        #expect(expectationResult.announcement == "AXPerformElementUpdateImmediatelyToken")
        #expect(evidence.announcement == "Ticket saved.")
    }

    @Test func `failed result exposes derived failure facts`() {
        let result = HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(path: "$.body[0]", message: "stop")]
        )

        #expect(result.isFailure)
        #expect(result.abortedAtPath == "$.body[0]")
        #expect(result.steps.first?.failure?.observed == "stop")
    }
}
