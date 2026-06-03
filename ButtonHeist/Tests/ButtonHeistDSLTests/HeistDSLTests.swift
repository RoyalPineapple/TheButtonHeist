import ButtonHeistDSL
import Foundation
import Testing
import TheScore

@Test
func actionConstructorBuildsOneActionStep() throws {
    let heist = try Heist {
        Activate(.label("Save"))
    }

    #expect(heist.plan == HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.label("Save")))),
    ]))
}

@Test
func actionExpectationAttachesWaitStep() throws {
    let heist = try Heist {
        Activate(.label("Sign In"))
            .expect(.present(.label("Home")), timeout: .seconds(5))
    }

    #expect(heist.plan == HeistPlan(steps: [
        .action(try ActionStep(
            command: .activate(.label("Sign In")),
            expectation: WaitStep(predicate: .present(.label("Home")), timeout: 5)
        )),
    ]))
}

@Test
func actionWithoutExpectationAttachesExplicitWaiver() throws {
    let heist = try Heist {
        Activate(.label("Optional"))
            .withoutExpectation("No durable semantic outcome")
    }

    #expect(heist.plan == HeistPlan(steps: [
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

    #expect(heist.plan.steps == [
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

    #expect(heist.plan.steps == [
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

    #expect(heist.plan == HeistPlan(steps: [
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

    #expect(heist.plan == HeistPlan(steps: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(
                predicate: .present(.label("Allow")),
                steps: [.action(try ActionStep(command: .activate(.label("Allow"))))]
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

    #expect(heist.plan == HeistPlan(steps: [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(predicate: .present(.label("Home")), steps: [.warn(WarnStep(message: "home"))]),
                PredicateCase(predicate: .present(.label("Login")), steps: [.warn(WarnStep(message: "login"))]),
            ],
            elseSteps: [.fail(FailStep(message: "unknown"))]
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

    #expect(heist.plan == HeistPlan(steps: [
        .waitForCases(try WaitForCasesStep(
            timeout: 8,
            cases: [
                PredicateCase(predicate: .present(.label("Home")), steps: [.warn(WarnStep(message: "logged in"))]),
                PredicateCase(predicate: .present(.label("Invalid password")), steps: [.fail(FailStep(message: "invalid password"))]),
            ],
            elseSteps: [.fail(FailStep(message: "no known result"))]
        )),
    ]))
}

@Test
func warnAndFailBuildTheirStepTypes() throws {
    let heist = try Heist {
        Warn("Optional onboarding was skipped")
        Fail("Unexpected login state")
    }

    #expect(heist.plan == HeistPlan(steps: [
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

    #expect(heist.plan.steps == [
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
func stringForEachBuildsRuntimeStringLoop() throws {
    let heist = try Heist {
        try ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label("Add item"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }
    }

    #expect(heist.plan.steps == [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            steps: [
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

    guard case .forEachElement(let step) = heist.plan.steps.first else {
        Issue.record("Expected semantic ForEach step")
        return
    }

    #expect(step.matching == matching)
    #expect(step.limit == 20)
    #expect(step.parameter == "target")
    #expect(step.steps == [
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
        #expect(context.codingPath.map(\.stringValue) == ["steps"])
        #expect(context.debugDescription == "HeistPlan requires at least one step")
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
