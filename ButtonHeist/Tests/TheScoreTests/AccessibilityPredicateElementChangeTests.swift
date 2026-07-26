import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

extension AccessibilityPredicateTests {

    // MARK: - Codable

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    /// A screen change replaces the baseline wholesale, which leaves a single
    /// capture — and a single capture admits only capture predicates.
    ///
    /// `disappeared`/`appeared` read two graphs, so they have nothing to read
    /// here. This used to hold: the boundary projected the whole outgoing graph
    /// as `disappeared` and the whole incoming graph as `appeared`, which made
    /// these predicates true of *every* element on either side — a guarantee
    /// worth nothing. Ask `changed(.screen())` about the boundary itself.
    func testDeltaPredicatesAreUnanswerableAcrossAScreenChange() throws {
        let trace = screenTrace(
            before: makeTestInterface(elements: [element(label: "Home")]),
            after: makeTestInterface(elements: [element(label: "Settings")])
        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .disappeared(.label("Home")),
            .appeared(.label("Settings")),
        ]))

        let outcome = try predicate.resolve(in: .empty)
            .validate(against: result(success: true, trace: trace, completeness: .incomplete))
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(
            outcome.actual?.contains("the screen changed"),
            true,
            "The failure must say the screen changed, not that the elements were absent"
        )
    }

    /// The old projection decided lifecycle by which side of the boundary a
    /// node sat on, so an element present on *both* sides counted as having
    /// disappeared and appeared. Identity said it never went anywhere.
    func testUnchangedTargetDoesNotDisappearAndReappearAcrossAScreenChange() throws {
        let shared = element(label: "Continue", traits: [.button])
        let trace = screenTrace(
            before: makeTestInterface(elements: [shared]),
            after: makeTestInterface(elements: [shared])
        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .disappeared(.label("Continue")),
            .appeared(.label("Continue")),
        ]))

        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: result(success: true, trace: trace, completeness: .incomplete)).met)
    }

    /// The discrimination law: the gate is specific to a baseline replacement,
    /// not a blanket disable. The same target, the same lifecycle predicate —
    /// answerable within a screen, unanswerable across one.
    ///
    /// Without this, "always false" would satisfy the two tests above.
    func testLifecyclePredicatesAnswerWithinAScreenButNotAcrossOne() throws {
        let empty = makeTestInterface(elements: [])
        let arrived = makeTestInterface(elements: [element(label: "Toast")])
        let sameScreen = AccessibilityTrace(first: empty).appending(arrived)
        let screenBoundary = screenTrace(before: empty, after: arrived)
        let predicate = AccessibilityPredicate.changed(.elements([
            .appeared(.label("Toast")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result(success: true, trace: sameScreen, completeness: .incomplete)).met)
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: result(success: true, trace: screenBoundary, completeness: .incomplete)).met)
    }

    func testUpdatedOnlyMatchesSameScreenElementFacts() throws {
        let before = makeTestInterface(elements: [element(label: "Count", value: "1")])
        let after = makeTestInterface(elements: [element(label: "Count", value: "2")])
        let sameScreen = AccessibilityTrace(first: before).appending(after)
        let screenBoundary = screenTrace(before: before, after: after)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Count"), .value(before: "1", after: "2")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result(success: true, trace: sameScreen, completeness: .incomplete)).met)
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: result(success: true, trace: screenBoundary, completeness: .incomplete)).met)
    }

    func testNotificationOnlyFactSatisfiesGenericElementsChange() throws {
        let interface = makeTestInterface(elements: [element(label: "Status")])
        let notification = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .none,
            associatedElement: .none
        )
        let trace = AccessibilityTrace(first: interface).appending(
            interface,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [notification])
        )

        XCTAssertTrue(
            try AccessibilityPredicate.changed(.elements())
                .resolve(in: .empty)
                .validate(against: result(success: true, trace: trace, completeness: .incomplete)).met
        )
    }

    func testActionResultValidationUsesAccumulatedTraceEvidence() throws {
        let baseline = makeTestInterface(elements: [
            element(label: "Counter", value: "0"),
        ])
        let updated = makeTestInterface(elements: [
            element(label: "Counter", value: "1"),
        ])
        let final = makeTestInterface(elements: [
            element(label: "Counter", value: "0"),
        ])
        let trace = AccessibilityTrace(first: baseline)
            .appending(updated)
            .appending(final)

        XCTAssertEqual(trace.changeFacts.map(\.kind), [.elementsChanged, .elementsChanged])

        let action = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(trace, completeness: .incomplete))

        )
        let changePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(before: "0", after: "1")),
        ]))

        XCTAssertTrue(try changePredicate.resolve(in: .empty).validate(against: action).met)
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenTraceChangesElements() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenTraceHasNoChange() throws {
        let action = result(success: true, trace: .noChangeForTests(elementCount: 5), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    /// Element change, screen change and announcement are sibling events. None
    /// nests inside another, so no predicate answers about a kind it did not
    /// ask for — just as `announcement` stays silent on an element change.
    ///
    /// This used to pass: a boundary projected element facts, so "did elements
    /// change?" was true of every navigation and `changed(.elements())` was a
    /// strict superset of `changed(.screen())`. They are disjoint now.
    func testElementsChangedNotMetForAScreenChange() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = result(success: true, trace: .screenChangedForTests(replacementInterface: interface), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(before: "3", after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedRequiresTargetAndPropertyAtEncodeBoundary() throws {
        let stale = Data(#"{"type":"updated","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"counter"}}]}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ChangeDeclaration.ElementAssertion.self, from: stale)
        )
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedPassReportsObservedPropertyEvidence() throws {
        let trace = try makeUpdateTrace(label: "Quantity", property: .value, old: "2", new: "3")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Quantity"), .value(before: "2", after: "3")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testElementUpdatedDoesNotPassWhenCurrentValueAlreadyMatchedWithoutChangeEvidence() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Quantity"), .value(before: "3", after: "3")),
        ]))
        let trace = AccessibilityTrace.noChangeForTests(elementCount: 1)
        let result = try predicate.resolve(in: .empty).evaluate(in: evidence(trace))

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementUpdatedNotMetWhenNoMatch() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            try makeUpdate(label: "Other", property: .value, old: "1", new: "5"),
            try makeUpdate(label: "Counter", property: .value, old: "3", new: "5"),
        ]))
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() throws {
        let trace = try makeUpdateTrace(label: "Other", property: .value, old: "3", new: "5")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(before: "3", after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForOldAndNewValues() throws {
        let trace = try makeUpdateTrace(label: "cart", property: .value, old: "cart: empty", new: "3 items")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("cart"), .value(before: .prefix("cart:"), after: .suffix("items"))),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForEveryModeAcrossBeforeAndAfter() throws {
        let trace = try makeUpdateTrace(
            label: "Search Field",
            property: .value,
            old: "Search for tea",
            new: "John Smith"
        )
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let changes: [ElementPropertyChange] = [
            .value(before: .exact("Search for tea"), after: .exact("John Smith")),
            .value(before: .contains("for"), after: .contains("Smith")),
            .value(before: .prefix("Search"), after: .prefix("John")),
            .value(before: .suffix("tea"), after: .suffix("Smith")),
        ]

        for change in changes {
            let predicate = AccessibilityPredicate.changed(.elements([
                .updated(.label("Search Field"), change),
            ]))
            XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
        }
    }

    func testElementUpdatedMatchesTraitGainAndLossAcrossBeforeAndAfter() throws {
        let gained = try makeTraitUpdate(label: "Favorites", beforeTraits: [.button], afterTraits: [.button, .selected])
        let lost = try makeTraitUpdate(label: "Disabled", beforeTraits: [.button, .notEnabled], afterTraits: [.button])
        let action = result(
            success: true,
            trace: .elementsChangedForTests(elementCount: 2, edits: ElementEdits(updated: [gained, lost])),
            completeness: .incomplete
        )

        let selectedGain = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Favorites"),
                .traits(before: .init(exclude: [.selected]), after: .init(include: [.selected]))
            ),
        ]))
        let enabledLoss = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Disabled"),
                .traits(before: .init(include: [.notEnabled]), after: .init(exclude: [.notEnabled]))
            ),
        ]))

        XCTAssertTrue(try selectedGain.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try enabledLoss.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedActionChecker() throws {
        let update = try XCTUnwrap(projectElementStateChange(
            old: element(label: "Stepper", actions: [.increment]),
            new: element(label: "Stepper", actions: [.increment, .activate])
        ))
        let action = result(
            success: true,
            trace: .elementsChangedForTests(elementCount: 1, edits: ElementEdits(updated: [update])),
            completeness: .incomplete
        )

        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Stepper"),
                .actions(
                    before: ActionSetMatch(exclude: Set<ElementAction>([.activate])),
                    after: ActionSetMatch(include: Set<ElementAction>([.activate]))
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(.label("Stepper"), .actions(after: ActionSetMatch(exclude: [.activate]))),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedGeometryCheckers() throws {
        let frameUpdate = try XCTUnwrap(projectElementStateChange(
            old: element(label: "Card", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44),
            new: element(label: "Card", frameX: 12, frameY: 20, frameWidth: 120, frameHeight: 44)
        ))
        let pointUpdate = try XCTUnwrap(projectElementStateChange(
            old: element(label: "Knob", activationPointEvidence: .explicit(ScreenPoint(x: 10, y: 12))),
            new: element(label: "Knob", activationPointEvidence: .explicit(ScreenPoint(x: 42, y: 64)))
        ))
        let action = result(
            success: true,
            trace: .elementsChangedForTests(
                elementCount: 2,
                edits: ElementEdits(updated: [frameUpdate, pointUpdate])
            ),
            completeness: .incomplete
        )

        let framePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 12, y: 20, width: 120, height: 44))),
        ]))
        let pointPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Knob"), .activationPoint(after: ElementPointMatch(x: 42, y: 64))),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 13))),
        ]))

        XCTAssertTrue(try framePredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try pointPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedCustomContentAndRotorCheckers() throws {
        let customContent = HeistCustomContent(label: "Status", value: "Ready to submit", isImportant: true)
        let customUpdate = try XCTUnwrap(projectElementStateChange(
            old: element(label: "Form", customContent: [HeistCustomContent(label: "Help", value: "Optional", isImportant: false)]),
            new: element(label: "Form", customContent: [customContent])
        ))
        let rotorUpdate = try XCTUnwrap(projectElementStateChange(
            old: element(label: "Article", rotors: [HeistRotor(name: "Links")]),
            new: element(label: "Article", rotors: [HeistRotor(name: "Headings"), HeistRotor(name: "Links")])
        ))
        let action = result(
            success: true,
            trace: .elementsChangedForTests(
                elementCount: 2,
                edits: ElementEdits(updated: [customUpdate, rotorUpdate])
            ),
            completeness: .incomplete
        )

        let customPredicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch.exact("Status"),
                    value: StringMatch.contains("Ready"),
                    isImportant: true
                ))
            ),
        ]))
        let rotorPredicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Article"),
                .rotors(
                    before: RotorSetMatch(exclude: [StringMatch.exact("Headings")]),
                    after: RotorSetMatch(include: [StringMatch.contains("Head")])
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch.exact("Status"),
                    isImportant: false
                ))
            ),
        ]))

        XCTAssertTrue(try customPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try rotorPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedResolvesTargetThroughCaptureReferences() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "a", new: "b")
        let edge = try XCTUnwrap(trace.changeFacts.first?.metadata.captureEdge)
        XCTAssertEqual(trace.capture(ref: edge.before)?.sequence, edge.before.sequence)
        XCTAssertEqual(trace.capture(ref: edge.after)?.sequence, edge.after.sequence)

        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value()),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedNotMetWithoutTrace() throws {
        let action = result(success: true)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits())
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no matching element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 10, edits: ElementEdits(updated: [
            try makeUpdate(label: "label", property: .value, old: "A", new: "B"),
            try makeUpdate(label: "counter", property: .value, old: "3", new: "5"),
        ]))
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(
                before: element(label: "Toggle", traits: [.button]),
                after: element(label: "Toggle", value: "5", traits: [.button, .selected]),
                changes: [
                    try XCTUnwrap(PropertyChange.traits(old: [.button], new: [.button, .selected])),
                    try XCTUnwrap(PropertyChange.value(old: "3", new: "5")),
                ]
            ),
        ]))
        let action = result(success: true, trace: trace, completeness: .incomplete)
        let traitsPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .traits()),
        ]))
        let traitsResult = try traitsPredicate.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valuePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .value(after: "5")),
        ]))
        let valueResult = try valuePredicate.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .hint()),
        ]))
        let hintResult = try hintPredicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() throws {
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "btn_1", property: .value, old: "OFF", new: "ON"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("btn_1"), .value(before: "OFF", after: "ON")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testElementUpdatedPropertyOnly() throws {
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "any", property: .value, old: "A", new: "B"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() throws {
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(elementCount: 5, edits: ElementEdits()),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        let outcome = try predicate.resolve(in: .empty).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no matching element updates")
    }

    func testElementUpdatedPropertyMismatch() throws {
        let result = ActionResult.success(
            payload: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "btn_1", property: .hint, old: "A", new: "B"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("btn_1"), .value()),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    // MARK: - Helpers

    func makeUpdateTrace(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        elementCount: Int = 5
    ) throws -> AccessibilityTrace {
        .elementsChangedForTests(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                try makeUpdate(label: label, property: property, old: old, new: new),
            ])
        )
    }

    private func makeUpdate(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait] = [],
        afterTraits: [HeistTrait] = []
    ) throws -> ElementUpdate {
        ElementUpdate(
            before: makeElementForUpdate(label: label, property: property, value: old, traits: beforeTraits),
            after: makeElementForUpdate(label: label, property: property, value: new, traits: afterTraits),
            changes: [try propertyChange(
                property: property,
                old: old,
                new: new,
                beforeTraits: beforeTraits,
                afterTraits: afterTraits
            )]
        )
    }

    private func makeTraitUpdate(
        label: String,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) throws -> ElementUpdate {
        ElementUpdate(
            before: element(label: label, traits: beforeTraits),
            after: element(label: label, traits: afterTraits),
            changes: [
                try XCTUnwrap(PropertyChange.traits(old: beforeTraits, new: afterTraits)),
            ]
        )
    }

    private func propertyChange(
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) throws -> PropertyChange {
        switch property {
        case .label:
            return try XCTUnwrap(PropertyChange.label(old: old, new: new))
        case .identifier:
            return try XCTUnwrap(PropertyChange.identifier(old: old, new: new))
        case .value:
            return try XCTUnwrap(PropertyChange.value(old: old, new: new))
        case .hint:
            return try XCTUnwrap(PropertyChange.hint(old: old, new: new))
        case .traits:
            return try XCTUnwrap(PropertyChange.traits(old: beforeTraits, new: afterTraits))
        case .actions, .frame, .activationPoint, .customContent, .rotors:
            fatalError("Unsupported test property \(property)")
        }
    }

    private func makeElementForUpdate(
        label: String,
        property: ElementProperty,
        value: String?,
        traits: [HeistTrait]
    ) -> HeistElement {
        switch property {
        case .label:
            return element(label: value ?? label, traits: traits)
        case .identifier:
            return element(label: label, identifier: value, traits: traits)
        case .value:
            return element(label: label, value: value, traits: traits)
        case .traits:
            return element(label: label, traits: traits)
        case .hint:
            return element(label: label, hint: value, traits: traits)
        default:
            return element(label: label, value: value, traits: traits)
        }
    }

}
