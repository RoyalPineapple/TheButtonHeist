import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistReceiptPublicAPIContractTests {
    @Test func `evidence proofs admit only their legal completion polarity`() {
        let passedAction = HeistActionEvidence.dispatch(
            dispatchResult: .success(method: .dismiss, evidence: .none)
        )
        let failedAction = HeistActionEvidence.dispatch(
            dispatchResult: .failure(method: .dismiss, errorKind: .actionFailed, evidence: .none)
        )

        #expect(HeistPassedActionEvidence(passedAction) != nil)
        #expect(HeistFailedActionEvidence(passedAction) == nil)
        #expect(HeistPassedActionEvidence(failedAction) == nil)
        #expect(HeistFailedActionEvidence(failedAction) != nil)
    }

    @Test func `wait completion round trips with matched evidence`() throws {
        let step = HeistReceiptFixture.wait()
        let data = try JSONEncoder().encode(step)

        #expect(try JSONDecoder().decode(HeistExecutionStepResult.self, from: data) == step)
        #expect(step.kind == .wait)
        #expect(step.status == .passed)
    }

    @Test func `failed receipt exposes derived failure facts`() {
        let result = HeistReceiptFixture.result(
            steps: [HeistReceiptFixture.explicitFailure(path: "$.body[4]", message: "stop")]
        )

        #expect(result.isFailure)
        #expect(result.abortedAtPath == "$.body[4]")
        #expect(result.steps.first?.failure?.observed == "stop")
    }
}
