import Testing
import ThePlans

@Test func `inline plan source simple Activate compiles to HeistPlan`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.label("Pay"))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
    ])

    #expect(plan == expected)
}

@Test func `runtime parser accepts StringMatch enum cases for all string predicate fields`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.label(.exact("Search")))
    Activate(.identifier(.suffix("field")))
    WaitFor(.present(.element(label: .prefix("No results"), identifier: .contains("empty_state"), value: .suffix("items"))), timeout: .seconds(2))
    TypeText("milk", into: .value(.prefix("Search")))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.label(.exact("Search")))))),
        .action(try ActionStep(command: .activate(.predicate(.identifier(.suffix("field")))))),
        .wait(WaitStep(
            predicate: .present(ElementPredicateTemplate.element(
                label: .prefix(.literal("No results")),
                identifier: .contains(.literal("empty_state")),
                value: .suffix(.literal("items"))
            )),
            timeout: 2
        )),
        .action(try ActionStep(command: .typeText(
            text: .literal("milk"),
            target: .predicate(.value(.prefix("Search")))
        ))),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source chained expectation compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Activate(.label("Pay")).expect(.changed(.screen()))
    """))
    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectation: WaitStep(predicate: .changed(.screen()), timeout: 0)
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source property update expectations compile`() throws {
    let scoped = try HeistPlanSourceCompiler().compile(root(#"""
    TypeText("Bruschetta", into: .identifier("Search"))
        .expect(.changed(.updated(.identifier("Search"), property: .value, to: "Bruschetta")))
    """#))
    let unscoped = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.changed(.updated(property: .value, to: "3")))
    """#))
    let fromTo = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.changed(.updated(.identifier("Quantity"), property: .value, from: "2", to: "3")))
    """#))
    let broadFromTo = try HeistPlanSourceCompiler().compile(root(#"""
    Increment(.identifier("Quantity"))
        .expect(.changed(.updated(.identifier("Quantity"), property: .value, from: .prefix("cart:"), to: .contains("items"))))
    """#))

    let expectedScoped = try HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(
                text: .literal("Bruschetta"),
                target: .predicate(.identifier("Search"))
            ),
            expectation: WaitStep(predicate: .changed(.updated(ElementUpdatePredicateExpr(
                element: .identifier("Search"),
                property: .value,
                to: "Bruschetta"
            ))))
        )),
    ])
    let expectedUnscoped = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectation: WaitStep(predicate: .changed(.updated(ElementUpdatePredicateExpr(
                property: .value,
                to: "3"
            ))))
        )),
    ])
    let expectedFromTo = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectation: WaitStep(predicate: .changed(.updated(ElementUpdatePredicateExpr(
                element: .identifier("Quantity"),
                property: .value,
                from: "2",
                to: "3"
            ))))
        )),
    ])
    let expectedBroadFromTo = try HeistPlan(body: [
        .action(try ActionStep(
            command: .increment(.predicate(.identifier("Quantity"))),
            expectation: WaitStep(predicate: .changed(.updated(ElementUpdatePredicateExpr(
                element: .identifier("Quantity"),
                property: .value,
                from: .prefix("cart:"),
                to: .contains("items")
            ))))
        )),
    ])

    #expect(scoped == expectedScoped)
    #expect(unscoped == expectedUnscoped)
    #expect(fromTo == expectedFromTo)
    #expect(broadFromTo == expectedBroadFromTo)
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
            expectation: WaitStep(predicate: .changed(.elements), timeout: 0)
        )),
        .wait(WaitStep(
            predicate: .present(.label("Receipt")),
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
                .expect(.present(.label("Added")))
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
            Case(.present(.label("Cart"))) {
                Warn("Cart ready")
            }
            Else {
                Warn("Cart missing")
            }
        }

        If(.present(.label("Pay"))) {
            Warn("Pay visible")
        }.else {
            Warn("Pay missing")
        }

        ForEach(["Milk", "Bread"]) { item in
            RunHeist("Cart.addItem", item)
        }

        ForEach(.matching(.element(label: "Message", traits: [.button])), limit: 2) { message in
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

@Test func `inline plan source ForEach string compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    ForEach(["a", "b"]) { item in
        Activate(.label(item)).expect(.present(.label(item)))
    }
    """))
    let expected = try HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["a", "b"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .activate(.predicate(.label(.ref("item")))),
                    expectation: WaitStep(predicate: .state(.present(.label(.ref("item")))), timeout: 0)
                )),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source WaitFor and If compile`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    WaitFor(.present(.label("Home")), timeout: .seconds(1))
    If {
        Case(.present(.label("Pay"))) {
            Warn("ready")
        }
    }
    """))
    let expected = try HeistPlan(body: [
        .wait(WaitStep(predicate: .state(.present(.label("Home"))), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Pay"))), body: [.warn(WarnStep(message: "ready"))]),
        ])),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source ForEach matching compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    ForEach(.matching(.label("Row")), limit: 2) { target in
        Activate(target).expect(.absent(target))
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
                    expectation: WaitStep(predicate: .state(.absentTarget(.ref("target"))), timeout: 0)
                )),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source RunHeist syntax validates through normal runtime pipeline`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile(root("""
        RunHeist("CartScreen.checkout")
        """))
    }
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
            expectation: WaitStep(predicate: .changed(.screen()), timeout: 0)
        )),
        .action(try ActionStep(
            command: .typeText(text: .literal("milk"), target: .predicate(.label("Search"))),
            expectation: WaitStep(predicate: .present(.value("milk")), timeout: 2)
        )),
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
            expectationWaiver: "intentionally optional"
        )),
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"), ordinal: 0)))),
        .action(try ActionStep(command: .activate(.predicate(.element(
            label: "Delete",
            traits: [.button],
            excludeTraits: [.header]
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
                PredicateCase(predicate: .present(.label("Pay")), body: [
                    .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                ]),
            ],
            elseBody: [.fail(FailStep(message: "Pay button missing"))]
        )),
        .wait(WaitStep(
            predicate: .changed(.screen()),
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
            matching: .element(label: "Delete", traits: [.button]),
            limit: 2,
            parameter: "rowTarget",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("rowTarget")),
                    expectation: WaitStep(predicate: .absent(.ref("rowTarget")), timeout: 2)
                )),
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

    let traits = try HeistPlanSourceCompiler().compile(root(#"Activate(.element(label: "Pay", traits: [.button]))"#))
    #expect(traits.body == [
        .action(try ActionStep(command: .activate(.predicate(.element(label: "Pay", traits: [.button]))))),
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
            expectationWaiver: "reason"
        )),
    ])
}

@Test func `reported agent grammar mistakes fail with corrections`() throws {
    let stringTraits = compileError(root(#"Activate(.element(label: "Pay", traits: ["button"]))"#))
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
    If(.present(.label("Pay"))) {
        Activate(.label("Pay"))
    }.else {
        Fail("missing")
    }
    """))
    #expect(ifShorthand.body == [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: .present(.label("Pay")),
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
        Case(.present(.label("Pay"))) {
            Activate(.label("Pay"))
        }
    }
    """))
    expect(caseAfterElse, contains: "Case must appear before Else")
    let changeAlias = compileError(root(#"Activate(.label("Pay")).expect(.changed(.screenChanged))"#))
    expect(changeAlias, contains: "unsupported change predicate '.screenChanged'")

    let screenChangedAlias = compileError(root(#"Activate(.label("Pay")).expect(.screenChanged)"#))
    expect(screenChangedAlias, contains: "unsupported accessibility predicate '.screenChanged'")

    let existsAlias = compileError(root(#"WaitFor(.exists(.label("Receipt")))"#))
    expect(existsAlias, contains: "unsupported accessibility predicate '.exists'")
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
            root(#"WaitFor(AccessibilityPredicate.present(.label("Pay")))"#),
            "expected a ButtonHeist expression beginning with '.'"
        ),
        (
            root(#"Activate(.element(label: StringMatch.contains("Pay")))"#),
            "expected a string literal or scoped string reference"
        ),
        (
            root(#"WaitFor(.present(.label("Pay")), timeout: 1)"#),
            "expected a timeout duration such as .seconds(1)"
        ),
        (
            root(#"WaitFor(.present(.label("Pay")), timeout: Double.seconds(1))"#),
            "expected a timeout duration such as .seconds(1)"
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
        TypeText("milk", into: .element(label: "Search", traits: [.searchField]))
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

        If(.present(.label(rootAlias))) {
            TypeText(rootAlias)
        }

        ForEach(["inner"]) { loopItem in
            TypeText(loopItem, into: .label(rootAlias))
        }

        ForEach(.matching(.label("Message")), limit: 1) { rowTarget in
            Activate(rowTarget).expect(.absent(rowTarget))
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
                predicate: .present(.label(.ref("rootValue"))),
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
                    expectation: WaitStep(predicate: .absent(.ref("rowTarget")), timeout: 0)
                )),
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
                Activate(row).expect(.absent(row))
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

private enum ParsedHeistStepKind: Equatable {
    case action
    case wait
    case conditional
    case forEachElement
    case forEachString
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
        case .warn: return .warn
        case .fail: return .fail
        case .heist: return .heist
        case .invoke: return .invoke
        }
    }
}
