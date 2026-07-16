import ThePlans
import Testing

@Test
func `canonical authoring module exposes predicates with concrete types`() throws {
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

    #expect(plan.body.count == 6)
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

@Test
func `public payload construction exposes only admitted values`() throws {
    let gesture = try GestureDuration(validatingSeconds: GestureDuration.maximumSeconds)
    let text: TextInputText = "milk"
    let pasteboardText: PasteboardText = "milk"
    let timeout: WaitTimeout = 1
    let append = TypeTextTarget(text: text)
    let replacement = TypeTextTarget(text: .replacing(""))
    let pasteboard = SetPasteboardTarget(text: pasteboardText)
    let wait = WaitTarget(predicate: .exists(.label("Ready")), timeout: timeout)

    #expect(gesture.seconds == GestureDuration.maximumSeconds)
    #expect(append.source == .text("milk"))
    #expect(replacement.source == .text(.replacing("")))
    #expect(pasteboard.text.description == "milk")
    #expect(wait.resolvedTimeout == timeout)
}
