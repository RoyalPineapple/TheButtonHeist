#if canImport(UIKit)
import ButtonHeistTestSupport
import UIKit
import XCTest
@testable import ButtonHeistTesting
@_spi(ButtonHeistInternals) @testable import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@testable import TheInsideJob

@MainActor
final class HeistInAppExecutionTests: XCTestCase {

    func testRunHeistFacadeProducesCanonicalInvocationResult() async throws {
        let heist = try await runHeist("PublicFacade.warn") {
            Warn("ok")
        }

        let invocation = try XCTUnwrap(heist.result.steps.first)
        let report = HeistReport.project(result: heist.result)
        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
        XCTAssertEqual(invocation.reportDisplayName, #"RunHeist("PublicFacade.warn")"#)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn])
        XCTAssertEqual(invocation.children.first?.reportMessage, "ok")
        XCTAssertEqual(report.warnings, [
            HeistExecutionWarning(path: "$.body[0].invoke.body[0]", message: "ok"),
        ])
    }

    func testRunHeistSyncRecordsPassingResultWhenRequested() throws {
        try withResultDirectory(prefix: "buttonheist-sync-results") { directory in
            let heist = try XCTUnwrap(runHeistSync(
                "syncResult",
                recordResult: .always,
                to: directory
            ) {
                Warn("sync")
            })

            let resultURL = try assertSingleResultArtifactURL(in: directory)
            let recording = try HeistResultCodec.decode(contentsOf: resultURL)
            XCTAssertEqual(recording.result, heist.result)
        }
    }

    func testRunHeistSyncRecordsXCTestFailureWithoutAmbientArtifactWhenDisabled() throws {
        try withResultDirectory(prefix: "buttonheist-sync-results-off") { directory in
            let previousDirectory = EnvironmentKey.buttonheistResultsDir.value
            let previousMode = EnvironmentKey.buttonheistResultsMode.value
            setEnvironment(EnvironmentKey.buttonheistResultsDir.rawValue, directory.path)
            setEnvironment(
                EnvironmentKey.buttonheistResultsMode.rawValue,
                HeistResultRecordingMode.failures.rawValue
            )
            defer {
                setEnvironment(EnvironmentKey.buttonheistResultsDir.rawValue, previousDirectory)
                setEnvironment(EnvironmentKey.buttonheistResultsMode.rawValue, previousMode)
            }

            let expectedFile = String(describing: #filePath)
            let expectedLine: UInt = 4_241
            let options = XCTExpectedFailure.Options()
            options.issueMatcher = { issue in
                issue.type == .assertionFailure
                    && issue.compactDescription.contains(
                        "Heist failed at $.body[0].invoke.body[0] (fail)"
                    )
                    && issue.compactDescription.contains("Cause: stop")
                    && issue.sourceCodeContext.location?.fileURL.path == expectedFile
                    && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
            }
            var heist: Heist?

            XCTExpectFailure(
                "runHeistSync reports failed heists through XCTest at the call site",
                options: options
            ) {
                heist = runHeistSync(
                    "syncFailure",
                    recordResult: .off,
                    file: #filePath,
                    line: expectedLine
                ) {
                    Fail("stop")
                }
            }

            XCTAssertNil(heist)
            XCTAssertTrue(try resultArtifactURLs(in: directory).isEmpty)
        }
    }

    func testPrebuiltPlanRunsThroughInAppRuntimeWithoutTransport() async throws {
        let job = try TheInsideJob(token: "in-app-heist-plan-test")
        let plan = try HeistPlan("login") {
            Warn("prebuilt")
        }

        XCTAssertFalse(job.isRunning)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)

        let heist = try await Heist(plan, argument: .none, runtime: .insideJob(job))

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(heist.result.steps.first?.reportMessage, "prebuilt")
        XCTAssertFalse(job.isRunning)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
    }

    func testRunHeistSwiftBoundaryBindsOneStringArgument() async throws {
        let heist = try await runHeist("addToCart", argument: "Milk") { _ in
            Warn("adding")
        }
        let request = try HeistRunCommand("addToCart", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try XCTUnwrap(heist.result.steps.first)
        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
        XCTAssertEqual(invocation.reportDisplayName, #"RunHeist("addToCart", input)"#)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn])
        XCTAssertEqual(invocation.children.first?.reportMessage, "adding")
        XCTAssertEqual(request.argument, .string("Milk"))
    }

    func testWarningsRollUpWithRuntimePath() async throws {
        enum Library {
            static let marker = HeistDef<Void>("Library.marker") {
                Warn("nested")
            }
        }

        let heist = try await runHeist("warningsRollUp") {
            Warn("root")
            try Library.marker()
        }

        let report = HeistReport.project(result: heist.result)
        XCTAssertEqual(report.warnings, [
            HeistExecutionWarning(path: "$.body[0].invoke.body[0]", message: "root"),
            HeistExecutionWarning(path: "$.body[0].invoke.body[1].invoke.body[0]", message: "nested"),
        ])
    }

    func testFailedHeistThrowsFailureWithInspectableResult() async throws {
        do {
            _ = try await HeistResultRecording.withEnvironmentRecording(false) {
                try await runHeist("failedHeist") {
                    Fail("stop")
                }
            }
            XCTFail("Expected failed heist to throw")
        } catch let failure as Heist.Failure {
            let invocation = try XCTUnwrap(failure.result.steps.first)
            XCTAssertEqual(failure.failedStepPath, "$.body[0].invoke.body[0]")
            XCTAssertEqual(failure.failedStepKind, .fail)
            XCTAssertEqual(failure.message, "stop")
            XCTAssertEqual(invocation.kind, .invoke)
            XCTAssertEqual(invocation.status, .failed)
            XCTAssertEqual(invocation.children.map(\.kind), [.fail])
            XCTAssertEqual(invocation.children.first?.path, failure.failedStepPath)
            XCTAssertNotNil(failure.result.failureScreenshotPayload)
        }
    }

    func testFailureAbortsAtFirstFailedStepAndRestoresRuntime() async throws {
        let job = try TheInsideJob(token: "in-app-heist-abort-test")

        do {
            _ = try await HeistResultRecording.withEnvironmentRecording(false) {
                try await Heist(runtime: .insideJob(job)) {
                    Warn("before")
                    Fail("abort")
                    Warn("after")
                }
            }
            XCTFail("Expected failed heist to throw")
        } catch let failure as Heist.Failure {
            XCTAssertEqual(failure.failedStepPath, "$.body[1]")
            XCTAssertEqual(failure.result.abortedAtPath, "$.body[1]")
            XCTAssertEqual(Array(failure.result.steps.prefix(3)).map(\.kind), [.warn, .fail, .warn])
            XCTAssertEqual(Array(failure.result.steps.prefix(3)).map(\.status), [.passed, .failed, .skipped])
            XCTAssertNotNil(failure.result.failureScreenshotPayload)
            let skipped = try XCTUnwrap(failure.result.steps.dropFirst(2).first)
            XCTAssertEqual(skipped.path, "$.body[2]")
            XCTAssertEqual(skipped.kind, .warn)
            XCTAssertNil(skipped.failure)
            XCTAssertFalse(job.isRunning)
            XCTAssertFalse(job.brains.semanticObservationIsActive)
            XCTAssertFalse(job.tripwire.isPulseRunning)
        }
    }

    private func setEnvironment(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}
#endif // canImport(UIKit)
