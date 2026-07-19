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
        let raw = HeistPlanAdmissionCandidate(body: [
            .action(ActionStep(command: .activate(.ref("missing")))),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
            XCTAssertTrue(String(describing: error).contains("$.body[0].action.command.payload.target"))
            XCTAssertTrue(String(describing: error).contains("target ref must resolve"))
        }
    }

    func testHeistRuntimeSafetyRejectsOversizedForEachBeforeObservation() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: HeistPlanRuntimeSafetyLimits.standard.maxForEachElementLimit + 1,
                parameter: "target",
                body: [.action(ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
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
        let plan = try HeistPlanAdmissionCandidate(definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                definitions: [
                    HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                        .action(ActionStep(
                            command: .activate(.label("Add to Cart"))
                        )),
                    ]),
                ],
                body: [
                    .action(ActionStep(command: .activate(.label(
                        HeistReferenceName(stringLiteral: "item")
                    )))),
                    .invoke(HeistInvocationStep(path: "tapAddButton")),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(
                path: "addToCart",
                argument: .string("Milk")
            )),
        ]).validatedForRuntimeSafety()

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        let expectedCommands = try ["Milk", "Add to Cart"].map {
            try HeistActionCommand.activate(.label($0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistInvocationExpectationReturnsEvidenceOnInvokeNode() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let expectation = WaitStep(
            predicate: .changed(.elements([.appeared(.label("subtotal"))])),
            timeout: defaultActionExpectationTimeout
        )
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Search"]),
                observedState(labels: ["Search", "subtotal"]),
            ],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(payload: .activate)
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
                observedState(labels: ["Checkout"]),
                observedState(labels: ["Payment Complete"]),
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
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                observedState(elements: [
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
                observedState(labels: ["Checkout"], screenId: "checkout"),
                observedState(labels: ["Receipt"], screenId: "receipt", screenChanged: true),
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
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                observedState(elements: [
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
        let plan = try HeistPlanAdmissionCandidate(definitions: [
            HeistPlanAdmissionCandidate(name: "lib", definitions: [
                HeistPlanAdmissionCandidate(name: "payOpen", body: [
                    .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
                ]),
                HeistPlanAdmissionCandidate(name: "checkout", body: [
                    .invoke(HeistInvocationStep(path: "lib.payOpen")),
                ]),
            ], body: []),
        ], body: [
            .invoke(HeistInvocationStep(path: "lib.checkout")),
        ]).validatedForRuntimeSafety()

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
