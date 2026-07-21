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

    func testWaitResultFactoriesBindCanonicalActionAndExpectationOutcomes() {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let met = ExpectationResult.Met(predicate: predicate, actual: "found")
        let unmet = ExpectationResult.Unmet(predicate: predicate, actual: "not found")

        let matched = HeistWaitResult.matched(
            message: "matched",
            traceEvidence: nil,
            expectation: met
        )
        let timedOut = HeistWaitResult.timedOut(
            message: "timed out",
            traceEvidence: nil,
            expectation: unmet
        )
        let failed = HeistWaitResult.failed(
            failureKind: .actionFailed,
            message: "failed",
            traceEvidence: nil,
            expectation: unmet
        )

        guard case .matched(let matchedResult, let matchedExpectation) = matched.outcome else {
            return XCTFail("matched result must carry a matched result")
        }
        XCTAssertTrue(matchedResult.outcome.isSuccess)
        XCTAssertEqual(matchedExpectation, met)
        XCTAssertEqual(matchedResult.method, .wait)

        guard case .unmatched(let timeoutResult, let timeoutExpectation) = timedOut.outcome else {
            return XCTFail("timed-out result must carry an unmatched result")
        }
        XCTAssertEqual(timeoutResult.outcome.failureKind, .timeout)
        XCTAssertEqual(timeoutExpectation, unmet)

        guard case .unmatched(let failedResult, let failedExpectation) = failed.outcome else {
            return XCTFail("failed result must carry an unmatched result")
        }
        XCTAssertEqual(failedResult.outcome.failureKind, .actionFailed)
        XCTAssertEqual(failedExpectation, unmet)
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

    func testRunHeistFacadeAcceptsEvidenceContinuity() async throws {
        let reference = try evidenceContinuityReference()

        let heist = try await runHeist(
            "PublicFacade.continuity",
            continuity: reference
        ) {
            Warn("continued")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke])
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

    func testRunHeistSyncAcceptsEvidenceContinuity() throws {
        let heist = runHeistSync(
            "syncContinuity",
            continuity: try evidenceContinuityReference()
        ) {
            Warn("continued")
        }

        XCTAssertNotNil(heist)
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

    func testHeistInitializersForwardEvidenceContinuityToInAppRuntime() async throws {
        let job = try TheInsideJob(token: "in-app-heist-continuity-test")
        let capture = RuntimeCapture(job: job)
        let reference = try evidenceContinuityReference()
        let plan = try HeistPlan { Warn("prebuilt") }

        _ = try await Heist(
            plan,
            continuity: reference,
            runtime: capture.runtime
        )
        XCTAssertEqual(capture.continuity, reference)

        _ = try await Heist(
            continuity: reference,
            runtime: capture.runtime
        ) {
            Warn("builder")
        }
        XCTAssertEqual(capture.continuity, reference)

        _ = try await Heist(
            "milk",
            continuity: reference,
            runtime: capture.runtime
        ) { _ in
            Warn("string")
        }
        XCTAssertEqual(capture.continuity, reference)

        _ = try await Heist(
            AccessibilityTarget.label("Delete"),
            continuity: reference,
            runtime: capture.runtime
        ) { _ in
            Warn("target")
        }
        XCTAssertEqual(capture.continuity, reference)
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
        job.brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(staleDiscovery)

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
        let waitScript = WaitResultScript(states: [
            observedQuantityState(job: job, value: "0"),
            observedQuantityState(job: job, value: "2"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, waitScript: waitScript) { command in
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
        let waitScript = WaitResultScript(states: [
            observedQuantityState(job: job, value: "0"),
        ])
        var incrementCount = 0
        let runtime = repeatUntilRuntime(job: job, waitScript: waitScript) { command in
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

    func testFailureDescriptionIncludesScreenshotInterfaceDump() throws {
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

    func testResultMatchesDirectBrainsExecutionShape() async throws {
        let job = try TheInsideJob(token: "in-app-heist-machinery-test")
        let plan = try HeistPlan {
            Warn("same executor")
        }

        job.brains.startSemanticObservation()
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
    private(set) var continuity: EvidenceContinuity.Reference?

    init(job: TheInsideJob) {
        self.job = job
    }

    var runtime: InAppHeistRuntime {
        InAppHeistRuntime { plan, argument, continuity in
            self.plan = plan
            self.argument = argument
            self.continuity = continuity
            return await self.job.executeInAppHeist(
                plan,
                argument: argument,
                continuity: continuity
            )
        }
    }
}

private func evidenceContinuityReference() throws -> EvidenceContinuity.Reference {
    try JSONDecoder().decode(
        EvidenceContinuity.Reference.self,
        from: Data(#""4B47F5F7-76E7-4DF1-A52E-658343D48091""#.utf8)
    )
}

@MainActor
private final class WaitResultScript {
    private var states: [ActionEvidenceProjector.Baseline]
    private var previousObservation: SettledObservation?
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextSequence: SettledObservationSequence = 0

    init(states: [ActionEvidenceProjector.Baseline]) {
        self.states = states
    }

    func observation(scope: SemanticObservationScope) -> SettledObservationEvidence? {
        guard !states.isEmpty else { return nil }
        let state = states.removeFirst()
        nextSequence += 1
        let trace = previousCapture.map {
            AccessibilityTrace(capture: $0).appending(
                state.capture.interface,
                context: state.capture.context,
                transition: state.capture.transition
            )
        } ?? AccessibilityTrace(capture: state.capture)
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
        previousCapture = trace.captures.last
        return SettledObservationEvidence(
            event: event,
            baseline: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }

    func result(for step: ResolvedWaitRuntimeInput) -> HeistWaitResult {
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
) -> ActionEvidenceProjector.Baseline {
    let element = AccessibilityElement.make(
        value: value,
        identifier: "quantity",
        traits: .staticText
    )
    job.brains.vault.installObservationForTesting(.makeForTests(elements: [(element, HeistId(rawValue: "quantity"))]))
    return job.brains.actionEvidenceProjector.projectBaseline()
}

@MainActor
private func repeatUntilRuntime(
    job _: TheInsideJob,
    waitScript: WaitResultScript,
    execute: @escaping @MainActor (ResolvedHeistActionCommand) async -> ActionResult
) -> TheBrains.HeistExecutionRuntime {
    TheBrains.HeistExecutionRuntime(
        execute: { command, _ in
            RuntimeActionExecution(
                result: await execute(command),
                successfulActionBoundary: nil,
                includesExpectationBaseline: false
            )
        },
        wait: { request in
            waitScript.result(for: request.step)
        },
        selectPredicateCase: { _, _ in
            .selectingFirstMatch(cases: [], ifNone: .noMatch, elapsedMs: 0)
        },
        settledEvidence: { scope, _, _ in
            waitScript.observation(scope: scope)
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
