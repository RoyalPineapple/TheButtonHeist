import ButtonHeistDSL
import Testing

@Test
func `public facade authors predicates with concrete types`() throws {
    let literalMatch: StringMatch = "Checkout"
    let element = ElementPredicateTemplate(
        label: literalMatch,
        identifier: "checkout.button",
        value: "Ready",
        hint: "Opens checkout",
        rotors: ["Actions"]
    )
    let elementExists: AccessibilityPredicate = .exists(.predicate(element))
    let checkoutContainer: ContainerPredicate = .label("Checkout")
    let containerExists: AccessibilityPredicate = .exists(.container(checkoutContainer))
    let valueChanged: ElementPropertyChange = .value(after: "Ready")
    let screenAssertion: ChangeDeclaration.ScreenAssertion = .exists(.label("Checkout"))
    let elementAssertion: ChangeDeclaration.ElementAssertion = .updated(
        .identifier("checkout.status"),
        valueChanged
    )
    let screenChanged: AccessibilityPredicate = .changed(.screen([screenAssertion]))
    let changed: AccessibilityPredicate = .changed(.elements([
        elementAssertion,
    ]))

    let plan = try HeistPlan {
        WaitFor(elementExists)
        WaitFor(containerExists)
        WaitFor(screenChanged)
        WaitFor(changed)
        WaitFor(.changed(.screen([.exists(.label("Checkout"))])))
        WaitFor(.changed(.elements([
            .exists(.identifier("checkout.status")),
            .appeared(.identifier("checkout.status")),
            .updated(.identifier("checkout.status"), valueChanged),
        ])))
    }

    #expect(plan.body.count == 7)
}

@Test
func `value reference sugar projects to an exact string match`() throws {
    let sugar = try HeistPlan(parameter: "query") { query in
        WaitFor(.exists(.value(query)))
    }
    let explicit = try HeistPlan(parameter: "query") { query in
        WaitFor(.exists(.value(.exact(query))))
    }

    #expect(sugar == explicit)
}
