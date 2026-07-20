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

    @Test func `failed result exposes derived failure facts`() {
        let result = HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(path: "$.body[0]", message: "stop")]
        )

        #expect(result.isFailure)
        #expect(result.abortedAtPath == "$.body[0]")
        #expect(result.steps.first?.failure?.observed == "stop")
    }
}
