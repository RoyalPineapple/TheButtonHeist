import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistReceiptPublicAPIContractTests {
    @Test func `contradictory receipt factories are package scoped`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contracts = [
            (
                path: "Sources/TheScore/Receipts/HeistExecutionStepResult.swift",
                packageDeclarations: [
                    "package struct HeistStepReceiptKind",
                    "package static func passed(",
                    "package static func passed<",
                    "package static func failed(",
                    "package static func failed<",
                    "package static func childAborted",
                    "package static func skipped(",
                ]
            ),
            (
                path: "Sources/TheScore/Receipts/HeistExecutionResult.swift",
                packageDeclarations: [
                    "package static func passed(",
                    "package static func failed(",
                ]
            ),
            (
                path: "Sources/TheScore/Reports/HeistJUnitReport.swift",
                packageDeclarations: [
                    "package static func passed(",
                    "package static func failed(",
                ]
            ),
        ]

        for contract in contracts {
            let source = try String(
                contentsOf: root.appendingPathComponent(contract.path),
                encoding: .utf8
            )
            for declaration in contract.packageDeclarations {
                #expect(source.contains(declaration), "\(contract.path): \(declaration)")
            }
            #expect(!source.contains("public static func passed("), "\(contract.path)")
            #expect(!source.contains("public static func passed<"), "\(contract.path)")
            #expect(!source.contains("public static func failed("), "\(contract.path)")
            #expect(!source.contains("public static func failed<"), "\(contract.path)")
            #expect(!source.contains("public static func childAborted"), "\(contract.path)")
            #expect(!source.contains("public static func skipped("), "\(contract.path)")
            if contract.path.contains("/Receipts/") {
                #expect(source.contains("public init(from decoder: Decoder) throws"), "\(contract.path)")
            }
        }
    }

    @Test func `decode rejects structural evidence that contradicts failed outcome`() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let matched = try #require(ExpectationResult.Met(ExpectationResult(
            met: true,
            predicate: predicate
        )))
        let waitCheck = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(method: .wait, evidence: .none),
            expectation: matched
        ))
        let fixtures: [(HeistExecutionStepResult, String)] = [
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .wait,
                    durationMs: 1,
                    evidence: HeistWaitEvidence.matched(waitCheck)
                ),
                "failed wait step requires failed wait evidence outcome"
            ),
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .forEachString,
                    durationMs: 1,
                    evidence: HeistForEachStringEvidence(
                        parameter: "item",
                        count: 1,
                        iterationCount: 1
                    )
                ),
                "failed loop step requires failure reason evidence"
            ),
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .forEachElement,
                    durationMs: 1,
                    evidence: HeistForEachElementEvidence(
                        parameter: "item",
                        matching: ElementPredicate(label: "Cell"),
                        limit: 1,
                        matchedCount: 1,
                        iterationCount: 1
                    )
                ),
                "failed loop step requires failure reason evidence"
            ),
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .repeatUntil,
                    durationMs: 1,
                    evidence: HeistRepeatUntilEvidence.predicateMet(
                        predicate: predicate,
                        timeout: 1,
                        iterationCount: 1,
                        expectation: matched
                    )
                ),
                "failed repeat_until step requires failed repeat_until evidence outcome"
            ),
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .invocation,
                    durationMs: 1,
                    evidence: HeistInvocationEvidence.invocation(
                        invocation: HeistInvocationStep(path: ["checkout"]),
                        name: "checkout",
                        argument: nil,
                        outcome: .completed(expectation: nil)
                    )
                ),
                "failed invocation step requires child failure evidence"
            ),
            (
                .passed(
                    path: "$.body[0]",
                    receiptKind: .heist,
                    durationMs: 1,
                    evidence: HeistInvocationEvidence.heist(
                        name: "nested",
                        childFailedPath: nil
                    )
                ),
                "failed invocation step requires child failure evidence"
            ),
        ]

        for (step, message) in fixtures {
            expectDecodingFailure(try failedReceiptData(from: step), message: message)
        }
    }

    @Test func `child aborted structural evidence keeps its own polarity`() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let unmatched = try #require(HeistWaitEvidence.UnmatchedCheck(
            actionResult: .success(method: .wait, evidence: .none),
            expectation: ExpectationResult(met: false, predicate: predicate)
        ))
        let failedChild = explicitFailureStep(path: "$.body[0].else[0]")
        let step = HeistExecutionStepResult.childAborted(
            path: "$.body[0]",
            receiptKind: .wait,
            durationMs: 1,
            evidence: HeistWaitEvidence.handledElse(unmatched),
            failure: failure,
            child: failedChild
        )

        let decoded = try JSONDecoder().decode(
            HeistExecutionStepResult.self,
            from: JSONEncoder().encode(step)
        )

        #expect(decoded == step)
    }

    private var failure: HeistFailureDetail {
        HeistFailureDetail(
            category: .explicitFailure,
            contract: "step succeeds",
            observed: "failed"
        )
    }

    private func explicitFailureStep(path: String) -> HeistExecutionStepResult {
        .failed(path: path, kind: .fail, durationMs: 1, failure: failure)
    }

    private func failedReceiptData(from step: HeistExecutionStepResult) throws -> Data {
        var object = try jsonObject(step)
        var outcome = try #require(object["outcome"] as? [String: Any])
        outcome["type"] = "failed"
        outcome["failure"] = try jsonObject(failure)
        object["outcome"] = outcome
        return try JSONSerialization.data(withJSONObject: object)
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
