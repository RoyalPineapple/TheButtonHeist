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

            let resultURL = try assertSingleResultArtifactURL(in: directory, matchingSuffix: "-passed.json.gz")
            let result = try HeistResultCodec.decode(contentsOf: resultURL)
            XCTAssertEqual(result, heist.result)
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

    func testRepeatUntilSuccessResultDoesNotSynthesizeWaitActionResult() async throws {
        let job = try TheInsideJob(token: "in-app-repeat-until-success-result-test")
        let settlementScript = SettlementResultScript(states: [
            await observedQuantityState(job: job, value: "0"),
            await observedQuantityState(job: job, value: "2"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, settlementScript: settlementScript) { command in
            if case .increment = command {
                incrementCount += 1
            }
            return ActionResult.success(payload: .increment)
        }
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 1,
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await job.brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let evidence = try XCTUnwrap(step.repeatUntilEvidence)
        let iterationEvidence = try XCTUnwrap(step.children.first?.repeatUntilEvidence)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(evidence.iterationCount, 1)
        XCTAssertTrue(evidence.expectation.met)
        XCTAssertNil(evidence.actionResult)
        XCTAssertNil(iterationEvidence.actionResult)
        XCTAssertNil(step.reportActionResult)
    }

    func testRepeatUntilTimeoutResultDoesNotSynthesizeWaitActionResult() async throws {
        let job = try TheInsideJob(token: "in-app-repeat-until-timeout-result-test")
        let settlementScript = SettlementResultScript(states: [
            await observedQuantityState(job: job, value: "0"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, settlementScript: settlementScript) { command in
            if case .increment = command {
                incrementCount += 1
            }
            return ActionResult.success(payload: .increment)
        }
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: .milliseconds(1),
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await job.brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let evidence = try XCTUnwrap(step.repeatUntilEvidence)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration])
        XCTAssertFalse(evidence.expectation.met)
        XCTAssertEqual(evidence.outcome, .failed)
        XCTAssertNil(evidence.actionResult)
        XCTAssertNil(step.reportActionResult)
        XCTAssertTrue(evidence.failureReason?.contains("timed out") == true)
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
        let tree: [AccessibilityHierarchy] = elements.enumerated().map { index, element in
            AccessibilityHierarchy.element(element, traversalIndex: index)
        }
        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: tree
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
        XCTAssertEqual(result.failureDiagnosticInterface?.projectedElements.first?.label, "Actual Empty State")
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
        let directAction = await job.brains.executeHeistPlan(plan)
        job.brains.stopSemanticObservation()
        let directResult = try XCTUnwrap(directAction.resultPayload)

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

    init(job: TheInsideJob) {
        self.job = job
    }

    var runtime: InAppHeistRuntime {
        InAppHeistRuntime { plan, argument in
            self.plan = plan
            self.argument = argument
            return await self.job.executeInAppHeist(plan, argument: argument)
        }
    }
}

@MainActor
private final class SettlementResultScript {
    private var events: [Observation.SnapshotEvent]
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextSequence: SettledObservationSequence = 0
    private var log = Observation.Log(retentionLimit: Observation.Store.defaultRetentionLimit)

    init(states: [Observation.SnapshotEvent]) {
        events = states
    }

    func event(scope: SemanticObservationScope) -> Observation.SnapshotEvent? {
        guard !events.isEmpty else { return nil }
        let sourceEvent = events.removeFirst()
        let capture = sourceEvent.moment.capture
        nextSequence += 1
        let trace = previousCapture.map {
            AccessibilityTrace(capture: $0).appending(
                capture.interface,
                context: capture.context,
                transition: capture.transition
            )
        } ?? AccessibilityTrace(capture: capture)
        let snapshot = Observation.Snapshot(
            sequence: nextSequence,
            generation: .initial,
            sourceScope: scope,
            observation: sourceEvent.snapshot.observation,
            semanticSignal: .empty,
            notificationSequence: 0,
            trace: trace
        )
        let event: Observation.SnapshotEvent
        do {
            event = try log.record(snapshot: snapshot, continuity: .sameGeneration)
        } catch {
            preconditionFailure("Wait result fixture produced an invalid observation transition: \(error)")
        }
        previousCapture = trace.captures.last
        return event
    }

    func result(for command: Settlement.Command) -> Settlement.Result {
        scriptedSettlement(command, observation: event(scope: command.observationScope))
    }
}

@MainActor
private func observedQuantityState(
    job: TheInsideJob,
    value: String
) async -> Observation.SnapshotEvent {
    let element = AccessibilityElement.make(
        value: value,
        identifier: "quantity",
        traits: .staticText
    )
    return await job.brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
        .makeForTests(elements: [(element, HeistId(rawValue: "quantity"))])
    )
}

@MainActor
private func repeatUntilRuntime(
    job _: TheInsideJob,
    settlementScript: SettlementResultScript,
    execute: @escaping @MainActor (ResolvedHeistActionCommand) async -> ActionResult
) -> TheBrains.HeistExecutionRuntime {
    TheBrains.HeistExecutionRuntime(
        execute: { command, _ in
            RuntimeActionExecution(
                result: await execute(command)
            )
        },
        settle: { command in
            settlementScript.result(for: command)
        }
    )
}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
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
