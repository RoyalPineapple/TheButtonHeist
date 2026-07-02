import Testing
@testable import ThePlans

@Test func `inline plan source simple Activate compiles to HeistPlan`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.label("Pay"))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
    ])

    #expect(plan == expected)
}

@Test func `runtime parser accepts broad StringMatch enum cases for all string predicate fields`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.identifier(.suffix("field")))
    WaitFor(.exists(.element(.label(.prefix("No results")), .identifier(.contains("empty_state")), .value(.suffix("items")))), timeout: .seconds(2))
    TypeText("milk", into: .value(.prefix("Search")))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.identifier(.suffix("field")))))),
        .wait(WaitStep(predicate: .exists(ElementPredicateTemplate.element(
            .label(.prefix(.literal("No results"))),
            .identifier(.contains(.literal("empty_state"))),
            .value(.suffix(.literal("items")))
        )), timeout: 2)),
        .action(try ActionStep(command: .typeText(
            text: .literal("milk"),
            target: .predicate(.value(.prefix("Search")))
        ))),
    ])

    #expect(plan == expected)
}

@Test func `runtime parser rejects exact StringMatch source spelling`() {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile(root("""
        Activate(.label(.exact("Search")))
        """))
    }
}

@Test func `runtime parser rejects labeled element predicate fields`() {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile(root("""
        Activate(.element(label: "Pay", traits: [.button]))
        """))
    }
}

@Test func `inline plan source type text replacement and clear compile`() throws {
    let replacement = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("b", into: .identifier("Field"), replacingExisting: true)
    """#))
    let replacementWithArgumentsReordered = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("b", replacingExisting: true, into: .identifier("Field"))
    """#))
    let clear = try HeistPlanSourceCompiler().compile(root(#"""
    ClearText(.identifier("Field"))
    """#))
    let emptyReplacement = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("", into: .identifier("Field"), replacingExisting: true)
    """#))

    let expectedReplacement = try HeistPlan(body: [
        .action(try ActionStep(command: .typeText(
            text: .literal("b"),
            target: .predicate(.identifier("Field")),
            replacingExisting: true
        ))),
    ])
    let expectedClear = try HeistPlan(body: [
        .action(try ActionStep(command: .typeText(
            text: .literal(""),
            target: .predicate(.identifier("Field")),
            replacingExisting: true
        ))),
    ])

    #expect(replacement == expectedReplacement)
    #expect(replacementWithArgumentsReordered == expectedReplacement)
    #expect(clear == expectedClear)
    #expect(emptyReplacement == expectedClear)
    try assertCanonicalRoundTrip(replacement)
    try assertCanonicalRoundTrip(clear)
}

@Test func `runtime parser accepts repeated string predicate checks for one field`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.element(.label(.prefix("foo")), .label(.contains("bar")), .label(.suffix("baz")), .traits([.button])))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.element(
            .label(.prefix(.literal("foo"))),
            .label(.contains(.literal("bar"))),
            .label(.suffix(.literal("baz"))),
            .traits([.button])
        ))))),
    ])

    #expect(plan == expected)
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source chained expectation compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.label("Pay")).expect(.change(.screen()))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 1)))),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source RunHeist expectation compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    HeistPlan("shop") {
        HeistDef<String>("Cart.addItem", parameter: "item") { item in
            Activate(.label(item))
        }

        HeistDef<Void>("Checkout.pay") {
            Activate(.label("Pay"))
        }

        RunHeist("Cart.addItem", "Milk")
            .expect(.appeared(.label("subtotal")))

        RunHeist("Cart.addItem", "Eggs")
            .expect(.updated(.label("subtotal"), .value(.contains("2 items"))))

        RunHeist("Checkout.pay")
            .expect(.exists(.label("Payment Complete")))

        RunHeist("Checkout.pay")
            .expect(.screenChanged(.exists(.label("Receipt"))))
    }
    """)
    let expected = try HeistPlan(
        name: "shop",
        definitions: [
            try HeistPlan(name: "Cart", definitions: [
                try HeistPlan(
                    name: "addItem",
                    parameter: .string(name: "item"),
                    body: [
                        .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                    ]
                ),
            ], body: []),
            try HeistPlan(name: "Checkout", definitions: [
                try HeistPlan(name: "pay", body: [
                    .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                ]),
            ], body: []),
        ],
        body: [
            .invoke(HeistInvocationStep(
                path: ["Cart", "addItem"],
                argument: .string(.literal("Milk")),
                expectation: WaitStep(
                    predicate: .change(.elements(.appearedElement(.label("subtotal")))),
                    timeout: defaultActionExpectationTimeout
                )
            )),
            .invoke(HeistInvocationStep(
                path: ["Cart", "addItem"],
                argument: .string(.literal("Eggs")),
                expectation: WaitStep(
                    predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                        element: .label("subtotal"),
                        change: .value(after: .contains(.literal("2 items")))
                    )))),
                    timeout: defaultActionExpectationTimeout
                )
            )),
            .invoke(HeistInvocationStep(
                path: ["Checkout", "pay"],
                expectation: WaitStep(
                    predicate: .exists(.label("Payment Complete")),
                    timeout: defaultActionExpectationTimeout
                )
            )),
            .invoke(HeistInvocationStep(
                path: ["Checkout", "pay"],
                expectation: WaitStep(
                    predicate: .change(.screen(.exists(.label("Receipt")))),
                    timeout: defaultActionExpectationTimeout
                )
            )),
        ]
    )

    #expect(plan == expected)
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source rejects empty HeistDef path components`() throws {
    do {
        _ = try HeistPlanSourceCompiler().compile("""
        HeistPlan("cart") {
            HeistDef<Void>("Cart..checkout") {
                Warn("checkout")
            }

            RunHeist("Cart.checkout")
        }
        """)
        Issue.record("Expected source compiler to reject empty HeistDef path component")
    } catch let error as HeistPlanSourceCompilerError {
        let diagnostic = error.diagnostic
        #expect(diagnostic.code == .dslInvalidDefinition)
        #expect(diagnostic.title == "Invalid heist definition")
        #expect(diagnostic.phase == .sourceCompilation)
        #expect(diagnostic.path == "Cart..checkout")
        #expect(diagnostic.sourceSpan?.line == 2)
        expect(error.description, contains: "heist definition path component at index 1 must not be empty")
    } catch {
        Issue.record("Expected HeistPlanSourceCompilerError, got \(error)")
    }
}

@Test func `inline plan source property update expectations compile`() throws {
    let scoped = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("Bruschetta", into: .identifier("Search"))
        .expect(.change(.elements(.updated(.identifier("Search"), .value("Bruschetta")))))
    """#))
    let unscoped = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.change(.elements(.updated(.value("3")))))
    """#))
    let beforeAfter = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.change(.elements(.updated(
            .identifier("Quantity"),
            .value(before: "2", after: "3")
        ))))
    """#))
    let broadBeforeAfter = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.change(.elements(.updated(.value(before: .prefix("cart:"), after: .contains("items"))))))
    """#))

    let expectedScoped = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(
                text: .literal("Bruschetta"),
                target: .predicate(.identifier("Search"))
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                element: .identifier("Search"),
                change: .value(after: "Bruschetta")
            )))), timeout: 1)))),
    ])
    let expectedUnscoped = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                change: .value(after: "3")
            )))), timeout: 1)))),
    ])
    let expectedBeforeAfter = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                element: .identifier("Quantity"),
                change: .value(before: "2", after: "3")
            )))), timeout: 1)))),
    ])
    let expectedBroadBeforeAfter = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                change: .value(before: .prefix("cart:"), after: .contains("items"))
            )))), timeout: 1)))),
    ])

    #expect(scoped == expectedScoped)
    #expect(unscoped == expectedUnscoped)
    #expect(beforeAfter == expectedBeforeAfter)
    #expect(broadBeforeAfter == expectedBroadBeforeAfter)
    try assertCanonicalRoundTrip(scoped)
    try assertCanonicalRoundTrip(beforeAfter)
}

@Test func `inline plan source custom content update queries label and value`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root(#"""
    WaitFor(.change(.elements(.updated(.customContent(after: .match(
        label: "Status",
        value: .contains("Ready"),
        isImportant: true
    ))))))
    """#))
    let expected = try HeistPlan(body: [
        .wait(WaitStep(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
            change: .customContent(after: CustomContentMatch<StringExpr>.match(
                label: .exact(.literal("Status")),
                value: .contains(.literal("Ready")),
                isImportant: true
            ))
        )))))),
    ])

    #expect(plan == expected)
    #expect(try plan.canonicalSwiftDSL().contains(#".customContent(after: .match(label: "Status", value: .contains("Ready"), isImportant: true))"#))
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source accepts direct delta change predicates`() throws {
    let appeared = try HeistPlanSourceCompiler().compile(root(#"""
    Activate(.label("Add")).expect(.change(.appeared(.label("Back"))))
    """#))
    let disappeared = try HeistPlanSourceCompiler().compile(root(#"""
    Activate(.label("Clear")).expect(.change(.disappeared(.identifier("row-1"))))
    """#))
    let updatedPropertyOnly = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("milk", into: .identifier("Search"))
        .expect(.change(.updated(.value())))
    """#))
    let updatedBeforeAfterOnly = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("milk", into: .identifier("Search"))
        .expect(.change(.updated(.value(before: "", after: "milk"))))
    """#))
    let updatedAllFields = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("milk", into: .identifier("Search"))
        .expect(.change(.updated(.identifier("Search"), .value(before: "", after: "milk"))))
    """#))

    let expectedAppeared = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Add"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.appearedElement(.label("Back")))), timeout: 1)))),
    ])
    let expectedDisappeared = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Clear"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.disappearedElement(.identifier("row-1")))), timeout: 1)))),
    ])
    let expectedUpdatedPropertyOnly = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(text: "milk", target: .predicate(.identifier("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                change: .value()
            )))), timeout: 1)))),
    ])
    let expectedUpdatedBeforeAfterOnly = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(text: "milk", target: .predicate(.identifier("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                change: .value(before: "", after: "milk")
            )))), timeout: 1)))),
    ])
    let expectedUpdatedAllFields = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(text: "milk", target: .predicate(.identifier("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                element: .identifier("Search"),
                change: .value(before: "", after: "milk")
            )))), timeout: 1)))),
    ])
    #expect(appeared == expectedAppeared)
    #expect(disappeared == expectedDisappeared)
    #expect(updatedPropertyOnly == expectedUpdatedPropertyOnly)
    #expect(updatedBeforeAfterOnly == expectedUpdatedBeforeAfterOnly)
    #expect(updatedAllFields == expectedUpdatedAllFields)
}

@Test func `inline plan source accepts inferred element change predicates`() throws {
    let appeared = try HeistPlanSourceCompiler().compile(root(#"""
    Activate(.label("Add Bruschetta"))
        .expect(.appeared(.label(.contains("Bruschetta, $9.00"))))
    """#))
    let disappeared = try HeistPlanSourceCompiler().compile(root(#"""
    Activate(.label("Remove Bruschetta"))
        .expect(.disappeared(.identifier("cart-row-bruschetta")))
    """#))
    let updated = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("Bruschetta", into: .identifier("Search"))
        .expect(.updated(.value("Bruschetta")))
    """#))

    let expectedAppeared = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Add Bruschetta"))),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .change(.elements(.appearedElement(.label(.contains("Bruschetta, $9.00"))))),
                timeout: 1
            )))),
    ])
    let expectedDisappeared = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Remove Bruschetta"))),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .change(.elements(.disappearedElement(.identifier("cart-row-bruschetta")))),
                timeout: 1
            )))),
    ])
    let expectedUpdated = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(
                text: .literal("Bruschetta"),
                target: .predicate(.identifier("Search"))
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                change: .value(after: "Bruschetta")
            )))), timeout: 1)))),
    ])

    #expect(appeared == expectedAppeared)
    #expect(disappeared == expectedDisappeared)
    #expect(updated == expectedUpdated)
    try assertCanonicalRoundTrip(appeared)
    try assertCanonicalRoundTrip(disappeared)
    try assertCanonicalRoundTrip(updated)
}

@Test func `inline plan source accepts controlled predicate and loop sugar`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root(#"""
    Activate(.label("Search"))
        .expect(.label("Results"))
    Activate(.label("Open Details"))
        .expect(.change(.screen(.label("Details"))))
    If(.value(.contains("Promo"))) {
        Warn("promo visible")
    }
    ForEach("Milk", "Eggs") { item in
        TypeText(item, into: .label("Search"))
    }
    ForEach(.label("Delete"), limit: 2) { target in
        Activate(target).expect(.missing(target))
    }
    """#))

    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Results")), timeout: 1)))),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Open Details"))),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .change(.screen(.exists(.label("Details")))),
                timeout: 1
            )))),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .exists(.value(.contains("Promo"))),
                body: [.warn(WarnStep(message: "promo visible"))]
            ),
        ])),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("item"),
                    target: .target(.label("Search"))
                ))),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 2,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("target")), timeout: 1)))),
            ]
        )),
    ])

    #expect(plan == expected)
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source unicode string escapes preserve following characters`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root(#"""
    Warn("A\u0062C")
    """#))
    let expected = try HeistPlan(body: [
        .warn(WarnStep(message: "AbC")),
    ])

    #expect(plan == expected)
}

@Test func `runtime authored product DSL compiles through canonical parser`() throws {
    let source = """
    HeistPlan("checkout") {
        HeistDef<String>("Cart.addItem", parameter: "item") { item in
            Activate(.label(item))
        }

        Activate(.label("Pay")).expect()

        WaitFor(.label("Receipt"), timeout: .seconds(5)).else {
            Fail("Receipt did not appear")
        }

        Warn("Receipt appeared")

        ForEach(["Milk", "Bread"]) { item in
            RunHeist("Cart.addItem", item)
        }
    }
    """

    let plan = try HeistPlanSourceCompiler().compile(source)

    #expect(plan.name == "checkout")
    #expect(plan.definitions.first?.name == "Cart")
    #expect(plan.definitions.first?.definitions.first?.name == "addItem")
    #expect(plan.body == [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.elements()), timeout: 1)))),
        .wait(WaitStep(
            predicate: .exists(.label("Receipt")),
            timeout: 5,
            elseBody: [.fail(FailStep(message: "Receipt did not appear"))]
        )),
        .warn(WarnStep(message: "Receipt appeared")),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Bread"],
            parameter: "item",
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string(.ref("item"))
                )),
            ]
        )),
    ])

    try assertCanonicalRoundTrip(plan)
}

@Test func `runtime parser accepts the complete durable ButtonHeist DSL surface`() throws {
    let source = """
    HeistPlan("RuntimeSurface", targetParameter: "rootTarget") { rootTarget in
        HeistDef<String>("Cart.addItem", parameter: "item") { item in
            Activate(.label(item))
                .expect(.exists(.label("Added")))
        }

        HeistDef<ElementTarget>("Messages.archive", parameter: "message") { message in
            CustomAction("Archive", on: message)
        }

        Activate(rootTarget)
        Activate(.label("Pay"))
            .expect()

        WaitFor(.label("Receipt"), timeout: .seconds(5)).else {
            Fail("Receipt did not appear")
        }

        Warn("Receipt appeared")

        If {
            Case(.exists(.label("Cart"))) {
                Warn("Cart ready")
            }
            Else {
                Warn("Cart missing")
            }
        }

        If(.exists(.label("Pay"))) {
            Warn("Pay visible")
        }.else {
            Warn("Pay missing")
        }

        ForEach(["Milk", "Bread"]) { item in
            RunHeist("Cart.addItem", item)
        }

        ForEach(.matching(.element(.label("Message"), .traits([.button]))), limit: 2) { message in
            RunHeist("Messages.archive", message)
        }
    }
    """

    let plan = try HeistPlanSourceCompiler().compile(source)

    #expect(plan.name == "RuntimeSurface")
    #expect(plan.parameter == .elementTarget(name: "rootTarget"))
    #expect(plan.body.map(\.testKind) == [
        .action,
        .action,
        .wait,
        .warn,
        .conditional,
        .conditional,
        .forEachString,
        .forEachElement,
    ])

    let cart = try #require(plan.definitions.first { $0.name == "Cart" })
    let addItem = try #require(cart.definitions.first { $0.name == "addItem" })
    #expect(addItem.parameter == .string(name: "item"))
    #expect(addItem.body.map(\.testKind) == [.action])

    let messages = try #require(plan.definitions.first { $0.name == "Messages" })
    let archive = try #require(messages.definitions.first { $0.name == "archive" })
    #expect(archive.parameter == .elementTarget(name: "message"))
    #expect(archive.body.map(\.testKind) == [.action])

    try assertCanonicalRoundTrip(plan)
}

@Test func `namespace block allows qualified reusable capability composition`() throws {
    let source = """
    HeistPlan("Checkout") {
        Namespace("lib") {
            HeistDef<Void>("payOpen") {
                Warn("pay opened")
            }

            HeistDef<Void>("clearCheck") {
                Warn("check cleared")
            }

            HeistDef<Void>("checkout") {
                RunHeist("lib.payOpen")
                RunHeist("lib.clearCheck")
            }
        }

        RunHeist("lib.checkout")
    }
    """

    let plan = try HeistPlanSourceCompiler().compile(source)
    let lib = try #require(plan.definitions.first { $0.name == "lib" })
    let checkout = try #require(lib.definitions.first { $0.name == "checkout" })

    #expect(checkout.body == [
        .invoke(HeistInvocationStep(path: ["lib", "payOpen"])),
        .invoke(HeistInvocationStep(path: ["lib", "clearCheck"])),
    ])
    #expect(plan.body == [
        .invoke(HeistInvocationStep(path: ["lib", "checkout"])),
    ])

    try assertCanonicalRoundTrip(plan)
}

@Test func `qualified namespace calls fail clearly when the export is missing`() throws {
    let diagnostic = compileError("""
    HeistPlan {
        HeistDef<Void>("caller") {
            RunHeist("lib.nope")
        }

        RunHeist("caller")
    }
    """)

    expect(diagnostic, contains: "heist run path must resolve to a declared exported capability")
    expect(diagnostic, contains: "No export named 'lib.nope'")
}

@Test func `unqualified sibling call inside namespace remains local only`() throws {
    let diagnostic = compileError("""
    HeistPlan {
        Namespace("lib") {
            HeistDef<Void>("payOpen") {
                Warn("pay opened")
            }

            HeistDef<Void>("checkout") {
                RunHeist("payOpen")
            }
        }

        RunHeist("lib.checkout")
    }
    """)

    expect(diagnostic, contains: "heist run path must resolve to a local capability")
}

@Test func `exported namespace capability cycle is rejected`() throws {
    let diagnostic = compileError("""
    HeistPlan {
        Namespace("lib") {
            HeistDef<Void>("a") {
                RunHeist("lib.b")
            }

            HeistDef<Void>("b") {
                RunHeist("lib.a")
            }
        }

        RunHeist("lib.a")
    }
    """)

    expect(diagnostic, contains: "heist runs must not be recursive")
    expect(diagnostic, contains: "lib.a -> lib.b -> lib.a")
}

@Test func `exported namespace calls enforce target arity`() throws {
    let diagnostic = compileError("""
    HeistPlan {
        Namespace("lib") {
            HeistDef<String>("addItem", parameter: "dish") { dish in
                TypeText(dish, into: .label("Search"))
            }

            HeistDef<Void>("caller") {
                RunHeist("lib.addItem")
            }
        }

        RunHeist("lib.caller")
    }
    """)

    expect(diagnostic, contains: "heist run argument type must match the target parameter")
}

@Test func `inline plan source ForEach string compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    ForEach(["a", "b"]) { item in
        Activate(.label(item)).expect(.exists(.label(item)))
    }
    """))
    let expected = try HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["a", "b"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .activate(.predicate(.label(.ref("item")))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .state(.exists(.label(.ref("item")))), timeout: 1)))),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source RepeatUntil compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    RepeatUntil(.exists(.value("3")), timeout: .seconds(2)) {
        Increment(.identifier("Quantity"))
    }.else {
        Fail("quantity did not reach 3")
    }
    """))
    let expected = try HeistPlan(body: [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.value("3")),
            timeout: 2,
            body: [
                .action(try ActionStep(command: .increment(.predicate(.identifier("Quantity"))))),
            ],
            elseBody: [
                .fail(FailStep(message: "quantity did not reach 3")),
            ]
        )),
    ])

    #expect(plan == expected)
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source action until compiles to repeat until`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Increment(.label("Volume")).until(.exists(.element(.label("Volume"), .value("100"))))
    """))
    let expected = try HeistPlan(body: [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.element(.label("Volume"), .value("100"))),
            timeout: defaultWaitTimeout,
            body: [
                .action(try ActionStep(
                    command: .increment(.predicate(.label("Volume"))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .change(), timeout: 1)))),
            ]
        )),
    ])

    #expect(plan == expected)
    try assertCanonicalRoundTrip(plan)
}

@Test func `inline plan source WaitFor and If compile`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    WaitFor(.exists(.label("Home")), timeout: .seconds(1))
    If {
        Case(.exists(.label("Pay"))) {
            Warn("ready")
        }
    }
    """))
    let expected = try HeistPlan(body: [
        .wait(WaitStep(predicate: .state(.exists(.label("Home"))), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Pay")), body: [.warn(WarnStep(message: "ready"))]),
        ])),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source ForEach matching compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    ForEach(.matching(.label("Row")), limit: 2) { target in
        Activate(target).expect(.missing(target))
    }
    """))
    let expected = try HeistPlan(body: [
        .forEachElement(try ForEachElementStep(
            matching: .label("Row"),
            limit: 2,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .state(.missingTarget(.ref("target"))), timeout: 1)))),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source RunHeist syntax validates through normal runtime pipeline`() throws {
    let diagnostic = compileDiagnostic(root("""
    RunHeist("CartScreen.checkout")
    """))

    #expect(diagnostic.code.rawValue == "heist.plan.runtime_safety")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == "$.body[0].invoke.path")
}

@Test func `non-durable action admission exposes source diagnostic code and path`() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .action(try ActionStep(command: .viewportScroll(ScrollTarget(direction: .down)))),
    ])
    guard case .failure(let diagnostics) = raw.runtimeSafetyValidationResult(),
          let diagnostic = diagnostics.first else {
        Issue.record("Expected non-durable action to fail runtime safety admission")
        return
    }

    #expect(diagnostics.count == 1)
    #expect(diagnostic.code == .nonDurableAction)
    #expect(diagnostic.code.rawValue == "heist.plan.non_durable_action")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == "$.body[0].action.command")
    #expect(diagnostic.message == "durable heist action; observed scroll is a viewport debug command, not a durable heist action")
    #expect(diagnostic.hint == nonDurableHeistActionRepairHint)
}

@Test func `inline plan source unsupported Swift syntax is rejected`() throws {
    for source in [
        "let x = 1",
        "FileManager.default",
        "Process()",
        #"await Warn("x")"#,
    ] {
        #expect(throws: HeistPlanSourceCompilerError.self) {
            _ = try HeistPlanSourceCompiler().compile(source)
        }
    }
}

@Test func `inline plan source syntax errors expose typed diagnostic fields`() throws {
    let diagnostic = compileDiagnostic("""
    HeistPlan {
        let label = "Pay"
        Activate(.label(label))
    }
    """)

    #expect(diagnostic.code.rawValue == "heist.source.invalid_syntax")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .sourceCompilation)
    #expect(diagnostic.sourceSpan?.sourceName == "inline-heist-plan")
    #expect(diagnostic.sourceSpan?.line == 2)
    #expect(diagnostic.sourceSpan?.column == 5)
}

@Test func `planning admission exposes typed diagnostics before rendering`() {
    let result = HeistPlanning.rejectRawStructuredJSONIRSourceFieldsResult(
        commandName: "run_heist",
        fields: [.body, .version]
    )

    guard let diagnostic = result.failureDiagnostics?.first else {
        Issue.record("Expected raw JSON IR fields to fail planning admission")
        return
    }

    #expect(diagnostic.code.rawValue == "heist.planning.raw_json_ir_fields")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planning)
    #expect(diagnostic.sourceSpan == nil)
}

@Test func `canonical ForEach string compiles without body try`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    ForEach(["a"]) { item in
        TypeText(item)
    }
    """))
    let expected = try HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["a"],
            parameter: "item",
            body: [
                .action(try ActionStep(command: .typeText(text: .ref("item"), target: nil))),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source import Foundation is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        import Foundation
        Activate(.label("Pay"))
        """)
    }
}

@Test func `inline plan source while true is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        while true {
            Activate(.label("Pay"))
        }
        """)
    }
}

@Test func `inline plan source arbitrary function declaration is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        func pay() {
            Activate(.label("Pay"))
        }
        """)
    }
}

@Test func `canonical semantic actions round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 0)))),
        .action(try ActionStep(
            command: .typeText(text: .literal("milk"), target: .predicate(.label("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.value("milk")), timeout: 2)))),
        .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
        .action(try ActionStep(command: .decrement(.predicate(.identifier("quantity"))))),
        .action(try ActionStep(command: .customAction(name: "Archive", target: .predicate(.label("Message"))))),
        .action(try ActionStep(command: .rotor(
            selection: .named("Headings"),
            target: .predicate(.label("Article")),
            direction: .previous
        ))),
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(try ActionStep(command: .dismissKeyboard)),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Maybe Later"))),
            expectationPolicy: .waived(try ActionExpectationWaiver("intentionally optional")))),
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"), ordinal: 0)))),
        .action(try ActionStep(command: .activate(.predicate(.element(
            .label("Delete"),
            .traits([.button]),
            .excludeTraits([.header])
        ))))),
    ]))
}

@Test func `canonical mechanical actions round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 12, y: 34))
        )))),
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .elementUnitPoint(.label("Cell"), UnitPoint(x: 0.25, y: 0.75))
        )))),
        .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 20, y: 40)),
            duration: GestureDuration(seconds: 1)
        )))),
        .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(.label("Message"), UnitPoint(x: 0.5, y: 0.2)),
            duration: GestureDuration(seconds: 1.4)
        )))),
        .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(
            .label("Carousel"),
            start: UnitPoint(x: 0.8, y: 0.5),
            end: UnitPoint(x: 0.2, y: 0.5)
        ))))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .elementToPoint(.label("Slider"), start: UnitPoint(x: 0.8, y: 0.5), end: ScreenPoint(x: 200, y: 40))
        )))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .pointToPoint(start: ScreenPoint(x: 10, y: 10), end: ScreenPoint(x: 100, y: 100))
        )))),
    ]))
}

@Test func `mechanical tap ScreenPoint source compiles to raw coordinate tap`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Mechanical.Tap(ScreenPoint(x: 888, y: 372))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 888, y: 372))
        )))),
    ])

    #expect(plan == expected)
}

@Test func `mechanical element unit-point source compiles to element-relative gesture`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Mechanical.Tap(.label("Row"), at: UnitPoint(x: 0.25, y: 0.75))
    Mechanical.LongPress(.label("Row"), at: UnitPoint(x: 0.5, y: 0.5), duration: GestureDuration(seconds: 1.4))
    Mechanical.Drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 200, y: 40))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(selection: .elementUnitPoint(
            .predicate(.label("Row")),
            UnitPoint(x: 0.25, y: 0.75)
        ))))),
        .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Row")),
                UnitPoint(x: 0.5, y: 0.5)
            ),
            duration: GestureDuration(seconds: 1.4)
        )))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .elementToPoint(
                .predicate(.label("Slider")),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: ScreenPoint(x: 200, y: 40)
            )
        )))),
    ])

    #expect(plan == expected)
}

@Test func `canonical control flow and loops round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(predicate: .exists(.label("Pay")), body: [
                    .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                ]),
            ],
            elseBody: [.fail(FailStep(message: "Pay button missing"))]
        )),
        .wait(WaitStep(
            predicate: .change(.screen()),
            timeout: 3,
            elseBody: [.fail(FailStep(message: "screen did not change"))]
        )),
        .warn(WarnStep(message: "screen changed")),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "itemName",
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("itemName"),
                    target: .predicate(.label("Add item"))
                ))),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .element(.label("Delete"), .traits([.button])),
            limit: 2,
            parameter: "rowTarget",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("rowTarget")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("rowTarget")), timeout: 2)))),
            ]
        )),
    ]))
}

@Test func `canonical definitions and root parameters round trip through source compiler`() throws {
    let tapDefinition = try HeistPlan(
        name: "tap",
        body: [.action(try ActionStep(command: .activate(.predicate(.label("Add to Cart")))))]
    )
    let addButtonNamespace = try HeistPlan(name: "AddButton", definitions: [tapDefinition], body: [])
    let addToCart = try HeistPlan(
        name: "addToCart",
        parameter: .string(name: "item"),
        definitions: [addButtonNamespace],
        body: [
            .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
            .invoke(HeistInvocationStep(path: ["AddButton", "tap"])),
        ]
    )
    let library = try HeistPlan(name: "LibraryScreen", definitions: [addToCart], body: [])
    let plan = try HeistPlan(
        name: "purchaseFlow",
        definitions: [library],
        body: [
            .invoke(HeistInvocationStep(
                path: ["LibraryScreen", "addToCart"],
                argument: .string(.literal("Milk"))
            )),
        ]
    )

    try assertCanonicalRoundTrip(plan)
}

@Test func `reported agent target grammar gaps parse`() throws {
    let ordinal = try HeistPlanSourceCompiler().compile(root(#"Activate(.target(.label("Pay"), ordinal: 0))"#))
    #expect(ordinal.body == [
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"), ordinal: 0)))),
    ])

    let traits = try HeistPlanSourceCompiler().compile(root(#"Activate(.element(.label("Pay"), .traits([.button])))"#))
    #expect(traits.body == [
        .action(try ActionStep(command: .activate(.predicate(.element(.label("Pay"), .traits([.button])))))),
    ])

    let typeText = try HeistPlanSourceCompiler().compile(root(#"TypeText("milk", into: .label("Search"))"#))
    #expect(typeText.body == [
        .action(try ActionStep(command: .typeText(text: .literal("milk"), target: .predicate(.label("Search"))))),
    ])

    let screenshot = try HeistPlanSourceCompiler().compile(root("TakeScreenshot()"))
    #expect(screenshot.body == [
        .action(try ActionStep(command: .takeScreenshot)),
    ])

    let waived = try HeistPlanSourceCompiler().compile(root(#"Activate(.label("Pay")).withoutExpectation("reason")"#))
    #expect(waived.body == [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .waived(try ActionExpectationWaiver("reason")))),
    ])
}

@Test func `reported agent grammar mistakes fail with corrections`() throws {
    let stringTraits = compileError(root(#"Activate(.element(.label("Pay"), .traits(["button"])))"#))
    expect(stringTraits, contains: "traits must use enum-style syntax like [.button]")

    let actionOrdinal = compileError(root(#"Activate(.label("Pay"), ordinal: 0)"#))
    expect(
        actionOrdinal,
        contains: #"Ordinal belongs to the target. Use Activate(.target(.label("Pay"), ordinal: 0))."#
    )

    let labeledStringMatchMode = compileError(root(#"Activate(.label(contains: "Pay"))"#))
    expect(labeledStringMatchMode, contains: #"StringMatch modes use enum-case syntax; use `.label(.contains("..."))`"#)

    let nativeIf = compileError(root("""
    if true {
        Activate(.label("Pay"))
    } else {
        Fail("missing")
    }
    """))
    expect(nativeIf, contains: "native Swift if/else is not supported")
    expect(nativeIf, contains: "If { Case(...) { ... } Else { ... } }")

    let ifShorthand = try HeistPlanSourceCompiler().compile(root("""
    If(.exists(.label("Pay"))) {
        Activate(.label("Pay"))
    }.else {
        Fail("missing")
    }
    """))
    #expect(ifShorthand.body == [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: .exists(.label("Pay")),
                    body: [.action(try ActionStep(command: .activate(.predicate(.label("Pay")))))]
                ),
            ],
            elseBody: [.fail(FailStep(message: "missing"))]
        )),
    ])

    let unknownAction = compileError(root(#"Tap(.label("Pay"))"#))
    expect(unknownAction, contains: "unsupported ButtonHeist source statement 'Tap'")

    let wrongRunHeistArgument = compileError("""
    HeistPlan {
        HeistDef<String>("addItem", parameter: "item") { item in
            Activate(.label(item))
        }

        RunHeist("addItem", .label("Milk"))
    }
    """)
    expect(wrongRunHeistArgument, contains: "heist run argument type must match the target parameter")

    let emptyCustomActionName = compileError(root(#"CustomAction("", on: .label("Message"))"#))
    expect(emptyCustomActionName, contains: "custom action name must not be empty")

    let emptyRunHeistPath = compileError(root(#"RunHeist("")"#))
    expect(emptyRunHeistPath, contains: "heist invocation path must not be empty")

    let emptyRunHeistPathComponent = compileError(root(#"RunHeist("lib..checkout")"#))
    expect(emptyRunHeistPathComponent, contains: "heist invocation path component at index 1 must not be empty")

    let bodyTry = compileError(root("""
    try ForEach(["Milk"]) { item in
        Activate(.label(item))
    }
    """))
    expect(bodyTry, contains: "`try` is only allowed in Swift wrapper code")

    let caseAfterElse = compileError(root("""
    If {
        Else {
            Warn("fallback")
        }
        Case(.exists(.label("Pay"))) {
            Activate(.label("Pay"))
        }
    }
    """))
    expect(caseAfterElse, contains: "Case must appear before Else")
    let emptyUpdated = compileError(root(#"Activate(.label("Pay")).expect(.updated())"#))
    expect(emptyUpdated, contains: ".updated(...) requires an update matcher")

    let elementOnlyUpdated = compileError(root(#"Activate(.label("Pay")).expect(.updated(.label("Total")))"#))
    expect(elementOnlyUpdated, contains: ".updated(...) with an element matcher also requires an update matcher")

    let explicitlyElementOnlyUpdated = compileError(root(#"Activate(.label("Pay")).expect(.updated(.element(.label("Quantity"))))"#))
    expect(explicitlyElementOnlyUpdated, contains: ".updated(...) with an element matcher also requires an update matcher")

    let labeledElementUpdated = compileError(root(#"Activate(.label("Pay")).expect(.updated(element: .label("Total"), .value("$3")))"#))
    expect(labeledElementUpdated, contains: "updated(element:) is not supported")

    let labeledExplicitElementUpdated = compileError(root(#"Activate(.label("Pay")).expect(.updated(element: .element(.label("Total")), .value("$3")))"#))
    expect(labeledExplicitElementUpdated, contains: "updated(element:) is not supported")

    let beforeOnlyUpdate = compileError(root(#"Activate(.label("Pay")).expect(.updated(.value(before: "$2")))"#))
    expect(beforeOnlyUpdate, contains: "value update predicate requires after when before is set")

    let fromToUpdate = compileError(root(#"Activate(.label("Pay")).expect(.updated(.value(from: "$2", to: "$3")))"#))
    expect(fromToUpdate, contains: "value update predicate accepts before and after")

    let labelUpdate = compileError(root(#"Activate(.label("Pay")).expect(.updated(.label(before: "Old", after: "New")))"#))
    expect(labelUpdate, contains: "expected a string literal or scoped string reference")

    let identifierUpdate = compileError(root(#"Activate(.label("Pay")).expect(.updated(.identifier(before: "old", after: "new")))"#))
    expect(identifierUpdate, contains: "expected a string literal or scoped string reference")

    let screenChangedAppeared = compileError(root(#"Activate(.label("Pay")).expect(.screenChanged(.appeared(.label("Receipt"))))"#))
    expect(screenChangedAppeared, contains: "unsupported state predicate '.appeared'")

    let screenChangedUpdated = compileError(root(#"Activate(.label("Pay")).expect(.screenChanged(.updated(.value("$3"))))"#))
    expect(screenChangedUpdated, contains: "unsupported state predicate '.updated'")

    let genericScreenUpdated = compileError(root(#"Activate(.label("Pay")).expect(.change(.screen(.updated(.value("$3")))))"#))
    expect(genericScreenUpdated, contains: "unsupported state predicate '.updated'")

    let bareActionString = compileError(root(#"Activate("Pay")"#))
    expect(bareActionString, contains: "target expression requires an explicit accessibility property")

    let presentAlias = compileError(root(#"WaitFor(.present(.label("Receipt")))"#))
    expect(presentAlias, contains: "unsupported accessibility predicate '.present'")
}

@Test func `runtime parser rejects empty predicates and bare wait strings`() throws {
    let emptyExists = compileError(root(#"WaitFor(.exists())"#))
    expect(emptyExists, contains: ".exists requires an element matcher or target")

    let emptyMissing = compileError(root(#"WaitFor(.missing())"#))
    expect(emptyMissing, contains: ".missing requires an element matcher or target")

    let emptyAppeared = compileError(root(#"WaitFor(.appeared())"#))
    expect(emptyAppeared, contains: ".appeared requires an element matcher")

    let emptyDisappeared = compileError(root(#"WaitFor(.disappeared())"#))
    expect(emptyDisappeared, contains: ".disappeared requires an element matcher")

    let bareWaitString = compileError(root(#"WaitFor("Receipt")"#))
    expect(bareWaitString, contains: "accessibility predicate requires an explicit accessibility property")
}

@Test func `runtime parser rejects transition predicates in conditionals`() throws {
    let ifAppeared = compileError(root(#"""
    If(.appeared(.label("Receipt"))) {
        Warn("ready")
    }
    """#))
    expect(ifAppeared, contains: "unsupported state predicate '.appeared'")

    let caseUpdated = compileError(root(#"""
    If {
        Case(.updated(.value("Ready"))) {
            Warn("ready")
        }
    }
    """#))
    expect(caseUpdated, contains: "unsupported state predicate '.updated'")
}

@Test func `runtime parser rejects arbitrary Swift and bypass shapes`() throws {
    let cases: [(String, String)] = [
        (
            """
            import Foundation
            HeistPlan {
                Warn("x")
            }
            """,
            "import declarations are not supported"
        ),
        (
            root("""
            let items = ["Milk", "Bread"]
            Warn("x")
            """),
            "let declarations are not supported"
        ),
        (
            root("""
            var item = "Milk"
            Warn("x")
            """),
            "var declarations are not supported"
        ),
        (
            root("""
            func helper() {
                Warn("x")
            }
            """),
            "function declarations are not supported"
        ),
        (
            root("""
            if Bool.random() {
                Warn("x")
            }
            """),
            "native Swift if/else is not supported"
        ),
        (
            root("""
            for item in ["Milk"] {
                Warn("x")
            }
            """),
            "native Swift for statements are not supported"
        ),
        (
            root("""
            switch "x" {
            default:
                Warn("x")
            }
            """),
            "native Swift switch statements are not supported"
        ),
        (
            root("""
            struct Helper {}
            """),
            "type declarations are not supported"
        ),
        (
            root("""
            .init("Bypass") {
                Warn("x")
            }
            """),
            "expected an identifier"
        ),
        (
            """
            HeistPlan(body: [
                .warn(WarnStep(message: "raw"))
            ])
            """,
            "expected a string literal"
        ),
        (
            root(#"Activate(.label(helper()))"#),
            "arbitrary calls are not supported"
        ),
        (
            root(#"try RunHeist("Cart.addItem")"#),
            "`try` is only allowed in Swift wrapper code"
        ),
    ]

    for (source, expectedDiagnostic) in cases {
        expect(compileError(source), contains: expectedDiagnostic)
    }
}

@Test func `runtime parser rejects removed compatibility spellings`() {
    let cases: [(String, String)] = [
        (
            root(#"Activate(ElementTarget.label("Pay"))"#),
            "expected a ButtonHeist expression beginning with '.'"
        ),
        (
            root(#"WaitFor(AccessibilityPredicate.exists(.label("Pay")))"#),
            "expected a ButtonHeist expression beginning with '.'"
        ),
        (
            root(#"Activate(.element(.label(StringMatch.contains("Pay"))))"#),
            "expected a string literal or scoped string reference"
        ),
        (
            root(#"WaitFor(.exists(.label("Pay")), timeout: 1)"#),
            "expected a timeout duration such as .seconds(1)"
        ),
        (
            root(#"WaitFor(.exists(.label("Pay")), timeout: Double.seconds(1))"#),
            "expected a timeout duration such as .seconds(1)"
        ),
        (
            root(#"WaitFor(.change(.updated(.title())))"#),
            "unsupported element predicate '.title'"
        ),
    ]

    for (source, expectedDiagnostic) in cases {
        expect(compileError(source), contains: expectedDiagnostic)
    }
}

@Test func `element actions share the same target grammar`() throws {
    let source = """
    HeistPlan("TargetGrammar", targetParameter: "targetRef") { targetRef in
        Activate(.label("Pay"))
        Activate(.target(.label("Pay"), ordinal: 0))
        Activate(targetRef)
        Increment(.identifier("quantity"))
        Increment(.target(.identifier("quantity"), ordinal: 0))
        Increment(targetRef)
        Decrement(.value("5"))
        Decrement(.target(.value("5"), ordinal: 0))
        Decrement(targetRef)
        TypeText("milk", into: .element(.label("Search"), .traits([.searchField])))
        TypeText("milk", into: .target(.label("Search"), ordinal: 0))
        TypeText("milk", into: targetRef)
        CustomAction("Archive", on: .label("Message"))
        CustomAction("Archive", on: .target(.label("Message"), ordinal: 0))
        CustomAction("Archive", on: targetRef)
        Rotor("Headings", on: .label("Article"))
        Rotor("Headings", on: .target(.label("Article"), ordinal: 0))
        Rotor("Headings", on: targetRef)
    }
    """

    _ = try HeistPlanSourceCompiler().compile(source)
}

@Test func `parser scopes aliases through nested bodies`() throws {
    let source = """
    HeistPlan("Scoped", parameter: "rootValue") { rootAlias in
        HeistDef<String>("Echo.item", parameter: "item") { itemAlias in
            TypeText(itemAlias, into: .label(itemAlias))
        }

        HeistDef<ElementTarget>("Messages.archive", parameter: "message") { messageAlias in
            CustomAction("Archive", on: messageAlias)
        }

        If(.exists(.label(rootAlias))) {
            TypeText(rootAlias)
        }

        ForEach(["inner"]) { loopItem in
            TypeText(loopItem, into: .label(rootAlias))
        }

        ForEach(.matching(.label("Message")), limit: 1) { rowTarget in
            Activate(rowTarget).expect(.missing(rowTarget))
        }
    }
    """

    let plan = try HeistPlanSourceCompiler().compile(source)
    let echo = try #require(plan.definitions.first { $0.name == "Echo" })
    let item = try #require(echo.definitions.first { $0.name == "item" })
    let messages = try #require(plan.definitions.first { $0.name == "Messages" })
    let archive = try #require(messages.definitions.first { $0.name == "archive" })

    #expect(plan.parameter == .string(name: "rootValue"))
    #expect(item.parameter == .string(name: "item"))
    #expect(item.body == [
        .action(try ActionStep(command: .typeText(
            text: .ref("item"),
            target: .predicate(.label(.ref("item")))
        ))),
    ])
    #expect(archive.parameter == .elementTarget(name: "message"))
    #expect(archive.body == [
        .action(try ActionStep(command: .customAction(name: "Archive", target: .ref("message")))),
    ])
    #expect(plan.body == [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .exists(.label(.ref("rootValue"))),
                body: [.action(try ActionStep(command: .typeText(text: .ref("rootValue"), target: nil)))]
            ),
        ])),
        .forEachString(try ForEachStringStep(
            values: ["inner"],
            parameter: "loopItem",
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("loopItem"),
                    target: .predicate(.label(.ref("rootValue")))
                ))),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Message"),
            limit: 1,
            parameter: "rowTarget",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("rowTarget")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("rowTarget")), timeout: 1)))),
            ]
        )),
    ])
}

@Test func `parser rejects references outside lexical scope`() {
    let cases: [(source: String, diagnostic: String)] = [
        (
            root("""
            ForEach(["Milk"]) { item in
                TypeText(item)
            }
            TypeText(item)
            """),
            "expected a string literal or scoped string reference"
        ),
        (
            root("""
            ForEach(.matching(.label("Row")), limit: 1) { row in
                Activate(row).expect(.missing(row))
            }
            Activate(row)
            """),
            "expected a ButtonHeist expression beginning with '.'"
        ),
        (
            """
            HeistPlan {
                HeistDef<String>("Echo.item", parameter: "item") { itemAlias in
                    TypeText(itemAlias)
                }
                TypeText(itemAlias)
            }
            """,
            "expected a string literal or scoped string reference"
        ),
    ]

    for testCase in cases {
        expect(compileError(testCase.source), contains: testCase.diagnostic)
    }
}

@Test func `parser accepts nested ForEach bodies and scopes aliases`() throws {
    let source = """
    HeistPlan("NestedLoops", parameter: "screen") { screen in
        If(.exists(.label(screen))) {
            ForEach(["Milk", "Eggs"]) { item in
                ForEach(["Small"]) { size in
                    TypeText(size, into: .label(item))
                }
            }
        }

        ForEach(["Message"]) { rowName in
            ForEach(.matching(.label("Message")), limit: 1) { rowTarget in
                Activate(rowTarget).expect(.exists(rowTarget))
                TypeText(rowName, into: .label("Search"))
            }
        }
    }
    """

    _ = try HeistPlanSourceCompiler().compile(source)
}

@Test func `runtime source compiler rejects standard definition cap`() throws {
    let definitions = (0...250).map { index in
        """
            HeistDef<String>("Definitions.definition\(index)", parameter: "value") { value in
                Activate(.label(value))
            }
        """
    }.joined(separator: "\n\n")
    let source = """
    HeistPlan("tooManyDefinitions") {
    \(definitions)

        Warn("body")
    }
    """

    let diagnostic = compileError(source)

    expect(diagnostic, contains: "max total heist definitions")
    expect(diagnostic, contains: "252 definitions")

    let typedDiagnostic = compileDiagnostic(source)
    #expect(typedDiagnostic.code.rawValue == "heist.plan.runtime_safety")
    #expect(typedDiagnostic.phase == .planValidation)
    #expect(typedDiagnostic.path == "$.definitions[0].definitions")
    #expect(typedDiagnostic.hint == "Use 250 definitions or fewer.")
}

private func assertCanonicalRoundTrip(_ plan: HeistPlan) throws {
    let source = try plan.canonicalSwiftDSL()
    let compiled = try HeistPlanSourceCompiler().compile(source)
    #expect(compiled == plan, "Rendered source did not compile back to the same plan:\n\(source)")
}

private func compileError(_ source: String) -> String {
    do {
        _ = try HeistPlanSourceCompiler().compile(source)
        Issue.record("Expected source to fail: \(source)")
        return ""
    } catch {
        return String(describing: error)
    }
}

private func compileDiagnostic(_ source: String) -> HeistBuildDiagnostic {
    do {
        _ = try HeistPlanSourceCompiler().compile(source)
        Issue.record("Expected source to fail: \(source)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.missing_diagnostic",
            phase: .sourceCompilation,
            message: "Expected source to fail"
        )
    } catch let error as HeistPlanSourceCompilerError {
        return error.diagnostic
    } catch {
        Issue.record("Expected HeistPlanSourceCompilerError, got \(error)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.unexpected_error",
            phase: .sourceCompilation,
            message: String(describing: error)
        )
    }
}

private func root(_ body: String) -> String {
    """
    HeistPlan {
    \(body)
    }
    """
}

private func expect(_ string: String, contains substring: String) {
    if !string.contains(substring) {
        Issue.record("Expected error to contain '\(substring)', got: \(string)")
    }
    #expect(string.contains(substring))
}

private let nonDurableHeistActionRepairHint =
    "Use a direct client command for viewport/debug/session actions, or replace " +
    "this with a canonical durable DSL action."

private enum ParsedHeistStepKind: Equatable {
    case action
    case wait
    case conditional
    case forEachElement
    case forEachString
    case repeatUntil
    case warn
    case fail
    case heist
    case invoke
}

private extension HeistStep {
    var testKind: ParsedHeistStepKind {
        switch self {
        case .action: return .action
        case .wait: return .wait
        case .conditional: return .conditional
        case .forEachElement: return .forEachElement
        case .forEachString: return .forEachString
        case .repeatUntil: return .repeatUntil
        case .warn: return .warn
        case .fail: return .fail
        case .heist: return .heist
        case .invoke: return .invoke
        }
    }
}
