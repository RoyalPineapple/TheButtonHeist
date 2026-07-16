import ButtonHeistTestSupport
import Foundation
import Testing
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistReceiptCodecTests {
    @Test func `decode plain heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .json)

        #expect(try HeistReceiptCodec.decode(data, format: .json) == receipt)
    }

    @Test func `decode gzip heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .gzipJSON)

        #expect(try HeistReceiptCodec.decode(data, format: .gzipJSON) == receipt)
    }

    @Test func `round trip gzip receipt from file extension`() throws {
        let receipt = sampleReceipt()
        try withTemporaryDirectory(prefix: "heist-doctor-receipt") { directory in
            let url = directory.appendingPathComponent("receipt.json.gz")
            try HeistReceiptCodec.write(receipt, to: url)
            #expect(try HeistReceiptCodec.decode(contentsOf: url) == receipt)
        }
    }

    @Test func `receipt uses direct semantic node wire`() throws {
        let data = try HeistReceiptCodec.encode(sampleReceipt(), format: .json)
        let object = try JSONProbe(data: data)
        let step = try #require(try object.array("steps").first)
        let node = try step.object("node")

        #expect(try step.string("path") == "$.body[0]")
        #expect(try node.string("type") == "action")
        #expect(try node.string("outcome") == "passed")
        try step.assertMissing("kind")
        try step.assertMissing("status")
        try object.assertMissing("abortedAtPath")
    }

    @Test func `decode rejects unknown and malformed variants`() throws {
        let invalid = [
            #"{"steps":[],"durationMs":1,"outcome":"passed"}"#,
            #"{"steps":[{"path":"$.body[0]","durationMs":1,"node":{"type":"warning","outcome":"passed","message":"notice","#
                + #"children":[],"legacy":true}}],"durationMs":1}"#,
            #"{"steps":[{"path":"$.body[0]","durationMs":1,"node":{"type":"warning","outcome":"failed","message":"notice","children":[]}}],"durationMs":1}"#,
            #"{"steps":[{"path":"body[0]","durationMs":1,"node":{"type":"warning","outcome":"passed","message":"notice","children":[]}}],"durationMs":1}"#,
        ]

        for json in invalid {
            #expect(throws: Error.self) {
                _ = try HeistReceiptCodec.decode(Data(json.utf8), format: .json)
            }
        }
    }

    @Test func `failure state is derived after decode`() throws {
        let receipt = HeistReceiptFixture.result(
            steps: [HeistReceiptFixture.explicitFailure(message: "stop")]
        )
        let data = try HeistReceiptCodec.encode(receipt, format: .json)
        let decoded = try HeistReceiptCodec.decode(data, format: .json)

        #expect(decoded.isFailure)
        #expect(decoded.abortedAtPath == "$.body[0]")
        #expect(decoded.firstFailedStep?.failure?.observed == "stop")
    }

    private func sampleReceipt() -> HeistExecutionResult {
        HeistReceiptFixture.result(steps: [HeistReceiptFixture.action(durationMs: 12)], durationMs: 12)
    }
}
