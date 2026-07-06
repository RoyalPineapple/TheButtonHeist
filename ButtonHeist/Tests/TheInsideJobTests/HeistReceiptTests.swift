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

    func testRunHeistFacadeWarnRunsInAppProcess() async throws {
        let heist = try await runHeist("publicFacadeWarn") {
            Warn("ok")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(heist.result.steps.first?.reportMessage, "ok")
        XCTAssertEqual(heist.result.warnings, [
            HeistExecutionWarning(path: "$.body[0]", message: "ok"),
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
        XCTExpectFailure("runHeistSync reports failed heists through XCTest at the call site") {
            let heist = runHeistSync("syncFailure") {
                Fail("stop")
            }
            XCTAssertNil(heist)
        }
    }

    func testPublicRunHeistFacadeDottedNameRunsAsNamedCapability() async throws {
        let heist = try await runHeist("PublicFacade.warn") {
            Warn("ok")
        }

        let step = try XCTUnwrap(heist.result.steps.first)
        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
        XCTAssertEqual(step.reportDisplayName, #"RunHeist("PublicFacade.warn")"#)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
        XCTAssertEqual(step.children.first?.reportMessage, "ok")
    }

    func testRunHeistTestingFacadeDottedStringArgumentBuildsValidatedInvocation() throws {
        let request = try makeRunHeistRequest("Cart.addItem", argument: "Milk") { _ in
            Warn("adding")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .string(name: "input"))
        XCTAssertEqual(request.argument, .string(.literal("Milk")))
        XCTAssertEqual(invocation.path, ["Cart", "addItem"])
        XCTAssertEqual(invocation.argument, .string(.ref("input")))
    }

    func testRunHeistTestingFacadeDottedElementTargetArgumentBuildsValidatedInvocation() throws {
        let request = try makeRunHeistRequest("Rows.activate", argument: ElementTarget.label("Milk")) { _ in
            Warn("activating")
        }

        let invocation = try invocationStep(in: request.plan)
        XCTAssertNil(request.plan.name)
        XCTAssertEqual(request.plan.parameter, .elementTarget(name: "input"))
        XCTAssertEqual(request.argument, .elementTarget(.target(.label("Milk"))))
        XCTAssertEqual(invocation.path, ["Rows", "activate"])
        XCTAssertEqual(invocation.argument, .elementTarget(.ref("input")))
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
        let staleDiscovery = Screen.makeForTests(
            elements: [(staleHeader, "controls_demo")],
            offViewport: [Screen.OffViewportEntry(staleOffscreen, heistId: "stale_row")]
        )
        job.brains.stash.semanticObservationStream.commitSettledDiscoveryObservation(staleDiscovery)

        let currentHeader = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .header,
            respondsToUserInteraction: false
        )
        let currentScreen = Screen.makeForTests(elements: [(currentHeader, HeistId(rawValue: "buttonheist_demo"))])
        job.brains.stash.nextVisibleRefreshScreenForTesting = currentScreen

        let plan = try HeistPlan {
            Warn("bootstrapped")
        }

        _ = try await Heist(plan, runtime: .insideJob(job))

        XCTAssertEqual(job.brains.stash.lastScreenName, "ButtonHeist Demo")
        XCTAssertEqual(job.brains.stash.knownElementIds, ["buttonheist_demo"])
        XCTAssertNil(job.brains.stash.knownElement(heistId: "stale_row"))
    }

    func testSingleStringRootHeistBindsOneRootArgument() async throws {
        let job = TheInsideJob(token: "in-app-heist-string-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist("milk", runtime: capture.runtime) { _ in
            Warn("string root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .string(.literal("milk")))
        XCTAssertEqual(capture.plan?.parameter, .string(name: "input"))
    }

    func testRunHeistSwiftBoundaryBindsOneStringArgument() async throws {
        let heist = try await runHeist("addToCart", argument: "Milk") { _ in
            Warn("adding")
        }
        let request = try makeRunHeistRequest("addToCart", argument: "Milk") { _ in
            Warn("adding")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(request.argument, .string(.literal("Milk")))
        XCTAssertEqual(request.plan.name, "addToCart")
        XCTAssertEqual(request.plan.parameter, .string(name: "input"))
    }

    func testRunHeistTestingFacadeNoArgumentLowersLikeNamedHeistPlan() throws {
        let expectedPlan = try HeistPlan("CheckoutPay") {
            Warn("paying")
        }
        let request = try makeRunHeistRequest("CheckoutPay") {
            Warn("paying")
        }

        XCTAssertEqual(request.plan, expectedPlan)
        XCTAssertEqual(request.plan.name, "CheckoutPay")
        XCTAssertEqual(request.argument, .none)
    }

    func testRunHeistTestingFacadeStringArgumentLowersLikeNamedHeistPlan() throws {
        let expectedPlan = try HeistPlan("CartAddItem", parameter: "input") { _ in
            Warn("adding")
        }
        let request = try makeRunHeistRequest("CartAddItem", argument: "Milk") { _ in
            Warn("adding")
        }

        XCTAssertEqual(request.plan, expectedPlan)
        XCTAssertEqual(request.plan.name, "CartAddItem")
        XCTAssertEqual(request.plan.parameter, .string(name: "input"))
        XCTAssertEqual(request.argument, .string(.literal("Milk")))
    }

    func testRunHeistTestingFacadeElementTargetArgumentLowersLikeNamedHeistPlan() throws {
        let expectedPlan = try HeistPlan("RowsActivate", targetParameter: "input") { _ in
            Warn("activating")
        }
        let request = try makeRunHeistRequest(
            "RowsActivate",
            argument: ElementTarget.label("Milk")
        ) { _ in
            Warn("activating")
        }

        XCTAssertEqual(request.plan, expectedPlan)
        XCTAssertEqual(request.plan.name, "RowsActivate")
        XCTAssertEqual(request.plan.parameter, .elementTarget(name: "input"))
        XCTAssertEqual(request.argument, .elementTarget(.target(.label("Milk"))))
    }

    func testSingleElementTargetRootHeistBindsOneRootArgument() async throws {
        let job = TheInsideJob(token: "in-app-heist-target-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist(ElementTarget.label("Delete"), runtime: capture.runtime) { _ in
            Warn("target root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .elementTarget(.target(.label("Delete"))))
        XCTAssertEqual(capture.plan?.parameter, .elementTarget(name: "input"))
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
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await job.brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let evidence = try XCTUnwrap(step.repeatUntilEvidence)
        let iterationEvidence = try XCTUnwrap(step.children.first?.repeatUntilEvidence)

        XCTAssertTrue(result.success, result.message ?? "repeat_until failed")
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
                timeout: 0,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
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

        XCTAssertTrue(result.success, result.message ?? "repeat_until else failed")
        XCTAssertEqual(incrementCount, 0)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
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
            HeistExecutionWarning(path: "$.body[0]", message: "root"),
            HeistExecutionWarning(path: "$.body[1].invoke.body[0]", message: "nested"),
        ])
    }

    func testFailedHeistThrowsFailureWithInspectableResult() async throws {
        do {
            _ = try await runHeist("failedHeist") {
                Fail("stop")
            }
            XCTFail("Expected failed heist to throw")
        } catch let failure as Heist.Failure {
            XCTAssertEqual(failure.failedStepPath, "$.body[0]")
            XCTAssertEqual(failure.failedStepKind, .fail)
            XCTAssertEqual(failure.message, "stop")
            XCTAssertEqual(failure.result.steps.first?.kind, .fail)
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
                .failed(
                    path: "$.body[0]",
                    kind: .fail,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail(...) aborts the heist",
                        observed: "stop"
                    )
                ),
                .passed(
                    path: "$.body[0].failure.actions[0]",
                    kind: .action,
                    durationMs: 1,
                    intent: .action(command: .takeScreenshot),
                    evidence: .action(.dispatch(
                        command: .takeScreenshot,
                        dispatchResult: ActionResult.success(payload: .screenshot(screenshot))
                    ))
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[0]"
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
            XCTAssertNil(skipped.intent)
            XCTAssertNil(skipped.evidence)
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
    private var states: [PostActionObservation.BeforeState]
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextSequence: SettledObservationSequence = 0

    init(states: [PostActionObservation.BeforeState]) {
        self.states = states
    }

    func receipt(for step: ResolvedWaitStep) -> HeistWaitReceipt {
        guard !states.isEmpty else {
            let expectation = ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: "no settled semantic observation available"
            )
            return HeistWaitReceipt(
                status: .timedOut,
                message: expectation.actual,
                accessibilityTrace: nil,
                expectation: expectation
            )
        }

        let state = states.removeFirst()
        nextSequence += 1
        let trace = previousCapture.map { AccessibilityTrace(captures: [$0, state.capture]) }
            ?? AccessibilityTrace(capture: state.capture)
        previousCapture = state.capture

        let expectation = PredicateEvaluation.evaluate(step.predicate, in: trace)
        return HeistWaitReceipt(
            status: expectation.met ? .matched : .timedOut,
            message: expectation.actual,
            accessibilityTrace: trace,
            expectation: expectation,
            observedSequence: nextSequence,
            observationSummary: "known: \(state.interface.projectedElements.count) elements"
        )
    }
}

@MainActor
private func observedQuantityState(
    job: TheInsideJob,
    value: String
) -> PostActionObservation.BeforeState {
    let element = AccessibilityElement.make(
        value: value,
        identifier: "quantity",
        traits: .staticText
    )
    job.brains.stash.installScreenForTesting(.makeForTests(elements: [(element, HeistId(rawValue: "quantity"))]))
    return job.brains.postActionObservation.captureSemanticState()
}

@MainActor
private func repeatUntilRuntime(
    job _: TheInsideJob,
    waitScript: ReceiptWaitScript,
    execute: @escaping @MainActor (RuntimeActionMessage) async -> ActionResult
) -> TheBrains.HeistExecutionRuntime {
    TheBrains.HeistExecutionRuntime(
        execute: execute,
        wait: { request in
            waitScript.receipt(for: request.step)
        },
        selectPredicateCase: { _, _ in
            HeistCaseSelectionResult(cases: [], outcome: .noMatch, elapsedMs: 0)
        },
        observeSemanticState: { _, _, _ in
            nil
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
        throw HeistReceiptTestFailure("Expected wrapper plan to invoke a dotted heist definition")
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
