import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

private func runtimeValidationFailures(
    for raw: UnvalidatedHeistPlan,
    limits: HeistPlanRuntimeValidationLimits = .standard
) -> [HeistPlanValidationFailure] {
    do {
        _ = try raw.validatedForRuntime(limits: limits)
        return []
    } catch let error as HeistPlanValidationError {
        return error.failures
    } catch {
        Issue.record("Expected runtime validation error, got \(error)")
        return []
    }
}

private func validatedPlan(_ raw: UnvalidatedHeistPlan) throws -> HeistPlan {
    try raw.validatedForRuntime()
}

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
    let plan = try HeistPlan(body: [
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
    let plan = try HeistPlan(body: [
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
    let plan = try HeistPlan(body: [
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
    let plan = try HeistPlan(body: [
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
    let plan = try HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), body: []),
        ])),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages == ["Branch has no steps"])
    #expect(plan.lint(.strictTest).map(\.path) == ["$.body[0].conditional.cases[0]"])
}

@Test
func runtimeValidationRejectsInvalidLoopParameters() throws {
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
        let raw = UnvalidatedHeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: parameter,
                body: [.warn(WarnStep(message: "body"))]
            )),
        ])

        let failures = runtimeValidationFailures(for: raw)

        #expect(failures.contains { $0.path == "$.body[0].for_each_element.parameter" })
        #expect(failures.contains { $0.contract.contains("Swift-style identifier") })
    }
}

@Test
func runtimeValidationRejectsInvalidRefs() throws {
    let tooLong = String(repeating: "a", count: HeistPlanRuntimeValidationLimits.standard.maxParameterBytes + 1)
    let cases: [(String, UnvalidatedHeistPlan, String)] = [
        (
            "empty target ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .activate(.ref(""))))]),
            "target_ref"
        ),
        (
            "whitespace target ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .activate(.ref(" "))))]),
            "target_ref"
        ),
        (
            "unknown target ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .activate(.ref("target"))))]),
            "target_ref must resolve"
        ),
        (
            "empty text ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref(""),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "whitespace text ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref(" "),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "unknown text ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .typeText(
                text: .ref("item"),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref must resolve"
        ),
        (
            "long target ref",
            UnvalidatedHeistPlan(body: [.action(try ActionStep(command: .activate(.ref(tooLong))))]),
            "max parameter/ref length"
        ),
    ]

    for (label, raw, expected) in cases {
        let failures = runtimeValidationFailures(for: raw)
        #expect(failures.contains { $0.contract.contains(expected) }, "\(label): \(failures)")
    }
}

@Test
func runtimeValidationRejectsRefsOutsideTheirLoopScope() throws {
    let raw = UnvalidatedHeistPlan(body: [
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

    let failures = runtimeValidationFailures(for: raw)

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
func runtimeValidationRejectsStringRefThatLowersToInvalidCommandPayload() throws {
    let raw = UnvalidatedHeistPlan(body: [
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

    let failures = runtimeValidationFailures(for: raw)

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text must be non-empty") })
}

@Test
func runtimeValidationRejectsEmptySetPasteboardPayload() throws {
    let raw = UnvalidatedHeistPlan(body: [
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "")))),
    ])

    let failures = runtimeValidationFailures(for: raw)

    #expect(failures.contains {
        $0.path == "$.body[0].action.command.payload.text"
            && $0.contract == "set_pasteboard text must be non-empty"
    })
}

@Test
func runtimeValidationEnforcesBounds() throws {
    let limits = HeistPlanRuntimeValidationLimits(
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
    let raw = UnvalidatedHeistPlan(body: [
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

    let contracts = runtimeValidationFailures(for: raw, limits: limits).map(\.contract)

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
func runtimeValidationRejectsNestedCollectionLoops() throws {
    let nested = try ForEachStringStep(
        values: ["Milk"],
        parameter: "item",
        body: [.warn(WarnStep(message: "nested"))]
    )
    let cases: [(UnvalidatedHeistPlan, String)] = [
        (UnvalidatedHeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(predicate: .state(.present(.label("Home"))), body: [.forEachString(nested)]),
            ])),
        ]), "$.body[0].conditional.cases[0].body[0].for_each_string"),
        (UnvalidatedHeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [PredicateCase(predicate: .state(.present(.label("Home"))), body: [.forEachString(nested)])]
            )),
        ]), "$.body[0].wait_for_cases.cases[0].body[0].for_each_string"),
        (UnvalidatedHeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: "target",
                body: [.forEachString(nested)]
            )),
        ]), "$.body[0].for_each_element.body[0].for_each_string"),
    ]

    for (raw, path) in cases {
        let failures = runtimeValidationFailures(for: raw)
        #expect(failures.contains {
            $0.path == path && $0.contract == "collection ForEach steps are top-level only"
        }, "\(path): \(failures)")
    }
}

@Test
func runtimeValidationRejectsInvalidHeistDefinitionsAndInvocations() throws {
    let definition = UnvalidatedHeistPlan(
        name: "addToCart",
        parameter: .string(name: "item"),
        body: [.action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .ref("item"))))))]
    )
    let cases: [(UnvalidatedHeistPlan, String)] = [
        (
            UnvalidatedHeistPlan(definitions: [
                UnvalidatedHeistPlan(name: nil, body: [.warn(WarnStep(message: "x"))]),
            ], body: [
                .warn(WarnStep(message: "body")),
            ]),
            "heist definitions must have a non-empty name"
        ),
        (
            UnvalidatedHeistPlan(definitions: [
                UnvalidatedHeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "a"))]),
                UnvalidatedHeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "b"))]),
            ], body: [.warn(WarnStep(message: "body"))]),
            "duplicate heist definition names are not allowed"
        ),
        (
            UnvalidatedHeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(
                    path: ["missing"],
                    argument: .string(.literal("Milk"))
                )),
            ]),
            "heist run path must resolve"
        ),
        (
            UnvalidatedHeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(path: ["addToCart"], argument: .none)),
            ]),
            "heist run argument type must match"
        ),
        (
            UnvalidatedHeistPlan(definitions: [definition], body: [
                .invoke(HeistInvocationStep(path: [], argument: .none)),
            ]),
            "heist run path must not be empty"
        ),
    ]

    for (raw, expectedContract) in cases {
        let failures = runtimeValidationFailures(for: raw)
        #expect(failures.contains {
            $0.contract.contains(expectedContract)
        }, "\(expectedContract): \(failures)")
    }
}

@Test
func decodedHeistArgumentsRejectStringArrayShape() throws {
    let payloads = [
        #"{"type":"string","values":["Milk","Bread"]}"#,
        #"{"type":"string","values":["Milk"]}"#,
        #"{"type":"strings","values":["Milk"]}"#,
    ]

    for payload in payloads {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(HeistArgument.self, from: Data(payload.utf8))
        }
    }
}

@Test
func runtimeValidationRejectsDefinitionSelfInvocationOutsideLocalScope() throws {
    let recursiveName = "repeatHeist"
    let raw = UnvalidatedHeistPlan(definitions: [
        UnvalidatedHeistPlan(name: recursiveName, body: [
            .invoke(HeistInvocationStep(path: [recursiveName])),
        ]),
    ], body: [
        .invoke(HeistInvocationStep(path: [recursiveName])),
    ])

    let failures = runtimeValidationFailures(for: raw)

    #expect(failures.contains {
        $0.contract == "heist run path must resolve to a local capability"
    })
}

@Test
func runtimeValidationAcceptsSingularElementTargetCapability() throws {
    // `elementTarget` is singular by type — a predicate for exactly one element.
    // Multiple targets are unrepresentable; a capability run with one target is
    // runtime-valid.
    let definition = UnvalidatedHeistPlan(
        name: "deleteItem",
        parameter: .elementTarget(name: "target"),
        body: [.action(try ActionStep(command: .activate(.ref("target"))))]
    )
    let raw = UnvalidatedHeistPlan(definitions: [definition], body: [
        .invoke(HeistInvocationStep(
            path: ["deleteItem"],
            argument: .elementTarget(.target(.label("Row 1")))
        )),
    ])
    _ = try validatedPlan(raw)
}

@Test
func runtimeValidationAcceptsParameterizedRootAndScratchRootCaller() throws {
    let parameterizedRoot = UnvalidatedHeistPlan(
        name: "search",
        parameter: .string(name: "query"),
        body: [.action(try ActionStep(command: .typeText(
            text: .ref("query"),
            target: .target(.predicate(.label("Search")))
        )))]
    )
    _ = try validatedPlan(parameterizedRoot)

    let scratchRoot = UnvalidatedHeistPlan(
        definitions: [
            UnvalidatedHeistPlan(name: "search", parameter: .string(name: "query"), body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]),
        ],
        body: [.invoke(HeistInvocationStep(path: ["search"], argument: .string(.literal("Milk"))))]
    )
    _ = try validatedPlan(scratchRoot)
}

@Test
func runtimeValidationUsesInvokedDefinitionScopeForHelperDependencies() throws {
    let raw = UnvalidatedHeistPlan(definitions: [
        UnvalidatedHeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            definitions: [
                UnvalidatedHeistPlan(name: "tapAddButton", body: [
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
            argument: .string(.literal("Milk"))
        )),
    ])

    _ = try validatedPlan(raw)
}

@Test
func runtimeValidationAllowsSameLeafDefinitionNamesInDifferentScopes() throws {
    let raw = UnvalidatedHeistPlan(definitions: [
        UnvalidatedHeistPlan(
            name: "setup",
            definitions: [
                UnvalidatedHeistPlan(name: "setup", body: [
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

    _ = try validatedPlan(raw)
}

@Test
func runtimeValidationValidatesInvokedBodiesWithBoundArguments() throws {
    let raw = UnvalidatedHeistPlan(definitions: [
        UnvalidatedHeistPlan(
            name: "typeSearch",
            parameter: .string(name: "query"),
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
            argument: .string(.literal(""))
        )),
    ])

    let failures = runtimeValidationFailures(for: raw)

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text must be non-empty") })
}

@Test
func runtimeValidationAcceptsRepresentativeCanonicalPlan() throws {
    let plan = try HeistPlan(body: [
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

    _ = plan
}
