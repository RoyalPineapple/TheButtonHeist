import ButtonHeistDSL
import Foundation
import Testing
import TheScore

@Test
func actionConstructorBuildsOneActionStep() throws {
    let heist = try Heist {
        Activate(.label("Save"))
    }

    #expect(heist.plan == HeistPlan(body: [
        .action(try ActionStep(command: .activate(.label("Save")))),
    ]))
}

@Test
func actionExpectationAttachesWaitStep() throws {
    let heist = try Heist {
        Activate(.label("Sign In"))
            .expect(.present(.label("Home")), timeout: .seconds(5))
    }

    #expect(heist.plan == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Sign In")),
            expectation: WaitStep(predicate: .present(.label("Home")), timeout: 5)
        )),
    ]))
}

@Test
func `chained screen and state expectations compose into one action expectation`() throws {
    let forward = try Heist {
        Activate(.label("Search"))
            .expect(.changed(.screen()))
            .expect(.present(.label("Results")), timeout: .seconds(5))
    }.plan
    let reversed = try Heist {
        Activate(.label("Search"))
            .expect(.present(.label("Results")), timeout: .seconds(5))
            .expect(.changed(.screen()))
    }.plan
    let expected = HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectation: WaitStep(
                predicate: .changed(.screen(where: .present(.label("Results")))),
                timeout: 5
            )
        )),
    ])

    #expect(forward == expected)
    #expect(reversed == expected)
    #expect(forward.body.count == 1)
    #expect(forward.runtimeAdmissionFailures().isEmpty)
}

@Test
func `chained state expectations compose with all`() throws {
    let heist = try Heist {
        Activate(.label("Save"))
            .expect(.present(.label("A")))
            .expect(.present(.label("B")))
    }

    #expect(heist.plan == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Save")),
            expectation: WaitStep(predicate: .state(.all([
                .present(.label("A")),
                .present(.label("B")),
            ])))
        )),
    ]))
}

@Test
func `chained state expectation joins existing screen where clause`() throws {
    let forward = try Heist {
        Activate(.label("Search"))
            .expect(.changed(.screen(where: .present(.label("Results")))))
            .expect(.present(.label("Filter")))
    }.plan
    let reversed = try Heist {
        Activate(.label("Search"))
            .expect(.present(.label("Filter")))
            .expect(.changed(.screen(where: .present(.label("Results")))))
    }.plan

    let expected = HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Search")),
            expectation: WaitStep(predicate: .changed(.screen(where: .all([
                .present(.label("Results")),
                .present(.label("Filter")),
            ]))))
        )),
    ])

    #expect(forward == expected)
    #expect(reversed == expected)
}

@Test
func `different explicit chained expectation timeouts fail admission`() throws {
    let heist = try Heist {
        Activate(.label("Save"))
            .expect(.present(.label("A")), timeout: .seconds(1))
            .expect(.present(.label("B")), timeout: .seconds(2))
    }

    #expect(heist.plan.runtimeAdmissionFailures().contains {
        $0.contract == "action expectation composition must be supported and unambiguous"
            && $0.observed.contains("multiple explicit expectation timeouts")
    })
}

@Test
func `unsupported chained change expectations fail admission without replacement`() throws {
    let heist = try Heist {
        Activate(.label("Save"))
            .expect(.changed(.elements))
            .expect(.changed(.screen()))
    }

    #expect(heist.plan.body == [
        .action(try ActionStep(
            command: .activate(.label("Save")),
            expectation: WaitStep(predicate: .changed(.elements)),
            expectationValidationFailure: "unsupported expectation composition: changed(elements_changed) + changed(screen_changed)"
        )),
    ])
    #expect(heist.plan.runtimeAdmissionFailures().contains {
        $0.contract == "action expectation composition must be supported and unambiguous"
            && $0.observed.contains("unsupported expectation composition")
    })
}

@Test
func `string heist search flow preserves query ref in composed post activation expectation JSON`() throws {
    enum SearchScreen {
        static let search = HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.present(.value(query)), timeout: .seconds(1))

            Activate(.label("Search"))
                .expect(.changed(.screen()))
                .expect(.present(.label(query)), timeout: .seconds(5))
        }
    }

    let heist = try Heist("searchFlow") {
        try SearchScreen.search("milk")
    }
    let searchDefinition = try #require(heist.plan.definitions.first?.definitions.first)

    #expect(searchDefinition.body == [
        .action(try ActionStep(
            command: .typeText(text: .ref("query"), target: .target(.label("Search"))),
            expectation: WaitStep(predicate: .present(.value(.ref("query"))), timeout: 1)
        )),
        .action(try ActionStep(
            command: .activate(.target(.label("Search"))),
            expectation: WaitStep(
                predicate: .changed(.screen(where: .present(.label(.ref("query"))))),
                timeout: 5
            )
        )),
    ])
    #expect(heist.plan.runtimeAdmissionFailures().isEmpty)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist.plan)
    let json = String(data: data, encoding: .utf8)!
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

    #expect(decoded == heist.plan)
    #expect(json.contains(#""label_ref":"query""#))
}

@Test
func actionWithoutExpectationAttachesExplicitWaiver() throws {
    let heist = try Heist {
        Activate(.label("Optional"))
            .withoutExpectation("No durable semantic outcome")
    }

    #expect(heist.plan == HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.label("Optional")),
            expectationWaiver: "No durable semantic outcome"
        )),
    ]))
}

@Test
    func heistLintForwardsToPlanLint() throws {
    let heist = try Heist {
        Activate(.label("Save"))
    }

    #expect(heist.lint(.strictTest).map(\.message) == ["Semantic action has no expectation"])
}

@Test
func mechanicalAndViewportNamespacesBuildExplicitEscapeHatches() throws {
    let heist = try Heist {
        Mechanical.Tap(x: 12, y: 34)
        Mechanical.Drag(from: ScreenPoint(x: 1, y: 2), to: ScreenPoint(x: 3, y: 4))
        Viewport.Scroll(.down)
        Viewport.ScrollToEdge(.bottom)
        Viewport.ScrollToVisible(.label("Checkout"))
    }

    #expect(heist.plan.body == [
        .action(try ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 12, y: 34)))))),
        .action(try ActionStep(command: .drag(DragTarget(
            start: .coordinate(ScreenPoint(x: 1, y: 2)),
            end: ScreenPoint(x: 3, y: 4)
        )))),
        .action(try ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
        .action(try ActionStep(command: .scrollToEdge(ScrollToEdgeTarget(edge: .bottom)))),
        .action(try ActionStep(command: .scrollToVisible(ScrollToVisibleTarget(elementTarget: .label("Checkout"))))),
    ])
}

@Test
func customActionAndRotorBuildSemanticActionSteps() throws {
    let heist = try Heist {
        CustomAction("Archive", on: .label("Message"))
            .expect(.changed(.elements), timeout: .seconds(1))
        Rotor("Headings", on: .label("Article"), direction: .next)
            .withoutExpectation("Navigation cursor only")
    }

    #expect(heist.plan.body == [
        .action(try ActionStep(
            command: .performCustomAction(CustomActionTarget(
                elementTarget: .label("Message"),
                actionName: "Archive"
            )),
            expectation: WaitStep(predicate: .changed(.elements), timeout: 1)
        )),
        .action(try ActionStep(
            command: .rotor(RotorTarget(
                elementTarget: .label("Article"),
                selection: .named("Headings"),
                direction: .next
            )),
            expectationWaiver: "Navigation cursor only"
        )),
    ])
}

@Test
func waitForBuildsWaitStep() throws {
    let heist = try Heist {
        WaitFor(.present(.label("Home")), timeout: .seconds(5))
    }

    #expect(heist.plan == HeistPlan(body: [
        .wait(WaitStep(predicate: .present(.label("Home")), timeout: 5)),
    ]))
}

@Test
func singleIfBuildsConditionalStep() throws {
    let heist = try Heist {
        If(.present(.label("Allow"))) {
            Activate(.label("Allow"))
        }
    }

    #expect(heist.plan == HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .present(.label("Allow")),
                body: [.action(try ActionStep(command: .activate(.label("Allow"))))]
            ),
        ])),
    ]))
}

@Test
func multiCaseIfBuildsConditionalStep() throws {
    let heist = try Heist {
        If {
            Case(.present(.label("Home"))) {
                Warn("home")
            }

            Case(.present(.label("Login"))) {
                Warn("login")
            }

            Else {
                Fail("unknown")
            }
        }
    }

    #expect(heist.plan == HeistPlan(body: [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(predicate: .present(.label("Home")), body: [.warn(WarnStep(message: "home"))]),
                PredicateCase(predicate: .present(.label("Login")), body: [.warn(WarnStep(message: "login"))]),
            ],
            elseBody: [.fail(FailStep(message: "unknown"))]
        )),
    ]))
}

@Test
func multiCaseWaitForBuildsWaitForCasesStep() throws {
    let heist = try Heist {
        WaitFor(timeout: .seconds(8)) {
            Case(.present(.label("Home"))) {
                Warn("logged in")
            }

            Case(.present(.label("Invalid password"))) {
                Fail("invalid password")
            }

            Else {
                Fail("no known result")
            }
        }
    }

    #expect(heist.plan == HeistPlan(body: [
        .waitForCases(try WaitForCasesStep(
            timeout: 8,
            cases: [
                PredicateCase(predicate: .present(.label("Home")), body: [.warn(WarnStep(message: "logged in"))]),
                PredicateCase(predicate: .present(.label("Invalid password")), body: [.fail(FailStep(message: "invalid password"))]),
            ],
            elseBody: [.fail(FailStep(message: "no known result"))]
        )),
    ]))
}

@Test
func canonicalProductDemoCompilesAsAccessibilityContractProgram() throws {
    let heist = try Heist("searchFlow") {
        TypeText("milk", into: .label("Search"))
            .expect(.present(ElementPredicate.element(label: "Search", value: "milk")), timeout: .seconds(2))

        Activate(.label("Search"))
            .expect(.changed(.screen()), timeout: .seconds(5))

        WaitFor(timeout: .seconds(5)) {
            Case(.present(.label("Results"))) {
                Warn("Search results loaded")
            }

            Case(.present(.label("No Results"))) {
                Fail("Expected search results")
            }

            Else {
                Fail("Search did not settle")
            }
        }
    }

    #expect(heist.plan.name == "searchFlow")
    #expect(heist.plan.body.count == 3)
    #expect(heist.plan.runtimeAdmissionFailures().isEmpty)
    #expect(heist.lint(.strictTest).isEmpty)
}

@Test
func warnAndFailBuildTheirStepTypes() throws {
    let heist = try Heist {
        Warn("Optional onboarding was skipped")
        Fail("Unexpected login state")
    }

    #expect(heist.plan == HeistPlan(body: [
        .warn(WarnStep(message: "Optional onboarding was skipped")),
        .fail(FailStep(message: "Unexpected login state")),
    ]))
}

@Test
func helperFunctionsFlattenIntoParentPlan() throws {
    let heist = try Heist {
        try loginFlow(email: "alex@example.com", password: "secret")
        Activate(.label("Checkout"))
    }

    #expect(heist.plan.body == [
        .action(try ActionStep(command: .typeText(TypeTextTarget(text: "alex@example.com", elementTarget: .identifier("email"))))),
        .action(try ActionStep(command: .typeText(TypeTextTarget(text: "secret", elementTarget: .identifier("password"))))),
        .action(try ActionStep(
            command: .activate(.label("Sign In")),
            expectation: WaitStep(predicate: .present(.label("Home")), timeout: 5)
        )),
        .action(try ActionStep(command: .activate(.label("Checkout")))),
    ])
}

@Test
func heistDefinitionsCompileToInvocationsWithLocalDefinitions() throws {
    enum LibraryScreen {
        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
            Activate(.label("Add to Cart"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }
    }

    let heist = try Heist("purchaseFlow") {
        try LibraryScreen.addToCart("Milk")
        try LibraryScreen.addToCart("Bread")
    }

    #expect(heist.plan.name == "purchaseFlow")
    #expect(heist.plan.body == [
        .invoke(HeistInvocationStep(
            path: ["LibraryScreen", "addToCart"],
            argument: .strings([.literal("Milk")])
        )),
        .invoke(HeistInvocationStep(
            path: ["LibraryScreen", "addToCart"],
            argument: .strings([.literal("Bread")])
        )),
    ])
    #expect(heist.plan.definitions == [
        HeistPlan(name: "LibraryScreen", definitions: [
            HeistPlan(
                name: "addToCart",
                parameter: .strings(name: "item"),
                body: [
                    .action(try ActionStep(command: .activate(.label(.ref("item"))))),
                    .action(try ActionStep(
                        command: .activate(.target(.label("Add to Cart"))),
                        expectation: WaitStep(predicate: .present(.label(.ref("item"))), timeout: 2)
                    )),
                ]
            ),
        ], body: []),
    ])
}

@Test
func heistDefinitionsPreserveConflictingDuplicatesForAdmission() throws {
    let first = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
        Activate(.label(item))
    }
    let second = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { _ in
        Activate(.label("Add to Cart"))
    }

    let heist = try Heist {
        try first("Milk")
        try second("Bread")
    }

    let namespace = try #require(heist.plan.definitions.first)
    #expect(namespace.definitions.count == 2)
    #expect(heist.plan.runtimeAdmissionFailures().contains {
        $0.contract.contains("duplicate heist definition names")
    })
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

    let heist = try Heist {
        try LibraryScreen.addToCart("Milk")
    }

    #expect(heist.plan.runtimeAdmissionFailures().isEmpty)
    #expect(heist.plan.definitions == [
        HeistPlan(name: "LibraryScreen", definitions: [
            HeistPlan(
                name: "addToCart",
                parameter: .strings(name: "item"),
                definitions: [
                    HeistPlan(name: "AddButton", definitions: [
                        HeistPlan(
                            name: "tap",
                            body: [
                                .action(try ActionStep(command: .activate(.target(.label("Add to Cart"))))),
                            ]
                        ),
                    ], body: []),
                ],
                body: [
                    .action(try ActionStep(command: .activate(.label(.ref("item"))))),
                    .invoke(HeistInvocationStep(path: ["AddButton", "tap"])),
                ]
            ),
        ], body: []),
    ])
}

@Test
func rawHeistPlanContentCarriesDefinitions() throws {
    let rawPlan = HeistPlan(definitions: [
        HeistPlan(name: "setup", body: [
            .action(try ActionStep(command: .activate(.target(.label("Setup"))))),
        ]),
    ], body: [
        .invoke(HeistInvocationStep(path: ["setup"])),
    ])

    let heist = try Heist {
        rawPlan
    }

    #expect(heist.plan.body == rawPlan.body)
    #expect(heist.plan.definitions == rawPlan.definitions)
    #expect(heist.plan.runtimeAdmissionFailures().isEmpty)
}

@Test
func heistDefinitionsCanBeInvokedFromForEachBodies() throws {
    enum LibraryScreen {
        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
        }
    }
    enum CartScreen {
        static let deleteItem = HeistDef<ElementTarget>("CartScreen.deleteItem", parameter: "target") { target in
            Activate(target)
                .expect(.absent(target), timeout: .seconds(2))
        }
    }

    let heist = try Heist {
        try ForEach(["Milk", "Bread"]) { item in
            try LibraryScreen.addToCart(item)
        }

        try ForEach(.matching(.label("Delete")), limit: 20) { target in
            try CartScreen.deleteItem(target)
        }
    }

    #expect(heist.plan.body == [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Bread"],
            parameter: "item",
            body: [
                .invoke(HeistInvocationStep(
                    path: ["LibraryScreen", "addToCart"],
                    argument: .strings([.ref("item")])
                )),
            ]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 20,
            parameter: "target",
            body: [
                .invoke(HeistInvocationStep(
                    path: ["CartScreen", "deleteItem"],
                    argument: .elementTargets([.ref("target")])
                )),
            ]
        )),
    ])
    #expect(heist.plan.runtimeAdmissionFailures().isEmpty)
}

@Test
func stringForEachBuildsRuntimeStringLoop() throws {
    let heist = try Heist {
        try ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label("Add item"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }
    }

    #expect(heist.plan.body == [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .typeText(text: .ref("item"), target: .target(.label("Add item"))),
                    expectation: WaitStep(
                        predicate: .present(.label(.ref("item"))),
                        timeout: 2
                    )
                )),
            ]
        )),
    ])
}

@Test
func semanticForEachCallsBodyWithRuntimeIterationTarget() throws {
    let matching = ElementPredicate.label("Delete")
    let heist = try Heist {
        try ForEach(.matching(matching), limit: 20) { element in
            Activate(element)
                .expect(.absent(element), timeout: .seconds(2))
        }
    }

    guard case .forEachElement(let step) = heist.plan.body.first else {
        Issue.record("Expected semantic ForEach step")
        return
    }

    #expect(step.matching == matching)
    #expect(step.limit == 20)
    #expect(step.parameter == "target")
    #expect(step.body == [
        .action(try ActionStep(
            command: .activate(.ref("target")),
            expectation: WaitStep(
                predicate: .absent(.ref("target")),
                timeout: 2
            )
        )),
    ])
}

@Test
func encodedJSONDecodesBackToEqualPlanAndContainsNoSourceMetadata() throws {
    let heist = try Heist {
        try loginFlow(email: "alex@example.com", password: "secret")

        try ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label("Add item"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist.plan)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)
    let json = String(data: data, encoding: .utf8)!

    #expect(decoded == heist.plan)
    #expect(!json.contains("Login"))
    #expect(!json.contains("ForEach"))
    #expect(!json.contains("function"))
    #expect(!json.contains("call"))
    #expect(!json.contains("source"))
    #expect(!json.contains("source_map"))
    #expect(!json.contains("static_loop"))
}

@Test
func runHeistHelperPassesPlanToExecutor() async throws {
    let heist = try Heist {
        Activate(.label("Save"))
    }

    let executedPlan = try await runHeist(heist) { plan in
        plan
    }

    #expect(executedPlan == heist.plan)
}

@Test
func emptyHeistRejectsPlanUsingDecodedHeistPlanContract() {
    do {
        _ = try Heist {}
        Issue.record("Expected empty Heist construction to throw")
    } catch DecodingError.dataCorrupted(let context) {
        #expect(context.codingPath.map(\.stringValue) == ["body"])
        #expect(context.debugDescription == "HeistPlan requires a non-empty body or definitions")
    } catch {
        Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
    }
}

private func loginFlow(email: String, password: String) throws -> some HeistContent {
    try Heist {
        TypeText(email, into: .identifier("email"))
        TypeText(password, into: .identifier("password"))

        Activate(.label("Sign In"))
            .expect(.present(.label("Home")), timeout: .seconds(5))
    }
}
