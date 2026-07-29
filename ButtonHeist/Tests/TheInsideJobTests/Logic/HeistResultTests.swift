#if canImport(UIKit)
import ButtonHeistTestSupport
import UIKit
import XCTest
@testable import AccessibilitySnapshotParser
@testable import ButtonHeistTesting
@_spi(ButtonHeistInternals) @testable import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@testable import TheInsideJob

@MainActor
final class HeistResultTests: XCTestCase {

    func testInactiveRuntimeProducesTypedExecutionFailure() async throws {
        let job = try TheInsideJob(token: "inactive-heist-boundary-test")
        let execution = await job.brains.executeHeistPlan(try HeistPlan {
            Warn("unreachable")
        })

        guard case .failure(let failure) = execution else {
            return XCTFail("Expected typed heist execution failure")
        }
        guard case .runtimeUnavailable = failure else {
            return XCTFail("Expected runtimeUnavailable, got \(failure)")
        }
        XCTAssertEqual(failure.serverError.kind, .general)
        XCTAssertEqual(failure.serverError.message, "ButtonHeist runtime is not active.")
    }

    func testExecutionFailureTransportPreservesDiagnosticsAndKind() {
        let detail = HeistExecution.Failure.Detail(
            HeistResultTestFailure("duplicate execution path")
        )
        let runtimeFailure = HeistExecution.Failure.runtimeBoundary(detail)
        let admissionFailure = HeistExecution.Failure.invalidResult(detail)

        XCTAssertEqual(runtimeFailure.serverError.kind, .general)
        XCTAssertTrue(runtimeFailure.serverError.message.description.contains("duplicate execution path"))
        XCTAssertEqual(admissionFailure.serverError.kind, .validationError)
        XCTAssertTrue(admissionFailure.serverError.message.description.contains("duplicate execution path"))
    }

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
                        "Heist failed path=$.body[0].invoke.body[0] kind=fail message=stop"
                    )
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

    func testXCTestFailureReporterRecordsAnAssertionAtTheSuppliedCallSite() async {
        let expectedMessage = "runHeistSyncOperation must be called on the main thread"
        let expectedFile = String(describing: #filePath)
        let expectedLine: UInt = 4_242
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.type == .assertionFailure
                && issue.compactDescription.contains(expectedMessage)
                && issue.sourceCodeContext.location?.fileURL.path == expectedFile
                && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
        }

        XCTExpectFailure(
            "Button Heist assertion failures must be recorded by XCTest",
            options: options
        ) {
            recordHeistXCTestIssue(
                .synchronousOperationRequiresMainThread,
                file: #filePath,
                line: expectedLine
            )
        }
    }

    func testRunHeistTestingFacadeDottedStringArgumentBuildsValidatedInvocation() async throws {
        let input: HeistReferenceName = "input"
        let request = try HeistRunCommand("Cart.addItem", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .string(name: input))
        XCTAssertEqual(request.argument, .string("Milk"))
        XCTAssertEqual(invocation.path, "Cart.addItem")
        XCTAssertEqual(invocation.argument, .string(reference: input))
    }

    func testRunHeistTestingFacadeDottedAccessibilityTargetArgumentBuildsValidatedInvocation() async throws {
        let input: HeistReferenceName = "input"
        let request = try HeistRunCommand("Rows.activate", argument: AccessibilityTarget.label("Milk")) { _ in
            Warn("activating")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .accessibilityTarget(name: input))
        XCTAssertEqual(request.argument, .accessibilityTarget(.label("Milk")))
        XCTAssertEqual(invocation.path, "Rows.activate")
        XCTAssertEqual(invocation.argument, .accessibilityTarget(AccessibilityTarget(ref: input)))
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

    func testTopLevelHeistBootstrapsFromFreshVisibleScreen() async throws {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let job = try TheInsideJob(
            token: "in-app-heist-bootstrap-test",
            visibleObservationSource: visibleObservationSource.capture
        )
        let staleHeader = AccessibilityElement.make(
            label: "Controls Demo",
            traits: .header,
            respondsToUserInteraction: false
        )
        let staleOffscreen = AccessibilityElement.make(
            label: "Stale Row",
            traits: .button,
            respondsToUserInteraction: false
        )
        let staleDiscovery = InterfaceObservation.makeForTests(
            elements: [(staleHeader, "controls_demo")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleOffscreen, heistId: "stale_row")]
        )
        await job.brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(staleDiscovery)

        let currentHeader = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .header,
            respondsToUserInteraction: false
        )
        visibleObservationSource.observation = .makeForTests(
            elements: [(currentHeader, HeistId(rawValue: "buttonheist_demo"))]
        )

        _ = try await Heist(runtime: .insideJob(job)) {
            Warn("bootstrapped")
        }

        XCTAssertEqual(job.brains.vault.lastScreenName, "ButtonHeist Demo")
        XCTAssertEqual(job.brains.vault.interfaceElementIDs, ["buttonheist_demo"])
        XCTAssertNil(job.brains.vault.interfaceElement(heistId: "stale_row"))
    }

    func testSingleStringRootHeistBindsOneRootArgument() async throws {
        let job = try TheInsideJob(token: "in-app-heist-string-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist("milk", runtime: capture.runtime) { _ in
            Warn("string root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .string("milk"))
        XCTAssertEqual(capture.plan?.parameter, .string(name: "input"))
    }

    func testInProcessHeistPropagatesWholeHeistTimeout() async throws {
        let job = try TheInsideJob(token: "in-app-heist-timeout-test")
        let capture = RuntimeCapture(job: job)
        let timeout = try HeistTimeout(validatingSeconds: 123.5)

        _ = try await Heist(
            try HeistPlan { Warn("timeout") },
            timeout: timeout,
            runtime: capture.runtime
        )

        XCTAssertEqual(capture.timeout, timeout)
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

    func testRunHeistTestingFacadeNoArgumentUsesCanonicalInvocationTopology() async throws {
        let request = try HeistRunCommand("CheckoutPay") {
            Warn("paying")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(invocation.path, "CheckoutPay")
        XCTAssertEqual(invocation.argument, .none)
        XCTAssertEqual(request.argument, .none)
    }

    func testRunHeistTestingFacadeStringArgumentUsesCanonicalInvocationTopology() async throws {
        let request = try HeistRunCommand("CartAddItem", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .string(name: "input"))
        XCTAssertEqual(request.argument, .string("Milk"))
        XCTAssertEqual(invocation.path, "CartAddItem")
        XCTAssertEqual(invocation.argument, .string(reference: "input"))
    }

    func testRunHeistTestingFacadeAccessibilityTargetArgumentUsesCanonicalInvocationTopology() async throws {
        let request = try HeistRunCommand(
            "RowsActivate",
            argument: AccessibilityTarget.label("Milk")
        ) { _ in
            Warn("activating")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .accessibilityTarget(name: "input"))
        XCTAssertEqual(request.argument, .accessibilityTarget(.label("Milk")))
        XCTAssertEqual(invocation.path, "RowsActivate")
        XCTAssertEqual(invocation.argument, .accessibilityTarget(AccessibilityTarget(ref: "input")))
    }

    func testSingleAccessibilityTargetRootHeistBindsOneRootArgument() async throws {
        let job = try TheInsideJob(token: "in-app-heist-target-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist(AccessibilityTarget.label("Delete"), runtime: capture.runtime) { _ in
            Warn("target root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .accessibilityTarget(.label("Delete")))
        XCTAssertEqual(capture.plan?.parameter, .accessibilityTarget(name: "input"))
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
            XCTAssertEqual(failure.result.failureScreenshotStep?.kind, .action)
        }
    }

    func testFailureDescriptionIncludesScreenshotInterfaceDump() async throws {
        var elements: [AccessibilityElement] = []
        elements.reserveCapacity(21)
        for index in 0..<21 {
            elements.append(AccessibilityElement.make(
                label: index == 0 ? "Actual Empty State" : "Actual Empty State \(index)",
                identifier: index == 0 ? "empty_state" : "empty_state_\(index)",
                traits: .staticText,
                frame: CGRect(x: 10 + index, y: 20 + index, width: 100, height: 44),
                respondsToUserInteraction: false
            ))
        }
        let interface = makeTestInterface(
            nodes: elements.map { TestInterfaceNode.parsedElement($0, actions: []) }
        )
        let screenshot = ScreenPayload(
            pngData: "png",
            width: 12,
            height: 34,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: interface
        )
        let result = try HeistResult(
            steps: [
                HeistResultFixture.explicitFailure(
                    path: "$.body[0]",
                    message: "stop"
                ),
                HeistResultFixture.action(
                    path: "$.body[0].failure.actions[0]",
                    command: .takeScreenshot,
                    result: ActionResult.success(
                        payload: .screenshot(screenshot),
                    )
                ),
            ],
            durationMs: 2
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(description.contains("Heist failed path=$.body[0] kind=fail message=stop"), description)
        XCTAssertTrue(
            description.contains("failure screenshot: 12x34 result=$.body[0].failure.actions[0] interface=21 elements"),
            description
        )
        XCTAssertTrue(description.contains("failure interface: 21 elements"), description)
        XCTAssertTrue(description.contains("[0] \"Actual Empty State\" staticText id=\"empty_state\""), description)
        XCTAssertTrue(description.contains("[20] \"Actual Empty State 20\" staticText id=\"empty_state_20\""), description)
        XCTAssertFalse(description.contains("... and 1 more"), description)
        XCTAssertTrue(description.contains("frame=(10,20,100,44) activation=(60,42)"), description)
        XCTAssertEqual(result.failureScreenshotPayload, screenshot)
        XCTAssertEqual(
            result.failureDiagnosticInterface?.projectedElements.first?.semantics.assertable.label,
            "Actual Empty State"
        )
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
            XCTAssertEqual(failure.result.failureScreenshotStep?.kind, .action)
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

    func testResultMatchesDirectBrainsExecutionShape() async throws {
        let job = try TheInsideJob(token: "in-app-heist-machinery-test")
        let plan = try HeistPlan {
            Warn("same executor")
        }

        await job.brains.startSemanticObservation()
        let directResult = try await job.brains.executeHeistPlan(plan).get()
        job.brains.stopSemanticObservation()

        let heist = try await Heist(plan, runtime: .insideJob(job))

        XCTAssertEqual(heist.result.steps.map(\.path), directResult.steps.map(\.path))
        XCTAssertEqual(heist.result.steps.map(\.kind), directResult.steps.map(\.kind))
        XCTAssertEqual(heist.result.steps.map(\.reportMessage), directResult.steps.map(\.reportMessage))
    }
}

@MainActor
private final class RuntimeCapture {
    private let job: TheInsideJob
    private(set) var plan: HeistPlan?
    private(set) var argument: HeistArgument?
    private(set) var timeout: HeistTimeout?

    init(job: TheInsideJob) {
        self.job = job
    }

    var runtime: InAppHeistRuntime {
        InAppHeistRuntime { plan, argument, timeout in
            self.plan = plan
            self.argument = argument
            self.timeout = timeout
            return try await self.job.executeInAppHeist(
                plan,
                argument: argument,
                timeout: timeout
            )
        }
    }
}

private func invocationStep(in plan: HeistPlan) throws -> HeistInvocationStep {
    guard case .invoke(let invocation)? = plan.body.first else {
        throw HeistResultTestFailure("Expected wrapper plan to invoke its typed heist definition")
    }
    return invocation
}

private struct HeistResultTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

#endif // canImport(UIKit)
