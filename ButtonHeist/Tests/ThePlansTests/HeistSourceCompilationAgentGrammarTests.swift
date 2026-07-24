import Testing
@testable import ThePlans

@Test func `reported agent target grammar gaps parse`() throws {
    let ordinal = try HeistSourceCompilation.compile(root(#"Activate(.target(.label("Pay"), ordinal: 0))"#))
    #expect(ordinal.body == [
        .action(ActionStep(command: .activate(.predicate(.label("Pay"), ordinal: 0)))),
    ])

    let scopedOrdinal = try HeistSourceCompilation.compile(root(
        #"Activate(.within(container: .identifier("Sheet"), .target(.label("Pay"), ordinal: 0)))"#
    ))
    #expect(scopedOrdinal.body == [
        .action(ActionStep(command: .activate(.within(
            container: .identifier("Sheet"),
            target: .predicate(.label("Pay"), ordinal: 0)
        )))),
    ])

    let traits = try HeistSourceCompilation.compile(root(#"Activate(.element(.label("Pay"), .traits([.button])))"#))
    #expect(traits.body == [
        .action(ActionStep(command: .activate(.predicate(.element(.label("Pay"), .traits([.button])))))),
    ])

    let typeText = try HeistSourceCompilation.compile(root(#"TypeText("milk", into: .label("Search"))"#))
    #expect(typeText.body == [
        .action(ActionStep(command: .typeText(text: "milk", target: .predicate(.label("Search"))))),
    ])

    let screenshot = try HeistSourceCompilation.compile(root("TakeScreenshot()"))
    #expect(screenshot.body == [
        .action(ActionStep(command: .takeScreenshot)),
    ])

    let waived = try HeistSourceCompilation.compile(root(#"Activate(.label("Pay")).withoutExpectation("reason")"#))
    #expect(waived.body == [
        .action(ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .waived("reason"))),
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

    let scopedActionOrdinal = compileError(root(
        #"Activate(.within(container: .identifier("Sheet"), .label("Pay")), ordinal: 0)"#
    ))
    expect(
        scopedActionOrdinal,
        contains: #"Use Activate(.within(container: .identifier("Sheet"), .target(.label("Pay"), ordinal: 0)))."#
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

    let ifShorthand = try HeistSourceCompilation.compile(root("""
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
                    body: [.action(ActionStep(command: .activate(.predicate(.label("Pay")))))]
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
    expect(emptyCustomActionName, contains: "custom action name must not be blank")

    let emptyRunHeistPath = compileError(root(#"RunHeist("")"#))
    expect(emptyRunHeistPath, contains: "heist path must not be empty")

    let emptyRunHeistPathComponent = compileError(root(#"RunHeist("lib..checkout")"#))
    expect(emptyRunHeistPathComponent, contains: "heist path component at index 1 must not be empty")

    let bodyTry = compileError(root("""
    try ForEach("Milk") { item in
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
}

@Test func `reported agent update grammar mistakes fail with corrections`() throws {
    let emptyUpdated = compileError(root(#"Activate(.label("Pay")).expect(.changed(.elements([.updated()])))"#))
    expect(emptyUpdated, contains: "expected a ButtonHeist expression beginning with '.'")

    let elementOnlyUpdated = compileError(root(
        #"Activate(.label("Pay")).expect(.changed(.elements([.updated(.label("Total"))])))"#
    ))
    expect(elementOnlyUpdated, contains: "expected ','")

    let explicitlyElementOnlyUpdated = compileError(root(
        #"Activate(.label("Pay")).expect("# +
            #".changed(.elements([.updated(.element(.label("Quantity")))])))"#
    ))
    expect(explicitlyElementOnlyUpdated, contains: "expected ','")

    let labeledElementUpdated = compileError(root(
        #"Activate(.label("Pay")).expect("# +
            #".changed(.elements([.updated(element: .label("Total"), .value("$3"))])))"#
    ))
    expect(labeledElementUpdated, contains: "expected a ButtonHeist expression beginning with '.'")

    let labeledExplicitElementUpdated = compileError(root(
        #"Activate(.label("Pay")).expect("# +
            #".changed(.elements([.updated(element: .element(.label("Total")), "# +
            #".value("$3"))])))"#
    ))
    expect(labeledExplicitElementUpdated, contains: "expected a ButtonHeist expression beginning with '.'")

    let beforeOnlyUpdate = compileError(root(
        #"Activate(.label("Pay")).expect("# +
            #".changed(.elements([.updated(.label("Total"), .value(before: "$2"))])))"#
    ))
    expect(beforeOnlyUpdate, contains: "value update predicate requires after when before is set")

    let screenChangedAppeared = compileError(root(
        #"Activate(.label("Pay")).expect(.changed(.screen([.appeared(.label("Receipt"))])))"#
    ))
    expect(screenChangedAppeared, contains: "screen assertions accept only .exists and .missing")

    let screenChangedUpdated = compileError(root(
        #"Activate(.label("Pay")).expect("# +
            #".changed(.screen([.updated(.label("Total"), .value("$3"))])))"#
    ))
    expect(screenChangedUpdated, contains: "screen assertions accept only .exists and .missing")

}

@Test func `runtime parser rejects empty predicates`() throws {
    let emptyExists = compileError(root(#"WaitFor(.exists())"#))
    expect(emptyExists, contains: "expected a ButtonHeist expression beginning with '.'")

    let emptyMissing = compileError(root(#"WaitFor(.missing())"#))
    expect(emptyMissing, contains: "expected a ButtonHeist expression beginning with '.'")

    let emptyAppeared = compileError(root(#"WaitFor(.changed(.elements([.appeared()])))"#))
    expect(emptyAppeared, contains: "expected a ButtonHeist expression beginning with '.'")

    let emptyDisappeared = compileError(root(#"WaitFor(.changed(.elements([.disappeared()])))"#))
    expect(emptyDisappeared, contains: "expected a ButtonHeist expression beginning with '.'")

}

@Test func `runtime parser rejects transition predicates in conditionals`() throws {
    let ifAppeared = compileError(root(#"""
    If(.appeared(.label("Receipt"))) {
        Warn("ready")
    }
    """#))
    expect(ifAppeared, contains: "screen assertion accepts only .exists and .missing")

    let caseUpdated = compileError(root(#"""
    If {
        Case(.updated(.value("Ready"))) {
            Warn("ready")
        }
    }
    """#))
    expect(caseUpdated, contains: "screen assertion accepts only .exists and .missing")
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
