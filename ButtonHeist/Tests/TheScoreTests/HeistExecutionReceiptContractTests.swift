import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistExecutionReceiptContractTests {
    @Test func `semantic nodes round trip through their single codec owner`() throws {
        let steps = try [
            HeistReceiptFixture.action(),
            HeistReceiptFixture.warning(path: "$.body[1]", message: "notice"),
            HeistReceiptFixture.explicitFailure(path: "$.body[2]", message: "stop"),
        ] + relationshipSteps()

        #expect(steps[1].kind == .warn)
        #expect(steps[2].kind == .fail)
        for step in steps {
            let data = try JSONEncoder().encode(step)
            #expect(try JSONDecoder().decode(HeistExecutionStepResult.self, from: data) == step)
        }
    }

    @Test func `step encoding owns semantics and completion in one node`() throws {
        let object = try jsonObject(HeistReceiptFixture.warning(message: "notice"))

        #expect(Set(object.keys) == ["path", "durationMs", "node"])
        let node = try #require(object["node"] as? [String: Any])
        #expect(node["type"] as? String == "warning")
        #expect(node["outcome"] as? String == "passed")
        #expect(node["message"] as? String == "notice")
        #expect(node["children"] is [Any])
    }

    @Test func `decode rejects unknown missing and incompatible node fields`() {
        let malformed = [
            #"{"path":"$.body[0]","durationMs":1,"node":{"type":"warning","outcome":"passed","message":"notice","children":[],"extra":true}}"#,
            #"{"path":"$.body[0]","durationMs":1,"node":{"type":"warning","outcome":"passed","children":[]}}"#,
            #"{"path":"$.body[0]","durationMs":1,"node":{"type":"warning","outcome":"failed","message":"notice","failure":{"category":"explicitFailure","#
                + #"contract":"x","observed":"y"},"children":[]}}"#,
            #"{"path":"$.body[0]","durationMs":1,"node":{"type":"unknown","outcome":"passed","children":[]}}"#,
        ]

        for receipt in malformed {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: Data(receipt.utf8))
            }
        }
    }

    @Test func `decode rejects malformed external receipt relationships`() throws {
        let steps = try relationshipSteps()
        let malformed = try [
            replacingNode(in: steps[0]) { node in
                node["command"] = try jsonValue(HeistActionCommand.magicTap)
            },
            replacingNode(in: steps[1]) { node in
                node["count"] = 1
            },
            replacingNode(in: steps[2]) { node in
                node["type"] = "for_each_string"
            },
            replacingNode(in: steps[4]) { node in
                node["type"] = "for_each_element"
            },
            replacingNode(in: steps[5]) { node in
                node["predicate"] = try jsonValue(AccessibilityPredicate.exists(.label("Other")))
            },
            replacingNode(in: steps[6]) { node in
                node["type"] = "repeat_until"
            },
        ]

        for object in malformed {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: data)
            }
        }
    }

    @Test func `execution result derives failure and has no parallel outcome fields`() throws {
        let result = HeistReceiptFixture.result(
            steps: [HeistReceiptFixture.explicitFailure(message: "stop")],
            durationMs: 3
        )
        let object = try jsonObject(result)

        #expect(result.isFailure)
        #expect(result.abortedAtPath == "$.body[0]")
        #expect(Set(object.keys) == ["steps", "durationMs"])
        #expect(try JSONDecoder().decode(
            HeistExecutionResult.self,
            from: JSONSerialization.data(withJSONObject: object)
        ) == result)
    }

    @Test func `element loop construction accepts only explicit over-limit failure evidence`() throws {
        let declaration = try #require(HeistForEachElementDeclaration(
            parameter: "item",
            matching: ElementPredicateTemplate(label: "Row"),
            limit: 1
        ))
        let passedEvidence = HeistForEachElementEvidence(
            matchedCount: 2,
            iterationCount: 1
        ).flatMap(HeistPassedForEachElementEvidence.init)
        let failedEvidence = HeistForEachElementEvidence(
            matchedCount: 2,
            iterationCount: 0,
            failureReason: "matched count exceeded limit"
        ).flatMap(HeistFailedForEachElementEvidence.init)

        let invalid = HeistExecutionStepResult.construct(
            path: "$.body[0]",
            durationMs: 1,
            node: .forEachElement(
                declaration: declaration,
                completion: .passed(evidence: try #require(passedEvidence))
            )
        )
        guard case .failure(let error) = invalid else {
            Issue.record("Expected over-limit passing evidence to be rejected")
            return
        }
        #expect(error == .forEachElementEvidenceMismatch)

        let valid = try HeistExecutionStepResult.construct(
            path: "$.body[0]",
            durationMs: 1,
            node: .forEachElement(
                declaration: declaration,
                completion: .failed(
                    evidence: .observed(try #require(failedEvidence)),
                    failure: .init(
                        category: .loop,
                        contract: "matched count does not exceed limit",
                        observed: "matched count exceeded limit"
                    )
                )
            )
        ).get()
        #expect(valid.kind == .forEachElement)
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func relationshipSteps() throws -> [HeistExecutionStepResult] {
        let stringDeclaration = try #require(HeistForEachStringDeclaration(parameter: "item", count: 2))
        let stringSummary = try #require(HeistForEachStringEvidence(iterationCount: 2))
        let elementDeclaration = try #require(HeistForEachElementDeclaration(
            parameter: "item",
            matching: ElementPredicateTemplate(label: "Row"),
            limit: 2
        ))
        let elementSummary = try #require(HeistForEachElementEvidence(matchedCount: 1, iterationCount: 1))
        let elementIteration = try #require(HeistForEachElementEvidence(
            matchedCount: 1,
            iterationCount: 1,
            iterationOrdinal: 0,
            targetOrdinal: 0,
            targetSummary: "Row"
        ))
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let repeatDeclaration = HeistRepeatUntilDeclaration(predicate: predicate, timeout: 1)
        let repeatSummary = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        let repeatIteration = try #require(HeistRepeatUntilEvidence.continued(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: ExpectationResult.Unmet(predicate: predicate)
        ))
        let passedStringSummary = try #require(HeistPassedForEachStringEvidence(stringSummary))
        let passedElementSummary = try #require(HeistPassedForEachElementEvidence(elementSummary))
        let passedElementIteration = try #require(HeistPassedForEachElementEvidence(elementIteration))
        let passedRepeatSummary = try #require(HeistPassedRepeatUntilEvidence(repeatSummary))
        let passedRepeatIteration = try #require(HeistPassedRepeatUntilIterationEvidence(repeatIteration))

        return [
            HeistReceiptFixture.action(command: .dismiss, result: .success(method: .dismiss)),
            try HeistExecutionStepResult.construct(
                path: "$.body[1]",
                durationMs: 1,
                node: .forEachString(
                    declaration: stringDeclaration,
                    completion: .passed(evidence: passedStringSummary)
                )
            ).get(),
            HeistReceiptFixture.forEachStringIteration(
                path: "$.body[2].for_each_string.iterations[0]",
                count: 2,
                iterationCount: 1,
                ordinal: 0,
                value: "one",
                status: .passed,
                children: []
            ),
            try HeistExecutionStepResult.construct(
                path: "$.body[3]",
                durationMs: 1,
                node: .forEachElement(
                    declaration: elementDeclaration,
                    completion: .passed(evidence: passedElementSummary)
                )
            ).get(),
            try HeistExecutionStepResult.construct(
                path: "$.body[4].for_each_element.iterations[0]",
                durationMs: 1,
                node: .forEachElementIteration(
                    declaration: elementDeclaration,
                    completion: .passed(evidence: passedElementIteration)
                )
            ).get(),
            try HeistExecutionStepResult.construct(
                path: "$.body[5]",
                durationMs: 1,
                node: .repeatUntil(
                    declaration: repeatDeclaration,
                    completion: .passed(evidence: passedRepeatSummary)
                )
            ).get(),
            try HeistExecutionStepResult.construct(
                path: "$.body[6].repeat_until.iterations[0]",
                durationMs: 1,
                node: .repeatUntilIteration(
                    declaration: repeatDeclaration,
                    completion: .passed(evidence: passedRepeatIteration)
                )
            ).get(),
        ]
    }

    private func replacingNode(
        in step: HeistExecutionStepResult,
        update: (inout [String: Any]) throws -> Void
    ) throws -> [String: Any] {
        var object = try jsonObject(step)
        var node = try #require(object["node"] as? [String: Any])
        try update(&node)
        object["node"] = node
        return object
    }

    private func jsonValue<Value: Encodable>(_ value: Value) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
