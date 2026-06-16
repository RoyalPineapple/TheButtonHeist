import Testing
import ThePlans

@Suite("Canonical Heist Source Round Trip")
struct CanonicalHeistSourceRoundTripTests {
    @Test("actions, targets, expectations, and waivers round trip")
    func actionsTargetsExpectationsAndWaiversRoundTrip() throws {
        try assertRoundTrip(try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectation: WaitStep(predicate: .changed(.screen()), timeout: 0)
            )),
            .action(try ActionStep(
                command: .typeText(text: .literal("milk"), target: .predicate(.label("Search"))),
                expectation: WaitStep(predicate: .present(.element(label: "Search", value: "milk")), timeout: 2)
            )),
            .action(try ActionStep(
                command: .typeText(text: .literal("Bruschetta"), target: .predicate(.identifier("Search"))),
                expectation: WaitStep(predicate: .changed(.updated(ElementUpdatePredicateExpr(
                    element: .identifier("Search"),
                    property: .value,
                    from: "",
                    to: "Bruschetta"
                ))))
            )),
            .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
            .action(try ActionStep(command: .decrement(.predicate(.identifier("quantity"), ordinal: 0)))),
            .action(try ActionStep(command: .customAction(
                name: "Archive",
                target: .predicate(.element(label: "Message", traits: [.button]))
            ))),
            .action(try ActionStep(command: .rotor(
                selection: .named("Headings"),
                target: .predicate(.label("Article")),
                direction: .next
            ))),
            .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
            .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
            .action(try ActionStep(command: .dismissKeyboard)),
            .action(try ActionStep(
                command: .activate(.predicate(.label("Optional"))),
                expectationWaiver: "No durable semantic outcome"
            )),
        ]))
    }

    @Test("durable mechanical actions round trip")
    func durableMechanicalActionsRoundTrip() throws {
        try assertRoundTrip(try HeistPlan(body: [
            .action(try ActionStep(command: .mechanicalTap(TapTarget(
                selection: .coordinate(ScreenPoint(x: 12, y: 34))
            )))),
            .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
                selection: .coordinate(ScreenPoint(x: 20, y: 40)),
                duration: GestureDuration(seconds: 1)
            )))),
            .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(
                .label("List"),
                .down
            ))))),
            .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(
                .label("Carousel"),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: UnitPoint(x: 0.2, y: 0.5)
            ))))),
            .action(try ActionStep(command: .mechanicalDrag(DragTarget(
                selection: .pointToPoint(start: ScreenPoint(x: 10, y: 10), end: ScreenPoint(x: 100, y: 100))
            )))),
        ]))
    }

    @Test("waits, conditionals, loops, warnings, and failures round trip")
    func controlsWarningsAndFailuresRoundTrip() throws {
        try assertRoundTrip(try HeistPlan(body: [
            .wait(WaitStep(predicate: .present(.label("Home")), timeout: 1)),
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
                parameter: "item",
                body: [
                    .action(try ActionStep(command: .typeText(
                        text: .ref("item"),
                        target: .predicate(.label("Add item"))
                    ))),
                ]
            )),
            .forEachElement(try ForEachElementStep(
                matching: .element(label: "Delete", traits: [.button]),
                limit: 2,
                parameter: "target",
                body: [
                    .action(try ActionStep(
                        command: .activate(.ref("target")),
                        expectation: WaitStep(predicate: .absent(.ref("target")), timeout: 2)
                    )),
                ]
            )),
            .warn(WarnStep(message: "done")),
            .fail(FailStep(message: "stop")),
        ]))
    }

    @Test("definitions, parameters, and RunHeist composition round trip")
    func definitionsParametersAndCompositionRoundTrip() throws {
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
                .action(try ActionStep(
                    command: .activate(.predicate(.label(.ref("item")))),
                    expectation: WaitStep(predicate: .present(.label("Added")), timeout: 2)
                )),
                .invoke(HeistInvocationStep(path: ["AddButton", "tap"])),
            ]
        )
        let targetDefinition = try HeistPlan(
            name: "archive",
            parameter: .elementTarget(name: "row"),
            body: [
                .action(try ActionStep(command: .customAction(name: "Archive", target: .ref("row")))),
            ]
        )
        let library = try HeistPlan(name: "LibraryScreen", definitions: [addToCart, targetDefinition], body: [])
        let plan = try HeistPlan(
            name: "purchaseFlow",
            definitions: [library],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["LibraryScreen", "addToCart"],
                    argument: .string(.literal("Milk"))
                )),
                .invoke(HeistInvocationStep(
                    path: ["LibraryScreen", "archive"],
                    argument: .elementTarget(.predicate(.label("Milk")))
                )),
            ]
        )

        try assertRoundTrip(plan)
    }

    private func assertRoundTrip(_ plan: HeistPlan) throws {
        let source = try plan.canonicalSwiftDSL()
        let parsed = try HeistPlanSourceCompiler().compile(source)
        #expect(parsed == plan, "Canonical source failed round trip:\n\(source)")
    }
}
