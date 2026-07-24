import ThePlans
import Testing

@Test
func `canonical authoring module exposes predicates with concrete types`() throws {
    let literalMatch: StringMatch = "Checkout"
    let element = ElementPredicate(
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
func `canonical matcher and target forms compile through the public module`() throws {
    let reference = try HeistReferenceName(validating: "checkout")
    let matches: [StringMatch] = [
        "Checkout",
        .exact("Checkout"),
        .contains("Check"),
        .prefix("Check"),
        .suffix("out"),
        .isEmpty,
        .exact(reference),
        .contains(reference),
        .prefix(reference),
        .suffix(reference),
    ]
    let checks: [ElementPredicateCheck] = [
        .label(matches[0]),
        .identifier("checkout.button"),
        .value(reference),
        .hint(.contains("checkout")),
        .traits([.button]),
        .actions([.activate]),
        .customContent(CustomContentMatch(label: "State", value: "Ready")),
        .rotors(["Actions"]),
        .exclude(.traits([.notEnabled])),
    ]
    let predicates: [ElementPredicate] = [
        .label(matches[0]),
        .identifier("checkout.button"),
        .value(reference),
        .hint(.contains("checkout")),
        .traits([.button]),
        .actions([.activate]),
        .customContent(CustomContentMatch(label: "State", value: "Ready")),
        .rotors(["Actions"]),
        .exclude(.traits([.notEnabled])),
        .element(checks[0], checks[1], traits: [.button], actions: [.activate]),
        ElementPredicate(checks),
    ]
    let targets: [AccessibilityTarget] = [
        .label(matches[0]),
        .identifier("checkout.button"),
        .value(reference),
        .hint(.contains("checkout")),
        .traits([.button]),
        .actions([.activate]),
        .customContent(CustomContentMatch(label: "State", value: "Ready")),
        .rotors(["Actions"]),
        .exclude(.traits([.notEnabled])),
        .element(checks[0], checks[1], traits: [.button], actions: [.activate]),
        .target(predicates[0], ordinal: 0),
        .within(container: .label("Checkout"), .label("Pay")),
        .ref(reference),
    ]
    #expect(
        !matches.isEmpty
            && !checks.isEmpty
            && !predicates.isEmpty
            && AccessibilityPredicate.exists(targets[0]) != .missing(targets[1])
    )
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

@Test
func `public spatial gesture authoring uses direct concrete verbs`() throws {
    let plan = try HeistPlan {
        oneFingerTap(ScreenPoint(x: 10, y: 20))
        longPress(.label("Message"))
        swipe(.label("Carousel"), .left)
        drag(from: ScreenPoint(x: 10, y: 20), to: ScreenPoint(x: 30, y: 40))
        dismissKeyboard()
    }

    let methods: [HeistActionCommandType] = plan.body.compactMap { step in
        guard case .action(let action) = step else { return nil }
        return action.command.wireType
    }
    #expect(methods == [.oneFingerTap, .longPress, .swipe, .drag, .dismissKeyboard])
}

@Test
func `public command construction preserves one action spelling`() {
    let commands: [HeistActionCommand] = [
        .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))),
        .longPress(LongPressTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))),
        .swipe(SwipeTarget(selection: .pointDirection(
            start: ScreenPoint(x: 10, y: 20),
            direction: .left
        ))),
        .drag(DragTarget(
            start: .coordinate(ScreenPoint(x: 10, y: 20)),
            end: ScreenPoint(x: 30, y: 40)
        )),
        .scroll(ScrollTarget(direction: .down)),
        .scrollToVisible(.label("Checkout")),
        .scrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
        .dismissKeyboard,
    ]

    #expect(commands.map(\.wireType) == [
        .oneFingerTap, .longPress, .swipe, .drag,
        .scroll, .scrollToVisible, .scrollToEdge, .dismissKeyboard,
    ])
}
