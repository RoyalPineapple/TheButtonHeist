import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

private func runtimeSafetyFailures(
    for raw: HeistPlanAdmissionCandidate,
    limits: HeistPlanRuntimeSafetyLimits = .standard
) -> [HeistPlanRuntimeSafetyFailure] {
    do {
        _ = try raw.validatedForRuntimeSafety(limits: limits)
        return []
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.failures
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
        return []
    }
}

private func validatedPlan(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
    try raw.validatedForRuntimeSafety()
}

private let nonDurableHeistActionRepairHint =
    "Use a direct client command for viewport/debug/session actions, or replace " +
    "this with a canonical durable DSL action."

private func expectNonDurableHeistActionFailure(
    _ failures: [HeistPlanRuntimeSafetyFailure],
    observed: String,
    path: String = "$.body[0].action.command"
) {
    #expect(failures.contains {
        $0.path.description == path
            && $0.contract == "durable heist action"
            && $0.observed == observed
            && $0.correction == nonDurableHeistActionRepairHint
    }, "\(failures)")
}

private struct EncodedActionStepContract: Decodable {
    let withoutExpectation: String

    private enum CodingKeys: String, CodingKey {
        case withoutExpectation = "without_expectation"
    }
}

private struct InvalidForEachElementPlanFixture: Encodable {
    let version = HeistPlan.currentVersion
    let body: [InvalidForEachElementStepFixture]
}

private struct InvalidForEachElementStepFixture: Encodable {
    let type = "for_each_element"
    let forEachElement: InvalidForEachElementPayloadFixture

    private enum CodingKeys: String, CodingKey {
        case type
        case forEachElement = "for_each_element"
    }
}

private struct InvalidForEachElementPayloadFixture: Encodable {
    let matching = EncodedElementPredicateFixture(label: "Delete")
    let limit = 1
    let parameter: String
    let body = [InvalidForEachElementWarnFixture()]
}

private struct EncodedElementPredicateFixture: Encodable {
    let checks: [EncodedElementPredicateCheckFixture]

    init(label: String) {
        checks = [EncodedElementPredicateCheckFixture(kind: "label", match: label)]
    }
}

private struct EncodedElementPredicateCheckFixture: Encodable {
    let kind: String
    let match: String
}

private struct InvalidForEachElementWarnFixture: Encodable {
    let type = "warn"
    let warn = InvalidForEachElementWarningFixture(message: "body")
}

private struct InvalidForEachElementWarningFixture: Encodable {
    let message: String
}

private func invalidForEachElementJSON(parameter: String) throws -> Data {
    try JSONEncoder().encode(InvalidForEachElementPlanFixture(
        body: [InvalidForEachElementStepFixture(
            forEachElement: InvalidForEachElementPayloadFixture(parameter: parameter)
        )]
    ))
}

@Test
func actionStepExpectationWaiverRoundTrips() throws {
    let step = try ActionStep(
        command: .activate(.predicate(.label("Save"))),
        expectationPolicy: .waived(try ActionExpectationWaiver("No durable semantic outcome")))

    let data = try JSONEncoder().encode(step)
    let json = try JSONDecoder().decode(EncodedActionStepContract.self, from: data)
    let decoded = try JSONDecoder().decode(ActionStep.self, from: data)

    #expect(json.withoutExpectation == "No durable semantic outcome")
    #expect(decoded == step)
}

@Test
func actionStepRejectsExpectationAndWaiverTogether() {
    let json = """
    {
      "command": {
        "type": "activate",
        "payload": {"target": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Save"}}]}}
      },
      "expectation": {
        "predicate": {
          "type": "exists",
          "target": {
            "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Done" } }]
          }
        },
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

    let finding = try #require(findings.first)
    #expect(findings.count == 1)
    #expect(finding.severity == .error)
    #expect(finding.path.description == "$.body[0].action")
    #expect(finding.message == "Semantic action has no expectation")
    #expect(finding.suggestion == "Attach .expect(...) or .withoutExpectation(\"reason\")")
}

@Test
func `composition quality allows explicit expectation waiver`() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationPolicy: .waived(try ActionExpectationWaiver("No durable semantic outcome")))),
    ])

    #expect(plan.lint(.compositionQuality).isEmpty)
    #expect(plan.lint(.strictTest).isEmpty)
}

@Test
func lintFlagsMechanicalCommands() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))))),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages.contains("Mechanical command appears in strict semantic-test mode"))
}

@Test
func lintReportsTypeTextWithoutTarget() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(command: .typeText(text: "milk", target: nil))),
    ])

    let findings = plan.lint(.compositionQuality)

    let finding = try #require(findings.first)
    #expect(findings.count == 1)
    #expect(finding.severity == .warning)
    #expect(finding.path.description == "$.body[0].action")
    #expect(finding.message == "TypeText has no semantic target")
    #expect(finding.suggestion == "Use TypeText(text, into: target) for durable semantic tests")
}

@Test
func lintReportsEmptyBranches() throws {
    let plan = try HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Home")), body: []),
        ])),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages == ["Branch has no steps"])
    #expect(plan.lint(.strictTest).map(\.path.description) == ["$.body[0].conditional.cases[0]"])
}

@Test
func admissionDecodingRejectsInvalidLoopParameters() throws {
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
        let data = try invalidForEachElementJSON(parameter: parameter)

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: data)
        }
    }
}

@Test
func runtimeSafetyRejectsInvalidRefs() throws {
    let tooLong = String(repeating: "a", count: HeistPlanRuntimeSafetyLimits.standard.maxParameterBytes + 1)
    let cases: [(String, HeistPlanAdmissionCandidate, String)] = [
        (
            "unknown target ref",
            HeistPlanAdmissionCandidate(body: [.action(try ActionStep(command: .activate(.ref("target"))))]),
            "target ref must resolve"
        ),
        (
            "unknown text ref",
            HeistPlanAdmissionCandidate(body: [.action(try ActionStep(command: .typeText(
                reference: "item",
                target: .predicate(.label("Search"))
            )))]),
            "text_ref must resolve"
        ),
        (
            "long target ref",
            HeistPlanAdmissionCandidate(body: [.action(try ActionStep(command: .activate(.ref(
                try HeistReferenceName(validating: tooLong)
            ))))]),
            "max parameter/ref length"
        ),
    ]

    for (label, raw, expected) in cases {
        let failures = runtimeSafetyFailures(for: raw)
        #expect(failures.contains { $0.contract.contains(expected) }, "\(label): \(failures)")
    }
}

@Test
func heistPlanConstructionRejectsNonDurableActions() throws {
    let command = HeistActionCommand.rotor(
        selection: .index(0),
        target: .predicate(.label("Article")),
        direction: .next
    )
    let expectedFailure = try #require(command.durableHeistActionFailure)

    do {
        _ = try HeistPlan(body: [.action(try ActionStep(command: command))])
        Issue.record("Expected non-durable action to fail plan construction")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(error.failures, observed: expectedFailure)
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

@Test
func heistPlanJSONDecodeRejectsNonDurableActions() throws {
    let expectedFailure = try #require(
        HeistActionCommand
            .viewportScroll(ScrollTarget(selection: .container("scrollable_0_0_40_50"), direction: .down))
            .durableHeistActionFailure
    )
    let json = """
    {
      "version": \(HeistPlan.currentVersion),
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "scroll",
              "payload": {
                "containerName": "scrollable_0_0_40_50",
                "direction": "down"
              }
            }
          }
        }
      ]
    }
    """

    do {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))
        Issue.record("Expected non-durable JSON action to fail plan decode")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(error.failures, observed: expectedFailure)
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

@Test
func runtimeSafetyRejectsRefsOutsideTheirLoopScope() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachString(try ForEachStringStep(
            values: ["Milk"],
            parameter: "item",
            body: [.warn(WarnStep(message: "inside string loop"))]
        )),
        .action(try ActionStep(command: .typeText(
            reference: "item",
            target: .predicate(.label("Search"))
        ))),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 1,
            parameter: "target",
            body: [.warn(WarnStep(message: "inside element loop"))]
        )),
        .action(try ActionStep(command: .activate(.ref("target")))),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains {
        $0.path.description == "$.body[1].action.command.payload.text_ref"
            && $0.contract == "text_ref must resolve in the current heist scope"
    })
    #expect(failures.contains {
        $0.path.description == "$.body[3].action.command.payload.target"
            && $0.contract == "target ref must resolve in the current heist scope"
    })
}

@Test
func runtimeSafetyRejectsStringRefThatLowersToInvalidCommandPayload() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachString(try ForEachStringStep(
            values: [""],
            parameter: "item",
            body: [
                .action(try ActionStep(command: .typeText(
                    reference: "item",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text to append must be non-empty") })
}

@Test
func runtimeSafetyRejectsEmptyBroadConcreteAccessibilityTargets() throws {
    let targets: [(String, AccessibilityTarget)] = [
        ("label exact", .label("")),
        ("label contains", .label(.contains(""))),
        ("label prefix", .label(.prefix(""))),
        ("label suffix", .label(.suffix(""))),
        ("identifier exact", .identifier("")),
        ("identifier contains", .identifier(.contains(""))),
        ("identifier prefix", .identifier(.prefix(""))),
        ("identifier suffix", .identifier(.suffix(""))),
        ("value exact", .value("")),
        ("value contains", .value(.contains(""))),
        ("value prefix", .value(.prefix(""))),
        ("value suffix", .value(.suffix(""))),
        ("hint exact", .hint("")),
        ("traits empty", .traits([])),
        ("actions empty", .actions([])),
        ("custom content empty", .customContent(CustomContentMatch())),
        ("rotors empty", .rotors([])),
    ]

    for (label, target) in targets {
        let raw = HeistPlanAdmissionCandidate(body: [
            .action(try ActionStep(command: .activate(target))),
        ])

        let failures = runtimeSafetyFailures(for: raw)

        #expect(
            failures.contains { $0.contract.contains("element predicate") },
            "\(label): \(failures)"
        )
    }
}

@Test
func runtimeSafetyRejectsNegativeOrdinalsBeforeRuntimeUse() throws {
    let concreteRaw = HeistPlanAdmissionCandidate(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"), ordinal: -1)))),
    ])
    let expressionRaw = HeistPlanAdmissionCandidate(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"), ordinal: -1)))),
    ])

    for raw in [concreteRaw, expressionRaw] {
        let failures = runtimeSafetyFailures(for: raw)

        #expect(failures.contains {
            $0.contract == "ordinal must be non-negative"
                && $0.observed == "-1"
        }, "\(failures)")
    }
}

@Test
func runtimeSafetyRejectsEmptyElementPredicatesBeforeRuntimeUse() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .wait(WaitStep(predicate: .exists(.predicate(ElementPredicateTemplate())))),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains {
        $0.contract == "element predicate must not be empty"
            && $0.observed.contains("AccessibilityTarget predicate requires")
    }, "\(failures)")
}

@Test
func runtimeSafetyEnforcesBounds() throws {
    let limits = HeistPlanRuntimeSafetyLimits(
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
    let deepPredicate = AccessibilityPredicate.changed(.elements([
        .exists(.label("Nested")),
        .exists(.label("Sibling")),
    ]))
    let raw = HeistPlanAdmissionCandidate(body: [
        .wait(WaitStep(predicate: deepPredicate, timeout: 0.5)),
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

    let contracts = runtimeSafetyFailures(for: raw, limits: limits).map(\.contract)

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
func runtimeSafetyRequiresForEachElementPositiveLimitUnderConfiguredMax() throws {
    #expect(throws: HeistPlanError.self) {
        _ = try ForEachElementStep(
            matching: .label("Delete"),
            limit: 0,
            parameter: "target",
            body: [.warn(WarnStep(message: "body"))]
        )
    }

    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 2,
            parameter: "target",
            body: [.warn(WarnStep(message: "body"))]
        )),
    ])

    let failures = runtimeSafetyFailures(
        for: raw,
        limits: HeistPlanRuntimeSafetyLimits(maxForEachElementLimit: 1)
    )

    #expect(failures.contains {
        $0.path.description == "$.body[0].for_each_element.limit"
            && $0.contract == "max for_each_element limit"
            && $0.observed == "2"
    }, "\(failures)")
}

@Test
func runtimeSafetyRequiresForEachStringExplicitValuesUnderConfiguredMax() throws {
    #expect(throws: HeistPlanError.self) {
        _ = try ForEachStringStep(
            values: [],
            parameter: "item",
            body: [.warn(WarnStep(message: "body"))]
        )
    }

    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [.warn(WarnStep(message: "body"))]
        )),
    ])

    let failures = runtimeSafetyFailures(
        for: raw,
        limits: HeistPlanRuntimeSafetyLimits(maxForEachStringValues: 1)
    )

    #expect(failures.contains {
        $0.path.description == "$.body[0].for_each_string.values"
            && $0.contract == "max for_each_string values"
            && $0.observed == "2 values"
    }, "\(failures)")
}

@Test
func runtimeSafetyEnforcesConfiguredRepeatUntilTimeoutCap() throws {
    let validTimeouts: [WaitTimeout] = [0.5, 1]
    for timeout in validTimeouts {
        let raw = HeistPlanAdmissionCandidate(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.label("Done")),
                timeout: timeout,
                body: [.warn(WarnStep(message: "retry"))]
            )),
        ])

        let failures = runtimeSafetyFailures(
            for: raw,
            limits: HeistPlanRuntimeSafetyLimits(maxRepeatUntilTimeout: 1)
        )

        #expect(failures.isEmpty, "\(timeout): \(failures)")
    }

    let excessive = HeistPlanAdmissionCandidate(body: [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.label("Done")),
            timeout: 2,
            body: [.warn(WarnStep(message: "retry"))]
        )),
    ])

    let excessiveFailures = runtimeSafetyFailures(
        for: excessive,
        limits: HeistPlanRuntimeSafetyLimits(maxRepeatUntilTimeout: 1)
    )

    #expect(excessiveFailures.contains {
        $0.path.description == "$.body[0].repeat_until.timeout"
            && $0.contract == "max repeat_until timeout"
            && $0.observed == "2 seconds"
    }, "\(excessiveFailures)")
}

@Test
func runtimeSafetyRejectsNestedStepDepthWithPreciseDiagnostic() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Home")), body: [.warn(WarnStep(message: "nested"))]),
        ])),
    ])

    let failures = runtimeSafetyFailures(
        for: raw,
        limits: HeistPlanRuntimeSafetyLimits(maxNestedStepDepth: 1)
    )

    #expect(failures.contains {
        $0.path.description == "$.body[0].conditional.cases[0].body[0]"
            && $0.contract == "max nested step depth"
            && $0.observed == "depth 2"
    }, "\(failures)")
}

@Test
func runtimeSafetyRejectsMaxDefinitionsWithPreciseDiagnostic() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "one", body: [.warn(WarnStep(message: "one"))]),
        HeistPlanAdmissionCandidate(name: "two", body: [.warn(WarnStep(message: "two"))]),
    ], body: [
        .warn(WarnStep(message: "body")),
    ])

    let failures = runtimeSafetyFailures(
        for: raw,
        limits: HeistPlanRuntimeSafetyLimits(maxDefinitions: 1)
    )

    #expect(failures.contains {
        $0.path.description == "$.definitions"
            && $0.contract == "max total heist definitions"
            && $0.observed == "2 definitions"
    }, "\(failures)")
}

@Test
func runtimeSafetyRejectsStandardDefinitionCapByDefault() throws {
    let definitions = try (0...HeistPlanRuntimeSafetyLimits.standardMaxDefinitions).map { index in
        HeistPlanAdmissionCandidate(name: try HeistPlanName(validating: "definition\(index)"), body: [
            .warn(WarnStep(message: try HeistWarningMessage(validating: "definition \(index)"))),
        ])
    }
    let raw = HeistPlanAdmissionCandidate(definitions: definitions, body: [
        .warn(WarnStep(message: "body")),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    let expectedObserved = "\(HeistPlanRuntimeSafetyLimits.standardMaxDefinitions + 1) definitions"
    #expect(failures.contains {
        $0.path.description == "$.definitions"
            && $0.contract == "max total heist definitions"
            && $0.observed == expectedObserved
    }, "\(failures)")
}

@Test
func runtimeSafetyAllowsCollectionLoopsInsideControlFlowButRejectsNestedCollectionLoops() throws {
    let nestedString = try ForEachStringStep(
        values: ["Milk"],
        parameter: "item",
        body: [.warn(WarnStep(message: "nested string"))]
    )
    let nestedElement = try ForEachElementStep(
        matching: .label("Delete"),
        limit: 1,
        parameter: "target",
        body: [.action(try ActionStep(command: .activate(.ref("target"))))]
    )
    let allowedCases: [HeistPlanAdmissionCandidate] = [
        HeistPlanAdmissionCandidate(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(predicate: .exists(.label("Home")), body: [.forEachString(nestedString)]),
            ])),
        ]),
        HeistPlanAdmissionCandidate(body: [
            .wait(WaitStep(
                predicate: .exists(.label("Home")),
                timeout: 1,
                elseBody: [.forEachElement(nestedElement)]
            )),
        ]),
    ]
    let rejectedCases: [(HeistPlanAdmissionCandidate, String, String)] = [
        (
            HeistPlanAdmissionCandidate(body: [
                .forEachElement(try ForEachElementStep(
                    matching: .label("Row"),
                    limit: 1,
                    parameter: "row",
                    body: [.forEachString(nestedString)]
                )),
            ]),
            "$.body[0].for_each_element.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [
                .forEachString(try ForEachStringStep(
                    values: ["Row"],
                    parameter: "rowName",
                    body: [.forEachElement(nestedElement)]
                )),
            ]),
            "$.body[0].for_each_string.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
    ]

    for raw in allowedCases {
        let failures = runtimeSafetyFailures(for: raw)
        #expect(failures.isEmpty, "\(failures)")
    }

    for (raw, path, observed) in rejectedCases {
        let failures = runtimeSafetyFailures(for: raw)

        #expect(failures.contains {
            $0.path.description == path
                && $0.contract == "collection loops must not be nested"
                && $0.observed == observed
        }, "\(failures)")
    }
}

@Test
func runtimeSafetyEnforcesBoundsOnCollectionLoopsInsideControlFlow() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Home")), body: [
                .forEachString(try ForEachStringStep(
                    values: ["Milk", "Eggs"],
                    parameter: "item",
                    body: [.warn(WarnStep(message: "nested"))]
                )),
                .forEachElement(try ForEachElementStep(
                    matching: .label("Delete"),
                    limit: 2,
                    parameter: "target",
                    body: [.action(try ActionStep(command: .activate(.ref("target"))))]
                )),
            ]),
        ])),
    ])
    let failures = runtimeSafetyFailures(
        for: raw,
        limits: HeistPlanRuntimeSafetyLimits(maxForEachStringValues: 1, maxForEachElementLimit: 1)
    )
    let contracts = failures.map(\.contract)

    #expect(contracts.contains("max for_each_string values"))
    #expect(contracts.contains("max for_each_element limit"))
}

@Test
func runtimeSafetyRejectsInvalidHeistDefinitionsAndInvocations() throws {
    let itemReference: HeistReferenceName = "item"
    let definition = HeistPlanAdmissionCandidate(
        name: "addToCart",
        parameter: .string(name: "item"),
        body: [.action(try ActionStep(command: .activate(.predicate(
            ElementPredicateTemplate(label: .exact(itemReference))
        ))))]
    )
    let cases: [(HeistPlanAdmissionCandidate, String)] = [
        (
            HeistPlanAdmissionCandidate(definitions: [
                HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "a"))]),
                HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "b"))]),
            ], body: [.warn(WarnStep(message: "body"))]),
            "duplicate heist definition names are not allowed"
        ),
        (
            HeistPlanAdmissionCandidate(definitions: [definition], body: [
                .invoke(HeistInvocationStep(
                    path: "missing",
                    argument: .string("Milk")
                )),
            ]),
            "heist run path must resolve"
        ),
        (
            HeistPlanAdmissionCandidate(definitions: [definition], body: [
                .invoke(HeistInvocationStep(path: "addToCart", argument: .none)),
            ]),
            "heist run argument type must match"
        ),
    ]

    for (raw, expectedContract) in cases {
        let failures = runtimeSafetyFailures(for: raw)
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
func admissionDecodingRejectsEmptyPredicates() throws {
    let json = """
    {
      "version": \(HeistPlan.currentVersion),
      "body": [
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {},
            "limit": 1,
            "parameter": "target",
            "body": [
              { "type": "warn", "warn": { "message": "body" } }
            ]
          }
        }
      ]
    }
    """

    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: Data(json.utf8))
    }
}

@Test
func admissionDecodingRejectsUnsupportedAndInvalidCommands() throws {
    let unsupportedCommand = """
    {
      "version": \(HeistPlan.currentVersion),
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "teleport",
              "payload": {}
            }
          }
        }
      ]
    }
    """
    let missingPayload = """
    {
      "version": \(HeistPlan.currentVersion),
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "activate"
            }
          }
        }
      ]
    }
    """

    let cases = [
        (unsupportedCommand, "is not a heist action command"),
        (missingPayload, "Missing payload for heist action command type activate"),
    ]

    for (payload, expected) in cases {
        do {
            _ = try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: Data(payload.utf8))
            Issue.record("Expected admission decoding to fail")
        } catch {
            #expect("\(error)".contains(expected), "\(error)")
        }
    }
}

@Test
func runtimeSafetyRejectsDefinitionSelfInvocationOutsideLocalScope() throws {
    let recursiveName: HeistPlanName = "repeatHeist"
    let recursivePath: HeistInvocationPath = "repeatHeist"
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: recursiveName, body: [
            .invoke(HeistInvocationStep(path: recursivePath)),
        ]),
    ], body: [
        .invoke(HeistInvocationStep(path: recursivePath)),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains {
        $0.contract == "heist run path must resolve to a local capability"
    })
}

@Test
func runtimeSafetyAcceptsSingularAccessibilityTargetCapability() throws {
    // `target` is singular by type — a predicate for exactly one element.
    // Multiple targets are unrepresentable; a capability run with one target is
    // runtime-valid.
    let definition = HeistPlanAdmissionCandidate(
        name: "deleteItem",
        parameter: .accessibilityTarget(name: "target"),
        body: [.action(try ActionStep(command: .activate(.ref("target"))))]
    )
    let raw = HeistPlanAdmissionCandidate(definitions: [definition], body: [
        .invoke(HeistInvocationStep(
            path: "deleteItem",
            argument: .accessibilityTarget(.predicate(.label("Row 1")))
        )),
    ])
    _ = try validatedPlan(raw)
}

@Test
func runtimeSafetyAcceptsParameterizedRootAndScratchRootCaller() throws {
    let parameterizedRoot = HeistPlanAdmissionCandidate(
        name: "search",
        parameter: .string(name: "query"),
        body: [.action(try ActionStep(command: .typeText(
            reference: "query",
            target: .predicate(.label("Search"))
        )))]
    )
    _ = try validatedPlan(parameterizedRoot)

    let scratchRoot = HeistPlanAdmissionCandidate(
        definitions: [
            HeistPlanAdmissionCandidate(name: "search", parameter: .string(name: "query"), body: [
                .action(try ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]),
        ],
        body: [.invoke(HeistInvocationStep(path: "search", argument: .string("Milk")))]
    )
    _ = try validatedPlan(scratchRoot)
}

@Test
func runtimeSafetyUsesInvokedDefinitionScopeForHelperDependencies() throws {
    let itemReference: HeistReferenceName = "item"
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(
            name: "addToCart",
            parameter: .string(name: "item"),
            definitions: [
                HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                    .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Add to Cart"))))),
                ]),
            ],
            body: [
                .action(try ActionStep(command: .activate(.predicate(
                    ElementPredicateTemplate(label: .exact(itemReference))
                )))),
                .invoke(HeistInvocationStep(path: "tapAddButton")),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(
            path: "addToCart",
            argument: .string("Milk")
        )),
    ])

    _ = try validatedPlan(raw)
}

@Test
func runtimeSafetyAllowsSameLeafDefinitionNamesInDifferentScopes() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(
            name: "setup",
            definitions: [
                HeistPlanAdmissionCandidate(name: "setup", body: [
                    .warn(WarnStep(message: "Nested setup")),
                ]),
            ],
            body: [
                .invoke(HeistInvocationStep(path: "setup")),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(path: "setup")),
    ])

    _ = try validatedPlan(raw)
}

@Test
func runtimeSafetyValidatesInvokedBodiesWithBoundArguments() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(
            name: "typeSearch",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]
        ),
    ], body: [
        .invoke(HeistInvocationStep(
            path: "typeSearch",
            argument: .string("")
        )),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains { $0.contract.contains("heist action payload contract") })
    #expect(failures.contains { $0.observed.contains("text to append must be non-empty") })
}

@Test
func runtimeSafetyAcceptsRepresentativeCanonicalPlan() throws {
    let itemReference: HeistReferenceName = "item"
    let plan = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Sign In"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Home")), timeout: 5)))),
        .wait(WaitStep(predicate: .missing(.label("Loading")), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Home")), body: [.warn(WarnStep(message: "home"))]),
        ])),
        .wait(WaitStep(
            predicate: .exists(.label("Done")),
            timeout: 2,
            elseBody: [.fail(FailStep(message: "timeout"))]
        )),
        .warn(WarnStep(message: "done")),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 20,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("target")), timeout: 2)))),
            ]
        )),
        .forEachString(try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .typeText(reference: itemReference, target: .predicate(.label("Add item"))),
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: .exists(.predicate(ElementPredicateTemplate(label: .exact(itemReference)))),
                        timeout: 2
                    )))),
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
