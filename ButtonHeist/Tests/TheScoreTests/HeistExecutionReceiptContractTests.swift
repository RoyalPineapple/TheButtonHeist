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

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
