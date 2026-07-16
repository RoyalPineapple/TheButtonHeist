import Foundation
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
func actionConstructorBuildsOneActionStep() throws {
    let heist = try HeistPlan {
        Activate(.label("Save"))
    }

    #expect(try heist == HeistPlan(body: [
        .action(try ActionStep(command: .activate(.label("Save")))),
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
        .action(try ActionStep(command: .activate(.predicate(.element(
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
        .action(try ActionStep(
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
                .action(try ActionStep(
                    command: .increment(.label("Volume")))),
            ]
        )),
    ]))
}

@Test
func actionExpectationSupportsScopedPropertyUpdateDelta() throws {
    let heist = try HeistPlan {
        TypeText("Bruschetta", into: .identifier("Search"))
            .expect(.changed(.elements([
                .updated(.identifier("Search"), .value("Bruschetta")),
            ])))
    }

    #expect(try heist == HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(
                text: "Bruschetta",
                target: .identifier("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.elements([
                .updated(.identifier("Search"), .value(after: "Bruschetta")),
            ])), timeout: 1)))),
    ]))
}

@Test
func actionExpectationUsesCanonicalElementChangeAssertions() throws {
    let appeared = try HeistPlan {
        Activate(.label("Add Bruschetta"))
            .expect(.changed(.elements([
                .appeared(.label(.contains("Bruschetta, $9.00"))),
            ])))
    }
    let disappeared = try HeistPlan {
        Activate(.label("Remove Bruschetta"))
            .expect(.changed(.elements([
                .disappeared(.identifier("cart-row-bruschetta")),
            ])))
    }
    let updated = try HeistPlan {
        TypeText("Bruschetta", into: .identifier("Search"))
            .expect(.changed(.elements([
                .updated(.identifier("Search"), .value("Bruschetta")),
            ])))
    }

    #expect(try appeared == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Add Bruschetta")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .changed(.elements([
                    .appeared(.label(.contains("Bruschetta, $9.00"))),
                ])),
                timeout: 1
            )))),
    ]))
    #expect(try disappeared == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Remove Bruschetta")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .changed(.elements([
                    .disappeared(.identifier("cart-row-bruschetta")),
                ])),
                timeout: 1
            )))),
    ]))
    #expect(try updated == HeistPlan(body: [
        .action(try ActionStep(
            command: .typeText(
                text: "Bruschetta",
                target: .identifier("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.elements([
                .updated(.identifier("Search"), .value(after: "Bruschetta")),
            ])), timeout: 1)))),
    ]))
}

@Test
func predicateContextsUseExplicitCanonicalAssertions() throws {
    let heist = try HeistPlan {
        Activate(.label("Search"))
            .expect(.exists(.label("Results")))

        Activate(.label("Open Details"))
            .expect(.changed(.screen([.exists(.label("Details"))])))

        WaitFor(.exists(.identifier("ready")), timeout: 2)

        If(.exists(.value(.contains("Promo")))) {
            Warn("promo visible")
        }
    }

    #expect(try heist == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Results")), timeout: 1)))),
        .action(try ActionStep(
            command: .activate(.label("Open Details")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .changed(.screen([.exists(.label("Details"))])),
                timeout: 1
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
                .action(try ActionStep(command: .typeText(
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
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("target")), timeout: 1)))),
            ]
        )),
    ]))
}

@Test
func `chained screen and state expectations compose into one action expectation`() throws {
    let forward = try HeistPlan {
        Activate(.label("Search"))
            .expect(.changed(.screen()))
            .expect(.exists(.label("Results")), timeout: 5)
    }
    let reversed = try HeistPlan {
        Activate(.label("Search"))
            .expect(.exists(.label("Results")), timeout: 5)
            .expect(.changed(.screen()))
    }
    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .changed(.screen([.exists(.label("Results"))])),
                timeout: 5
            )))),
    ])

    #expect(forward == expected)
    #expect(reversed == expected)
    #expect(forward.body.count == 1)
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

@Test
func `chained state expectation joins existing screen where clause`() throws {
    let forward = try HeistPlan {
        Activate(.label("Search"))
            .expect(.changed(.screen([.exists(.label("Results"))])))
            .expect(.exists(.label("Filter")))
    }
    let reversed = try HeistPlan {
        Activate(.label("Search"))
            .expect(.exists(.label("Filter")))
            .expect(.changed(.screen([.exists(.label("Results"))])))
    }

    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen([
                .exists(.label("Results")),
                .exists(.label("Filter"))
            ])), timeout: 1)))),
    ])

    #expect(forward == expected)
    #expect(reversed == expected)
}

@Test
func `different explicit chained expectation timeouts fail validation`() throws {
    do {
        _ = try HeistPlan {
            Activate(.label("Save"))
                .expect(.changed(.screen()), timeout: 1)
                .expect(.exists(.label("B")), timeout: 2)
        }
        Issue.record("Expected HeistPlanBuildError")
    } catch let error as HeistPlanBuildError {
        let diagnostic = try #require(error.diagnostics.first)

        #expect(error.diagnostics.count == 1)
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
    let diagnostic = HeistBuildDiagnostic(
        code: .dslInvalidActionExpectation,
        phase: .dslBuild,
        path: "activate",
        message: "unsupported expectation composition: changed(elements(*)) + changed(screen(*))",
        hint: "Use one canonical predicate per expectation, or add current-tree assertions inside .changed(.screen(...))."
    )
    let step = try ActionStep(
        command: .activate(.label("Save")),
        expectationPolicy: .expect(ActionExpectation(predicate: .changed(.elements()), timeout: 1)),
        expectationValidationDiagnostics: [diagnostic]
    )
    #expect(throws: HeistPlanBuildError.self) {
        try HeistPlan {
            Activate(.label("Save"))
                .expect(.changed(.elements()))
                .expect(.changed(.screen()))
        }
    }
    #expect(try step == ActionStep(
        command: .activate(.label("Save")),
        expectationPolicy: .expect(ActionExpectation(predicate: .changed(.elements()), timeout: 1)),
        expectationValidationDiagnostics: [diagnostic]
    ))
}
@Test
func `string heist search flow preserves query ref in composed post activation expectation JSON`() throws {
    enum SearchScreen {
        static let search = HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.exists(.value(query)), timeout: 1)

            Activate(.label("Search"))
                .expect(.changed(.screen()))
                .expect(.exists(.label(query)), timeout: 5)
        }
    }

    let heist = try HeistPlan("searchFlow") {
        try SearchScreen.search("milk")
    }
    let searchDefinition = try #require(heist.definitions.first?.definitions.first)

    #expect(searchDefinition.body == [
        .action(try ActionStep(
            command: .typeText(
                reference: HeistReferenceName(stringLiteral: "query"),
                target: .label("Search")
            ),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .exists(.value(HeistReferenceName(stringLiteral: "query"))),
                timeout: 1
            )))),
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectationPolicy: .expect(ActionExpectation(
                predicate: .changed(.screen([
                    .exists(.label(HeistReferenceName(stringLiteral: "query"))),
                ])),
                timeout: 5
            )))),
    ])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)
    let encodedJSON = try EncodedJSONValue(data: data)

    #expect(decoded == heist)
    #expect(encodedJSON.containsLabelCheckReference("query"))
}

@Test
func actionWithoutExpectationAttachesExplicitWaiver() throws {
    let heist = try HeistPlan {
        Activate(.label("Optional"))
            .withoutExpectation("No durable semantic outcome")
    }

    #expect(try heist == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Optional")),
            expectationPolicy: .waived(try ActionExpectationWaiver("No durable semantic outcome")))),
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
func mechanicalNamespaceBuildsExplicitEscapeHatches() throws {
    let heist = try HeistPlan {
        Mechanical.Tap(ScreenPoint(x: 12, y: 34))
        Mechanical.Tap(.label("Handle"), at: UnitPoint(x: 0.25, y: 0.75))
        Mechanical.Drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 200, y: 40))
        Mechanical.Drag(from: ScreenPoint(x: 1, y: 2), to: ScreenPoint(x: 3, y: 4))
    }

    #expect(heist.body == [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(selection: .coordinate(ScreenPoint(x: 12, y: 34)))))),
        .action(try ActionStep(command: .mechanicalTap(TapTarget(selection: .elementUnitPoint(
            .predicate(.label("Handle")),
            UnitPoint(x: 0.25, y: 0.75)
        ))))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            start: .elementUnitPoint(.predicate(.label("Slider")), UnitPoint(x: 0.8, y: 0.5)),
            end: ScreenPoint(x: 200, y: 40)
        )))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            start: .coordinate(ScreenPoint(x: 1, y: 2)),
            end: ScreenPoint(x: 3, y: 4)
        )))),
    ])
}

@Test
func screenActionsNamespaceBuildsRegularActionContent() throws {
    let heist = try HeistPlan {
        ScreenActions.Dismiss()
            .expect(.changed(.screen()))
        ScreenActions.MagicTap()
            .withoutExpectation("Magic tap toggles process-local playback state")
    }

    #expect(heist.body == [
        .action(try ActionStep(
            command: .dismiss,
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 1)))),
        .action(try ActionStep(
            command: .magicTap,
            expectationPolicy: .waived(try ActionExpectationWaiver("Magic tap toggles process-local playback state")))),
    ])
}

@Test
func customActionAndRotorBuildSemanticActionSteps() throws {
    let heist = try HeistPlan {
        CustomAction("Archive", on: .label("Message"))
            .expect(.changed(.elements()), timeout: 1)
        Rotor("Headings", on: .label("Article"), direction: .next)
            .withoutExpectation("Navigation cursor only")
    }

    #expect(heist.body == [
        .action(try ActionStep(
            command: .customAction(name: "Archive", target: .label("Message")),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.elements()), timeout: 1)))),
        .action(try ActionStep(
            command: .rotor(selection: .named("Headings"), target: .label("Article"), direction: .next),
            expectationPolicy: .waived(try ActionExpectationWaiver("Navigation cursor only")))),
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
        .action(try ActionStep(command: .activate(.within(container: .label("Checkout"), .label("Pay"))))),
    ]))
    let canonical = try heist.canonicalSwiftDSL()
    #expect(canonical.contains(#"WaitFor(.exists(.container(.label("Checkout"))), timeout: 2)"#))
    #expect(canonical.contains(#"WaitFor(.exists(.container(.actions(.init(.custom("Archive"))))), timeout: 1)"#))
    #expect(canonical.contains(#"Activate(.within(container: .label("Checkout"), .label("Pay")))"#))
}

@Test
func singleIfBuildsConditionalStep() throws {
    let heist = try HeistPlan {
        If {
            Case(.exists(.label("Allow"))) {
                Activate(.label("Allow"))
            }
        }
    }

    #expect(try heist == HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .exists(.label("Allow")),
                body: [.action(try ActionStep(command: .activate(.label("Allow"))))]
            ),
        ])),
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
            .expect(.changed(.screen()), timeout: 5)

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
        .action(try ActionStep(command: .typeText(text: "alex@example.com", target: .identifier("email")))),
        .action(try ActionStep(command: .typeText(text: "secret", target: .identifier("password")))),
        .action(try ActionStep(
            command: .activate(.label("Sign In")),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Home")), timeout: 5)))),
        .action(try ActionStep(command: .activate(.label("Checkout")))),
    ])
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
                    .action(try ActionStep(command: .activate(
                        .label(HeistReferenceName(stringLiteral: "item"))
                    ))),
                    .action(try ActionStep(
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
                    .action(try ActionStep(
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
                    .action(try ActionStep(
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
                                .action(try ActionStep(command: .activate(.label("Add to Cart")))),
                            ]
                        ),
                    ], body: []),
                ],
                body: [
                    .action(try ActionStep(command: .activate(
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
            .action(try ActionStep(command: .activate(.label("Setup")))),
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
                    .action(try ActionStep(command: .activate(.label("Checkout")))),
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
                    .action(try ActionStep(command: .activate(.label("Checkout")))),
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
                .action(try ActionStep(
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
func repeatUntilBuildsRuntimeLoopWithElseBody() throws {
    let heist = try HeistPlan {
        RepeatUntil(.exists(.value("2")), timeout: 3) {
            Increment(.identifier("Quantity"))
        }.else {
            Fail("quantity did not reach 2")
        }
    }

    #expect(heist.body == [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.value("2")),
            timeout: 3,
            body: [
                .action(try ActionStep(command: .increment(.predicate(.identifier("Quantity"))))),
            ],
            elseBody: [
                .fail(FailStep(message: "quantity did not reach 2")),
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
        .action(try ActionStep(
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
    let matching = ElementPredicateTemplate.label("Delete")
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
        .action(try ActionStep(
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
    let encodedJSON = try EncodedJSONValue(data: data)

    #expect(decoded == heist)
    try encodedJSON.assertRecursivelyMissingKeys([
        "function",
        "call",
        "source",
        "source_map",
        "static_loop",
    ])
    try encodedJSON.assertRecursivelyMissingStringValues([
        "Login",
        "ForEach",
        "function",
        "call",
        "source",
        "source_map",
        "static_loop",
    ])
}

@Test
func emptyHeistRejectsPlanUsingDecodedHeistPlanContract() {
    do {
        _ = try HeistPlan {}
        Issue.record("Expected empty HeistPlan construction to throw")
    } catch DecodingError.dataCorrupted(let context) {
        #expect(context.codingPath.map(\.stringValue) == ["body"])
        #expect(context.debugDescription == "HeistPlan requires a non-empty body or definitions")
    } catch {
        Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
    }
}

private func loginFlow(email: TextInputText, password: TextInputText) throws -> some HeistContent {
    try HeistPlan {
        TypeText(email, into: .identifier("email"))
        TypeText(password, into: .identifier("password"))

        Activate(.label("Sign In"))
            .expect(.exists(.label("Home")), timeout: 5)
    }
}

private enum EncodedJSONValue: Decodable, Equatable {
    case object([String: EncodedJSONValue])
    case array([EncodedJSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: EncodedJSONCodingKey.self) {
            var values: [String: EncodedJSONValue] = [:]
            for key in object.allKeys {
                values[key.stringValue] = try object.decode(EncodedJSONValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        if var array = try? decoder.unkeyedContainer() {
            var values: [EncodedJSONValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(EncodedJSONValue.self))
            }
            self = .array(values)
            return
        }

        let scalar = try decoder.singleValueContainer()
        if scalar.decodeNil() {
            self = .null
        } else if let value = try? scalar.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? scalar.decode(Int.self) {
            self = .int(value)
        } else if let value = try? scalar.decode(Double.self) {
            self = .double(value)
        } else if let value = try? scalar.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: scalar,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func containsLabelCheckReference(_ reference: String) -> Bool {
        containsCheck(
            kind: "label",
            match: .object([
                "mode": .string("exact"),
                "value": .object(["ref": .string(reference)]),
            ])
        )
    }

    func assertRecursivelyMissingKeys(_ keys: [String]) throws {
        let disallowed = Set(keys)
        guard let hit = firstPath(containingKeyIn: disallowed) else { return }
        throw EncodedJSONFailure(path: hit.path, reason: "Expected key '\(hit.key)' to be absent recursively")
    }

    func assertRecursivelyMissingStringValues(_ values: [String]) throws {
        let disallowed = Set(values)
        guard let hit = firstPath(containingStringValueIn: disallowed) else { return }
        throw EncodedJSONFailure(path: hit.path, reason: "Expected string value '\(hit.value)' to be absent recursively")
    }

    private func containsCheck(kind: String, match: EncodedJSONValue) -> Bool {
        switch self {
        case .object(let object):
            if case .array(let checks)? = object["checks"],
               checks.contains(where: { check in
                   guard case .object(let checkObject) = check else { return false }
                   return checkObject["kind"] == .string(kind)
                       && checkObject["match"] == match
               }) {
                return true
            }
            return object.values.contains { $0.containsCheck(kind: kind, match: match) }

        case .array(let array):
            return array.contains { $0.containsCheck(kind: kind, match: match) }

        case .string, .int, .double, .bool, .null:
            return false
        }
    }

    private func firstPath(
        containingKeyIn disallowed: Set<String>,
        path: String = "$"
    ) -> (key: String, path: String)? {
        switch self {
        case .object(let object):
            for key in object.keys.sorted() {
                let childPath = path + Self.pathComponent(forKey: key)
                if disallowed.contains(key) {
                    return (key, childPath)
                }
                if let child = object[key],
                   let hit = child.firstPath(containingKeyIn: disallowed, path: childPath) {
                    return hit
                }
            }

        case .array(let array):
            for (index, value) in array.enumerated() {
                if let hit = value.firstPath(containingKeyIn: disallowed, path: "\(path)[\(index)]") {
                    return hit
                }
            }

        case .string, .int, .double, .bool, .null:
            break
        }
        return nil
    }

    private func firstPath(
        containingStringValueIn disallowed: Set<String>,
        path: String = "$"
    ) -> (value: String, path: String)? {
        switch self {
        case .object(let object):
            for key in object.keys.sorted() {
                let childPath = path + Self.pathComponent(forKey: key)
                if let child = object[key],
                   let hit = child.firstPath(containingStringValueIn: disallowed, path: childPath) {
                    return hit
                }
            }

        case .array(let array):
            for (index, value) in array.enumerated() {
                if let hit = value.firstPath(containingStringValueIn: disallowed, path: "\(path)[\(index)]") {
                    return hit
                }
            }

        case .string(let string):
            if disallowed.contains(string) {
                return (string, path)
            }

        case .int, .double, .bool, .null:
            break
        }
        return nil
    }

    private static func pathComponent(forKey key: String) -> String {
        guard isIdentifier(key) else {
            let escaped = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "[\"\(escaped)\"]"
        }
        return ".\(key)"
    }

    private static func isIdentifier(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isLetter else {
            return false
        }
        return key.dropFirst().allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
        }
    }
}

private struct EncodedJSONFailure: Error, CustomStringConvertible {
    let path: String
    let reason: String

    var description: String {
        "\(reason) at \(path)"
    }
}

private struct EncodedJSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
