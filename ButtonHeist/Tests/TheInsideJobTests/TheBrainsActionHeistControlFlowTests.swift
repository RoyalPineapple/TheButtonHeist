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
            await observedState(labels: ["Home", "Login"]),
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
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
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
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
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
    }

    func testHeistRepeatUntilChainsExactObservationMomentsAcrossPostBodyWaits() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let initialState = await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let firstMutation = await observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")])
        let secondMutation = await observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let states = [initialState, firstMutation, secondMutation]
        let moments = observationMoments(for: states)
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
            wait: { request in
                switch request {
                case .afterObservation(_, _, let baseline):
                    postBodyBaselines.append(baseline)
                    let state = states[nextObservationIndex]
                    let moment = moments[nextObservationIndex]
                    nextObservationIndex += 1
                    return .matched(
                        message: "observed change",
                        traceEvidence: makeTestTraceEvidence(
                            AccessibilityTrace(capture: state.capture),
                            completeness: .incomplete
                        ),
                        expectation: ExpectationResult.Met(
                            predicate: .changed(.elements()),
                            actual: "observed change"
                        ),
                        observationMoment: moment,
                        observationSummary: "interface: 1 elements"
                    )
                case .standalone, .actionEndpoint, .immediate, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        failureKind: .actionFailed,
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
        guard case .heist(let payload) = result.payload,
              let heistResult = payload else {
            return XCTFail("Expected heist execution payload")
        }
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
        XCTAssertEqual(postBodyBaselines.count, 2)
        XCTAssertEqual(postBodyBaselines[1], moments[1])
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

    func testHeistRepeatUntilPostBodyMatchedWaitWithoutObservedMomentDoesNotReusePreviousMoment() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let matchedState = await observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let initialMoment = observationMoments(for: [initialState])[0]
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let matchedTrace = AccessibilityTrace(interface: matchedState.interface)
        var afterObservationCount = 0
        let runtime = repeatUntilWaitRuntime(
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
                        observationMoment: initialMoment,
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
                        failureKind: .actionFailed,
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
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

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

    func testHeistRepeatUntilPostBodyNilTraceWithNewMomentDoesNotReuseStaleTraceOrSummary() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = await observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let moments = observationMoments(for: [initialState, initialState])
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let runtime = repeatUntilWaitRuntime(
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
                        observationMoment: moments[0],
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
                        observationMoment: moments[1],
                        observationSummary: nil
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        failureKind: .actionFailed,
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
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.actual, "no observed accessibility trace")
        XCTAssertNil(step.repeatUntilEvidence?.lastObservedSummary)
    }

    func testHeistIfSelectsMatchingCaseImmediately() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Home"]),
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
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testZeroTimeoutCaseMatchesLatestAdmittedLevelStateWithoutSchedulingWork() async throws {
        await installSyntheticObservation(.makeForTests(elements: [
            (makeElement(label: "Rotor Host"), HeistId(rawValue: "rotor_host")),
        ]))
        let stream = brains.vault.semanticObservationStream
        let initialMoment = await stream.storeOwner.latestCommittedMoment()
        var scheduledEffects: [PredicateWait.ScheduledEffect] = []
        brains.interactionCoordinator.observePredicateWaitScheduledEffects {
            scheduledEffects.append($0)
        }
        let predicateCase = PredicateCase(
            predicate: .exists(.label("Rotor Host")),
            body: []
        )
        let input = try ResolvedPredicateCaseRuntimeInput(
            resolving: predicateCase,
            in: .empty
        )

        let result = await brains.interactionCoordinator.waitForPredicateCases(
            [input],
            timeout: 0
        )
        let finalMoment = await stream.storeOwner.latestCommittedMoment()

        XCTAssertEqual(result.outcome, .matchedCase(index: 0))
        XCTAssertEqual(result.cases.map(\.met), [true])
        XCTAssertTrue(scheduledEffects.isEmpty)
        XCTAssertEqual(finalMoment, initialMoment)
    }

    func testZeroTimeoutAppearedEstablishesFreshBaselineWithoutSchedulingWork() async throws {
        let stream = brains.vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
        ]))
        _ = await stream.commitVisibleObservationForTesting(.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
            (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
        ]))
        let initialMoment = await stream.storeOwner.latestCommittedMoment()
        var scheduledEffects: [PredicateWait.ScheduledEffect] = []
        let expression = AccessibilityPredicate.changed(.elements([.appeared(.label("Ready"))]))
        let predicate = try resolvedPredicate(expression)
        let predicateWait = PredicateWait(
            vault: brains.vault,
            navigation: brains.navigation,
            actionEvidenceProjector: brains.actionEvidenceProjector
        )
        predicateWait.observeScheduledEffect = { scheduledEffects.append($0) }

        let result = await predicateWait.execute(
            start: RuntimeElapsed.now,
            timeout: 0,
            projection: PredicateWait.ExecutionProjection(
                target: predicate.waitTarget,
                continuesAfterInitialMiss: true,
                initialEvidence: PredicateWait.LifecycleEvidence(
                    predicate: expression,
                    target: predicate.waitTarget
                ),
                evaluate: { observation, isInitialVisible, evidence in
                    let reduced = await predicateWait.reduceObservation(
                        observation,
                        predicate: predicate,
                        predicateExpression: expression,
                        baselineSeed: isInitialVisible ? .currentObservation : .preserve,
                        stream: evidence.stream
                    )
                    let recorded = evidence.recording(reduced)
                    return PredicateWaitEvaluation(
                        evidence: recorded,
                        matched: recorded.evaluation.met
                    )
                },
                result: { _, _, evidence in evidence.evaluation }
            )
        )
        let finalMoment = await stream.storeOwner.latestCommittedMoment()

        XCTAssertFalse(result.met)
        XCTAssertEqual(
            result.actual,
            PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
        )
        XCTAssertTrue(scheduledEffects.isEmpty)
        XCTAssertEqual(finalMoment, initialMoment)
    }

    func testPredicateObservationStreamSeparatesStateAndChangeEvidence() async throws {
        let readyTarget = AccessibilityTarget.label("Ready")
        let observationStream = brains.vault.semanticObservationStream
        let baselineEvent = await observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [(makeElement(label: "Loading"), HeistId(rawValue: "loading"))])
        )
        let changedEvent = await observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [
                (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
                (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
            ])
        )
        var stream = PredicateObservationStreamState()

        let baselineObservation = brains.actionEvidenceProjector.projectSettledEvidence(from: baselineEvent)
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

        let changedObservation = brains.actionEvidenceProjector.projectSettledEvidence(from: changedEvent)
        let baseline = try XCTUnwrap(seeded.state.observationBaseline)
        let changed = stream.reducing(
            changedObservation,
            predicate: resolvedChangePredicate,
            predicateExpression: changePredicate,
            eventsSinceBaseline: await observationStream.storeOwner.readLog {
                $0.events(since: baseline)
            }
        )
        let stateExpression = AccessibilityPredicate.exists(readyTarget)
        let stateExpectation = PredicateEvaluation.evaluate(
            try resolvedPredicate(stateExpression),
            expression: stateExpression,
            in: changed.reduction.evidence
        )

        XCTAssertTrue(stateExpectation.met)
        XCTAssertTrue(changed.reduction.expectation.met)
        XCTAssertEqual(changed.reduction.changeBaseline?.sequence, baselineObservation.event.sequence)
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
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistIfPassesImmediateObservationBudget() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Settings"])],
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
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
