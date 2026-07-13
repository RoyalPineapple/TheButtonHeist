import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistReceiptCodecTests {

    @Test func `decode plain heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .json)

        #expect(decoded == receipt)
    }

    @Test func `decode gzip heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .gzipJSON)
        let jsonData = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .gzipJSON)

        #expect(decoded == receipt)
        #expect(data.count < jsonData.count)
    }

    @Test func `round trip gzip receipt from file extension`() throws {
        let receipt = sampleReceipt()
        try withReceiptDirectory(prefix: "heist-receipt-codec") { directory in
            let url = directory.appendingPathComponent("receipt.json.gz")
            try HeistReceiptCodec.write(receipt, to: url)

            let decoded = try HeistReceiptCodec.decode(contentsOf: url)

            #expect(decoded == receipt)
        }
    }

    @Test func `valid success receipt keeps stable external JSON shape`() throws {
        let data = try HeistReceiptCodec.encode(sampleReceipt(), format: .json)

        let object = try JSONProbe(data: data)
        let steps = try object.array("steps")
        let step = try #require(steps.first)

        try object.assertMissing("outcome")
        try object.assertMissing("abortedAtPath")
        #expect(try step.string("path") == "$.body[0]")
        #expect(try step.string("kind") == "action")
        try step.assertMissing("status")
        let outcome = try step.object("outcome")
        #expect(try outcome.string("type") == "passed")
        try step.assertMissing("failure")
        try step.assertMissing("evidence")
        try outcome.assertPresent("evidence")
        #expect(try outcome.array("children").isEmpty)
    }

    @Test func `valid failure receipt decodes with required failure facts`() throws {
        let receipt = failedReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .json)
        let object = try JSONProbe(data: data)
        let steps = try object.array("steps")
        let step = try #require(steps.first)

        #expect(decoded == receipt)
        #expect(decoded.abortedAtPath == "$.body[0]")
        #expect(decoded.steps.first?.failure?.observed == "stop")
        #expect(try object.string("abortedAtPath") == "$.body[0]")
        try step.assertMissing("status")
        try step.assertMissing("failure")
        let outcome = try step.object("outcome")
        #expect(try outcome.string("type") == "failed")
        try outcome.assertPresent("failure")
    }

    @Test func `decode rejects old status evidence failure step bag`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "status": "passed",
              "durationMs": 1,
              "evidence": null,
              "failure": {
                "category": "explicitFailure",
                "contract": "Fail",
                "observed": "stop"
              },
              "children": []
            }
          ],
          "durationMs": 1
        }
        """

        try expectReceiptDecodeError(
            json,
            containing: "Unknown heist execution step result field"
        )
    }

    @Test func `decode rejects fields incompatible with tagged step outcome`() throws {
        let invalidOutcomes = [
            (
                #"{"type":"passed","failure":{},"children":[]}"#,
                "passed heist execution step outcome cannot include failure"
            ),
            (
                #"{"type":"failed","abortedAtChildPath":"$.body[0]","failure":{},"children":[]}"#,
                "failed heist execution step outcome cannot include abortedAtChildPath"
            ),
            (
                #"{"type":"skipped","evidence":{},"children":[]}"#,
                "skipped heist execution step outcome cannot include evidence"
            ),
            (
                #"{"type":"child_aborted","status":"failed","children":[]}"#,
                "Unknown heist execution step outcome field \"status\""
            ),
        ]

        for (outcome, expectedError) in invalidOutcomes {
            let json = """
            {
              "steps": [
                {
                  "path": "$.body[0]",
                  "kind": "fail",
                  "durationMs": 1,
                  "outcome": \(outcome)
                }
              ],
              "durationMs": 1
            }
            """

            try expectReceiptDecodeError(json, containing: expectedError)
        }
    }

    @Test func `decode rejects malformed action evidence enum shapes`() throws {
        let data = try HeistReceiptCodec.encode(sampleReceipt(), format: .json)
        let receipt = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try #require(receipt["steps"] as? [[String: Any]])
        let step = try #require(steps.first)
        let outcome = try #require(step["outcome"] as? [String: Any])
        let evidence = try #require(outcome["evidence"] as? [String: Any])
        let action = try #require(evidence["action"] as? [String: Any])
        let unwrappedAction = try #require(action["_0"] as? [String: Any])
        var actionWithLegacyField = action
        actionWithLegacyField["legacy"] = true

        let invalidEvidence = [
            (unwrappedAction, "Unknown heist step evidence field"),
            (["action": actionWithLegacyField], "Unknown heist step evidence payload field \"legacy\""),
            (["action": action, "wait": action], "heist step evidence must contain exactly one evidence case"),
        ]

        for (replacement, expectedError) in invalidEvidence {
            var malformedOutcome = outcome
            malformedOutcome["evidence"] = replacement
            var malformedStep = step
            malformedStep["outcome"] = malformedOutcome
            var malformedSteps = steps
            malformedSteps[0] = malformedStep
            var malformedReceipt = receipt
            malformedReceipt["steps"] = malformedSteps

            try expectReceiptDecodeError(
                JSONSerialization.data(withJSONObject: malformedReceipt),
                containing: expectedError
            )
        }
    }

    @Test func `decode rejects failed step without failure facts`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "durationMs": 1,
              "outcome": {
                "type": "failed",
                "children": []
              }
            }
          ],
          "durationMs": 1,
          "abortedAtPath": "$.body[0]"
        }
        """

        try expectReceiptDecodeError(
            json,
            containing: "failed heist execution step outcome must include failure"
        )
    }

    @Test func `decode rejects failed heist without abort path`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "durationMs": 1,
              "outcome": {
                "type": "failed",
                "failure": {
                  "category": "explicitFailure",
                  "contract": "Fail",
                  "observed": "stop"
                },
                "children": []
              }
            }
          ],
          "durationMs": 1
        }
        """

        try expectReceiptDecodeError(
            json,
            containing: "failed heist execution result must include abortedAtPath for $.body[0]"
        )
    }

    @Test func `decode rejects abort path that disagrees with first failed step`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "durationMs": 1,
              "outcome": {
                "type": "failed",
                "failure": {
                  "category": "explicitFailure",
                  "contract": "Fail",
                  "observed": "stop"
                },
                "children": []
              }
            }
          ],
          "durationMs": 1,
          "abortedAtPath": "$.body[1]"
        }
        """

        try expectReceiptDecodeError(
            json,
            containing: "heist execution abortedAtPath $.body[1] must match first failed step $.body[0]"
        )
    }

    private func sampleReceipt() -> HeistExecutionResult {
        let before = makeTestInterface(elements: [
            element(label: "Checkout", traits: [.button], actions: [.activate]),
        ])
        let after = makeTestInterface(elements: [
            element(label: "Review Order", traits: [.header]),
        ])
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "checkout")
        )
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(
                observation: .trace(trace),
                subjectEvidence: ActionSubjectEvidence(
                    source: .resolvedSemanticTarget,
                    target: .predicate(.label("Checkout")),
                    element: element(label: "Checkout", traits: [.button], actions: [.activate])
                )
            )
        )
        return HeistExecutionResult(
            steps: [
                .passed(
                    path: "$.body[0]",
                    receiptKind: .action,
                    durationMs: 12,
                    intent: .action(command: .activate(.predicate(.label("Checkout")))),
                    evidence: .expectation(
                        command: .activate(.predicate(.label("Checkout"))),
                        dispatchResult: result,
                        expectationResult: ActionResult.success(method: .wait, message: "screenChanged", evidence: .none),
                        expectation: ExpectationResult(met: true, predicate: nil, actual: "screenChanged")
                    )
                ),
            ],
            durationMs: 12
        )
    }

    private func failedReceipt() -> HeistExecutionResult {
        HeistExecutionResult(
            steps: [
                .failed(
                    path: "$.body[0]",
                    kind: .fail,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail",
                        observed: "stop"
                    )
                ),
            ],
            durationMs: 1,
            abortedAtPath: "$.body[0]"
        )
    }

    private func expectReceiptDecodeError(
        _ json: String,
        containing substring: String
    ) throws {
        try expectReceiptDecodeError(Data(json.utf8), containing: substring)
    }

    private func expectReceiptDecodeError(
        _ data: Data,
        containing substring: String
    ) throws {
        do {
            _ = try HeistReceiptCodec.decode(data, format: .json)
            Issue.record("Expected receipt decode to fail")
        } catch {
            let description = String(describing: error)
            #expect(description.contains(substring), "\(description) did not contain \(substring)")
        }
    }

    private func element(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            description: label ?? "element",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: actions
        )
    }
}
