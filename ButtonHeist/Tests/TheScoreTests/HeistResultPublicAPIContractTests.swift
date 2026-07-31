import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistResultPublicAPIContractTests {
    @Test func `evidence admission permits only its legal completion polarity`() {
        let passedAction = HeistActionEvidence.completed(
            result: .success(payload: .dismiss),
            expectation: HeistResultFixture.defaultActionExpectationEvidence()
        )
        let failedAction = HeistActionEvidence.completed(
            result: .failure(payload: .dismiss, failureKind: .actionFailed),
            expectation: HeistResultFixture.defaultActionExpectationEvidence()
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

    @Test func `completed action evidence requires its structural expectation`() throws {
        let evidence = HeistActionEvidence.completed(
            result: .success(payload: .dismiss),
            expectation: HeistResultFixture.defaultActionExpectationEvidence()
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any]
        )
        object.removeValue(forKey: "expectationEvidence")

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                HeistActionEvidence.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func `failed result exposes derived failure facts`() {
        let result = HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(path: "$.body[0]", message: "stop")]
        )

        #expect(result.isFailure)
        #expect(result.steps.first?.failure?.observed == "stop")
    }
}
