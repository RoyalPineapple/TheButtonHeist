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
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heist-receipt-codec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipt.json.gz")
        try HeistReceiptCodec.write(receipt, to: url)

        let decoded = try HeistReceiptCodec.decode(contentsOf: url)

        #expect(decoded == receipt)
    }

    @Test func `valid success receipt keeps stable external JSON shape`() throws {
        let data = try HeistReceiptCodec.encode(sampleReceipt(), format: .json)

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        let step = try #require(steps.first)

        #expect(object.keys.contains("outcome") == false)
        #expect(object.keys.contains("abortedAtPath") == false)
        #expect(step["path"] as? String == "$.body[0]")
        #expect(step["kind"] as? String == "action")
        #expect(step["status"] as? String == "passed")
        #expect(step.keys.contains("outcome") == false)
        #expect(step.keys.contains("failure") == false)
        #expect(step["evidence"] != nil)
        #expect((step["children"] as? [Any])?.isEmpty == true)
    }

    @Test func `valid failure receipt decodes with required failure facts`() throws {
        let receipt = failedReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .json)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        let step = try #require(steps.first)

        #expect(decoded == receipt)
        #expect(decoded.abortedAtPath == "$.body[0]")
        #expect(decoded.steps.first?.failure?.observed == "stop")
        #expect(object["abortedAtPath"] as? String == "$.body[0]")
        #expect(step["status"] as? String == "failed")
        #expect(step["failure"] != nil)
    }

    @Test func `decode rejects passed step with failure facts`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "status": "passed",
              "durationMs": 1,
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
            containing: "passed heist execution step must not include failure"
        )
    }

    @Test func `decode rejects failed step without failure facts`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "status": "failed",
              "durationMs": 1,
              "children": []
            }
          ],
          "durationMs": 1,
          "abortedAtPath": "$.body[0]"
        }
        """

        try expectReceiptDecodeError(
            json,
            containing: "failed heist execution step must include failure"
        )
    }

    @Test func `decode rejects failed heist without abort path`() throws {
        let json = """
        {
          "steps": [
            {
              "path": "$.body[0]",
              "kind": "fail",
              "status": "failed",
              "durationMs": 1,
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
              "status": "failed",
              "durationMs": 1,
              "failure": {
                "category": "explicitFailure",
                "contract": "Fail",
                "observed": "stop"
              },
              "children": []
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
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            subjectEvidence: ActionSubjectEvidence(
                source: .resolvedSemanticTarget,
                target: .predicate(.label("Checkout")),
                element: element(label: "Checkout", traits: [.button], actions: [.activate])
            )
        )
        return HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .action,
                    status: .passed,
                    durationMs: 12,
                    intent: .action(command: "Activate", target: "target(predicate(label=\"Checkout\"))"),
                    evidence: .action(HeistActionEvidence(
                        command: .activate(.predicate(.label("Checkout"))),
                        actionResult: result,
                        expectation: ExpectationResult(met: true, predicate: nil, actual: "screenChanged")
                    ))
                ),
            ],
            durationMs: 12
        )
    }

    private func failedReceipt() -> HeistExecutionResult {
        HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .fail,
                    status: .failed,
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
        do {
            _ = try HeistReceiptCodec.decode(Data(json.utf8), format: .json)
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
