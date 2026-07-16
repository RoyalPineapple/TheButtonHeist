import ButtonHeistTestSupport
import Foundation
import Testing
import TheScore

@Suite struct HeistExecutionReceiptContractTests {
    @Test func `semantic nodes round trip through their single codec owner`() throws {
        let steps = [
            HeistReceiptFixture.action(),
            HeistReceiptFixture.warning(path: "$.body[1]", message: "notice"),
            HeistReceiptFixture.explicitFailure(path: "$.body[2]", message: "stop"),
        ]

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

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
