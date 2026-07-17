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
final class HeistReceiptTests: XCTestCase {

    func testWaitReceiptFactoriesBindCanonicalActionAndExpectationOutcomes() {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = ExpectationResult.Met(predicate: predicate, actual: "found")
        let unmet = ExpectationResult.Unmet(predicate: predicate, actual: "not found")

        let matched = HeistWaitReceipt.matched(
            message: "matched",
            traceEvidence: nil,
            expectation: met
        )
        let timedOut = HeistWaitReceipt.timedOut(
            message: "timed out",
            traceEvidence: nil,
            expectation: unmet
        )
        let failed = HeistWaitReceipt.failed(
            errorKind: .actionFailed,
            message: "failed",
            traceEvidence: nil,
            expectation: unmet
        )

        guard case .matched(let matchedResult, let matchedExpectation) = matched.result else {
            return XCTFail("matched receipt must carry a matched result")
        }
        XCTAssertTrue(matchedResult.outcome.isSuccess)
        XCTAssertEqual(matchedExpectation, met)
        XCTAssertEqual(matchedResult.method, .wait)

        guard case .unmatched(let timeoutResult, let timeoutExpectation) = timedOut.result else {
            return XCTFail("timed-out receipt must carry an unmatched result")
        }
        XCTAssertEqual(timeoutResult.outcome.errorKind, .timeout)
        XCTAssertEqual(timeoutExpectation, unmet)

        guard case .unmatched(let failedResult, let failedExpectation) = failed.result else {
            return XCTFail("failed receipt must carry an unmatched result")
        }
        XCTAssertEqual(failedResult.outcome.errorKind, .actionFailed)
        XCTAssertEqual(failedExpectation, unmet)
    }

    func testRunHeistFacadeProducesCanonicalInvocationReceipt() async throws {
        let heist = try await runHeist("PublicFacade.warn") {
            Warn("ok")
        }

        let invocation = try XCTUnwrap(heist.result.steps.first)
        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
        XCTAssertEqual(invocation.reportDisplayName, #"RunHeist("PublicFacade.warn")"#)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn])
        XCTAssertEqual(invocation.children.first?.reportMessage, "ok")
        XCTAssertEqual(heist.result.warnings, [
            HeistExecutionWarning(path: "$.body[0].invoke.body[0]", message: "ok"),
        ])
    }

    func testRunHeistSyncRecordsPassingReceiptWhenRequested() throws {
        try withReceiptDirectory(prefix: "buttonheist-sync-receipts") { directory in
            let heist = try XCTUnwrap(runHeistSync(
                "syncReceipt",
                recordReceipt: .always,
                to: directory
            ) {
                Warn("sync")
            })

            let receiptURL = try assertSingleReceiptArtifactURL(in: directory, matchingSuffix: "-passed.json.gz")
            let receipt = try HeistReceiptCodec.decode(contentsOf: receiptURL)
            XCTAssertEqual(receipt, heist.result)
        }
    }

    func testRunHeistSyncRecordsXCTestFailureWhenHeistFails() {
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
            heist = runHeistSync("syncFailure", file: #filePath, line: expectedLine) {
                Fail("stop")
            }
        }

        XCTAssertNil(heist)
    }

    func testXCTestFailureReporterRecordsAnAssertionAtTheSuppliedCallSite() {
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

    func testRunHeistTestingFacadeDottedStringArgumentBuildsValidatedInvocation() throws {
        let input: HeistReferenceName = "input"
        let request = try makeRunHeistRequest("Cart.addItem", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .string(name: input))
        XCTAssertEqual(request.argument, .string("Milk"))
        XCTAssertEqual(invocation.path, "Cart.addItem")
        XCTAssertEqual(invocation.argument, .string(reference: input))
    }

    func testRunHeistTestingFacadeDottedAccessibilityTargetArgumentBuildsValidatedInvocation() throws {
        let input: HeistReferenceName = "input"
        let request = try makeRunHeistRequest("Rows.activate", argument: AccessibilityTarget.label("Milk")) { _ in
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
        let job = TheInsideJob(token: "in-app-heist-plan-test")
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
        let job = TheInsideJob(token: "in-app-heist-bootstrap-test")
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
        job.brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(staleDiscovery)

        let currentHeader = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .header,
            respondsToUserInteraction: false
        )
        let currentScreen = InterfaceObservation.makeForTests(elements: [(currentHeader, HeistId(rawValue: "buttonheist_demo"))])
        job.brains.stash.nextVisibleRefreshObservationForTesting = currentScreen

        let plan = try HeistPlan {
            Warn("bootstrapped")
        }

        _ = try await Heist(plan, runtime: .insideJob(job))

        XCTAssertEqual(job.brains.stash.lastScreenName, "ButtonHeist Demo")
        XCTAssertEqual(job.brains.stash.interfaceElementIDs, ["buttonheist_demo"])
        XCTAssertNil(job.brains.stash.interfaceElement(heistId: "stale_row"))
    }

    func testSingleStringRootHeistBindsOneRootArgument() async throws {
        let job = TheInsideJob(token: "in-app-heist-string-test")
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
        let request = try makeRunHeistRequest("addToCart", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try XCTUnwrap(heist.result.steps.first)
        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
        XCTAssertEqual(invocation.reportDisplayName, #"RunHeist("addToCart", input)"#)
        XCTAssertEqual(invocation.children.map(\.kind), [.warn])
        XCTAssertEqual(invocation.children.first?.reportMessage, "adding")
        XCTAssertEqual(request.argument, .string("Milk"))
    }

    func testRunHeistTestingFacadeNoArgumentUsesCanonicalInvocationTopology() throws {
        let request = try makeRunHeistRequest("CheckoutPay") {
            Warn("paying")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(invocation.path, "CheckoutPay")
        XCTAssertEqual(invocation.argument, .none)
        XCTAssertEqual(request.argument, .none)
    }

    func testRunHeistTestingFacadeStringArgumentUsesCanonicalInvocationTopology() throws {
        let request = try makeRunHeistRequest("CartAddItem", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .string(name: "input"))
        XCTAssertEqual(request.argument, .string("Milk"))
        XCTAssertEqual(invocation.path, "CartAddItem")
        XCTAssertEqual(invocation.argument, .string(reference: "input"))
    }

    func testRunHeistTestingFacadeAccessibilityTargetArgumentUsesCanonicalInvocationTopology() throws {
        let request = try makeRunHeistRequest(
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
        let job = TheInsideJob(token: "in-app-heist-target-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist(AccessibilityTarget.label("Delete"), runtime: capture.runtime) { _ in
            Warn("target root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .accessibilityTarget(.label("Delete")))
        XCTAssertEqual(capture.plan?.parameter, .accessibilityTarget(name: "input"))
    }

    func testRepeatUntilSuccessReceiptDoesNotSynthesizeWaitActionResult() async throws {
        let job = TheInsideJob(token: "in-app-repeat-until-success-receipt-test")
        let waitScript = ReceiptWaitScript(states: [
            observedQuantityState(job: job, value: "0"),
            observedQuantityState(job: job, value: "2"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, waitScript: waitScript) { command in
            if case .increment = command {
                incrementCount += 1
            }
            return ActionResult.success(method: .increment)
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
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

    func testRepeatUntilTimeoutReceiptDoesNotSynthesizeWaitActionResult() async throws {
        let job = TheInsideJob(token: "in-app-repeat-until-timeout-receipt-test")
        let waitScript = ReceiptWaitScript(states: [
            observedQuantityState(job: job, value: "0"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, waitScript: waitScript) { command in
            if case .increment = command {
                incrementCount += 1
            }
            return ActionResult.success(method: .increment)
        }
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: .milliseconds(1),
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ],
                elseBody: [
                    .warn(WarnStep(message: "quantity did not reach 2")),
                ]
            )),
        ])

        let result = await job.brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let evidence = try XCTUnwrap(step.repeatUntilEvidence)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until else failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .warn])
        XCTAssertFalse(evidence.expectation.met)
        XCTAssertEqual(evidence.outcome, .handledElse)
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

        XCTAssertEqual(heist.result.warnings, [
            HeistExecutionWarning(path: "$.body[0].invoke.body[0]", message: "root"),
            HeistExecutionWarning(path: "$.body[0].invoke.body[1].invoke.body[0]", message: "nested"),
        ])
    }

    func testFailedHeistThrowsFailureWithInspectableResult() async throws {
        do {
            _ = try await runHeist("failedHeist") {
                Fail("stop")
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

    func testFailureDescriptionIncludesScreenshotInterfaceDump() {
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
        let result = HeistExecutionResult(
            steps: [
                HeistReceiptFixture.explicitFailure(
                    path: "$.body[0]",
                    message: "stop"
                ),
                HeistReceiptFixture.action(
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
            description.contains("failure screenshot: 12x34 receipt=$.body[0].failure.actions[0] interface=21 elements"),
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
        let job = TheInsideJob(token: "in-app-heist-abort-test")

        do {
            _ = try await Heist(runtime: .insideJob(job)) {
                Warn("before")
                Fail("abort")
                Warn("after")
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

    func testReceiptMatchesDirectBrainsExecutionShape() async throws {
        let job = TheInsideJob(token: "in-app-heist-machinery-test")
        let plan = try HeistPlan {
            Warn("same executor")
        }

        job.brains.startSemanticObservation()
        let directAction = await job.brains.executeHeistPlan(plan)
        job.brains.stopSemanticObservation()
        let direct = try XCTUnwrap(directAction.heistExecutionPayload)

        let heist = try await Heist(plan, runtime: .insideJob(job))

        XCTAssertEqual(heist.result.steps.map(\.path), direct.steps.map(\.path))
        XCTAssertEqual(heist.result.steps.map(\.kind), direct.steps.map(\.kind))
        XCTAssertEqual(heist.result.steps.map(\.reportMessage), direct.steps.map(\.reportMessage))
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
private final class ReceiptWaitScript {
    private var states: [PostActionObservation.ObservationBaseline]
    private var previousObservation: SettledObservation?
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextSequence: SettledObservationSequence = 0

    init(states: [PostActionObservation.ObservationBaseline]) {
        self.states = states
    }

    func observation(scope: SemanticObservationScope) -> SettledObservationEvidence? {
        guard !states.isEmpty else { return nil }
        let state = states.removeFirst()
        nextSequence += 1
        let trace = previousCapture.map { AccessibilityTrace(captures: [$0, state.capture]) }
            ?? AccessibilityTrace(capture: state.capture)
        let settledObservation = SettledObservation(
            sequence: nextSequence,
            scope: scope,
            observation: .empty,
            semanticSignal: .empty
        )
        let event = SettledObservationEvent(
            continuity: .sameGeneration,
            settledObservation: settledObservation,
            previous: previousObservation,
            trace: trace
        )
        previousObservation = settledObservation
        previousCapture = state.capture
        return SettledObservationEvidence(
            event: event,
            baseline: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }

    func receipt(for step: ResolvedWaitRuntimeInput) -> HeistWaitReceipt {
        guard let observation = observation(scope: .visible) else {
            let expectation = ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: "no settled semantic observation available"
            )
            return .timedOut(
                message: expectation.actual,
                traceEvidence: nil,
                expectation: expectation
            )
        }

        let state = observation.baseline
        let trace = observation.accessibilityTrace

        let expectation = PredicateEvaluation.evaluate(
            step.predicate,
            expression: step.predicateExpression,
            in: trace,
            completeness: .complete
        )
        let traceEvidence = makeTestTraceEvidence(trace, completeness: .complete)
        switch expectation {
        case .met(let expectation):
            return .matched(
                message: expectation.actual,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: observation.event.sequence,
                observationSummary: "interface: \(state.interface.projectedElements.count) elements"
            )
        case .unmet(let expectation):
            return .timedOut(
                message: expectation.actual,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: observation.event.sequence,
                observationSummary: "interface: \(state.interface.projectedElements.count) elements"
            )
        }
    }
}

@MainActor
private func observedQuantityState(
    job: TheInsideJob,
    value: String
) -> PostActionObservation.ObservationBaseline {
    let element = AccessibilityElement.make(
        value: value,
        identifier: "quantity",
        traits: .staticText
    )
    job.brains.stash.installObservationForTesting(.makeForTests(elements: [(element, HeistId(rawValue: "quantity"))]))
    return job.brains.postActionObservation.captureSemanticState()
}

@MainActor
private func repeatUntilRuntime(
    job _: TheInsideJob,
    waitScript: ReceiptWaitScript,
    execute: @escaping @MainActor (ResolvedHeistActionCommand) async -> ActionResult
) -> TheBrains.HeistExecutionRuntime {
    TheBrains.HeistExecutionRuntime(
        execute: { command, _ in
            RuntimeActionExecution(
                result: await execute(command),
                expectationBaseline: nil
            )
        },
        wait: { request in
            waitScript.receipt(for: request.step)
        },
        selectPredicateCase: { _, _ in
            .selectingFirstMatch(cases: [], ifNone: .noMatch, elapsedMs: 0)
        },
        observeSemanticState: { scope, _, _ in
            waitScript.observation(scope: scope)
        }
    )
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

private func invocationStep(in plan: HeistPlan) throws -> HeistInvocationStep {
    guard case .invoke(let invocation)? = plan.body.first else {
        throw HeistReceiptTestFailure("Expected wrapper plan to invoke its typed heist definition")
    }
    return invocation
}

private struct HeistReceiptTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

#endif // canImport(UIKit)
