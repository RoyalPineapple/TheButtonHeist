import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistResultPublicAPIContractTests {
    @Test func `evidence admission permits only its legal completion polarity`() {
        let passedAction = HeistActionEvidence.completed(
            result: .success(payload: .dismiss),
            expectation: nil
        )
        let failedAction = HeistActionEvidence.completed(
            result: .failure(payload: .dismiss, failureKind: .actionFailed),
            expectation: nil
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

    @Test func `strict decoder rejects removed expectationResult form`() {
        let oldForm = Data(
            """
            {
              "type": "expectation",
              "expectationResult": {}
            }
            """.utf8
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HeistActionEvidence.self, from: oldForm)
        }
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
