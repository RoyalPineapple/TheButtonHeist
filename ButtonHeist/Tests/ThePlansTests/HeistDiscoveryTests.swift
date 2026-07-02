import Foundation
import ButtonHeistTestSupport
import Testing
@_spi(ButtonHeistInternals) import ThePlans

private func validatedPlan(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
    try raw.validatedForRuntimeSafety()
}

@Test func `list heists includes root only entry`() throws {
    let catalog = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).heistCatalog()

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
    #expect(catalog.heists[0].validationStatus == nil)
}

@Test func `list heists includes unparameterized definition`() throws {
    let catalog = try HeistPlan(
        name: "root",
        definitions: [
            try HeistPlan(name: "openCart", body: [.warn(WarnStep(message: "open"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).heistCatalog()

    #expect(catalog.heists.map(\.name) == ["root", "openCart"])
    #expect(catalog.heists[0].role == .entry)
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .none)
    #expect(catalog.heists[1].requiresArgument == false)
    #expect(catalog.heists[1].summary == "Reusable heist capability")
    #expect(catalog.heists[1].tags == ["capability"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists includes string definition`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog()

    #expect(catalog.heists[1].name == "addToCart")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .string)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring string argument")
    #expect(catalog.heists[1].tags == ["capability", "parameterized", "semantic-action"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists includes element target definition`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "tapRow",
                parameter: .elementTarget(name: "row"),
                body: [
                    .action(try ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog()

    #expect(catalog.heists[1].name == "tapRow")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .elementTarget)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring element_target argument")
    #expect(catalog.heists[1].tags == ["capability", "parameterized", "semantic-action"])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists summary mode omits detailed structure`() throws {
    let catalog = try detailedSurfacePlan().heistCatalog()
    let checkout = try #require(catalog.heists.first { $0.name == "checkout" })

    #expect(checkout.summary == "Reusable heist capability")
    #expect(checkout.tags == ["capability", "composed", "assertion", "semantic-action"])
    #expect(checkout.parameterName == nil)
    #expect(checkout.nestedRunHeists == nil)
    #expect(checkout.actionCommands == nil)
    #expect(checkout.waitCount == nil)
    #expect(checkout.expectationCount == nil)
    #expect(checkout.semanticSurfaces == nil)
    #expect(checkout.validationStatus == nil)
}

@Test func `list heists detailed mode includes derived non raw fields`() throws {
    let catalog = try detailedSurfacePlan().heistCatalog(detail: .detailed)
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
    #expect(checkout.validationStatus == .validated)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("predicate(") }) == false)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("point") }) == false)
    #expect(checkout.semanticSurfaces?.contains(where: { $0.contains("target_ref") }) == false)
}

@Test func `list heists detailed mode includes parameter name for parameterized capability`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "tapRow",
                parameter: .elementTarget(name: "row"),
                body: [
                    .action(try ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog(detail: .detailed)

    let tapRow = try #require(catalog.heists.first { $0.name == "tapRow" })
    #expect(tapRow.parameterName == "row")
    #expect(tapRow.parameterKind == .elementTarget)
    #expect(tapRow.requiresArgument)
    #expect(tapRow.semanticSurfaces == nil)
}

@Test func `semantic discovery structurally dedupes before catalog projection`() throws {
    let duplicateTemplate = ElementPredicateTemplate([
        .label(.literal("Pay")),
        .label(.literal("Pay")),
        .traits([.link, .button]),
        .traits([.button, .link]),
    ])
    let catalog = try HeistPlan(
        name: "pay",
        body: [
            .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
            .action(try ActionStep(command: .activate(.predicate(duplicateTemplate)))),
        ]
    ).heistCatalog(detail: .detailed)

    let pay = try #require(catalog.heists.first)
    #expect(pay.actionCommands == ["activate"])
    #expect(pay.semanticSurfaces == [
        "label=Pay",
        "traits=button|link",
    ])
    #expect(pay.tags == ["entry", "semantic-action"])
}

@Test func `semantic discovery internals stay typed until catalog projection`() throws {
    let source = try discoverySource()
    let builderSource = try sourceSection(
        source,
        from: "private struct HeistSemanticSurfaceBuilder",
        to: "\nprivate func appendUnique"
    )
    let catalogTagsSource = try sourceSection(
        source,
        from: "    func catalogTags(",
        to: "\n}\n\nstruct ResolvedCatalogHeist"
    )

    #expect(builderSource.contains("var actionCommands: [HeistActionCommandType]"))
    #expect(builderSource.contains("var semanticFacets: [HeistSemanticSurfaceFacet]"))
    for forbidden in [
        "var actionCommands: [String]",
        "var semanticSurfaces: [String]",
        ".wireType.rawValue",
        "to: &semanticSurfaces",
        #""label="#,
        #""identifier="#,
        #""value="#,
        #""traits="#,
        #""excludeTraits="#,
    ] {
        #expect(!builderSource.contains(forbidden), "Builder collected early string state: \(forbidden)")
    }

    #expect(catalogTagsSource.contains("switch command"))
    for forbidden in [
        #""typeText""#,
        #""type_text""#,
        "contains(where: Self.isViewportAction)",
        "contains(where: Self.isGestureAction)",
        "contains(where: Self.isSemanticAction)",
    ] {
        #expect(!catalogTagsSource.contains(forbidden), "Catalog tags matched command strings: \(forbidden)")
    }
    #expect(!source.contains("static func isSemanticAction"))
    #expect(!source.contains("static func isGestureAction"))
    #expect(!source.contains("static func isViewportAction"))
}

@Test func `list heists cannot be reached for invalid raw plan`() throws {
    let raw = HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "one"))]),
            HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "two"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )

    #expect(throws: HeistPlanRuntimeSafetyError.self) {
        _ = try raw.validatedForRuntimeSafety()
    }
}

@Test func `list heists includes parameterized root entry`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        parameter: .string(name: "item"),
        body: [
            .action(try ActionStep(command: .typeText(
                text: .ref("item"),
                target: .target(.predicate(.label("Search")))
            ))),
        ]
    )).heistCatalog()

    let root = try #require(catalog.heists.first)
    #expect(root.name == "root")
    #expect(root.role == .entry)
    #expect(root.parameterKind == .string)
    #expect(root.requiresArgument)
    #expect(root.parameterName == nil)
    #expect(root.summary == "Root entry heist requiring string argument")
    #expect(root.tags == ["entry", "parameterized", "text-input"])
}

@Test func `describe root entry`() throws {
    let description = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).describeHeist(named: "checkout")

    #expect(description.name == "checkout")
    #expect(description.role == .entry)
    #expect(description.parameterKind == .none)
    #expect(description.requiresArgument == false)
    #expect(description.validationStatus == .validated)
}

@Test func `describe parameterized capability`() throws {
    let description = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).describeHeist(named: "addToCart")

    #expect(description.role == .capability)
    #expect(description.parameterKind == .string)
    #expect(description.parameterName == "item")
    #expect(description.requiresArgument)
}

@Test func `describe nested RunHeist includes call and expanded surface`() throws {
    let description = try HeistPlan(
        name: "root",
        definitions: [
            try HeistPlan(
                name: "checkout",
                definitions: [
                    try HeistPlan(
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
    ).describeHeist(named: "checkout")

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
    ).describeHeist(named: "activateSave")

    #expect(description.semanticSurface.actionCommands == ["activate"])
    #expect(description.semanticSurface.targetPredicates == [#"predicate(identifier="save_button")"#])
}

@Test func `describe waits expectations and expected effects`() throws {
    let description = try HeistPlan(
        name: "submit",
        body: [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Submit"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
            .wait(WaitStep(predicate: .change(.screen()), timeout: 2)),
        ]
    ).describeHeist(named: "submit")

    #expect(description.semanticSurface.expectations == [#"exists(predicate(label="Done"))"#])
    #expect(description.semanticSurface.waits == ["change(screen(*))"])
    #expect(description.semanticSurface.expectedEffects == [
        #"exists(predicate(label="Done"))"#,
        "change(screen(*))",
    ])
}

@Test func `describe missing name reports available names`() throws {
    let plan = try HeistPlan(
        name: "root",
        definitions: [
            try HeistPlan(name: "openCart", body: [.warn(WarnStep(message: "open"))]),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )

    #expect(throws: HeistDescriptionLookupError.self) {
        try plan.describeHeist(named: "checkout")
    }
    do {
        _ = try plan.describeHeist(named: "checkout")
        Issue.record("Expected missing heist diagnostic")
    } catch let error as HeistDescriptionLookupError {
        #expect(error.availableNames == ["root", "openCart"])
        #expect(error.description.contains("checkout"))
    }
}

private func detailedSurfacePlan() throws -> HeistPlan {
    try HeistPlan(
        name: "root",
        definitions: [
            try HeistPlan(
                name: "checkout",
                definitions: [
                    try HeistPlan(
                        name: "confirm",
                        body: [
                            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(
                                identifier: .exact(.literal("confirmation_button")),
                                traits: [.button]
                            ))))),
                        ]
                    ),
                ],
                body: [
                    .action(try ActionStep(
                        command: .activate(.predicate(.label("Checkout"))),
                        expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
                    .wait(WaitStep(predicate: .exists(.label("Confirm")), timeout: 1)),
                    .invoke(HeistInvocationStep(path: ["confirm"])),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )
}

private func discoverySource() throws -> String {
    try SourceShapeRepository(filePath: #filePath)
        .requiredFile(relativePath: "ButtonHeist/Sources/ThePlans/HeistPlan+Discovery.swift")
        .contents
}

private func sourceSection(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
    guard let start = source.range(of: startMarker),
          let end = source[start.upperBound...].range(of: endMarker)
    else {
        throw DiscoverySourceGuardrailError()
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

private struct DiscoverySourceGuardrailError: Error {}
