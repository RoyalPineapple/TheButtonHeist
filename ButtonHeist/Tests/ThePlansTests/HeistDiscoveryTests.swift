import Foundation
import ButtonHeistTestSupport
import Testing
@_spi(ButtonHeistInternals) import ThePlans

private func validatedPlan(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
    try raw.validatedForRuntimeSafety()
}

private func invocation(_ dottedName: String) -> HeistInvocationPath {
    do {
        return try HeistInvocationPath(validating: dottedName)
    } catch {
        preconditionFailure("invalid discovery fixture path \(dottedName): \(error)")
    }
}

private func exactSemanticString(_ value: String) -> HeistSemanticStringMatch {
    HeistSemanticStringMatch(mode: .exact, value: .literal(value))
}

private func existsLabel(_ label: String) -> AccessibilityPredicate {
    .exists(.label(label))
}

private let screenChangePredicate = AccessibilityPredicate.changed(.screen())

@Test func `list heists includes root only entry`() throws {
    let catalog = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).heistCatalog()

    #expect(catalog.heists.map { $0.identity.displayName } == ["checkout"])
    #expect(catalog.heists[0].role == .entry)
    #expect(catalog.heists[0].parameterKind == .none)
    #expect(catalog.heists[0].requiresArgument == false)
    #expect(catalog.heists[0].summary == "Root entry heist")
    #expect(catalog.heists[0].tags == [.entry])
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

    #expect(catalog.heists.map { $0.identity.displayName } == ["root", "openCart"])
    #expect(catalog.heists[0].role == .entry)
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .none)
    #expect(catalog.heists[1].requiresArgument == false)
    #expect(catalog.heists[1].summary == "Reusable heist capability")
    #expect(catalog.heists[1].tags == [.capability])
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
                    .action(ActionStep(command: .activate(.predicate(
                        .label(HeistReferenceName(stringLiteral: "item"))
                    )))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog()

    #expect(catalog.heists[1].identity.displayName == "addToCart")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .string)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring string argument")
    #expect(catalog.heists[1].tags == [.capability, .parameterized, .semanticAction])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists includes element target definition`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "tapRow",
                parameter: .accessibilityTarget(name: "row"),
                body: [
                    .action(ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog()

    #expect(catalog.heists[1].identity.displayName == "tapRow")
    #expect(catalog.heists[1].role == .capability)
    #expect(catalog.heists[1].parameterKind == .accessibilityTarget)
    #expect(catalog.heists[1].requiresArgument == true)
    #expect(catalog.heists[1].summary == "Reusable heist capability requiring accessibility_target argument")
    #expect(catalog.heists[1].tags == [.capability, .parameterized, .semanticAction])
    #expect(catalog.heists[1].parameterName == nil)
}

@Test func `list heists summary mode omits detailed structure`() throws {
    let catalog = try detailedSurfacePlan().heistCatalog()
    let checkout = try #require(catalog.heists.first { $0.identity.displayName == "checkout" })

    #expect(checkout.summary == "Reusable heist capability")
    #expect(checkout.tags == [.capability, .composed, .assertion, .semanticAction])
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
    let checkout = try #require(catalog.heists.first { $0.identity.displayName == "checkout" })

    #expect(checkout.parameterName == nil)
    #expect(checkout.nestedRunHeists == [invocation("checkout.confirm")])
    #expect(checkout.actionCommands == [.activate])
    #expect(checkout.waitCount == 1)
    #expect(checkout.expectationCount == 1)
    #expect(checkout.semanticSurfaces == [
        .label(exactSemanticString("Checkout")),
        .label(exactSemanticString("Done")),
        .label(exactSemanticString("Confirm")),
        .identifier(exactSemanticString("confirmation_button")),
        .traits([.button]),
    ])
    #expect(checkout.validationStatus == .validated)
}

@Test func `list heists detailed mode includes parameter name for parameterized capability`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        definitions: [
            HeistPlanAdmissionCandidate(
                name: "tapRow",
                parameter: .accessibilityTarget(name: "row"),
                body: [
                    .action(ActionStep(command: .activate(.ref("row")))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).heistCatalog(detail: .detailed)

    let tapRow = try #require(catalog.heists.first { $0.identity.displayName == "tapRow" })
    #expect(tapRow.parameterName == "row")
    #expect(tapRow.parameterKind == .accessibilityTarget)
    #expect(tapRow.requiresArgument)
    #expect(tapRow.semanticSurfaces == nil)
}

@Test func `semantic discovery structurally dedupes before catalog projection`() throws {
    let duplicateTemplate = ElementPredicateTemplate([
        .label("Pay"),
        .label("Pay"),
        .traits([.link, .button]),
        .traits([.button, .link]),
    ])
    let catalog = try HeistPlan(
        name: "pay",
        body: [
            .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
            .action(ActionStep(command: .activate(.predicate(duplicateTemplate)))),
        ]
    ).heistCatalog(detail: .detailed)

    let pay = try #require(catalog.heists.first)
    #expect(pay.actionCommands == [.activate])
    #expect(pay.semanticSurfaces == [
        .label(exactSemanticString("Pay")),
        .traits([.button, .link]),
    ])
    #expect(pay.tags == [.entry, .semanticAction])
}

@Test func `target discovery dedupes authored predicates structurally`() throws {
    let description = try HeistPlan(
        name: "pay",
        body: [
            .action(ActionStep(command: .activate(.label("Pay")))),
            .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
        ]
    ).describeHeist(at: "pay")

    #expect(description.semanticSurface.targetPredicates == [.predicate(.label("Pay"))])
    #expect(description.semanticSurface.semanticSurfaces == [.label(exactSemanticString("Pay"))])
}

@Test func `target discovery dedupes typed facts after ordinal projection`() throws {
    let description = try HeistPlan(
        name: "pay",
        body: [
            .action(ActionStep(command: .activate(.target(.label("Pay"), ordinal: 0)))),
            .action(ActionStep(command: .activate(.target(.label("Pay"), ordinal: 1)))),
        ]
    ).describeHeist(at: "pay")

    #expect(description.semanticSurface.targetPredicates == [.predicate(.label("Pay"))])
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

@Test func `catalog rejects entry and capability sharing one lookup path`() throws {
    let plan = try HeistPlan(
        name: "checkout",
        definitions: [
            try HeistPlan(name: "checkout", body: [.warn(WarnStep(message: "nested"))]),
        ],
        body: [.warn(WarnStep(message: "root"))]
    )

    #expect(throws: HeistCatalogError.self) {
        _ = try plan.heistCatalog()
    }
}

@Test func `list heists includes parameterized root entry`() throws {
    let catalog = try validatedPlan(HeistPlanAdmissionCandidate(
        name: "root",
        parameter: .string(name: "item"),
        body: [
            .action(ActionStep(command: .typeText(
                reference: "item",
                target: .label("Search")
            ))),
        ]
    )).heistCatalog()

    let root = try #require(catalog.heists.first)
    #expect(root.identity.displayName == "root")
    #expect(root.role == .entry)
    #expect(root.parameterKind == .string)
    #expect(root.requiresArgument)
    #expect(root.parameterName == nil)
    #expect(root.summary == "Root entry heist requiring string argument")
    #expect(root.tags == [.entry, .parameterized, .textInput])
}

@Test func `describe root entry`() throws {
    let description = try HeistPlan(
        name: "checkout",
        body: [.warn(WarnStep(message: "ready"))]
    ).describeHeist(at: "checkout")

    #expect(description.identity.displayName == "checkout")
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
                    .action(ActionStep(command: .activate(.predicate(
                        .label(HeistReferenceName(stringLiteral: "item"))
                    )))),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )).describeHeist(at: "addToCart")

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
                            .action(ActionStep(command: .activate(.predicate(.label("Confirm"))))),
                        ]
                    ),
                ],
                body: [
                    .invoke(HeistInvocationStep(path: "confirm")),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    ).describeHeist(at: "checkout")

    #expect(description.semanticSurface.nestedRunHeists == [invocation("checkout.confirm")])
    #expect(description.semanticSurface.actionCommands == [.activate])
    #expect(description.semanticSurface.targetPredicates.contains(.predicate(.label("Confirm"))))
}

@Test func `describe action targets and predicates`() throws {
    let description = try HeistPlan(
        name: "activateSave",
        body: [
            .action(ActionStep(command: .activate(.predicate(.identifier("save_button"))))),
        ]
    ).describeHeist(at: "activateSave")

    #expect(description.semanticSurface.actionCommands == [.activate])
    #expect(description.semanticSurface.targetPredicates == [.predicate(.identifier("save_button"))])
}

@Test func `describe waits expectations and expected effects`() throws {
    let announcement = AccessibilityPredicate.announcement(.contains("saved"))
    let description = try HeistPlan(
        name: "submit",
        body: [
            .action(ActionStep(
                command: .activate(.predicate(.label("Submit"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
            .wait(WaitStep(predicate: .changed(.screen()), timeout: 2)),
            .wait(WaitStep(predicate: announcement, timeout: 2)),
        ]
    ).describeHeist(at: "submit")

    #expect(description.semanticSurface.expectations == [existsLabel("Done")])
    #expect(description.semanticSurface.waits == [screenChangePredicate, announcement])
    #expect(description.semanticSurface.expectedEffects == [
        existsLabel("Done"),
        screenChangePredicate,
        announcement,
    ])
}

@Test func `describe expected effects dedupes typed predicates before projection`() throws {
    let description = try HeistPlan(
        name: "submit",
        body: [
            .action(ActionStep(
                command: .activate(.predicate(.label("Submit"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
            .wait(WaitStep(predicate: .exists(.label("Done")), timeout: 2)),
        ]
    ).describeHeist(at: "submit")

    #expect(description.semanticSurface.expectations == [existsLabel("Done")])
    #expect(description.semanticSurface.waits == [existsLabel("Done")])
    #expect(description.semanticSurface.expectedEffects == [existsLabel("Done")])
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
        try plan.describeHeist(at: "checkout")
    }
    do {
        _ = try plan.describeHeist(at: "checkout")
        Issue.record("Expected missing heist diagnostic")
    } catch let error as HeistDescriptionLookupError {
        #expect(error.availableIdentities.map(\.displayName) == ["root", "openCart"])
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
                            .action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(
                                identifier: .exact("confirmation_button"),
                                traits: [.button]
                            ))))),
                        ]
                    ),
                ],
                body: [
                    .action(ActionStep(
                        command: .activate(.predicate(.label("Checkout"))),
                        expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
                    .wait(WaitStep(predicate: .exists(.label("Confirm")), timeout: 1)),
                    .invoke(HeistInvocationStep(path: "confirm")),
                ]
            ),
        ],
        body: [.warn(WarnStep(message: "ready"))]
    )
}
