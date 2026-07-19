import Testing
@_spi(ButtonHeistInternals) import ThePlans

private func validatedDefinitions(_ definitions: [HeistPlanAdmissionCandidate]) throws -> [HeistPlan] {
    try HeistPlanAdmissionCandidate(
        definitions: definitions,
        body: [.warn(WarnStep(message: "root"))]
    )
    .validatedForRuntimeSafety()
    .definitions
}

@Test
func heistDefinitionsCompileToInvocationsWithLocalDefinitions() throws {
    enum LibraryScreen {
        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
            Activate(.label("Add to Cart"))
                .expect(.exists(.label(item)), timeout: 2)
        }
    }

    let heist = try HeistPlan("purchaseFlow") {
        try LibraryScreen.addToCart("Milk")
        try LibraryScreen.addToCart("Bread")
    }

    #expect(heist.name == "purchaseFlow")
    #expect(heist.body == [
        .invoke(HeistInvocationStep(
            path: "LibraryScreen.addToCart",
            argument: .string("Milk")
        )),
        .invoke(HeistInvocationStep(
            path: "LibraryScreen.addToCart",
            argument: .string("Bread")
        )),
    ])
    #expect(try heist.definitions == validatedDefinitions([
        HeistPlanAdmissionCandidate(name: "LibraryScreen", definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                body: [
                    .action(ActionStep(command: .activate(
                        .label(HeistReferenceName(stringLiteral: "item"))
                    ))),
                    .action(ActionStep(
                        command: .activate(.label("Add to Cart")),
                        expectationPolicy: .expect(ActionExpectation(
                            predicate: .exists(.label(HeistReferenceName(stringLiteral: "item"))),
                            timeout: 2
                        )))),
                ]
            ),
        ], body: []),
    ]))
}

@Test
func `string heist definitions default parameter to input`() throws {
    let search = HeistDef<String>("SearchScreen.search") { query in
        TypeText(query, into: .label("Search"))
    }

    let heist = try HeistPlan {
        try search("milk")
    }

    #expect(try heist.definitions == validatedDefinitions([
        HeistPlanAdmissionCandidate(name: "SearchScreen", definitions: [
            HeistPlanAdmissionCandidate(
                name: "search",
                parameter: .string(name: "input"),
                body: [
                    .action(ActionStep(
                        command: .typeText(
                            reference: HeistReferenceName(stringLiteral: "input"),
                            target: .label("Search")
                        )
                    )),
                ]
            ),
        ], body: []),
    ]))
}

@Test
func `accessibility target heist definitions default parameter to input`() throws {
    let delete = HeistDef<AccessibilityTarget>("Rows.delete") { row in
        Activate(row)
            .expect(.missing(row), timeout: 2)
    }

    let heist = try HeistPlan {
        try delete(.label("Delete"))
    }

    #expect(try heist.definitions == validatedDefinitions([
        HeistPlanAdmissionCandidate(name: "Rows", definitions: [
            HeistPlanAdmissionCandidate(
                name: "delete",
                parameter: .accessibilityTarget(name: "input"),
                body: [
                    .action(ActionStep(
                        command: .activate(.ref("input")),
                        expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("input")), timeout: 2)))),
                ]
            ),
        ], body: []),
    ]))
}

@Test
func heistDefinitionsRejectConflictingDuplicatesDuringValidation() throws {
    let first = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
        Activate(.label(item))
    }
    let second = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { _ in
        Activate(.label("Add to Cart"))
    }

    do {
        _ = try HeistPlan {
            try first("Milk")
            try second("Bread")
        }
        Issue.record("Expected conflicting nested definitions to fail admission")
    } catch let error as HeistPlanRuntimeSafetyError {
        let failure = try #require(error.failures.first)
        #expect(error.failures.count == 1)
        #expect(failure.path.description == "$.definitions[0].definitions[1].name")
        #expect(failure.contract == "duplicate heist definition names are not allowed in the same scope")
        #expect(failure.observed == #""addToCart""#)
    } catch {
        Issue.record("Expected HeistPlanRuntimeSafetyError, got \(error)")
    }
}

@Test
func heistDefinitionsCarryLocalDependenciesInDefinitionScope() throws {
    enum LibraryScreen {
        static let tapAddButton = HeistDef<Void>("AddButton.tap") {
            Activate(.label("Add to Cart"))
        }

        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
            try tapAddButton()
        }
    }

    let heist = try HeistPlan {
        try LibraryScreen.addToCart("Milk")
    }
    #expect(try heist.definitions == validatedDefinitions([
        HeistPlanAdmissionCandidate(name: "LibraryScreen", definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                definitions: [
                    HeistPlanAdmissionCandidate(name: "AddButton", definitions: [
                        HeistPlanAdmissionCandidate(
                            name: "tap",
                            body: [
                                .action(ActionStep(command: .activate(.label("Add to Cart")))),
                            ]
                        ),
                    ], body: []),
                ],
                body: [
                    .action(ActionStep(command: .activate(
                        .label(HeistReferenceName(stringLiteral: "item"))
                    ))),
                    .invoke(HeistInvocationStep(path: "AddButton.tap")),
                ]
            ),
        ], body: []),
    ]))
}

@Test
func rawHeistPlanContentCarriesDefinitions() throws {
    let rawPlan = try HeistPlan(definitions: [
        try HeistPlan(name: "setup", body: [
            .action(ActionStep(command: .activate(.label("Setup")))),
        ]),
    ], body: [
        .invoke(HeistInvocationStep(path: "setup")),
    ])

    let heist = try HeistPlan {
        rawPlan
    }

    #expect(heist.body == rawPlan.body)
    #expect(heist.definitions == rawPlan.definitions)
}

@Test
func runHeistBuildsHeistRunSteps() throws {
    let stringRun = ThePlans.RunHeist("LibraryScreen.addToCart", "Milk")
    #expect(stringRun.heistSteps == [
        .invoke(HeistInvocationStep(path: "LibraryScreen.addToCart", argument: .string("Milk"))),
    ])

    let noArgRun = ThePlans.RunHeist("CartScreen.checkout")
    #expect(noArgRun.heistSteps == [
        .invoke(HeistInvocationStep(path: "CartScreen.checkout", argument: .none)),
    ])

    let targetRun = ThePlans.RunHeist("Rows.activate", AccessibilityTarget.label("Row 1"))
    #expect(targetRun.heistSteps == [
        .invoke(HeistInvocationStep(path: "Rows.activate", argument: .accessibilityTarget(.label("Row 1")))),
    ])

    let expectedSubtotal = WaitStep(
        predicate: .changed(.elements([.appeared(.label("subtotal"))])),
        timeout: ThePlans.defaultActionExpectationTimeout
    )
    let expectedRun = ThePlans.RunHeist("Cart.addItem", "Milk")
        .expect(.changed(.elements([.appeared(.label("subtotal"))])))
    #expect(expectedRun.heistSteps == [
        .invoke(HeistInvocationStep(
            path: "Cart.addItem",
            argument: .string("Milk"),
            expectation: expectedSubtotal
        )),
    ])

    let expectedStatus = WaitStep(
        predicate: .changed(.elements([
            .updated(.label("subtotal"), .value(after: .contains("2 items"))),
        ])),
        timeout: ThePlans.defaultActionExpectationTimeout
    )
    let updatedRun = ThePlans.RunHeist("Cart.addItem", "Eggs")
        .expect(.changed(.elements([
            .updated(.label("subtotal"), .value(.contains("2 items"))),
        ])))
    #expect(updatedRun.heistSteps == [
        .invoke(HeistInvocationStep(
            path: "Cart.addItem",
            argument: .string("Eggs"),
            expectation: expectedStatus
        )),
    ])

    let expectedCompletion = WaitStep(
        predicate: .exists(.label("Payment Complete")),
        timeout: ThePlans.defaultActionExpectationTimeout
    )
    let snapshotRun = ThePlans.RunHeist("Checkout.pay")
        .expect(.exists(.label("Payment Complete")))
    #expect(snapshotRun.heistSteps == [
        .invoke(HeistInvocationStep(
            path: "Checkout.pay",
            expectation: expectedCompletion
        )),
    ])

    let expectedReceipt = WaitStep(
        predicate: .changed(.screen([.exists(.label("Receipt"))])),
        timeout: ThePlans.defaultActionExpectationTimeout
    )
    let screenRun = ThePlans.RunHeist("Checkout.pay")
        .expect(.changed(.screen([.exists(.label("Receipt"))])))
    #expect(screenRun.heistSteps == [
        .invoke(HeistInvocationStep(
            path: "Checkout.pay",
            expectation: expectedReceipt
        )),
    ])
}

@Test
func runHeistResolvesNamedCapabilityThroughValidation() throws {
    _ = try HeistPlan(
        definitions: [
            try HeistPlan(name: "CartScreen", definitions: [
                try HeistPlan(name: "checkout", body: [
                    .action(ActionStep(command: .activate(.label("Checkout")))),
                ]),
            ], body: []),
        ],
        body: [.invoke(HeistInvocationStep(path: "CartScreen.checkout"))]
    )
}

@Test
func runHeistRendersAsRunHeistInCanonicalSwift() throws {
    let plan = try HeistPlan(
        definitions: [
            try HeistPlan(name: "CartScreen", definitions: [
                try HeistPlan(name: "checkout", body: [
                    .action(ActionStep(command: .activate(.label("Checkout")))),
                ]),
            ], body: []),
        ],
        body: [.invoke(HeistInvocationStep(
            path: "CartScreen.checkout",
            expectation: WaitStep(predicate: .changed(.screen()), timeout: ThePlans.defaultActionExpectationTimeout)
        ))]
    )
    let rendered = try plan.canonicalSwiftDSL()
    #expect(rendered.contains("RunHeist(\"CartScreen.checkout\")"))
    #expect(rendered.contains(".expect(.changed(.screen()))"))
    #expect(!rendered.contains("CartScreen.checkout()"))
}

@Test
func heistDefinitionsCanBeInvokedFromForEachBodies() throws {
    enum LibraryScreen {
        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
        }
    }
    enum CartScreen {
        static let deleteItem = HeistDef<AccessibilityTarget>("CartScreen.deleteItem", parameter: "target") { target in
            Activate(target)
                .expect(.missing(target), timeout: 2)
        }
    }

    let heist = try HeistPlan {
        ForEach("Milk", "Bread") { item in
            try LibraryScreen.addToCart(item)
        }

        ForEach(.label("Delete"), limit: 20) { target in
            try CartScreen.deleteItem(target)
        }
    }

    #expect(heist.body == [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Bread"],
            parameter: "item",
            body: [
                .invoke(HeistInvocationStep(
                    path: "LibraryScreen.addToCart",
                    argument: .string(reference: HeistReferenceName(stringLiteral: "item"))
                )),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 20,
            parameter: "target",
            body: [
                .invoke(HeistInvocationStep(
                    path: "CartScreen.deleteItem",
                    argument: .accessibilityTarget(.ref("target"))
                )),
            ]
        )),
    ])
}
