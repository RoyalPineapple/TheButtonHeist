import ButtonHeistDSL
import Foundation
import Testing
import TheScore

@Test
func actionConstructorBuildsOneActionStep() throws {
    let heist = Heist {
        Activate(.label("Save"))
    }

    #expect(heist.plan == HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.label("Save")))),
    ]))
}

@Test
func actionExpectationAttachesWaitStep() throws {
    let heist = Heist {
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
func waitForBuildsWaitStep() {
    let heist = Heist {
        WaitFor(.present(.label("Home")), timeout: .seconds(5))
    }

    #expect(heist.plan == HeistPlan(steps: [
        .wait(WaitStep(predicate: .present(.label("Home")), timeout: 5)),
    ]))
}

@Test
func singleIfBuildsConditionalStep() throws {
    let heist = Heist {
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
    let heist = Heist {
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
    let heist = Heist {
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
func warnAndFailBuildTheirStepTypes() {
    let heist = Heist {
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
    let heist = Heist {
        loginFlow(email: "alex@example.com", password: "secret")
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
func staticForEachFlattensIntoLinearSteps() throws {
    let heist = Heist {
        ForEach(["Cart", "Checkout"]) { label in
            Activate(.label(label))
        }
    }

    #expect(heist.plan.steps == [
        .action(try ActionStep(command: .activate(.label("Cart")))),
        .action(try ActionStep(command: .activate(.label("Checkout")))),
    ])
}

@Test
func encodedJSONDecodesBackToEqualPlanAndContainsNoSourceMetadata() throws {
    let heist = Heist {
        loginFlow(email: "alex@example.com", password: "secret")

        ForEach(["Cart", "Checkout"]) { label in
            Activate(.label(label))
        }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(heist.plan)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)
    let json = try #require(String(data: data, encoding: .utf8))

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
func rendererProducesCanonicalExpandedDSL() throws {
    let heist = Heist {
        Activate(.label("Sign In"))
            .expect(.changed(.screen(where: .present(.label("Home")))), timeout: .seconds(5))

        WaitFor(.absent(.label("Loading")), timeout: .seconds(10))

        If(.present(.label("Home"))) {
            Warn("home")
        } otherwise: {
            Fail("unknown")
        }

        WaitFor(timeout: .seconds(8)) {
            Case(.present(.label("Receipt"))) {
                Warn("receipt")
            }

            Else {
                Fail("missing receipt")
            }
        }

        Warn("Optional onboarding was skipped")
        Fail("Unexpected login state")
    }

    let rendered = try HeistSwiftRenderer().render(heist.plan)

    #expect(rendered == """
    Heist {
        Activate(.label("Sign In"))
            .expect(.changed(.screen(where: .present(.label("Home")))), timeout: .seconds(5))
        WaitFor(.absent(.label("Loading")), timeout: .seconds(10))
        If(.present(.label("Home"))) {
            Warn("home")
        } otherwise: {
            Fail("unknown")
        }
        WaitFor(timeout: .seconds(8)) {
            Case(.present(.label("Receipt"))) {
                Warn("receipt")
            }

            Else {
                Fail("missing receipt")
            }
        }
        Warn("Optional onboarding was skipped")
        Fail("Unexpected login state")
    }
    """)
}

@Test
func runHeistHelperPassesPlanToExecutor() async throws {
    let heist = Heist {
        Activate(.label("Save"))
    }

    let executedPlan = try await runHeist(heist) { plan in
        plan
    }

    #expect(executedPlan == heist.plan)
}

private func loginFlow(email: String, password: String) -> some HeistContent {
    Heist {
        TypeText(email, into: .identifier("email"))
        TypeText(password, into: .identifier("password"))

        Activate(.label("Sign In"))
            .expect(.present(.label("Home")), timeout: .seconds(5))
    }
}
