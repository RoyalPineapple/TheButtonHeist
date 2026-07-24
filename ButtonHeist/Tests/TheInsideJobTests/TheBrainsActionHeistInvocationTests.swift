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

    func testHeistRuntimeSafetyRejectsInvalidPlanBeforeDispatchOrObservation() async throws {
        XCTAssertThrowsError(try HeistPlan(body: [
            .action(ActionStep(command: .activate(.ref("missing")))),
        ])) { error in
            XCTAssertTrue(String(describing: error).contains("$.body[0].action.command.payload.target"))
            XCTAssertTrue(String(describing: error).contains("target ref must resolve"))
        }
    }

    func testHeistRuntimeSafetyRejectsOversizedForEachBeforeObservation() async throws {
        XCTAssertThrowsError(try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: HeistPlanRuntimeSafetyLimits.standard.maxForEachElementLimit + 1,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])) { error in
            XCTAssertTrue(String(describing: error).contains("max for_each_element limit"))
        }
    }

    func testHeistInvocationExecutesHelperDependenciesInInvokedDefinitionScope() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let tapAddButton = HeistDef<Void>("tapAddButton") {
            Activate(.label("Add to Cart"))
        }
        let addToCart = HeistDef<String>("addToCart", parameter: "item") { item in
            Activate(.label(item))
            try tapAddButton()
        }
        let plan = try HeistPlan {
            try addToCart("Milk")
        }

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        let expectedCommands = try ["Milk", "Add to Cart"].map {
            try HeistActionCommand.activate(.label($0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistInvocationExpectationReturnsEvidenceOnInvokeNode() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        var settlementCommands: [Settlement.Command] = []
        let initialState = await observedState(labels: ["Search"])
        let finalState = await observedState(labels: ["Search", "subtotal"])
        let events = observationEvents(for: [initialState, finalState])
        var nextObservationIndex = 0
        let expectation = WaitStep(
            predicate: .changed(.elements([.appeared(.label("subtotal"))])),
            timeout: defaultActionExpectationTimeout
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            },
            settle: { command in
                settlementCommands.append(command)
                let event = events[nextObservationIndex]
                nextObservationIndex += 1
                return scriptedSettlement(command, observation: event)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(
                    name: "Cart",
                    definitions: [
                        try HeistPlan(
                            name: "addItem",
                            parameter: .string(name: "item"),
                            body: [
                                .action(ActionStep(command: .activate(.label(
                                    HeistReferenceName(stringLiteral: "item")
                                )))),
                            ]
                        ),
                    ],
                    body: []
                ),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Cart.addItem",
                    argument: .string("Milk"),
                    expectation: expectation
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let report = HeistReport.project(result: heistResult)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Milk")).resolve(in: .empty)]
        )
        XCTAssertEqual(settlementCommands.count, 2)
        XCTAssertEqual(
            settlementCommands[0],
            .currentState(scope: settlementCommands[1].observationScope)
        )
        XCTAssertEqual(settlementCommands[1].baseline, .supplied(.init(moment: events[0].moment)))
        XCTAssertEqual(report.summary.expectationsChecked, 1)
        XCTAssertEqual(report.summary.expectationsMet, 1)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.reportExpectation?.met, true)
    }

    func testHeistInvocationSnapshotExpectationEvaluatesFinalNestedState() async throws {
        let runtime = heistRuntime(
            observations: [
                await observedState(labels: ["Checkout"]),
                await observedState(labels: ["Payment Complete"]),
            ],
            execute: { _ in
                ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Checkout", definitions: [
                    try HeistPlan(name: "pay", body: [
                        .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
                    ]),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Checkout.pay",
                    expectation: WaitStep(
                        predicate: .exists(.label("Payment Complete")),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
        XCTAssertEqual(step.children.count, 1)
    }

    func testHeistInvocationTransitionExpectationEvaluatesAcrossNestedCall() async throws {
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                await observedState(elements: [
                    (makeElement(label: "subtotal", value: "2 items", identifier: "subtotal"), "subtotal"),
                ]),
            ],
            execute: { _ in
                ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(ActionStep(command: .activate(.label(
                                HeistReferenceName(stringLiteral: "item")
                            )))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Cart.addItem",
                    argument: .string("Eggs"),
                    expectation: WaitStep(
                        predicate: .changed(.elements([.updated(
                            .label("subtotal"),
                            .value(after: .contains("2 items"))
                        )])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
    }

    func testHeistInvocationScreenChangeExpectationEvaluatesAcrossNestedCall() async throws {
        let runtime = heistRuntime(
            observations: [
                await observedState(labels: ["Checkout"], screenId: "checkout"),
                await observedState(labels: ["Receipt"], screenId: "receipt", screenChanged: true),
            ],
            execute: { _ in
                ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Checkout", definitions: [
                    try HeistPlan(name: "pay", body: [
                        .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
                    ]),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Checkout.pay",
                    expectation: WaitStep(
                        predicate: .changed(.screen([.exists(.label("Receipt"))])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
    }

    func testHeistInvocationAttachedExpectationFailureStaysOnInvokeNode() async throws {
        let runtime = heistRuntime(
            observations: [
                await observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                await observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
            ],
            execute: { _ in
                ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(ActionStep(command: .activate(.label(
                                HeistReferenceName(stringLiteral: "item")
                            )))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: "Cart.addItem",
                    argument: .string("Eggs"),
                    expectation: WaitStep(
                        predicate: .changed(.elements([.updated(
                            .label("subtotal"),
                            .value(after: .contains("2 items"))
                        )])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heistResult.abortedAtPath, "$.body[0]")
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.status, .failed)
        XCTAssertNil(step.abortedAtChildPath)
        XCTAssertEqual(step.failure?.category, .expectation)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, false)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, false)
        XCTAssertTrue(step.children.allSatisfy { $0.status == .passed })
    }

    func testHeistInvocationExecutesQualifiedExportedNamespaceDependency() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let payOpen = HeistDef<Void>("lib.payOpen") {
            Activate(.label("Pay"))
        }
        let checkout = HeistDef<Void>("lib.checkout") {
            try payOpen()
        }
        let plan = try HeistPlan {
            try checkout()
        }

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Pay")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionBindsRootStringArgument() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .typeText(nil))
            }
        )
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .string("milk"),
            runtime: runtime
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.typeText(text: "milk", target: .label("Search")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionBindsRootAccessibilityTargetArgument() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .accessibilityTarget(name: "row"),
            body: [
                .action(ActionStep(command: .activate(.ref("row")))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .accessibilityTarget(.label("Row 1")),
            runtime: runtime
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Row 1")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionRejectsMissingRootArgument() async throws {
        let runtime = heistRuntime(observations: [])
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.failureKind, .validationError)
        XCTAssertEqual(result.message, "Could not bind root heist argument: heist argument type none does not match parameter type string")
    }

    func testHeistInvocationAllowsSameLeafDefinitionNamesInDifferentScopes() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(definitions: [
            try HeistPlan(
                name: "setup",
                definitions: [
                    try HeistPlan(name: "setup", body: [
                        .action(ActionStep(command: .activate(.predicate(.label("Nested Setup"))))),
                    ]),
                ],
                body: [
                    .invoke(HeistInvocationStep(path: "setup")),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(path: "setup")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Nested Setup")).resolve(in: .empty)]
        )
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
