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
        #expect(decoded.outcome == .failed(abortedAtPath: "$.body[0]"))
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

@Suite struct HeistResultPairSelectionTests {
    @Test func `select pair from decoded canonical recordings and return malformed warnings`() throws {
        try withTemporaryDirectory(prefix: "heist-doctor-pair") { root in
            let passes = root.appendingPathComponent("main", isDirectory: true)
            let failures = root.appendingPathComponent("pr", isDirectory: true)
            let plan = try fixturePlan("selected")

            _ = try writeRecording(in: passes, id: 1, plan: plan, recordedAt: 10, compressed: true)
            let selectedPass = try writeRecording(in: passes, id: 2, plan: plan, recordedAt: 20)
            _ = try writeRecording(in: passes, id: 3, plan: plan, recordedAt: 30)
            let malformed = passes.appendingPathComponent(
                "00000000-0000-0000-0000-000000000009.json"
            )
            try Data("{}".utf8).write(to: malformed)
            try Data("{}".utf8).write(to: passes.appendingPathComponent("ignored.json"))
            let selectedFail = try writeRecording(
                in: failures.appendingPathComponent("nested", isDirectory: true),
                id: 4,
                result: failedResult(),
                plan: plan,
                recordedAt: 30,
                compressed: true
            )
            _ = try writeRecording(
                in: failures,
                id: 5,
                result: failedResult(),
                plan: try fixturePlan("unmatched"),
                recordedAt: 40
            )
            _ = try writeRecording(
                in: passes,
                name: "not-a-uuid.json",
                plan: plan,
                recordedAt: 25
            )

            let result = try HeistResultPairSelection.select(
                lastPassDirectory: passes,
                newFailDirectory: failures
            )

            guard case .selected(let lastPass, let newFail, let fingerprint, let warnings) = result else {
                Issue.record("Expected a selected result pair")
                return
            }
            #expect(lastPass.standardizedFileURL == selectedPass.standardizedFileURL)
            #expect(newFail.standardizedFileURL == selectedFail.standardizedFileURL)
            #expect(fingerprint == (try HeistResultRecording.planFingerprint(for: plan)))
            #expect(warnings.map(\.recording.standardizedFileURL) == [malformed.standardizedFileURL])
            #expect(warnings.first?.reason.isEmpty == false)
        }
    }

    private func fixturePlan(_ message: String) throws -> HeistPlan {
        try HeistPlan(body: [
            .warn(WarnStep(message: try HeistWarningMessage(validating: message))),
        ])
    }

    private func passedResult() -> HeistResult {
        HeistResultFixture.result(steps: [HeistResultFixture.warning(message: "passed")])
    }

    private func failedResult() -> HeistResult {
        HeistResultFixture.result(steps: [HeistResultFixture.explicitFailure(message: "failed")])
    }

    @discardableResult
    private func writeRecording(
        in directory: URL,
        id: UInt64? = nil,
        name: String? = nil,
        result: HeistResult? = nil,
        plan: HeistPlan,
        recordedAt: TimeInterval,
        compressed: Bool = false
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let uuid = String(format: "00000000-0000-0000-0000-%012llx", id ?? 0)
        let filename = name ?? uuid
            + ".json"
            + (compressed ? ".gz" : "")
        let url = directory.appendingPathComponent(filename)
        let recording = try HeistResultRecording(
            result: result ?? passedResult(),
            plan: plan,
            recordedAt: Date(timeIntervalSince1970: recordedAt)
        )
        let format: HeistResultFormat = compressed ? .gzipJSON : .json
        try HeistResultCodec.encode(recording, format: format).write(to: url)
        return url
    }
}
