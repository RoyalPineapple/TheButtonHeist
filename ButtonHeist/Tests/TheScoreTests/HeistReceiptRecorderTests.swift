import ButtonHeistTestSupport
import Foundation
import ThePlans
import Testing
@testable import TheScore

@Suite(.serialized) struct HeistReceiptRecorderTests {

    @Test func `record failing receipt as gzip artifact`() throws {
        try withTemporaryDirectory(prefix: "heist-receipt-recorder") { directory in
            let plan = try samplePlan()
            let result = failedResult()

            let recording = try #require(try HeistReceiptRecorder.write(
                result,
                plan: plan,
                configuration: HeistReceiptRecordingConfiguration(rootDirectory: directory, mode: .failures)
            ))

            #expect(recording.status == .failed)
            #expect(recording.heistName == "Checkout_Flow")
            #expect(recording.fingerprint == (try HeistReceiptRecorder.heistFingerprint(for: plan)))
            #expect(recording.url.pathExtension == "gz")
            #expect(recording.url.deletingLastPathComponent().lastPathComponent.hasPrefix("checkout-flow-"))
            #expect(try HeistReceiptCodec.decode(contentsOf: recording.url) == result)
        }
    }

    @Test func `skip passing receipt unless mode records passing`() throws {
        try withTemporaryDirectory(prefix: "heist-receipt-recorder") { directory in
            let plan = try samplePlan()
            let result = passedResult()

            let skipped = try HeistReceiptRecorder.write(
                result,
                plan: plan,
                configuration: HeistReceiptRecordingConfiguration(rootDirectory: directory, mode: .failures)
            )
            let recording = try #require(try HeistReceiptRecorder.write(
                result,
                plan: plan,
                configuration: HeistReceiptRecordingConfiguration(rootDirectory: directory, mode: .failingAndPassing)
            ))

            #expect(skipped == nil)
            #expect(recording.status == .passed)
            #expect(try HeistReceiptCodec.decode(contentsOf: recording.url) == result)
        }
    }

    @Test func `environment process temporary directory resolves under process temp`() throws {
        let previousDirectory = EnvironmentKey.buttonheistReceiptsDir.value
        setEnvironment(
            EnvironmentKey.buttonheistReceiptsDir.rawValue,
            HeistReceiptRecordingConfiguration.processTemporaryDirectoryValue
        )
        defer { setEnvironment(EnvironmentKey.buttonheistReceiptsDir.rawValue, previousDirectory) }

        let configuration = try #require(HeistReceiptRecordingConfiguration.environment)
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let rootDirectory = configuration.rootDirectory.standardizedFileURL.path

        #expect(rootDirectory.hasPrefix(temporaryDirectory))
        #expect(configuration.rootDirectory.lastPathComponent == "buttonheist-receipts")
    }

    private func samplePlan() throws -> HeistPlan {
        try HeistPlan(
            name: "Checkout_Flow",
            body: [.warn(WarnStep(message: "record receipt"))]
        )
    }

    private func failedResult() -> HeistExecutionResult {
        HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .fail,
                    status: .failed,
                    durationMs: 3,
                    intent: .fail(message: "boom"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail",
                        observed: "boom"
                    )
                ),
            ],
            durationMs: 3,
            abortedAtPath: "$.body[0]"
        )
    }

    private func passedResult() -> HeistExecutionResult {
        HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .warn,
                    status: .passed,
                    durationMs: 2,
                    intent: .warn(message: "record receipt"),
                    evidence: .warning(HeistExecutionWarning(path: "$.body[0]", message: "record receipt"))
                ),
            ],
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
