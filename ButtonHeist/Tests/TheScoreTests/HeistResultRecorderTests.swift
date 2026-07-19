import ButtonHeistTestSupport
import Foundation
import ThePlans
import Testing
@testable import TheScore

@Suite(.serialized) struct HeistResultRecorderTests {

    @Test func `record failing result as gzip artifact`() throws {
        try withTemporaryDirectory(prefix: "heist-result-recorder") { directory in
            let plan = try samplePlan()
            let result = failedResult()

            let recording = try #require(try HeistResultRecorder.write(
                result,
                plan: plan,
                configuration: HeistResultRecordingConfiguration(rootDirectory: directory, mode: .failures)
            ))

            #expect(recording.heistName == "Checkout_Flow")
            #expect(recording.fingerprint == (try HeistResultRecorder.heistFingerprint(for: plan)))
            #expect(recording.url.pathExtension == "gz")
            #expect(recording.url.lastPathComponent.hasSuffix("-failed.json.gz"))
            #expect(recording.url.deletingLastPathComponent().lastPathComponent.hasPrefix("checkout-flow-"))
            #expect(try HeistResultCodec.decode(contentsOf: recording.url) == result)
        }
    }

    @Test func `skip passing result unless mode records passing`() throws {
        try withTemporaryDirectory(prefix: "heist-result-recorder") { directory in
            let plan = try samplePlan()
            let result = passedResult()

            let skipped = try HeistResultRecorder.write(
                result,
                plan: plan,
                configuration: HeistResultRecordingConfiguration(rootDirectory: directory, mode: .failures)
            )
            let recording = try #require(try HeistResultRecorder.write(
                result,
                plan: plan,
                configuration: HeistResultRecordingConfiguration(rootDirectory: directory, mode: .all)
            ))

            #expect(skipped == nil)
            #expect(recording.url.lastPathComponent.hasSuffix("-passed.json.gz"))
            #expect(try HeistResultCodec.decode(contentsOf: recording.url) == result)
        }
    }

    @Test func `recording modes decide from canonical result outcome`() {
        let failed = failedResult()
        let passed = passedResult()

        let expectations: [(HeistResultRecordingMode, failure: Bool, passing: Bool)] = [
            (.off, false, false),
            (.failures, true, false),
            (.all, true, true),
        ]
        for (mode, failure, passing) in expectations {
            #expect(mode.shouldRecord(failed) == failure)
            #expect(mode.shouldRecord(passed) == passing)
        }
    }

    @Test func `environment resolves process temp and rejects unknown mode`() throws {
        let previousDirectory = EnvironmentKey.buttonheistResultsDir.value
        let previousMode = EnvironmentKey.buttonheistResultsMode.value
        setEnvironment(
            EnvironmentKey.buttonheistResultsDir.rawValue,
            HeistResultRecordingConfiguration.processTemporaryDirectoryValue
        )
        setEnvironment(EnvironmentKey.buttonheistResultsMode.rawValue, nil)
        defer {
            setEnvironment(EnvironmentKey.buttonheistResultsDir.rawValue, previousDirectory)
            setEnvironment(EnvironmentKey.buttonheistResultsMode.rawValue, previousMode)
        }

        let configuration = try #require(HeistResultRecordingConfiguration.environment)
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let rootDirectory = configuration.rootDirectory.standardizedFileURL.path

        #expect(rootDirectory.hasPrefix(temporaryDirectory))
        #expect(configuration.rootDirectory.lastPathComponent == "buttonheist-results")

        setEnvironment(EnvironmentKey.buttonheistResultsMode.rawValue, "failed")
        #expect(HeistResultRecordingConfiguration.environment == nil)
    }

    @Test func `result mode parser accepts only canonical spellings`() {
        #expect(HeistResultRecordingMode(environmentValue: nil) == .failures)
        #expect(HeistResultRecordingMode(environmentValue: "off") == .off)
        #expect(HeistResultRecordingMode(environmentValue: "failures") == .failures)
        #expect(HeistResultRecordingMode(environmentValue: "all") == .all)

        for value in ["passing-and-failing", "failed", "always", "ALL"] {
            #expect(HeistResultRecordingMode(environmentValue: value) == nil)
        }
    }

    private func samplePlan() throws -> HeistPlan {
        try HeistPlan(
            name: "Checkout_Flow",
            body: [.warn(WarnStep(message: "record result"))]
        )
    }

    private func failedResult() -> HeistResult {
        HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(path: "$.body[0]", message: "boom", durationMs: 3)],
            durationMs: 3
        )
    }

    private func passedResult() -> HeistResult {
        HeistResultFixture.result(
            steps: [HeistResultFixture.warning(path: "$.body[0]", message: "record result", durationMs: 2)],
            durationMs: 2
        )
    }

    private func setEnvironment(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}
