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
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Home", "Login"]),
        ])
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistConditionalUnmatchedWithoutElseContinues() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(heist.steps.map(\.kind), [.conditional, .warn])
        XCTAssertEqual(
            heist.steps.first?.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
    }

    func testHeistWaitForTimeoutWithoutElseFails() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Home")),
                timeout: .milliseconds(1)
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistWaitForTimeoutWithElseRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Home")),
                timeout: .milliseconds(1),
                elseBody: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistRepeatUntilRepeatsBodyUntilPredicateMet() async throws {
        var incrementCount = 0
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue)
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

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
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue)
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

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
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue)
            },
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
    }

    func testHeistRepeatUntilUsesActionTraceProgressBeforePostBodyWait() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let firstMutation = observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")])
        let secondMutation = observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let states = [initialState, firstMutation, secondMutation]
        var incrementCount = 0
        let runtime = repeatUntilReceiptRuntime(
            observations: [initialState],
            execute: { command in
                guard case .increment = command else {
                    return ActionResult.success(method: .activate)
                }
                let before = states[incrementCount]
                incrementCount += 1
                let after = states[incrementCount]
                let actionTrace = AccessibilityTrace(capture: before.capture).appending(
                    after.capture.interface,
                    context: after.capture.context,
                    transition: after.capture.transition
                )
                return ActionResult.success(
                    method: .increment,
                        observation: .settledTrace(
                            makeTestTraceEvidence(
                                actionTrace,
                                completeness: .incomplete
                            ),
                            .settled(duration: 0)
                        )

                )
            },
            wait: { request in
                switch request {
                case .immediate:
                    let initialTrace = AccessibilityTrace(capture: initialState.capture)
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    XCTFail("repeat_until should use action trace progress before post-body wait")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected post-body wait",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected post-body wait"
                        )
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
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
        guard case .heistExecution(let heist) = result.payload else {
            return XCTFail("Expected heist execution payload")
        }
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
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
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult.failure(
                            method: .activate,
                            errorKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                        )
                    }
                }
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue)
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let secondIteration = try XCTUnwrap(step.children.last)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertNil(heist.abortedAtPath)
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
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult.failure(
                            method: .activate,
                            errorKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                        )
                    }
                }
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue)
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let failedIteration = try XCTUnwrap(step.children.last)
        let failedRetry = try XCTUnwrap(failedIteration.children.first)
        let failedRetryPath: HeistExecutionPath = "$.body[0].repeat_until.iterations[1].body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(heist.abortedAtPath, failedRetryPath)
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
        XCTAssertEqual(failedRetry.actionEvidence?.dispatchResult?.outcome.errorKind, .actionFailed)
    }

    func testHeistRepeatUntilMinimumTimeoutWithElseRunsBodyOnce() async throws {
        var incrementCount = 0
        let quantityZero = observedState(elements: [
            (makeElement(value: "0", identifier: "quantity"), "quantity"),
        ])
        let runtime = heistRuntime(
            observations: [quantityZero, quantityZero],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue)
            }
        )
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

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until else failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .handledElse)
        XCTAssertNil(step.failure)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .warn])
    }

    func testHeistRepeatUntilPostBodyMatchedWaitWithoutObservedSequenceDoesNotReusePreviousSequence() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let matchedState = observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let matchedTrace = AccessibilityTrace(interface: matchedState.interface)
        var afterObservationCount = 0
        let runtime = repeatUntilReceiptRuntime(
            observations: [initialState],
            wait: { request in
                switch request {
                case .immediate:
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    afterObservationCount += 1
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: matchedTrace,
                        completeness: .incomplete
                    )
                    return .matched(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(matchedTrace, completeness: .incomplete),
                        expectation: self.metExpectation(expectation)
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(afterObservationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(
            step.repeatUntilEvidence?.expectation.actual,
            "repeat_until post-body check matched without settled observation"
        )
        XCTAssertNil(step.repeatUntilEvidence?.lastObservedSummary)
    }

    func testHeistRepeatUntilPostBodyNilTraceWithNewSequenceDoesNotReuseStaleTraceOrSummary() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let runtime = repeatUntilReceiptRuntime(
            observations: [initialState],
            wait: { request in
                switch request {
                case .immediate:
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    return .timedOut(
                        message: "no observed accessibility trace",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: .changed(.elements()),
                            actual: "no observed accessibility trace"
                        ),
                        observedSequence: 2,
                        observationSummary: nil
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.actual, "no observed accessibility trace")
        XCTAssertNil(step.repeatUntilEvidence?.lastObservedSummary)
    }

    func testHeistRepeatUntilTimeoutElseChildFailureReportsElsePath() async throws {
        let quantityZero = observedState(elements: [
            (makeElement(value: "0", identifier: "quantity"), "quantity"),
        ])
        let runtime = heistRuntime(observations: [quantityZero, quantityZero])
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: .milliseconds(1),
                body: [
                    .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ],
                elseBody: [
                    .fail(FailStep(message: "quantity did not reach 2")),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let elseFailurePath: HeistExecutionPath = "$.body[0].repeat_until.else_body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heist.abortedAtPath, elseFailurePath)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.abortedAtChildPath, elseFailurePath)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertTrue(step.repeatUntilEvidence?.failureReason?.contains("else body failed at \(elseFailurePath)") == true)
        XCTAssertEqual(step.failure?.observed, "child failed at \(elseFailurePath)")
        XCTAssertEqual(step.children.last?.path, elseFailurePath)
    }

    func testHeistIfSelectsMatchingCaseImmediately() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Home"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .exists(.label("Settings")),
                    body: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testPredicateObservationStreamSeparatesStateAndChangeEvidence() async throws {
        let readyTarget = AccessibilityTarget.label("Ready")
        let observationStream = brains.vault.semanticObservationStream
        let baselineEvent = observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [(makeElement(label: "Loading"), HeistId(rawValue: "loading"))])
        )
        let changedEvent = observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [
                (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
                (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
            ])
        )
        var stream = PredicateObservationStreamState()

        let baselineObservation = brains.postActionObservation.semanticObservation(from: baselineEvent)
        let changePredicate = AccessibilityPredicate.changed(.elements([.appeared(readyTarget)]))
        let resolvedChangePredicate = try resolvedPredicate(changePredicate)
        stream = stream.seedingBaseline(
            .currentObservation,
            from: baselineEvent,
            when: resolvedChangePredicate.requiresChangeBaseline
        )
        let seeded = stream.reducing(
            baselineObservation,
            predicate: resolvedChangePredicate,
            predicateExpression: changePredicate
        )
        stream = seeded.state

        XCTAssertFalse(seeded.reduction.expectation.met)
        XCTAssertEqual(
            seeded.reduction.expectation.actual,
            PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
        )

        let changedObservation = brains.postActionObservation.semanticObservation(from: changedEvent)
        let baseline = try XCTUnwrap(seeded.state.observationBaseline)
        let changed = stream.reducing(
            changedObservation,
            predicate: resolvedChangePredicate,
            predicateExpression: changePredicate,
            observationWindow: try XCTUnwrap(observationStream.observationWindow(
                from: baseline,
                through: changedEvent
            ))
        )
        let stateExpression = AccessibilityPredicate.exists(readyTarget)
        let stateExpectation = PredicateEvaluation.evaluate(
            try resolvedPredicate(stateExpression),
            expression: stateExpression,
            in: changed.reduction.evidence
        )

        XCTAssertTrue(stateExpectation.met)
        XCTAssertTrue(changed.reduction.expectation.met)
        XCTAssertEqual(changed.reduction.changeBaseline?.cursor.sequence, baselineObservation.event.sequence)
    }

    func testHeistIfNoOpsWhenImmediateObservationIsUnavailable() async throws {
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistIfPassesImmediateObservationBudget() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Settings"])],
            observedTimeouts: { observedTimeouts.append($0) }
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

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedTimeouts, [0])
    }

}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

#endif
