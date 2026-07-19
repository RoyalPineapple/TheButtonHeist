import ButtonHeistTestSupport
import Foundation
import Testing
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistResultCodecTests {
    @Test func `decode plain heist execution result`() throws {
        let result = sampleResult()
        let data = try HeistResultCodec.encode(result, format: .json)

        #expect(try HeistResultCodec.decode(data, format: .json) == result)
    }

    @Test func `decode gzip heist execution result`() throws {
        let result = sampleResult()
        let data = try HeistResultCodec.encode(result, format: .gzipJSON)

        #expect(try HeistResultCodec.decode(data, format: .gzipJSON) == result)
    }

    @Test func `round trip gzip result from file extension`() throws {
        let result = sampleResult()
        try withTemporaryDirectory(prefix: "heist-doctor-result") { directory in
            let url = directory.appendingPathComponent("result.json.gz")
            try HeistResultCodec.write(result, to: url)
            #expect(try HeistResultCodec.decode(contentsOf: url) == result)
        }
    }

    @Test func `result uses direct semantic node wire`() throws {
        let data = try HeistResultCodec.encode(sampleResult(), format: .json)
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
                _ = try HeistResultCodec.decode(Data(json.utf8), format: .json)
            }
        }
    }

    @Test func `failure state is derived after decode`() throws {
        let result = HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(message: "stop")]
        )
        let data = try HeistResultCodec.encode(result, format: .json)
        let decoded = try HeistResultCodec.decode(data, format: .json)

        #expect(decoded.isFailure)
        #expect(decoded.abortedAtPath == "$.body[0]")
        #expect(decoded.firstFailedStep?.failure?.observed == "stop")
    }

    private func sampleResult() -> HeistResult {
        HeistResultFixture.result(steps: [HeistResultFixture.action(durationMs: 12)], durationMs: 12)
    }
}
