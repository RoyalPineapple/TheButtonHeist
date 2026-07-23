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

    func testHeistConditionalSelectsFirstMatchingCaseOnce() async throws {
        var observationTimeouts: [Double?] = []
        var waitCount = 0
        let runtime = heistRuntime(
            observations: [
                await observedState(labels: ["Home", "Login"]),
            ],
            wait: { _ in
                waitCount += 1
                preconditionFailure("conditional scheduled a wait")
            },
            observedTimeouts: { observationTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .exists(.label("Login")),
                    body: [.fail(FailStep(message: "wrong branch"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
        XCTAssertEqual(observationTimeouts, [0])
        XCTAssertEqual(waitCount, 0)
    }

    func testHeistConditionalUnmatchedWithoutElseContinues() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
            .warn(WarnStep(message: "continued")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(heistResult.steps.map(\.kind), [.conditional, .warn])
        XCTAssertEqual(
            heistResult.steps.first?.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.noMatch
        )
    }

    func testHeistConditionalUnmatchedRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.fail(FailStep(message: "should not run"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "settings flow"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let step = try XCTUnwrap(result.resultPayload?.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistWaitForTimeoutWithoutElseFails() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Home")),
                timeout: .milliseconds(1)
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistWaitForTimeoutWithElseRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Home")),
                timeout: .milliseconds(1),
                elseBody: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistRepeatUntilRepeatsBodyUntilPredicateMet() async throws {
        var incrementCount = 0
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(payload: .increment)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 1,
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertNil(step.repeatUntilEvidence?.failureReason)
        XCTAssertNil(step.failure)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .repeatUntilIteration])
    }

    func testHeistRepeatUntilExecutesBodyOnceWhenPredicateIsInitiallyMet() async throws {
        var incrementCount = 0
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(payload: .increment)
            },
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.identifier("quantity")),
                timeout: 5,
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(observedTimeouts.count, 2)
        XCTAssertEqual(observedTimeouts[0], 0)
        let observedTimeout = try XCTUnwrap(observedTimeouts[1])
        XCTAssertEqual(observedTimeout, defaultActionExpectationTimeout.seconds, accuracy: 0.1)
    }

    func testHeistRepeatUntilExecutesBodyWhenBaselineObservationIsUnavailable() async throws {
        var incrementCount = 0
        var waitBaselines: [Settlement.Baseline] = []
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(payload: .increment)
            },
            observedWaitCommands: { waitBaselines.append($0.baseline) },
            unavailableObservationCount: 1
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.identifier("quantity")),
                timeout: 1,
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(waitBaselines, [.capture])
    }

    func testHeistRepeatUntilChainsExactObservationMomentsAcrossPostBodyWaits() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let initialState = await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let firstMutation = await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")])
        let secondMutation = await observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let events = observationEvents(for: [initialState, firstMutation, secondMutation])
        var incrementCount = 0
        var nextObservationIndex = 1
        var postBodyBaselines: [Observation.Moment] = []
        let runtime = repeatUntilWaitRuntime(
            observations: [initialState],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(payload: command.resultPayload)
            },
            wait: { command in
                guard case .supplied(let boundary) = command.baseline else {
                    XCTFail("repeat_until should supply its exact observation boundary")
                    return scriptedSettlement(command, observation: nil)
                }
                postBodyBaselines.append(boundary.moment)
                let event = events[nextObservationIndex]
                nextObservationIndex += 1
                return scriptedSettlement(command, observation: event)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: 1,
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        guard case .heist(let payload) = result.payload,
              let heistResult = payload else {
            return XCTFail("Expected heist execution payload")
        }
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
        XCTAssertEqual(postBodyBaselines.count, 2)
        XCTAssertEqual(postBodyBaselines[0].capture, initialState.moment.capture)
        XCTAssertEqual(postBodyBaselines[1], events[1].moment)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(
            step.children.map(\.kind),
            [HeistExecutionStepKind.repeatUntilIteration, .repeatUntilIteration]
        )
    }

    func testHeistRepeatUntilSucceedsWhenBodyActionFailsAfterPredicateMet() async throws {
        var activationCount = 0
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult.failure(
                            payload: .activate,
                            failureKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                        )
                    }
                }
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 1,
                body: [
                    .action(ActionStep(command: .activate(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let secondIteration = try XCTUnwrap(step.children.last)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertNil(heistResult.abortedAtPath)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .repeatUntilIteration])
        XCTAssertEqual(secondIteration.status, .passed)
        XCTAssertNil(secondIteration.abortedAtChildPath)
        XCTAssertTrue(secondIteration.children.isEmpty)
    }

    func testHeistRepeatUntilBodyActionFailureStillFailsWhenPredicateUnmet() async throws {
        var activationCount = 0
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult.failure(
                            payload: .activate,
                            failureKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                        )
                    }
                }
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 1,
                body: [
                    .action(ActionStep(command: .activate(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)
        let failedIteration = try XCTUnwrap(step.children.last)
        let failedRetry = try XCTUnwrap(failedIteration.children.first)
        let failedRetryPath: HeistExecutionPath = "$.body[0].repeat_until.iterations[1].body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(heistResult.abortedAtPath, failedRetryPath)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(
            step.repeatUntilEvidence?.failureReason,
            "iteration 1 failed at \(failedRetryPath)"
        )
        XCTAssertEqual(step.failure?.observed, "iteration 1 failed at \(failedRetryPath)")
        XCTAssertEqual(failedIteration.status, .failed)
        XCTAssertEqual(
            failedIteration.repeatUntilEvidence?.failureReason,
            "child failed at \(failedRetryPath)"
        )
        XCTAssertEqual(failedRetry.status, .failed)
        XCTAssertEqual(failedRetry.actionEvidence?.dispatchResult?.outcome.failureKind, .actionFailed)
    }

    func testHeistRepeatUntilMinimumTimeoutFailsAfterRunningBodyOnce() async throws {
        var incrementCount = 0
        let quantityZero = await observedState(elements: [
            (makeElement(value: "0", identifier: "quantity"), "quantity"),
        ])
        let runtime = heistRuntime(
            observations: [quantityZero, quantityZero],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(payload: .increment)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: .milliseconds(1),
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .failed)
        XCTAssertTrue(step.repeatUntilEvidence?.failureReason?.contains("timed out") == true)
        XCTAssertNotNil(step.failure)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration])
    }

    func testHeistIfNoOpsWhenImmediateObservationIsUnavailable() async throws {
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Home"])],
            unavailableObservationCount: 1
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.noMatch
        )
        XCTAssertEqual(step.children.map(\.kind), [])
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
