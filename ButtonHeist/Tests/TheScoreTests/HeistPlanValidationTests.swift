import Foundation
import Testing
@testable import TheScore

@Test
func actionStepExpectationWaiverRoundTrips() throws {
    let step = try ActionStep(
        command: .activate(.predicate(.label("Save"))),
        expectationWaiver: "No durable semantic outcome"
    )

    let data = try JSONEncoder().encode(step)
    let object = try JSONSerialization.jsonObject(with: data)
    let json = try #require(object as? [String: Any])
    let decoded = try JSONDecoder().decode(ActionStep.self, from: data)

    #expect(json["without_expectation"] as? String == "No durable semantic outcome")
    #expect(decoded == step)
}

@Test
func actionStepRejectsExpectationAndWaiverTogether() {
    let json = """
    {
      "command": {
        "type": "activate",
        "payload": {"label": "Save"}
      },
      "expectation": {
        "predicate": {"type": "present", "element": {"label": "Done"}},
        "timeout": 1
      },
      "without_expectation": "not needed"
    }
    """

    do {
        _ = try JSONDecoder().decode(ActionStep.self, from: Data(json.utf8))
        Issue.record("Expected action step with expectation and waiver to fail")
    } catch {
        #expect("\(error)".contains("ambiguousExpectationContract"))
    }
}

@Test
func strictValidationRequiresSemanticActionExpectation() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    let findings = plan.lint(.strictTest)

    #expect(findings == [
        HeistPlanLintFinding(
            severity: .error,
            path: "$.body[0].action",
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        ),
    ])
}

@Test
func `composition quality allows explicit expectation waiver`() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationWaiver: "No durable semantic outcome"
        )),
    ])

    #expect(plan.lint(.compositionQuality).isEmpty)
    #expect(plan.lint(.strictTest).isEmpty)
}

@Test
func lintFlagsMechanicalCommandsAndViewportSetup() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))))),
        .action(try ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectation: WaitStep(predicate: .state(.present(.label("Done"))), timeout: 1)
        )),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages.contains("Mechanical command appears in strict semantic-test mode"))
    #expect(messages.contains("Viewport command appears in strict semantic-test mode"))
    #expect(messages.contains("Pre-action viewport movement immediately precedes a semantic action"))
}

@Test
func lintReportsTypeTextWithoutTarget() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(command: .typeText(TypeTextTarget(text: "milk")))),
    ])

    let findings = plan.lint(.compositionQuality)

    #expect(findings == [
        HeistPlanLintFinding(
            severity: .warning,
            path: "$.body[0].action",
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        ),
    ])
}

@Test
func lintReportsEmptyBranches() throws {
    let plan = HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), body: []),
        ])),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages == ["Branch has no steps"])
    #expect(plan.lint(.strictTest).map(\.path) == ["$.body[0].conditional.cases[0]"])
}

@Test
func runtimeAdmissionRejectsInvalidLoopParameters() throws {
    let invalidParameters = [
        "",
        " ",
        "target-name",
        "target name",
        "class",
        "../target",
        "target\nname",
        "target\0name",
    ]

    for parameter in invalidParameters {
        let plan = HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: parameter,
                body: [.warn(WarnStep(message: "body"))]
            )),
        ])

        let failures = plan.runtimeAdmissionFailures()

        #expect(failures.contains { $0.path == "$.body[0].for_each_element.parameter" })
        #expect(failures.contains { $0.contract.contains("Swift-style identifier") })
    }
}

@Test
func runtimeAdmissionRejectsInvalidRefs() throws {
    let tooLong = String(repeating: "a", count: HeistPlanRuntimeAdmissionLimits.standard.maxParameterBytes + 1)
    let cases: [(String, HeistPlan, String)] = [
        (
            "empty target ref",
            HeistPlan(body: [.action(try ActionStep(command: .activate(.ref(""))))]),
            "target_ref"
        ),
        (
            "whitespace target ref",
            HeistPlan(body: [.action(try ActionStep(command: .activate(.ref(" "))))]),
            "target_ref"
        ),
        (
            "unknown target ref",
            HeistPlan(body: [.action(try ActionStep(command: .activate(.ref("target"))))]),
            "target_ref must resolve"
        ),
        (
            "empty text ref",
            HeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref(""),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "whitespace text ref",
            HeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref(" "),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "unknown text ref",
            HeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref("item"),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref must resolve"
        ),
        (
            "long target ref",
            HeistPlan(body: [.action(try ActionStep(command: .activate(.ref(tooLong))))]),
            "max parameter/ref length"
        ),
    ]

    for (label, plan, expected) in cases {
        let failures = plan.runtimeAdmissionFailures()
        #expect(failures.contains { $0.contract.contains(expected) }, "\(label): \(failures)")
    }
}

@Test
func runtimeAdmissionRejectsRefsOutsideTheirLoopScope() throws {
    let plan = HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["Milk"],
            parameter: "item",
            body: [.warn(WarnStep(message: "inside string loop"))]
        )),
        .action(try ActionStep(command: .typeText(
            text: .ref("item"),
            target: .target(.predicate(.label("Search")))
        ))),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 1,
            parameter: "target",
            body: [.warn(WarnStep(message: "inside element loop"))]
        )),
        .action(try ActionStep(command: .activate(.ref("target")))),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains {
        $0.path == "$.body[1].action.command.payload.text"
            && $0.contract == "text_ref must resolve in the current heist scope"
    })
    #expect(failures.contains {
        $0.path == "$.body[3].action.command.payload.target"
            && $0.contract == "target_ref must resolve in the current heist scope"
    })
}

@Test
func runtimeAdmissionRejectsStringRefThatLowersToInvalidCommandPayload() throws {
    let plan = HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: [""],
            parameter: "item",
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("item"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        )),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text must be non-empty") })
}

@Test
func runtimeAdmissionRejectsEmptySetPasteboardPayload() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "")))),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains {
        $0.path == "$.body[0].action.command.payload.text"
            && $0.contract == "set_pasteboard text must be non-empty"
    })
}

@Test
func runtimeAdmissionEnforcesBounds() throws {
    let limits = HeistPlanRuntimeAdmissionLimits(
        maxTotalSteps: 2,
        maxNestedStepDepth: 2,
        maxPredicateDepth: 2,
        maxAllPredicateChildren: 1,
        maxForEachStringValues: 1,
        maxForEachElementLimit: 1,
        maxStringBytes: 5,
        maxTotalStringBytes: 10,
        maxParameterBytes: 4
    )
    let deepPredicate = AccessibilityPredicateExpr.state(.all([
        .all([
            .present(ElementPredicateTemplate(label: .literal("Nested"))),
        ]),
        .present(ElementPredicateTemplate(label: .literal("Sibling"))),
    ]))
    let plan = HeistPlan(body: [
        .wait(WaitStep(predicate: deepPredicate, timeout: 0)),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 2,
            parameter: "target",
            body: [.warn(WarnStep(message: "Nested body"))]
        )),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [.warn(WarnStep(message: "body"))]
        )),
    ])

    let contracts = plan.runtimeAdmissionFailures(limits: limits).map(\.contract)

    #expect(contracts.contains("max total heist steps"))
    #expect(contracts.contains("max predicate depth"))
    #expect(contracts.contains("max .all child count"))
    #expect(contracts.contains("max for_each_element limit"))
    #expect(contracts.contains("max for_each_string values"))
    #expect(contracts.contains("max string length"))
    #expect(contracts.contains("max total string bytes"))
    #expect(contracts.contains("max parameter/ref length"))
}

@Test
func runtimeAdmissionRejectsNestedCollectionLoops() throws {
    let nested = try ForEachStringStep(
        values: ["Milk"],
        parameter: "item",
        body: [.warn(WarnStep(message: "nested"))]
    )
    let cases: [(HeistPlan, String)] = [
        (HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(predicate: .state(.present(.label("Home"))), body: [.forEachString(nested)]),
            ])),
        ]), "$.body[0].conditional.cases[0].body[0].for_each_string"),
        (HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [PredicateCase(predicate: .state(.present(.label("Home"))), body: [.forEachString(nested)])]
            )),
        ]), "$.body[0].wait_for_cases.cases[0].body[0].for_each_string"),
        (HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: "target",
                body: [.forEachString(nested)]
            )),
        ]), "$.body[0].for_each_element.body[0].for_each_string"),
    ]

    for (plan, path) in cases {
        let failures = plan.runtimeAdmissionFailures()
        #expect(failures.contains {
            $0.path == path && $0.contract == "collection ForEach steps are top-level only"
        }, "\(path): \(failures)")
    }
}

@Test
func runtimeAdmissionRejectsInvalidHeistDefinitionsAndInvocations() throws {
    let definition = HeistPlan(
        name: "addToCart",
        parameter: .strings(name: "item"),
        body: [.action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .ref("item"))))))]
    )
    let cases: [(HeistPlan, String)] = [
        (
            HeistPlan(definitions: [HeistPlan(name: nil, body: [.warn(WarnStep(message: "x"))])], body: [
                .warn(WarnStep(message: "body")),
            ]),
            "heist definitions must have a non-empty name"
        ),
        (
            HeistPlan(definitions: [
                HeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "a"))]),
                HeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "b"))]),
            ], body: [.warn(WarnStep(message: "body"))]),
            "duplicate heist definition names are not allowed"
        ),
        (
            HeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(
                    path: ["missing"],
                    argument: .strings([.literal("Milk")])
                )),
            ]),
            "heist run path must resolve"
        ),
        (
            HeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(path: ["addToCart"], argument: .none)),
            ]),
            "heist run argument type must match"
        ),
        (
            HeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(
                    path: ["addToCart"],
                    argument: .strings([.literal("Milk"), .literal("Bread")])
                )),
            ]),
            "heist run argument must bind"
        ),
        (
            HeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(path: [], argument: .none)),
            ]),
            "heist run path must not be empty"
        ),
    ]

    for (plan, expectedContract) in cases {
        #expect(plan.runtimeAdmissionFailures().contains {
            $0.contract.contains(expectedContract)
        }, "\(expectedContract): \(plan.runtimeAdmissionFailures())")
    }
}

@Test
func runtimeAdmissionRejectsDefinitionSelfInvocationOutsideLocalScope() throws {
    let plan = HeistPlan(definitions: [
        HeistPlan(name: "repeat", body: [
            .invoke(HeistInvocationStep(path: ["repeat"])),
        ]),
    ], body: [
        .invoke(HeistInvocationStep(path: ["repeat"])),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains {
        $0.contract == "heist run path must resolve to a local capability"
    })
}

@Test
func runtimeAdmissionEnforcesSingularElementTargetArgument() throws {
    // An element-target capability is singular: a predicate for exactly one
    // element. Passing more than one target fails admission (the argument does
    // not bind), while exactly one is admissible.
    let definition = HeistPlan(
        name: "deleteItem",
        parameter: .elementTargets(name: "target"),
        body: [.action(try ActionStep(command: .activate(.ref("target"))))]
    )

    let twoTargets = HeistPlan(definitions: [definition], body: [
        .invoke(HeistInvocationStep(
            path: ["deleteItem"],
            argument: .elementTargets([.target(.label("Row 1")), .target(.label("Row 2"))])
        )),
    ])
    #expect(twoTargets.runtimeAdmissionFailures().contains {
        $0.contract == "heist run argument must bind to the target parameter"
            && $0.observed.contains("requires exactly one value")
    }, "\(twoTargets.runtimeAdmissionFailures())")

    let oneTarget = HeistPlan(definitions: [definition], body: [
        .invoke(HeistInvocationStep(
            path: ["deleteItem"],
            argument: .elementTargets([.target(.label("Row 1"))])
        )),
    ])
    #expect(oneTarget.runtimeAdmissionFailures().isEmpty, "\(oneTarget.runtimeAdmissionFailures())")
}

@Test
func runtimeAdmissionRejectsParameterizedEntryButAcceptsScratchRootCaller() throws {
    // The entry/root heist must be parameterless. Running a parameterized
    // capability standalone goes through a scratch root that calls RunHeist
    // with an explicit argument.
    let parameterizedRoot = HeistPlan(
        name: "search",
        parameter: .strings(name: "query"),
        body: [.action(try ActionStep(command: .typeText(
            text: .ref("query"),
            target: .target(.predicate(.label("Search")))
        )))]
    )
    #expect(parameterizedRoot.runtimeAdmissionFailures().contains {
        $0.contract == "entry heist must be parameterless"
    }, "\(parameterizedRoot.runtimeAdmissionFailures())")

    let scratchRoot = HeistPlan(
        definitions: [
            HeistPlan(name: "search", parameter: .strings(name: "query"), body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]),
        ],
        body: [.invoke(HeistInvocationStep(path: ["search"], argument: .strings([.literal("Milk")])))]
    )
    #expect(scratchRoot.runtimeAdmissionFailures().isEmpty, "\(scratchRoot.runtimeAdmissionFailures())")
}

@Test
func runtimeAdmissionUsesInvokedDefinitionScopeForHelperDependencies() throws {
    let plan = HeistPlan(definitions: [
        HeistPlan(
            name: "addToCart",
            parameter: .strings(name: "item"),
            definitions: [
                HeistPlan(name: "tapAddButton", body: [
                    .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .literal("Add to Cart")))))),
                ]),
            ],
            body: [
                .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .ref("item")))))),
                .invoke(HeistInvocationStep(path: ["tapAddButton"])),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(
            path: ["addToCart"],
            argument: .strings([.literal("Milk")])
        )),
    ])

    #expect(plan.runtimeAdmissionFailures().isEmpty)
}

@Test
func runtimeAdmissionAllowsSameLeafDefinitionNamesInDifferentScopes() throws {
    let plan = HeistPlan(definitions: [
        HeistPlan(
            name: "setup",
            definitions: [
                HeistPlan(name: "setup", body: [
                    .warn(WarnStep(message: "Nested setup")),
                ]),
            ],
            body: [
                .invoke(HeistInvocationStep(path: ["setup"])),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(path: ["setup"])),
    ])

    #expect(plan.runtimeAdmissionFailures().isEmpty)
}

@Test
func runtimeAdmissionValidatesInvokedBodiesWithBoundArguments() throws {
    let plan = HeistPlan(definitions: [
        HeistPlan(
            name: "typeSearch",
            parameter: .strings(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(
            path: ["typeSearch"],
            argument: .strings([.literal("")])
        )),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text must be non-empty") })
}

@Test
func runtimeAdmissionAcceptsRepresentativeCanonicalPlan() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.target(.predicate(.label("Sign In")))),
            expectation: WaitStep(predicate: .state(.present(.label("Home"))), timeout: 5)
        )),
        .wait(WaitStep(predicate: .state(.absent(.label("Loading"))), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), body: [.warn(WarnStep(message: "home"))]),
        ])),
        .waitForCases(try WaitForCasesStep(
            timeout: 2,
            cases: [
                PredicateCase(predicate: .state(.present(.label("Done"))), body: [.warn(WarnStep(message: "done"))]),
            ],
            elseBody: [.fail(FailStep(message: "timeout"))]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 20,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectation: WaitStep(predicate: .state(.absentTarget(.ref("target"))), timeout: 2)
                )),
            ]
        )),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .typeText(text: .ref("item"), target: .target(.predicate(.label("Add item")))),
                    expectation: WaitStep(
                        predicate: .state(.present(ElementPredicateTemplate(label: .ref("item")))),
                        timeout: 2
                    )
                )),
            ]
        )),
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(try ActionStep(command: .dismissKeyboard)),
        .warn(WarnStep(message: "done")),
        .fail(FailStep(message: "stop")),
    ])

    #expect(plan.runtimeAdmissionFailures().isEmpty)
}
