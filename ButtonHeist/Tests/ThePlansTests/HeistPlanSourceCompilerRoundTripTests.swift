import Testing
@testable import ThePlans

@Test func `canonical semantic actions round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 0.001)))),
        .action(ActionStep(
            command: .typeText(text: "milk", target: .predicate(.label("Search"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.value("milk")), timeout: 2)))),
        .action(ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
        .action(ActionStep(command: .decrement(.predicate(.identifier("quantity"))))),
        .action(ActionStep(command: .customAction(name: "Archive", target: .predicate(.label("Message"))))),
        .action(ActionStep(command: .rotor(
            selection: .named("Headings"),
            target: .predicate(.label("Article")),
            direction: .previous
        ))),
        .action(ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(ActionStep(command: .dismissKeyboard)),
        .action(ActionStep(
            command: .activate(.predicate(.label("Maybe Later"))),
            expectationPolicy: .waived("intentionally optional"))),
        .action(ActionStep(command: .activate(.predicate(.label("Pay"), ordinal: 0)))),
        .action(ActionStep(command: .activate(.predicate(.element(
            .label("Delete"),
            .traits([.button]),
            .exclude(.traits([.header]))
        ))))),
    ]))
}

@Test func `canonical mechanical actions round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .action(ActionStep(command: .mechanicalTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 12, y: 34))
        )))),
        .action(ActionStep(command: .mechanicalTap(TapTarget(
            selection: .elementUnitPoint(.label("Cell"), UnitPoint(x: 0.25, y: 0.75))
        )))),
        .action(ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 20, y: 40)),
            duration: 1
        )))),
        .action(ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(.label("Message"), UnitPoint(x: 0.5, y: 0.2)),
            duration: 1.4
        )))),
        .action(ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(
            .label("Carousel"),
            start: UnitPoint(x: 0.8, y: 0.5),
            end: UnitPoint(x: 0.2, y: 0.5)
        ))))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .elementToPoint(
                .label("Slider"),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: ScreenPoint(x: 200, y: 40)
            )
        )))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .pointToPoint(start: ScreenPoint(x: 10, y: 10), end: ScreenPoint(x: 100, y: 100))
        )))),
    ]))
}

@Test func `mechanical tap ScreenPoint source compiles to raw coordinate tap`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Mechanical.Tap(ScreenPoint(x: 888, y: 372))
    """))
    let expected = try HeistPlan(body: [
        .action(ActionStep(command: .mechanicalTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 888, y: 372))
        )))),
    ])

    #expect(plan == expected)
}

@Test func `mechanical element unit-point source compiles to element-relative gesture`() throws {
    let plan = try HeistPlanSourceCompiler().compile(root("""
    Mechanical.Tap(.label("Row"), at: UnitPoint(x: 0.25, y: 0.75))
    Mechanical.LongPress(.label("Row"), at: UnitPoint(x: 0.5, y: 0.5), duration: 1.4)
    Mechanical.Drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 200, y: 40))
    """))
    let expected = try HeistPlan(body: [
        .action(ActionStep(command: .mechanicalTap(TapTarget(selection: .elementUnitPoint(
            .predicate(.label("Row")),
            UnitPoint(x: 0.25, y: 0.75)
        ))))),
        .action(ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Row")),
                UnitPoint(x: 0.5, y: 0.5)
            ),
            duration: 1.4
        )))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            selection: .elementToPoint(
                .predicate(.label("Slider")),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: ScreenPoint(x: 200, y: 40)
            )
        )))),
    ])

    #expect(plan == expected)
}

@Test func `gesture point source rejects nonfinite decimal coordinates`() {
    let overflowingDecimal = String(repeating: "9", count: 400)
    let sources = [
        "Mechanical.Tap(ScreenPoint(x: \(overflowingDecimal), y: 0))",
        "Mechanical.Tap(.label(\"Row\"), at: UnitPoint(x: 0, y: \(overflowingDecimal)))",
    ]

    for source in sources {
        expect(compileError(root(source)), contains: "coordinate must be finite")
    }
}

@Test func `canonical control flow and loops round trip through source compiler`() throws {
    try assertCanonicalRoundTrip(try HeistPlan(body: [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(predicate: .exists(.label("Pay")), body: [
                    .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
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
                .action(ActionStep(command: .typeText(
                    reference: "itemName",
                    target: .predicate(.label("Add item"))
                ))),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .element(.label("Delete"), .traits([.button])),
            limit: 2,
            parameter: "rowTarget",
            body: [
                .action(ActionStep(
                    command: .activate(.ref("rowTarget")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("rowTarget")), timeout: 2)))),
            ]
        )),
    ]))
}

@Test func `canonical definitions and root parameters round trip through source compiler`() throws {
    let tapDefinition = try HeistPlan(
        name: "tap",
        body: [.action(ActionStep(command: .activate(.predicate(.label("Add to Cart")))))]
    )
    let addButtonNamespace = try HeistPlan(name: "AddButton", definitions: [tapDefinition], body: [])
    let addToCart = try HeistPlan(
        name: "addToCart",
        parameter: .string(name: "item"),
        definitions: [addButtonNamespace],
        body: [
            .action(ActionStep(command: .activate(.predicate(
                .label(HeistReferenceName(stringLiteral: "item"))
            )))),
            .invoke(HeistInvocationStep(path: "AddButton.tap")),
        ]
    )
    let library = try HeistPlan(name: "LibraryScreen", definitions: [addToCart], body: [])
    let plan = try HeistPlan(
        name: "purchaseFlow",
        definitions: [library],
        body: [
            .invoke(HeistInvocationStep(
                path: "LibraryScreen.addToCart",
                argument: .string("Milk")
            )),
        ]
    )

    try assertCanonicalRoundTrip(plan)
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

@Test func `element semantic surfaces parse and render canonically`() throws {
    let source = root(#"""
    WaitFor(.exists(.element(
        .label("Coke"),
        .hint(.contains("edit")),
        .actions([.custom("Modify")]),
        .exclude(.actions([.custom("Sub")])),
        .customContent(label: "Slot", value: "Main"),
        .rotors(["Actions"]),
        .exclude(.rotors(["Headings"]))
    )), timeout: 2)
    """#)

    let plan = try HeistPlanSourceCompiler().compile(source)
    let canonical = try plan.canonicalSwiftDSL()

    #expect(canonical.contains(#".hint(.contains("edit"))"#))
    #expect(canonical.contains(#".actions([.custom("Modify")])"#))
    #expect(canonical.contains(#".exclude(.actions([.custom("Sub")]))"#))
    #expect(canonical.contains(#".customContent(.init(label: "Slot", value: "Main"))"#))
    #expect(canonical.contains(#".rotors(["Actions"])"#))
    #expect(canonical.contains(#".exclude(.rotors(["Headings"]))"#))
}
