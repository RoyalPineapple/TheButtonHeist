import Testing
import ThePlans

@Test func `list heists includes root only entry`() throws {
    let catalog = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).admittedHeistCatalog()

    #expect(catalog.heists.map(\.name) == ["checkout"])
    #expect(catalog.heists[0].role == .entry)
    #expect(catalog.heists[0].parameterKind == .none)
    #expect(catalog.heists[0].requiresArgument == false)
    #expect(catalog.heists[0].summary == "Root entry heist")
    #expect(catalog.heists[0].tags == ["entry"])
    #expect(catalog.heists[0].parameterName == nil)
    #expect(catalog.heists[0].nestedRunHeists == nil)
    #expect(catalog.heists[0].actionCommands == nil)
    #expect(catalog.heists[0].waitCount == nil)
    #expect(catalog.heists[0].expectationCount == nil)
    #expect(catalog.heists[0].semanticSurfaces == nil)
    #expect(catalog.heists[0].admissionStatus == nil)
}

@Test func `list heists includes unparameterized definition`() throws {
    let catalog = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(name: "openCart", body: [.warn(WarnStep(message: "open"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).admittedHeistCatalog()

    #expect(catalog.heists.map(\.name) == ["root", "openCart"])
    #expect(catalog.heists[0].role == .entry)
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .none)
    #expect(catalog.heists[1].requiresArgument == false)
    #expect(catalog.heists[1].summary == "Reusable heist capability")
    #expect(catalog.heists[1].tags == ["capability"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists includes strings definition`() throws {
    let catalog = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "addToCart",
                parameter: .strings(name: "item"),
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).admittedHeistCatalog()

    #expect(catalog.heists[1].name == "addToCart")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .strings)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring strings argument")
    #expect(catalog.heists[1].tags == ["capability", "parameterized", "semantic-action"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists includes element target definition`() throws {
    let catalog = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "tapRow",
                parameter: .elementTarget(name: "row"),
                body: [
                    .action(try ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).admittedHeistCatalog()

    #expect(catalog.heists[1].name == "tapRow")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .elementTarget)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring element_target argument")
    #expect(catalog.heists[1].tags == ["capability", "parameterized", "semantic-action"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists summary mode omits detailed structure`() throws {
    let catalog = try detailedSurfacePlan().admittedHeistCatalog()
    let checkout = try #require(catalog.heists.first { $0.name == "checkout" })

    #expect(checkout.summary == "Reusable heist capability")
    #expect(checkout.tags == ["capability", "composed", "assertion", "semantic-action"])
    #expect(checkout.parameterName == nil)
    #expect(checkout.nestedRunHeists == nil)
    #expect(checkout.actionCommands == nil)
    #expect(checkout.waitCount == nil)
    #expect(checkout.expectationCount == nil)
    #expect(checkout.semanticSurfaces == nil)
    #expect(checkout.admissionStatus == nil)
}

@Test func `list heists detailed mode includes derived non raw fields`() throws {
    let catalog = try detailedSurfacePlan().admittedHeistCatalog(detail: .detailed)
    let checkout = try #require(catalog.heists.first { $0.name == "checkout" })

    #expect(checkout.parameterName == nil)
    #expect(checkout.nestedRunHeists == ["checkout.confirm"])
    #expect(checkout.actionCommands == ["activate"])
    #expect(checkout.waitCount == 1)
    #expect(checkout.expectationCount == 1)
    #expect(checkout.semanticSurfaces == [
        "label=Checkout",
        "label=Done",
        "label=Confirm",
        "identifier=confirmation_button",
        "traits=button",
    ])
    #expect(checkout.admissionStatus == .admitted)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("predicate(") }) == false)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("point") }) == false)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("target_ref") }) == false)
}

@Test func `list heists detailed mode includes parameter name for parameterized capability`() throws {
    let catalog = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "tapRow",
                parameter: .elementTarget(name: "row"),
                body: [
                    .action(try ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).admittedHeistCatalog(detail: .detailed)

    let tapRow = try #require(catalog.heists.first { $0.name == "tapRow" })
    #expect(tapRow.parameterName == "row")
    #expect(tapRow.parameterKind == .elementTarget)
    #expect(tapRow.requiresArgument)
    #expect(tapRow.semanticSurfaces == nil)
}

@Test func `list heists fails invalid admitted plan`() throws {
    let plan = HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "one"))]),
            HeistPlan(name: "duplicate", body: [.warn(WarnStep(message: "two"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )

    #expect(throws: HeistPlanAdmissionError.self) {
        try plan.admittedHeistCatalog()
    }
}

@Test func `direct discovery methods fail non admitted parameterized root`() throws {
    let plan = HeistPlan(
        name: "root",
        parameter: .strings(name: "item"),
        body: [.warn(WarnStep(message: "invalid root"))]
    )

    #expect(throws: HeistPlanAdmissionError.self) {
        try plan.heistCatalog()
    }
    #expect(throws: HeistPlanAdmissionError.self) {
        try plan.describeHeist(named: "root")
    }
}

@Test func `describe root entry`() throws {
    let description = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).describeAdmittedHeist(named: "checkout")

    #expect(description.name == "checkout")
    #expect(description.role == .entry)
    #expect(description.parameterKind == .none)
    #expect(description.requiresArgument == false)
    #expect(description.admissionStatus == .admitted)
}

@Test func `describe parameterized capability`() throws {
    let description = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "addToCart",
                parameter: .strings(name: "item"),
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).describeAdmittedHeist(named: "addToCart")

    #expect(description.role == .capability)
    #expect(description.parameterKind == .strings)
    #expect(description.parameterName == "item")
    #expect(description.requiresArgument)
}

@Test func `describe nested RunHeist includes call and expanded surface`() throws {
    let description = try HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "checkout",
                definitions: [
                    HeistPlan(
                        name: "confirm",
                        body: [
                            .action(try ActionStep(command: .activate(.predicate(.label("Confirm"))))),
                        ]
                    ),
                ],
                body: [
                    .invoke(HeistInvocationStep(path: ["confirm"])),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).describeAdmittedHeist(named: "checkout")

    #expect(description.semanticSurface.nestedRunHeists == ["checkout.confirm"])
    #expect(description.semanticSurface.actionCommands == ["activate"])
    #expect(description.semanticSurface.targetPredicates.contains(#"predicate(label="Confirm")"#))
}

@Test func `describe action targets and predicates`() throws {
    let description = try HeistPlan(
        name: "activateSave",
        body: [
            .action(try ActionStep(command: .activate(.predicate(.identifier(.literal("save_button")))))),
        ]
    ).describeAdmittedHeist(named: "activateSave")

    #expect(description.semanticSurface.actionCommands == ["activate"])
    #expect(description.semanticSurface.targetPredicates == [#"predicate(identifier="save_button")"#])
}

@Test func `describe waits expectations and expected effects`() throws {
    let description = try HeistPlan(
        name: "submit",
        body: [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Submit"))),
                expectation: WaitStep(predicate: .present(.label("Done")), timeout: 1)
            )),
            .wait(WaitStep(predicate: .changed(.screen()), timeout: 2)),
        ]
    ).describeAdmittedHeist(named: "submit")

    #expect(description.semanticSurface.expectations == [#"present(predicate(label="Done"))"#])
    #expect(description.semanticSurface.waits == ["changed(screen_changed)"])
    #expect(description.semanticSurface.expectedEffects == [
        #"present(predicate(label="Done"))"#,
        "changed(screen_changed)",
    ])
}

@Test func `describe missing name reports available names`() throws {
    let plan = HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(name: "openCart", body: [.warn(WarnStep(message: "open"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )

    #expect(throws: HeistDescriptionLookupError.self) {
        try plan.describeAdmittedHeist(named: "checkout")
    }
    do {
        _ = try plan.describeAdmittedHeist(named: "checkout")
        Issue.record("Expected missing heist diagnostic")
    } catch let error as HeistDescriptionLookupError {
        #expect(error.availableNames == ["root", "openCart"])
        #expect(error.description.contains("checkout"))
    }
}

private func detailedSurfacePlan() throws -> HeistPlan {
    HeistPlan(
        name: "root",
        definitions: [
            HeistPlan(
                name: "checkout",
                definitions: [
                    HeistPlan(
                        name: "confirm",
                        body: [
                            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(
                                identifier: .literal("confirmation_button"),
                                traits: [.button]
                            ))))),
                        ]
                    ),
                ],
                body: [
                    .action(try ActionStep(
                        command: .activate(.predicate(.label("Checkout"))),
                        expectation: WaitStep(predicate: .present(.label("Done")), timeout: 1)
                    )),
                    .wait(WaitStep(predicate: .present(.label("Confirm")), timeout: 1)),
                    .invoke(HeistInvocationStep(path: ["confirm"])),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )
}
