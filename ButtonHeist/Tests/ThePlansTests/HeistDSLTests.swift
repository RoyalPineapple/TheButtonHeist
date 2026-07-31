import ButtonHeistTestSupport
import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func actionConstructorBuildsOneActionStep() throws {
    let heist = try HeistPlan {
        Activate(.label("Save"))
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(command: .activate(.label("Save")))),
    ]))
}

@Test
func actionTargetSupportsRepeatedStringChecksForOneProperty() throws {
    let heist = try HeistPlan {
        Activate(.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
            traits: [.button]
        ))
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(command: .activate(.predicate(.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
            traits: [.button]
        ))))),
    ]))
}

@Test
func actionExpectationAttachesWaitStep() throws {
    let heist = try HeistPlan {
        Activate(.label("Sign In"))
            .expect(.exists(.label("Home")), timeout: 5)
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Sign In")),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Home")), timeout: 5)))),
    ]))
}

@Test
func actionUntilBuildsRepeatUntilWithDefaultProgressExpectation() throws {
    let heist = try HeistPlan {
        Increment(.label("Volume"))
            .until(.exists(.element(.label("Volume"), .value("100"))))
    }

    #expect(try heist == HeistPlan(body: [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.element(.label("Volume"), .value("100"))),
            timeout: ThePlans.defaultWaitTimeout,
            body: [
                .action(ActionStep(
                    command: .increment(.label("Volume")))),
            ]
        )),
    ]))
}

@Test
func actionExpectationSupportsScopedPropertyUpdateDelta() throws {
    let heist = try HeistPlan {
        TypeText("Bruschetta", into: .identifier("Search"))
            .expect(.elementsChanged([
                .updated(.identifier("Search"), .value("Bruschetta")),
            ]))
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(
            command: .typeText(
                text: "Bruschetta",
                target: .identifier("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .elementsChanged([
                .updated(.identifier("Search"), .value(after: "Bruschetta")),
            ]), timeout: .sessionDefault)))),
    ]))
}

@Test
func actionExpectationUsesCanonicalElementChangeAssertions() throws {
    let appeared = try HeistPlan {
        Activate(.label("Add Bruschetta"))
            .expect(.elementsChanged([
                .appeared(.label(.contains("Bruschetta, $9.00"))),
            ]))
    }
    let disappeared = try HeistPlan {
        Activate(.label("Remove Bruschetta"))
            .expect(.elementsChanged([
                .disappeared(.identifier("cart-row-bruschetta")),
            ]))
    }
    let updated = try HeistPlan {
        TypeText("Bruschetta", into: .identifier("Search"))
            .expect(.elementsChanged([
                .updated(.identifier("Search"), .value("Bruschetta")),
            ]))
    }

    #expect(try appeared == HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Add Bruschetta")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .elementsChanged([
                    .appeared(.label(.contains("Bruschetta, $9.00"))),
                ]),
                timeout: .sessionDefault
            )))),
    ]))
    #expect(try disappeared == HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Remove Bruschetta")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .elementsChanged([
                    .disappeared(.identifier("cart-row-bruschetta")),
                ]),
                timeout: .sessionDefault
            )))),
    ]))
    #expect(try updated == HeistPlan(body: [
        .action(ActionStep(
            command: .typeText(
                text: "Bruschetta",
                target: .identifier("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .elementsChanged([
                .updated(.identifier("Search"), .value(after: "Bruschetta")),
            ]), timeout: .sessionDefault)))),
    ]))
}

@Test
func predicateContextsUseExplicitCanonicalAssertions() throws {
    let heist = try HeistPlan {
        Activate(.label("Search"))
            .expect(.exists(.label("Results")))

        Activate(.label("Open Details"))
            .expect(.screenChanged("Details"))

        WaitFor(.exists(.identifier("ready")), timeout: 2)

        If(.exists(.value(.contains("Promo")))) {
            Warn("promo visible")
        }
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .exists(.label("Results")),
                timeout: .sessionDefault
            )))),
        .action(ActionStep(
            command: .activate(.label("Open Details")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .screenChanged("Details"),
                timeout: .sessionDefault
            )))),
        .wait(WaitStep(predicate: .exists(.identifier("ready")), timeout: 2)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .exists(.value(.contains("Promo"))),
                body: [.warn(WarnStep(message: "promo visible"))]
            ),
        ])),
    ]))
}

@Test
func forEachInfersStringValuesAndElementPredicates() throws {
    let heist = try HeistPlan {
        ForEach("Milk", "Eggs") { item in
            TypeText(item, into: .label("Search"))
        }

        ForEach(.label("Delete"), limit: 2) { target in
            Activate(target).expect(.missing(target))
        }
    }

    #expect(try heist == HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(ActionStep(command: .typeText(
                    reference: HeistReferenceName(stringLiteral: "item"),
                    target: .label("Search")
                ))),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 2,
            parameter: "target",
            body: [
                .action(ActionStep(
                    command: .activate(.ref("target")),
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: .missing(.ref("target")),
                        timeout: .sessionDefault
                    )))),
            ]
        )),
    ]))
}

/// A screen boundary and an element on the arrived screen are two questions, and
/// an expectation holds one predicate. Authored as siblings they are two steps —
/// the boundary on the action, the element in the `WaitFor` after it.
@Test
func `screen and element expectations are authored as sibling steps`() throws {
    let plan = try HeistPlan {
        Activate(.label("Search"))
            .expect(.screenChanged, timeout: 5)

        WaitFor(.exists(.label("Results")), timeout: 5)
    }
    let expected = try HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .screenChanged,
                timeout: 5
            )))),
        .wait(WaitStep(predicate: .exists(.label("Results")), timeout: 5)),
    ])

    #expect(plan == expected)
    #expect(plan.body.count == 2)
}

@Test
func `chained root expectations fail canonical validation`() {
    #expect(throws: HeistPlanBuildError.self) {
        try HeistPlan {
            Activate(.label("Save"))
                .expect(.exists(.label("A")))
                .expect(.exists(.label("B")))
        }
    }
}

/// A named screen predicate does not absorb a second question either: chaining a
/// presence expectation onto it is the same unsupported composition, in either
/// authored order.
@Test
func `chained expectation onto a named screen predicate fails validation`() {
    #expect(throws: HeistPlanBuildError.self) {
        try HeistPlan {
            Activate(.label("Search"))
                .expect(.screenChanged("Results"))
                .expect(.exists(.label("Filter")))
        }
    }
    #expect(throws: HeistPlanBuildError.self) {
        try HeistPlan {
            Activate(.label("Search"))
                .expect(.exists(.label("Filter")))
                .expect(.screenChanged("Results"))
        }
    }
}

@Test
func testAuthoredActionExpectationRejectsConflictingExplicitTimeouts() throws {
    do {
        _ = try HeistPlan {
            Activate(.label("Save"))
                .expect(.screenChanged, timeout: 1)
                .expect(.exists(.label("B")), timeout: 2)
        }
        Issue.record("Expected HeistPlanBuildError")
    } catch let error as HeistPlanBuildError {
        // Chaining is itself unsupported, so the conflicting timeout is the
        // second diagnostic, not the only one.
        #expect(error.diagnostics.count == 2)
        let diagnostic = try #require(error.diagnostics.last)
        #expect(diagnostic.code == .dslInvalidActionExpectation)
        #expect(diagnostic.phase == .dslBuild)
        #expect(diagnostic.path == "activate")
        #expect(diagnostic.message.contains("multiple explicit expectation timeouts"))
        #expect(diagnostic.hint == "Use one explicit timeout for the composed expectation.")
    } catch {
        Issue.record("Expected HeistPlanBuildError, got \(error)")
    }
}

@Test
func `unsupported chained change expectations fail validation without replacement`() throws {
    #expect(throws: HeistPlanBuildError.self) {
        try HeistPlan {
            Activate(.label("Save"))
                .expect(.elementsChanged)
                .expect(.screenChanged)
        }
    }
}
@Test
func `string heist search flow preserves query ref in post activation expectation JSON`() throws {
    enum SearchScreen {
        static let search = HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.exists(.value(query)), timeout: 1)

            Activate(.label("Search"))
                .expect(.elementsChanged([.exists(.label(query))]), timeout: 5)
        }
    }

    let heist = try HeistPlan("searchFlow") {
        try SearchScreen.search("milk")
    }
    let searchDefinition = try #require(heist.definitions.first?.definitions.first)

    #expect(searchDefinition.body == [
        .action(ActionStep(
            command: .typeText(
                reference: HeistReferenceName(stringLiteral: "query"),
                target: .label("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .exists(.value(HeistReferenceName(stringLiteral: "query"))),
                timeout: 1
            )))),
        .action(ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .elementsChanged([
                    .exists(.label(HeistReferenceName(stringLiteral: "query"))),
                ]),
                timeout: 5
            )))),
    ])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)
    let encodedJSON = try #require(String(data: data, encoding: .utf8))

    #expect(decoded == heist)
    #expect(encodedJSON.contains(#""kind":"label""#))
    #expect(encodedJSON.contains(#""ref":"query""#))
}

@Test
func actionWithoutExpectationAttachesExplicitWaiver() throws {
    let heist = try HeistPlan {
        Activate(.label("Optional"))
            .withoutExpectation("No durable semantic outcome")
    }

    #expect(try heist == HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.label("Optional")),
            expectationPolicy: .waived("No durable semantic outcome"))),
    ]))
}

@Test
    func heistLintForwardsToPlanLint() throws {
    let heist = try HeistPlan {
        Activate(.label("Save"))
    }

    #expect(heist.lint(.strictTest).map(\.message) == ["Semantic action has no expectation"])
}

@Test
func spatialGestureVerbsBuildExplicitEscapeHatches() throws {
    let heist = try HeistPlan {
        oneFingerTap(ScreenPoint(x: 12, y: 34))
        oneFingerTap(.label("Handle"), at: UnitPoint(x: 0.25, y: 0.75))
        drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 200, y: 40))
        drag(from: ScreenPoint(x: 1, y: 2), to: ScreenPoint(x: 3, y: 4))
    }

    #expect(heist.body == [
        .action(ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 12, y: 34)))))),
        .action(ActionStep(command: .oneFingerTap(TapTarget(selection: .elementUnitPoint(
            .predicate(.label("Handle")),
            UnitPoint(x: 0.25, y: 0.75)
        ))))),
        .action(ActionStep(command: .drag(DragTarget(
            start: .elementUnitPoint(.predicate(.label("Slider")), UnitPoint(x: 0.8, y: 0.5)),
            end: ScreenPoint(x: 200, y: 40)
        )))),
        .action(ActionStep(command: .drag(DragTarget(
            start: .coordinate(ScreenPoint(x: 1, y: 2)),
            end: ScreenPoint(x: 3, y: 4)
        )))),
    ])
}

@Test
func actionExpectationPreservesDefaultAndExplicitAuthorship() {
    #expect(
        ActionExpectation(predicate: .exists(.label("Saved"))).timeout
            == .sessionDefault
    )
    #expect(
        ActionExpectation(predicate: .screenChanged).timeout
            == .sessionDefault
    )
    #expect(
        ActionExpectation(predicate: .screenChanged, timeout: 20).timeout
            == .explicit(20)
    )
}

@Test
func screenActionsNamespaceBuildsActions() throws {
    let heist = try HeistPlan {
        ScreenActions.Dismiss()
            .expect(.screenChanged)
        ScreenActions.MagicTap()
            .withoutExpectation("Magic tap toggles process-local playback state")
    }

    #expect(heist.body == [
        .action(ActionStep(
            command: .dismiss,
            expectationPolicy: .expect(ActionExpectation(
                predicate: .screenChanged
            )))),
        .action(ActionStep(
            command: .magicTap,
            expectationPolicy: .waived("Magic tap toggles process-local playback state"))),
    ])
}

@Test
func customActionAndRotorBuildSemanticActionSteps() throws {
    let heist = try HeistPlan {
        CustomAction("Archive", on: .label("Message"))
            .expect(.elementsChanged, timeout: 1)
        Rotor("Headings", on: .label("Article"), direction: .next)
            .withoutExpectation("Navigation cursor only")
    }

    #expect(heist.body == [
        .action(ActionStep(
            command: .customAction(name: "Archive", target: .label("Message")),
            expectationPolicy: .expect(ActionExpectation(predicate: .elementsChanged, timeout: 1)))),
        .action(ActionStep(
            command: .rotor(selection: .named("Headings"), target: .label("Article"), direction: .next),
            expectationPolicy: .waived("Navigation cursor only"))),
    ])
}

@Test
func waitForBuildsWaitStep() throws {
    let heist = try HeistPlan {
        WaitFor(.exists(.label("Home")), timeout: 5)
    }

    #expect(try heist == HeistPlan(body: [
        .wait(WaitStep(predicate: .exists(.label("Home")), timeout: 5)),
    ]))
}

@Test
func `container predicates and scoped targets render canonically`() throws {
    let heist = try HeistPlan {
        WaitFor(.exists(.container(.label("Checkout"))), timeout: 2)
        WaitFor(.exists(.container(.actions(.init(.custom("Archive"))))), timeout: 1)
        Activate(.within(container: .label("Checkout"), .label("Pay")))
    }

    #expect(try heist == HeistPlan(body: [
        .wait(WaitStep(predicate: .exists(.container(.label("Checkout"))), timeout: 2)),
        .wait(WaitStep(predicate: .exists(.container(.actions(.init(.custom("Archive"))))), timeout: 1)),
        .action(ActionStep(command: .activate(.within(container: .label("Checkout"), .label("Pay"))))),
    ]))
    let canonical = try heist.canonicalSwiftDSL()
    #expect(canonical.contains(#"WaitFor(.exists(.container(.label("Checkout"))), timeout: 2)"#))
    #expect(canonical.contains(#"WaitFor(.exists(.container(.actions(.init(.custom("Archive"))))), timeout: 1)"#))
    #expect(canonical.contains(#"Activate(.within(container: .label("Checkout"), .label("Pay")))"#))
}

@Test
func singlePredicateIfElseBuildsConditionalStep() throws {
    let heist = try HeistPlan {
        If(.exists(.label("Allow"))) {
            Activate(.label("Allow"))
        }
        .else {
            Fail("not allowed")
        }
    }

    #expect(try heist == HeistPlan(body: [
        .conditional(try ConditionalStep(
            cases: [PredicateCase(
                predicate: .exists(.label("Allow")),
                body: [.action(ActionStep(command: .activate(.label("Allow"))))]
            )],
            elseBody: [.fail(FailStep(message: "not allowed"))]
        )),
    ]))
}

@Test
func multiCaseIfBuildsConditionalStep() throws {
    let heist = try HeistPlan {
        If {
            Case(.exists(.label("Home"))) {
                Warn("home")
            }

            Case(.exists(.label("Login"))) {
                Warn("login")
            }

            Else {
                Fail("unknown")
            }
        }
    }

    #expect(try heist == HeistPlan(body: [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(predicate: .exists(.label("Home")), body: [.warn(WarnStep(message: "home"))]),
                PredicateCase(predicate: .exists(.label("Login")), body: [.warn(WarnStep(message: "login"))]),
            ],
            elseBody: [.fail(FailStep(message: "unknown"))]
        )),
    ]))
}

@Test
func waitForElseBuildsWaitStepWithElseBody() throws {
    let heist = try HeistPlan {
        WaitFor(.exists(.label("Home")), timeout: 8)
            .else {
                Fail("no known result")
            }
    }

    #expect(try heist == HeistPlan(body: [
        .wait(WaitStep(
            predicate: .exists(.label("Home")),
            timeout: 8,
            elseBody: [.fail(FailStep(message: "no known result"))]
        )),
    ]))
}

@Test
func canonicalProductDemoCompilesAsAccessibilityContractProgram() throws {
    let heist = try HeistPlan("searchFlow") {
        TypeText("milk", into: .label("Search"))
            .expect(.exists(.element(.label("Search"), .value("milk"))), timeout: 2)

        Activate(.label("Search"))
            .expect(.screenChanged, timeout: 5)

        WaitFor(.exists(.label("Results")), timeout: 5)
            .else {
                Fail("Search did not settle")
            }
    }

    #expect(heist.name == "searchFlow")
    #expect(heist.body.count == 3)
    #expect(heist.lint(.strictTest).isEmpty)
}

@Test
func warnAndFailBuildTheirStepTypes() throws {
    let heist = try HeistPlan {
        Warn("Optional onboarding was skipped")
        Fail("Unexpected login state")
    }

    #expect(try heist == HeistPlan(body: [
        .warn(WarnStep(message: "Optional onboarding was skipped")),
        .fail(FailStep(message: "Unexpected login state")),
    ]))
}

@Test
func helperFunctionsFlattenIntoParentPlan() throws {
    let heist = try HeistPlan {
        try loginFlow(email: "alex@example.com", password: "secret")
        Activate(.label("Checkout"))
    }

    #expect(heist.body == [
        .action(ActionStep(command: .typeText(text: "alex@example.com", target: .identifier("email")))),
        .action(ActionStep(command: .typeText(text: "secret", target: .identifier("password")))),
        .action(ActionStep(
            command: .activate(.label("Sign In")),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Home")), timeout: 5)))),
        .action(ActionStep(command: .activate(.label("Checkout")))),
    ])
}

@Test
func stringForEachBuildsRuntimeStringLoop() throws {
    let heist = try HeistPlan {
        ForEach("Milk", "Eggs") { item in
            TypeText(item, into: .label("Add item"))
                .expect(.exists(.label(item)), timeout: 2)
        }
    }

    #expect(heist.body == [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(ActionStep(
                    command: .typeText(
                        reference: HeistReferenceName(stringLiteral: "item"),
                        target: .label("Add item")
                    ),
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: .exists(.label(HeistReferenceName(stringLiteral: "item"))),
                        timeout: 2
                    )))),
            ]
        )),
    ])
}

@Test
func repeatUntilBuildsRuntimeLoop() throws {
    let heist = try HeistPlan {
        RepeatUntil(.exists(.value("2")), timeout: 3) {
            Increment(.identifier("Quantity"))
        }
    }

    #expect(heist.body == [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.value("2")),
            timeout: 3,
            body: [
                .action(ActionStep(command: .increment(.predicate(.identifier("Quantity"))))),
            ]
        )),
    ])
}

@Test
func namedHeistPlanCanDeclareSingularStringRootParameter() throws {
    let heist = try HeistPlan("Search", parameter: "query") { query in
        TypeText(query, into: .label("Search"))
            .expect(.exists(.value(query)), timeout: 2)
    }

    #expect(heist.parameter == .string(name: "query"))
    #expect(heist.body == [
        .action(ActionStep(
            command: .typeText(
                reference: HeistReferenceName(stringLiteral: "query"),
                target: .label("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .exists(.value(HeistReferenceName(stringLiteral: "query"))),
                timeout: 2
            )))),
    ])
    #expect(try heist.canonicalSwiftDSL() == """
    HeistPlan("Search", parameter: "query") { query in
        TypeText(query, into: .label("Search"))
            .expect(.exists(.value(query)), timeout: 2)
    }
    """)
}

@Test
func semanticForEachCallsBodyWithRuntimeIterationTarget() throws {
    let matching = ElementPredicate.label("Delete")
    let heist = try HeistPlan {
        ForEach(matching, limit: 20) { element in
            Activate(element)
                .expect(.missing(element), timeout: 2)
        }
    }

    guard case .forEachElement(let step) = heist.body.first else {
        Issue.record("Expected semantic ForEach step")
        return
    }

    #expect(step.matching == matching)
    #expect(step.limit == 20)
    #expect(step.parameter == "target")
    #expect(step.body == [
        .action(ActionStep(
            command: .activate(.ref("target")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .missing(.ref("target")),
                timeout: 2
            )))),
    ])
}

@Test
func encodedJSONDecodesBackToEqualPlanAndContainsNoSourceMetadata() throws {
    let heist = try HeistPlan {
        try loginFlow(email: "alex@example.com", password: "secret")

        ForEach("Milk", "Eggs") { item in
            TypeText(item, into: .label("Add item"))
                .expect(.exists(.label(item)), timeout: 2)
        }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)
    let probe = try JSONProbe(data: data)
    let encodedJSON = try #require(String(data: data, encoding: .utf8))

    #expect(decoded == heist)
    try probe.assertRecursivelyMissingKeys([
        "function",
        "call",
        "source",
        "source_map",
        "static_loop",
    ])
    for value in [
        "Login",
        "ForEach",
        "function",
        "call",
        "source",
        "source_map",
        "static_loop",
    ] {
        #expect(!encodedJSON.contains("\"\(value)\""))
    }
}

@Test
func emptyHeistRejectsPlanUsingDecodedHeistPlanContract() {
    do {
        _ = try HeistPlan {}
        Issue.record("Expected empty HeistPlan construction to throw")
    } catch let error as HeistPlanBuildError {
        #expect(error.diagnostics.map(\.path) == ["$.body"])
        #expect(
            error.diagnostics.map(\.message) == [
                "heist plan must contain a body or nested definitions; observed empty heist",
            ]
        )
    } catch {
        Issue.record("Expected HeistPlanBuildError, got \(error)")
    }
}

@HeistBuilder
private func loginFlow(email: TextInputText, password: TextInputText) throws -> HeistContent {
    TypeText(email, into: .identifier("email"))
    TypeText(password, into: .identifier("password"))

    Activate(.label("Sign In"))
        .expect(.exists(.label("Home")), timeout: 5)
}
