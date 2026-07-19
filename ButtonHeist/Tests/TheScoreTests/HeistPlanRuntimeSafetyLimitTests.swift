import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

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
func runtimeSafetyUsesTheAdmittedWaitTimeoutWithoutASecondRepeatUntilCap() throws {
    let configuredMaximum = WaitTimeout.maximumSeconds(environment: [
        WaitTimeoutEnvironmentKey.maximum.rawValue: "120",
    ])
    let timeout = try WaitTimeout(
        validatingSeconds: configuredMaximum,
        maximumSeconds: configuredMaximum
    )
    let raw = HeistPlanAdmissionCandidate(body: [
        .repeatUntil(try RepeatUntilStep(
            predicate: .exists(.label("Done")),
            timeout: timeout,
            body: [.warn(WarnStep(message: "retry"))]
        )),
    ])

    #expect(runtimeSafetyFailures(for: raw).isEmpty)
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
        body: [.action(ActionStep(command: .activate(.ref("target"))))]
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
                    body: [.action(ActionStep(command: .activate(.ref("target"))))]
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
