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
        let classifiedRuntimeFailure = HeistExecution.Failure.classify(
            HeistResultTestFailure("runtime boundary")
        )

        XCTAssertEqual(runtimeFailure.serverError.kind, .general)
        XCTAssertTrue(runtimeFailure.serverError.message.description.contains("duplicate execution path"))
        XCTAssertEqual(admissionFailure.serverError.kind, .validationError)
        XCTAssertTrue(admissionFailure.serverError.message.description.contains("duplicate execution path"))
        guard case .accessibilityTreeUnavailable = HeistExecution.Failure.classify(
            HeistExecution.Failure.accessibilityTreeUnavailable
        ) else {
            return XCTFail("Expected typed execution failure to retain its classification")
        }
        guard case .runtimeBoundary = classifiedRuntimeFailure else {
            return XCTFail("Expected an unknown error to become a runtime boundary failure")
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

    func testTopLevelHeistBootstrapsFromFreshVisibleScreen() async throws {
        let visibleObservationSource = VisibleObservationSourceFixture(observation: nil)
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

        _ = try await job.executeInAppHeist(try HeistPlan {
            Warn("bootstrapped")
        })

        XCTAssertEqual(job.brains.vault.interfaceElementIDs, ["buttonheist_demo"])
        XCTAssertNil(job.brains.vault.interfaceElement(heistId: "stale_row"))
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
        let cause = "Could not restore the accessibility viewport after observation"
        let expected = #".exists(.label("Order placed"))"#
        let result = try HeistResult(
            steps: [
                HeistResultFixture.action(
                    path: "$.body[0]",
                    result: HeistResultFixture.actionResult(
                        succeeded: false,
                        message: cause,
                        failureKind: .actionFailed
                    ),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "post-action expectation is met",
                        observed: cause,
                        expected: expected
                    )
                ),
            ],
            failureCapture: .captured(screenshot),
            durationMs: 2
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(
            description.hasPrefix(
                """
                Activate .label("Button") failed
                Cause: \(cause)
                Contract: post-action expectation is met
                Expected: \(expected)
                """
            ),
            description
        )
        XCTAssertTrue(
            description.contains("failure screenshot: 12x34 interface=21 elements"),
            description
        )
        XCTAssertTrue(description.contains("failure interface: 21 elements"), description)
        XCTAssertTrue(description.contains("[0] \"Actual Empty State\" staticText id=\"empty_state\""), description)
        XCTAssertTrue(description.contains("[20] \"Actual Empty State 20\" staticText id=\"empty_state_20\""), description)
        XCTAssertFalse(description.contains("... and 1 more"), description)
        XCTAssertTrue(description.contains("frame=(10,20,100,44) activation=(60,42)"), description)
        XCTAssertEqual(description.components(separatedBy: cause).count - 1, 1, description)
        XCTAssertFalse(description.contains("category="), description)
        XCTAssertFalse(description.contains("diagnostic="), description)
        XCTAssertFalse(description.contains("failureKind="), description)
        XCTAssertFalse(description.contains("observed="), description)
        XCTAssertEqual(result.failureScreenshotPayload, screenshot)
        XCTAssertEqual(
            result.failureDiagnosticInterface?.projectedElements.first?.semantics.assertable.label,
            "Actual Empty State"
        )
    }

    func testFailureDescriptionLabelsDispatchTarget() throws {
        let target = #".element(.label("Fallback field"), .traits([.textEntry]))"#
        let result = try HeistResult(
            steps: [
                HeistResultFixture.action(
                    path: "$.body[0]",
                    result: HeistResultFixture.actionResult(
                        succeeded: false,
                        message: "timed out while waiting for .exists(.value(\"fallback typed\"))",
                        failureKind: .timeout
                    ),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "action dispatch succeeds",
                        observed: "timed out while waiting for .exists(.value(\"fallback typed\"))",
                        expected: target
                    )
                ),
            ],
            durationMs: 2
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(description.contains("Target: \(target)"), description)
        XCTAssertFalse(description.contains("Expected:"), description)
        XCTAssertTrue(description.contains("Contract: action dispatch succeeds"), description)
    }

    func testFailureDescriptionLabelsWaitPredicateAsExpected() throws {
        let expected = #".exists(.label("Order placed"))"#
        let result = try HeistResult(
            steps: [
                HeistResultFixture.failedWait(
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "wait predicate is met before timeout",
                        observed: "Could not restore the accessibility viewport after observation",
                        expected: expected
                    )
                ),
            ],
            durationMs: 2
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(description.contains("Expected: \(expected)"), description)
        XCTAssertFalse(description.contains("Target:"), description)
    }

    func testFailureDescriptionIncludesValidationContract() throws {
        let result = try HeistResult(
            steps: [
                HeistResultFixture.action(
                    path: "$.body[0]",
                    result: HeistResultFixture.actionResult(
                        succeeded: false,
                        message: "invalid expectation",
                        failureKind: .validationError
                    ),
                    failure: HeistFailureDetail(
                        category: .validation,
                        contract: "action expectation predicate resolves before evaluation",
                        observed: "invalid expectation"
                    )
                ),
            ],
            durationMs: 2
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(
            description.contains("Contract: action expectation predicate resolves before evaluation"),
            description
        )
    }

    func testFailureDescriptionUsesHumanLocationAndExistingWaitEvidence() throws {
        let condition = AccessibilityPredicate.exists(.label("Add-ons"))
        let selection = HeistCaseSelectionResult.selectingFirstMatch(
            cases: [HeistCaseMatchResult(predicate: condition, met: false)],
            ifNone: .noMatch,
            elapsedMs: 1
        ).selectingElseBranch()
        let action = HeistResultFixture.action(
            path: "$.body[0].conditional.else_body[0]",
            command: .activate(.label("Add-ons"))
        )
        let current = makeTestObservationSnapshot(elements: [])
        let notification = try XCTUnwrap(Observation.Notification(text: "Still loading", element: nil))
        let waitEvidence = HeistResultFixture.expectationEvidence(
            predicate: .exists(.label("Done")),
            observation: Observation.Evidence(
                baseline: nil,
                events: [
                    .elementsChanged(current),
                    .notification(notification),
                    .noChange,
                ],
                current: current,
                coverage: .complete
            ),
            terminalCause: .deadline
        )
        let wait = HeistResultFixture.failedWait(
            path: "$.body[0].conditional.else_body[1]",
            evidence: waitEvidence,
            failure: HeistFailureDetail(
                category: .timeout,
                contract: "wait predicate is met before timeout",
                observed: "timed out",
                expected: AccessibilityPredicate.exists(.label("Done")).description
            )
        )
        let result = try HeistResult(
            steps: [HeistResultFixture.conditional(selection: selection, children: [action, wait])],
            durationMs: 251
        )

        let description = Heist.Failure(result).description

        XCTAssertTrue(
            description.hasPrefix(
                """
                Wait for .exists(.label("Done")) failed after 250ms
                Where:
                  Otherwise, when .exists(.label("Add-ons")) was not met
                Cause: timed out
                """
            ),
            description
        )
        XCTAssertTrue(description.contains("Recent steps:"), description)
        XCTAssertTrue(description.contains("✓ Activate .label(\"Add-ons\")  250ms"), description)
        XCTAssertTrue(description.contains("No semantic screen change observed"), description)
        XCTAssertTrue(description.contains("✗ Wait for .exists(.label(\"Done\"))  250ms"), description)
        XCTAssertTrue(description.contains("Wait evidence:"), description)
        XCTAssertTrue(description.contains("Screen changes: 0"), description)
        XCTAssertTrue(description.contains("Semantic element changes: 1"), description)
        XCTAssertTrue(description.contains("Notifications: 1"), description)
        XCTAssertTrue(description.contains("Final interface quiet: 125ms"), description)
        XCTAssertTrue(description.contains("Observation coverage: complete"), description)
        XCTAssertFalse(description.contains("$.body"), description)
        XCTAssertEqual(Heist.Failure(result).failedStepPath, "$.body[0].conditional.else_body[1]")
    }

    func testFailureDescriptionDoesNotInferAbsenceFromIncompleteEvidence() throws {
        let wait = HeistResultFixture.failedWait(
            evidence: HeistResultFixture.expectationEvidence(
                predicate: .exists(.label("Done")),
                observation: Observation.Evidence(
                    baseline: nil,
                    events: [.noChange],
                    current: nil,
                    coverage: .incomplete(.historyUnavailable)
                ),
                terminalCause: .deadline
            ),
            failure: HeistFailureDetail(
                category: .timeout,
                contract: "wait predicate is met before timeout",
                observed: "timed out"
            )
        )
        let result = try HeistResult(steps: [wait], durationMs: 500)

        let description = Heist.Failure(result).description

        XCTAssertTrue(description.contains("Screen changes: unknown"), description)
        XCTAssertTrue(description.contains("Semantic element changes recorded: 0"), description)
        XCTAssertTrue(description.contains("Notifications recorded: 0"), description)
        XCTAssertTrue(description.contains("Observation coverage: incomplete"), description)
        XCTAssertFalse(description.contains("Final interface quiet:"), description)
    }

    func testFailureDescriptionLimitsRecentStepsToFive() throws {
        let actions = (0..<6).map { index in
            HeistResultFixture.action(
                path: "$.body[\(index)]",
                command: .activate(.label("Action \(index)"))
            )
        }
        let wait = HeistResultFixture.failedWait(
            path: "$.body[6]",
            failure: HeistFailureDetail(
                category: .timeout,
                contract: "wait predicate is met before timeout",
                observed: "timed out"
            )
        )
        let result = try HeistResult(steps: actions + [wait], durationMs: 1_000)

        let description = Heist.Failure(result).description

        XCTAssertFalse(description.contains("Action 0"), description)
        XCTAssertFalse(description.contains("Action 1"), description)
        for index in 2..<6 {
            XCTAssertTrue(description.contains("Action \(index)"), description)
        }
        XCTAssertEqual(description.components(separatedBy: "  ✓ Activate").count - 1, 4)
        XCTAssertEqual(description.components(separatedBy: "  ✗ Wait for").count - 1, 1)
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
