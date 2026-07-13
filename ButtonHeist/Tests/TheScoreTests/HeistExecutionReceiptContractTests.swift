import Foundation
import Testing
import TheScore

@Suite struct HeistExecutionReceiptContractTests {
    @Test func `step encoding renders only the tagged outcome`() throws {
        let step = HeistExecutionStepResult.failed(
            path: "$.body[0]",
            kind: .fail,
            durationMs: 3,
            failure: failure
        )

        let object = try jsonObject(step)
        #expect(Set(object.keys) == ["path", "kind", "durationMs", "outcome"])
        let outcome = try #require(object["outcome"] as? [String: Any])
        #expect(Set(outcome.keys) == ["type", "failure", "children"])
        #expect(outcome["type"] as? String == "failed")
    }

    @Test func `decode rejects flattened optional bag step receipt`() throws {
        let oldReceipt = """
        {
          "path": "$.body[0]",
          "kind": "fail",
          "durationMs": 3,
          "status": "failed",
          "failure": {
            "category": "explicitFailure",
            "contract": "step succeeds",
            "observed": "failed"
          },
          "children": []
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: Data(oldReceipt.utf8))
        }
    }

    @Test func `decode rejects fields incompatible with tagged step outcome`() throws {
        let invalidOutcomes = [
            #"{"type":"passed","failure":{},"children":[]}"#,
            #"{"type":"failed","abortedAtChildPath":"$.body[0]","failure":{},"children":[]}"#,
            #"{"type":"skipped","evidence":{},"children":[]}"#,
            #"{"type":"child_aborted","failure":{},"abortedAtChildPath":"$.body[0]","children":[]}"#,
        ]

        for outcome in invalidOutcomes {
            let receipt = """
            {
              "path": "$.body[0]",
              "kind": "fail",
              "durationMs": 3,
              "outcome": \(outcome)
            }
            """
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: Data(receipt.utf8))
            }
        }
    }

    @Test func `decode rejects evidence with more than one typed owner`() {
        let receipt = """
        {
          "path": "$.body[0]",
          "kind": "warn",
          "durationMs": 1,
          "outcome": {
            "type": "passed",
            "evidence": {
              "warning": {"_0": {"path": "$.body[0]", "message": "notice"}},
              "action": {"_0": {"path": "$.body[0]", "message": "notice"}}
            },
            "children": []
          }
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: Data(receipt.utf8))
        }
    }

    @Test func `valid action warning fail and expectation outcomes round trip`() throws {
        let failedChild = explicitFailureStep(path: "$.body[0].children[0]")
        let steps = [
            actionStep(outcome: .passed, evidence: successfulDispatchEvidence),
            actionStep(outcome: .failed, evidence: failedDispatchEvidence),
            HeistExecutionStepResult.childAborted(
                path: "$.body[0]",
                receiptKind: .action,
                durationMs: 1,
                evidence: successfulDispatchEvidence,
                failure: failure,
                child: failedChild
            ),
            .passed(
                path: "$.body[0]",
                receiptKind: .warning,
                durationMs: 1,
                evidence: HeistExecutionWarning(path: "$.body[0]", message: "notice")
            ),
            explicitFailureStep(),
            actionStep(outcome: .passed, evidence: metExpectationEvidence),
            actionStep(outcome: .failed, evidence: unmetExpectationEvidence),
        ]

        for step in steps {
            let decoded = try JSONDecoder().decode(
                HeistExecutionStepResult.self,
                from: JSONEncoder().encode(step)
            )
            #expect(decoded == step)
        }
    }

    @Test func `decode rejects passed fail and failed warning outcomes`() throws {
        let passedFail = try receiptData(explicitFailureStep()) { outcome in
            outcome["type"] = "passed"
            outcome.removeValue(forKey: "failure")
        }
        expectDecodingFailure(
            passedFail,
            message: "fail heist execution step must use failed or skipped outcome"
        )

        let failedWarning = try receiptData(
            .passed(
                path: "$.body[0]",
                receiptKind: .warning,
                durationMs: 1,
                evidence: HeistExecutionWarning(path: "$.body[0]", message: "notice")
            )
        ) { outcome in
            outcome["type"] = "failed"
            outcome["failure"] = try jsonObject(failure)
        }
        expectDecodingFailure(
            failedWarning,
            message: "warn heist execution step must use passed or skipped outcome"
        )
    }

    @Test func `decode rejects action evidence that contradicts receipt outcome`() throws {
        let passedResolutionFailure = try receiptData(
            actionStep(outcome: .failed, evidence: .commandResolutionFailure(command: .dismiss))
        ) { outcome in
            outcome["type"] = "passed"
            outcome.removeValue(forKey: "failure")
        }
        expectDecodingFailure(
            passedResolutionFailure,
            message: "passed action heist execution step requires successful action evidence"
        )

        let failedSuccessfulExpectation = try receiptData(
            actionStep(outcome: .passed, evidence: metExpectationEvidence)
        ) { outcome in
            outcome["type"] = "failed"
            outcome["failure"] = try jsonObject(failure)
        }
        expectDecodingFailure(
            failedSuccessfulExpectation,
            message: "failed action heist execution step requires failed action evidence"
        )

        let passedFailedExpectation = try receiptData(
            actionStep(outcome: .failed, evidence: unmetExpectationEvidence)
        ) { outcome in
            outcome["type"] = "passed"
            outcome.removeValue(forKey: "failure")
        }
        expectDecodingFailure(
            passedFailedExpectation,
            message: "passed action heist execution step requires successful action evidence"
        )

        let failedChild = explicitFailureStep(path: "$.body[0].children[0]")
        let abortedFailedDispatch = try receiptData(
            actionStep(outcome: .failed, evidence: failedDispatchEvidence)
        ) { outcome in
            outcome["type"] = "child_aborted"
            outcome["abortedAtChildPath"] = failedChild.path
            outcome["children"] = [try jsonObject(failedChild)]
        }
        expectDecodingFailure(
            abortedFailedDispatch,
            message: "child_aborted action heist execution step requires successful action evidence"
        )
    }

    @Test func `decode rejects action command and expectation result binding contradictions`() throws {
        let mismatchedMethod = try receiptData(
            actionStep(outcome: .passed, evidence: successfulDispatchEvidence)
        ) { outcome in
            try mutateActionEvidence(in: &outcome) { evidence in
                var result = try #require(evidence["dispatchResult"] as? [String: Any])
                result["method"] = "activate"
                evidence["dispatchResult"] = result
            }
        }
        expectDecodingFailure(
            mismatchedMethod,
            message: "action command dismiss requires dismiss result method, got activate"
        )

        let failedExpectationDispatch = try receiptData(
            actionStep(outcome: .passed, evidence: metExpectationEvidence)
        ) { outcome in
            try mutateActionEvidence(in: &outcome) { evidence in
                evidence["dispatchResult"] = try jsonObject(ActionResult.failure(
                    method: .dismiss,
                    errorKind: .actionFailed,
                    evidence: .none
                ))
            }
        }
        expectDecodingFailure(
            failedExpectationDispatch,
            message: "action expectation evidence requires successful dispatch result"
        )

        let wrongExpectationMethod = try receiptData(
            actionStep(outcome: .passed, evidence: metExpectationEvidence)
        ) { outcome in
            try mutateActionEvidence(in: &outcome) { evidence in
                var result = try #require(evidence["expectationResult"] as? [String: Any])
                result["method"] = "activate"
                evidence["expectationResult"] = result
            }
        }
        expectDecodingFailure(
            wrongExpectationMethod,
            message: "action expectation result method must be wait, got activate"
        )

        let successBoundToUnmetExpectation = try receiptData(
            actionStep(outcome: .passed, evidence: metExpectationEvidence)
        ) { outcome in
            try mutateActionEvidence(in: &outcome) { evidence in
                var expectation = try #require(evidence["expectation"] as? [String: Any])
                expectation["met"] = false
                evidence["expectation"] = expectation
            }
        }
        expectDecodingFailure(
            successBoundToUnmetExpectation,
            message: "action expectation result success must match expectation met=false"
        )

        let failureBoundToMetExpectation = try receiptData(
            actionStep(outcome: .failed, evidence: unmetExpectationEvidence)
        ) { outcome in
            try mutateActionEvidence(in: &outcome) { evidence in
                var expectation = try #require(evidence["expectation"] as? [String: Any])
                expectation["met"] = true
                evidence["expectation"] = expectation
            }
        }
        expectDecodingFailure(
            failureBoundToMetExpectation,
            message: "action expectation result success must match expectation met=true"
        )
    }

    @Test func `execution decode rejects missing or stray abort path`() throws {
        let failedStep = HeistExecutionStepResult.failed(
            path: "$.body[0]",
            kind: .fail,
            durationMs: 3,
            failure: failure
        )
        let failedResult = HeistExecutionResult.failed(
            steps: [failedStep],
            durationMs: 3,
            abortedAtPath: failedStep.path
        )
        var failedObject = try jsonObject(failedResult)
        failedObject.removeValue(forKey: "abortedAtPath")

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                HeistExecutionResult.self,
                from: JSONSerialization.data(withJSONObject: failedObject)
            )
        }

        var passedObject = try jsonObject(HeistExecutionResult.passed(steps: [], durationMs: 0))
        passedObject["abortedAtPath"] = "$.body[0]"

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                HeistExecutionResult.self,
                from: JSONSerialization.data(withJSONObject: passedObject)
            )
        }
    }

    private var failure: HeistFailureDetail {
        HeistFailureDetail(
            category: .explicitFailure,
            contract: "step succeeds",
            observed: "failed"
        )
    }

    private enum ActionStepOutcome {
        case passed
        case failed
    }

    private var successfulDispatchEvidence: HeistActionEvidence {
        .dispatch(
            command: .dismiss,
            dispatchResult: .success(method: .dismiss, evidence: .none)
        )
    }

    private var failedDispatchEvidence: HeistActionEvidence {
        .dispatch(
            command: .dismiss,
            dispatchResult: .failure(method: .dismiss, errorKind: .actionFailed, evidence: .none)
        )
    }

    private var metExpectationEvidence: HeistActionEvidence {
        .expectation(
            command: .dismiss,
            dispatchResult: .success(method: .dismiss, evidence: .none),
            expectationResult: .success(method: .wait, evidence: .none),
            expectation: ExpectationResult(met: true, predicate: nil)
        )
    }

    private var unmetExpectationEvidence: HeistActionEvidence {
        .expectation(
            command: .dismiss,
            dispatchResult: .success(method: .dismiss, evidence: .none),
            expectationResult: .failure(method: .wait, errorKind: .timeout, evidence: .none),
            expectation: ExpectationResult(met: false, predicate: nil)
        )
    }

    private func actionStep(
        outcome: ActionStepOutcome,
        evidence: HeistActionEvidence
    ) -> HeistExecutionStepResult {
        switch outcome {
        case .passed:
            return .passed(
                path: "$.body[0]",
                receiptKind: .action,
                durationMs: 1,
                evidence: evidence
            )
        case .failed:
            return .failed(
                path: "$.body[0]",
                receiptKind: .action,
                durationMs: 1,
                evidence: evidence,
                failure: failure
            )
        }
    }

    private func explicitFailureStep(path: String = "$.body[0]") -> HeistExecutionStepResult {
        .failed(path: path, kind: .fail, durationMs: 1, failure: failure)
    }

    private func receiptData(
        _ step: HeistExecutionStepResult,
        mutatingOutcome: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try jsonObject(step)
        var outcome = try #require(object["outcome"] as? [String: Any])
        try mutatingOutcome(&outcome)
        object["outcome"] = outcome
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func mutateActionEvidence(
        in outcome: inout [String: Any],
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        var evidence = try #require(outcome["evidence"] as? [String: Any])
        var actionContainer = try #require(evidence["action"] as? [String: Any])
        var actionEvidence = try #require(actionContainer["_0"] as? [String: Any])
        try mutation(&actionEvidence)
        actionContainer["_0"] = actionEvidence
        evidence["action"] = actionContainer
        outcome["evidence"] = evidence
    }

    private func expectDecodingFailure(_ data: Data, message: String) {
        do {
            _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: data)
            Issue.record("Expected heist execution step decoding to fail")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription == message)
        } catch {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
        }
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
