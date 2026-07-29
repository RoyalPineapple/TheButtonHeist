import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistResultCodecTests {
    @Test func `decode plain heist execution recording`() throws {
        let result = sampleResult()
        let recording = try sampleRecording(result)
        let data = try HeistResultCodec.encode(recording, format: .json)

        #expect(try HeistResultCodec.decode(data, format: .json) == recording)
    }

    @Test func `decode gzip heist execution recording`() throws {
        let result = sampleResult()
        let recording = try sampleRecording(result)
        let data = try HeistResultCodec.encode(recording, format: .gzipJSON)

        #expect(try HeistResultCodec.decode(data, format: .gzipJSON) == recording)
    }

    @Test func `round trip gzip recording from file contents`() throws {
        let recording = try sampleRecording(sampleResult())
        try withTemporaryDirectory(prefix: "heist-doctor-result") { directory in
            let url = directory.appendingPathComponent("recording")
            try HeistResultCodec.write(recording, to: url)
            #expect(try HeistResultCodec.decode(contentsOf: url) == recording)
        }
    }

    @Test func `result uses direct semantic node wire`() throws {
        let data = try HeistResultCodec.encode(
            sampleRecording(sampleResult()),
            format: .json
        )
        let object = try JSONProbe(data: data)
        let result = try object.object("result")
        let step = try #require(try result.array("steps").first)
        let node = try step.object("node")

        #expect(try step.string("path") == "$.body[0]")
        #expect(try node.string("type") == "action")
        #expect(try node.string("outcome") == "passed")
        try step.assertMissing("kind")
        try step.assertMissing("status")
        try result.assertMissing("abortedAtPath")
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
                _ = try HeistResultCodec.decode(
                    try recordingData(resultJSON: json),
                    format: .json
                )
            }
        }
    }

    @Test func `failure state is derived after decode`() throws {
        let result = HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(message: "stop")]
        )
        let data = try HeistResultCodec.encode(sampleRecording(result), format: .json)
        let decoded = try HeistResultCodec.decode(data, format: .json).result

        #expect(decoded.isFailure)
        #expect(decoded.abortedAtPath == "$.body[0]")
        #expect(decoded.firstFailedStep?.failure?.observed == "stop")
    }

    private func sampleResult() -> HeistResult {
        HeistResultFixture.result(steps: [HeistResultFixture.action()], durationMs: 12)
    }

    private func sampleRecording(_ result: HeistResult) throws -> HeistResultRecording {
        try HeistResultRecording(
            result: result,
            plan: HeistPlan(body: [.warn(WarnStep(message: "codec fixture"))]),
            recordedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func recordingData(resultJSON: String) throws -> Data {
        let result = try JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": HeistResultRecording.currentSchemaVersion,
            "result": result,
            "planName": NSNull(),
            "planFingerprint": String(repeating: "0", count: 24),
            "recordedAt": 0,
            "producerVersion": buttonHeistVersion.description,
        ])
    }
}
