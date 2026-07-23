#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {

    func testHeistForEachWithZeroMatchesSucceedsWithoutIterations() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [
                await observedState(labels: ["Keep"]),
            ],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 20,
                parameter: "target",
                body: [.warn(WarnStep(message: "delete one"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .forEachElement)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(forEachResult.matchedCount, 0)
        XCTAssertEqual(step.forEachElementDeclaration?.limit, 20)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertNil(forEachResult.failureReason)
        XCTAssertNil(step.failure)
        XCTAssertTrue(step.children.isEmpty)
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistForEachStringChildFailureProducesExplicitLoopFailureOutcome() async throws {
        let runtime = heistRuntime(observations: [])
        let plan = try HeistPlan(body: [
            .forEachString(try ForEachStringStep(
                values: ["milk", "eggs"],
                parameter: "item",
                body: [.fail(FailStep(message: "stop loop"))]
            )),
            .warn(WarnStep(message: "should not run")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let forEachStep = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(forEachStep.forEachStringEvidence)
        let failedChildPath: HeistExecutionPath = "$.body[0].for_each_string.iterations[0].body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heistResult.abortedAtPath, failedChildPath)
        XCTAssertEqual(heistResult.steps.map(\.kind), [.forEachString, .warn, .action])
        XCTAssertEqual(heistResult.steps.map(\.status), [.failed, .skipped, .passed])
        XCTAssertEqual(forEachStep.status, .failed)
        XCTAssertEqual(forEachStep.forEachStringDeclaration?.count, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(
            forEachResult.failureReason,
            "iteration 0 failed for value \"milk\" at \(failedChildPath)"
        )
        XCTAssertEqual(
            forEachStep.failure?.observed,
            "iteration 0 failed for value \"milk\" at \(failedChildPath)"
        )
        XCTAssertEqual(forEachStep.abortedAtChildPath, failedChildPath)
        XCTAssertEqual(
            forEachStep.children.first?.forEachStringEvidence?.failureReason,
            "child failed at \(failedChildPath)"
        )
    }

    func testHeistForEachFailsBeforeMutationWhenMatchCountExceedsLimit() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [
                    (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
                    (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
                ]),
            ],
            execute: { command in
                executedCommands.append(command)
                if case .takeScreenshot = command {
                    return ActionResult.success(payload: .screenshot(nil))
                }
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 1,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(executedCommands, [.takeScreenshot])
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(step.forEachElementDeclaration?.limit, 1)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertEqual(forEachResult.failureReason, "matched 2 element(s), exceeding for_each_element limit 1")
        XCTAssertTrue(step.children.isEmpty)
        XCTAssertEqual(heistResult.steps.map(\.path), ["$.body[0]", "$.body[0].failure.actions[0]"])
        XCTAssertEqual(heistResult.failureScreenshotStep?.actionCommand, .takeScreenshot)
    }

    func testHeistForEachCallsBodyWithOrdinalTargetForEachInitialMatchWithoutMutatingPlan() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
            (makeElement(label: "Delete", identifier: "delete_third"), "delete_third"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, initialState, initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])
        let originalBody = plan.body

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 3)
        XCTAssertEqual(forEachResult.iterationCount, 3)
        let expectedCommands = try (0...2).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
        XCTAssertEqual(step.children.map(\.kind), [.forEachIteration, .forEachIteration, .forEachIteration])
        XCTAssertEqual(step.children.flatMap(\.children).map(\.kind), [.action, .action, .action])
        XCTAssertEqual(plan.body, originalBody)
    }

    func testHeistForEachPreservesCallerPredicateInsteadOfMinimumMatchers() async throws {
        let matching = ElementPredicateTemplate(label: "Delete", traits: [.button])
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = await observedState(elements: [
            (
                makeElement(label: "Delete", value: "First", identifier: "delete_first", traits: [.button]),
                "delete_first"
            ),
            (
                makeElement(label: "Delete", value: "Second", identifier: "delete_second", traits: [.button]),
                "delete_second"
            ),
        ])
        let runtime = heistRuntime(
            observations: [initialState, initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.resultPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommands = try (0...1).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistForEachResetsOrdinalWhenMatchedCollectionIdentityChanges() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let afterFirstMutation = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, afterFirstMutation],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertNil(forEachResult.failureReason)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        XCTAssertEqual(executedCommands, [expectedCommand, expectedCommand])
    }

    func testHeistForEachAdditionResetsOrdinalWithoutExtendingInitialIterationBudget() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let afterAddition = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_new"), "delete_new"),
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, afterAddition],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.resultPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        XCTAssertEqual(executedCommands, [expectedCommand, expectedCommand])
    }

    func testHeistForEachDoesNotResetOrdinalForStateOnlyMatchMutation() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first", traits: [.button]), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second", traits: [.button]), "delete_second"),
        ])
        let stateOnlyMutation = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first", traits: [.button, .selected]), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second", traits: [.button]), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, stateOnlyMutation],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.resultPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommands = try (0...1).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistForEachBodyFailureStopsBeforeFollowingTopLevelSteps() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState],
            execute: { _ in
                ActionResult.failure(
                    payload: .activate,
                    failureKind: .actionFailed,
                    message: "activate failed",
                )
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
            .warn(WarnStep(message: "should not run")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let forEachStep = try XCTUnwrap(heistResult.steps.first)
        let forEachResult = try XCTUnwrap(forEachStep.forEachElementEvidence)
        let failedActionPath: HeistExecutionPath = "$.body[0].for_each_element.iterations[0].body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heistResult.abortedAtPath, failedActionPath)
        XCTAssertEqual(heistResult.steps.map(\.kind), [.forEachElement, .warn])
        XCTAssertEqual(heistResult.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(forEachStep.status, .failed)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(forEachResult.failureReason, "iteration 0 failed at \(failedActionPath)")
        XCTAssertEqual(forEachStep.failure?.observed, "iteration 0 failed at \(failedActionPath)")
        XCTAssertEqual(forEachStep.abortedAtChildPath, failedActionPath)
        XCTAssertEqual(forEachStep.children.map(\.kind), [.forEachIteration])
        XCTAssertEqual(forEachStep.children.first?.children.map(\.kind), [.action])
        XCTAssertEqual(
            forEachStep.children.first?.forEachElementEvidence?.failureReason,
            "child failed at \(failedActionPath)"
        )
    }

    func testHeistForEachExpectationUsesCurrentSemanticTarget() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        var waitedSteps: [ResolvedWaitRuntimeInput] = []
        let initialState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let stillPresentState = await observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let waitObservedState = await observedState(labels: ["Done"])
        let runtime = heistRuntime(
            observations: [initialState, stillPresentState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(
                    payload: .activate,
                    observation: .trace(makeTestTraceEvidence(
                        AccessibilityTrace(capture: stillPresentState.capture),
                        completeness: .incomplete
                    ))
                )
            },
            wait: { request in
                waitedSteps.append(request.step)
                return ActionResult.success(
                    payload: .wait,
                    observation: .trace(makeTestTraceEvidence(
                        AccessibilityTrace(capture: waitObservedState.capture),
                        completeness: .incomplete
                    ))
                )
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [
                    .action(ActionStep(
                        command: .activate(.ref("target")),
                        expectationPolicy: .expect(ActionExpectation(
                            predicate: .missing(.ref("target")),
                            timeout: 2
                        )))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let forEachResult = try XCTUnwrap(heistResult.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        let authoredExpectation = AccessibilityPredicate.missing(.ref("target"))
        let resolvedExpectation = try resolvedPredicate(.missing(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(executedCommands.first, expectedCommand)
        XCTAssertEqual(waitedSteps.first?.predicateExpression, authoredExpectation)
        XCTAssertEqual(waitedSteps.first?.predicate, resolvedExpectation)
        XCTAssertEqual(executedCommands.last, expectedCommand)
        XCTAssertEqual(waitedSteps.last?.predicateExpression, authoredExpectation)
        XCTAssertEqual(waitedSteps.last?.predicate, resolvedExpectation)
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
