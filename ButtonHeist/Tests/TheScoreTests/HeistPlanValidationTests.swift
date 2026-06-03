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
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    let findings = plan.validate(.strictTest)

    #expect(findings == [
        HeistPlanValidationFinding(
            severity: .error,
            path: "$.steps[0].action",
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        ),
    ])
}

@Test
func recordingQualityAllowsExplicitExpectationWaiver() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationWaiver: "No durable semantic outcome"
        )),
    ])

    #expect(plan.validate(.recordingQuality).isEmpty)
    #expect(plan.validate(.strictTest).isEmpty)
}

@Test
func validationFlagsMechanicalCommandsAndViewportSetup() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))))),
        .action(try ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectation: WaitStep(predicate: .state(.present(.label("Done"))), timeout: 1)
        )),
    ])

    let messages = plan.validate(.strictTest).map(\.message)

    #expect(messages.contains("Mechanical command appears in strict semantic-test mode"))
    #expect(messages.contains("Viewport command appears in strict semantic-test mode"))
    #expect(messages.contains("Viewport setup immediately precedes a semantic action"))
}

@Test
func validationReportsTypeTextWithoutTarget() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .typeText(TypeTextTarget(text: "milk")))),
    ])

    let findings = plan.validate(.recordingQuality)

    #expect(findings == [
        HeistPlanValidationFinding(
            severity: .warning,
            path: "$.steps[0].action",
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        ),
    ])
}

@Test
func validationReportsEmptyBranchesAndLargeForEachLimit() throws {
    let matching = ElementPredicate.label("Delete")
    let plan = HeistPlan(steps: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), steps: []),
        ])),
        .forEachElement(try ForEachElementStep(
            matching: matching,
            limit: 101,
            parameter: "target",
            steps: [.warn(WarnStep(message: "too many"))]
        )),
    ])

    let messages = plan.validate(.strictTest).map(\.message)

    #expect(messages.contains("Branch has no steps"))
    #expect(messages.contains("ForEach limit is too large for a durable semantic heist"))
}

@Test
func runtimeValidationDoesNotEnforceRecordingQuality() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    #expect(plan.validate(.runtime).isEmpty)
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
        let plan = HeistPlan(steps: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: parameter,
                steps: [.warn(WarnStep(message: "body"))]
            )),
        ])

        let failures = plan.runtimeAdmissionFailures()

        #expect(failures.contains { $0.path == "$.steps[0].for_each_element.parameter" })
        #expect(failures.contains { $0.contract.contains("Swift-style identifier") })
    }
}

@Test
func runtimeAdmissionRejectsInvalidRefs() throws {
    let tooLong = String(repeating: "a", count: HeistPlanRuntimeAdmissionLimits.standard.maxParameterBytes + 1)
    let cases: [(String, HeistPlan, String)] = [
        (
            "empty target ref",
            HeistPlan(steps: [.action(try ActionStep(command: .activate(.ref(""))))]),
            "target_ref"
        ),
        (
            "whitespace target ref",
            HeistPlan(steps: [.action(try ActionStep(command: .activate(.ref(" "))))]),
            "target_ref"
        ),
        (
            "unknown target ref",
            HeistPlan(steps: [.action(try ActionStep(command: .activate(.ref("target"))))]),
            "target_ref must resolve"
        ),
        (
            "empty text ref",
            HeistPlan(steps: [.action(try ActionStep(command: .typeText(
                text: .ref(""),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "whitespace text ref",
            HeistPlan(steps: [.action(try ActionStep(command: .typeText(
                text: .ref(" "),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref"
        ),
        (
            "unknown text ref",
            HeistPlan(steps: [.action(try ActionStep(command: .typeText(
                text: .ref("item"),
                target: .target(.predicate(.label("Search")))
            )))]),
            "text_ref must resolve"
        ),
        (
            "long target ref",
            HeistPlan(steps: [.action(try ActionStep(command: .activate(.ref(tooLong))))]),
            "max parameter/ref length"
        ),
    ]

    for (label, plan, expected) in cases {
        let failures = plan.runtimeAdmissionFailures()
        #expect(failures.contains { $0.contract.contains(expected) }, "\(label): \(failures)")
    }
}

@Test
func runtimeAdmissionRejectsStringRefThatLowersToInvalidCommandPayload() throws {
    let plan = HeistPlan(steps: [
        .forEachString(try ForEachStringStep(
            values: [""],
            parameter: "item",
            steps: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("item"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        )),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains { $0.contract.contains("direct Fence command contract") })
    #expect(failures.contains { $0.observed.contains("text must be non-empty") })
}

@Test
func runtimeAdmissionRejectsEmptySetPasteboardPayload() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "")))),
    ])

    let failures = plan.runtimeAdmissionFailures()

    #expect(failures.contains {
        $0.path == "$.steps[0].action.command.payload.text"
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
            .present(ElementPredicateExpr(label: .literal("Nested"))),
        ]),
        .present(ElementPredicateExpr(label: .literal("Sibling"))),
    ]))
    let plan = HeistPlan(steps: [
        .wait(WaitStep(predicate: deepPredicate, timeout: 0)),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 2,
            parameter: "target",
            steps: [.warn(WarnStep(message: "Nested body"))]
        )),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            steps: [.warn(WarnStep(message: "body"))]
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
        steps: [.warn(WarnStep(message: "nested"))]
    )
    let plans = [
        HeistPlan(steps: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(predicate: .state(.present(.label("Home"))), steps: [.forEachString(nested)]),
            ])),
        ]),
        HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [PredicateCase(predicate: .state(.present(.label("Home"))), steps: [.forEachString(nested)])]
            )),
        ]),
        HeistPlan(steps: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: 1,
                parameter: "target",
                steps: [.forEachString(nested)]
            )),
        ]),
    ]

    for plan in plans {
        let failures = plan.runtimeAdmissionFailures()
        #expect(failures.contains { $0.contract == "collection ForEach steps are top-level only" })
    }
}

@Test
func runtimeAdmissionAcceptsRepresentativeCanonicalPlan() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(
            command: .activate(.target(.predicate(.label("Sign In")))),
            expectation: WaitStep(predicate: .state(.present(.label("Home"))), timeout: 5)
        )),
        .wait(WaitStep(predicate: .state(.absent(.label("Loading"))), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), steps: [.warn(WarnStep(message: "home"))]),
        ])),
        .waitForCases(try WaitForCasesStep(
            timeout: 2,
            cases: [
                PredicateCase(predicate: .state(.present(.label("Done"))), steps: [.warn(WarnStep(message: "done"))]),
            ],
            elseSteps: [.fail(FailStep(message: "timeout"))]
        )),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 20,
            parameter: "target",
            steps: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectation: WaitStep(predicate: .state(.absentTarget(.ref("target"))), timeout: 2)
                )),
            ]
        )),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            steps: [
                .action(try ActionStep(
                    command: .typeText(text: .ref("item"), target: .target(.predicate(.label("Add item")))),
                    expectation: WaitStep(
                        predicate: .state(.present(ElementPredicateExpr(label: .ref("item")))),
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
