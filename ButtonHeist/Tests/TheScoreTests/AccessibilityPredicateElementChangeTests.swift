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

    /// A pair is proved by two legs in order and a hash that differs, and the hash
    /// is taken at the scope the author named: the property on a named element, or
    /// the element, or — when nothing is named at all — the whole screen.
    ///
    /// `changed(.elements())` names nothing, so the screen is the scope. Two legs
    /// that any tree answers, separated by a screen that read differently.
    ///
    /// A notification riding the transition is not part of that. The two legs and
    /// the hash are the whole of what is checked, so a layout notification over an
    /// unchanged screen says the projection did not move — which is the answer.
    func testGenericElementsChangeNeedsTwoReadingsAndNotANotification() throws {
        let interface = makeTestInterface(elements: [element(label: "Status")])
        let notification = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .none,
            associatedElement: .none
        )
        let unmoved = AccessibilityTrace(first: interface).appending(
            interface,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [notification])
        )

        XCTAssertFalse(
            try AccessibilityPredicate.changed(.elements())
                .resolve(in: .empty)
                .validate(against: result(success: true, trace: unmoved, completeness: .incomplete)).met,
            "the same tree twice is one reading, whatever the notification claims"
        )

        let moved = AccessibilityTrace(first: interface).appending(
            makeTestInterface(elements: [element(label: "Status"), element(label: "Detail")])
        )

        XCTAssertTrue(
            try AccessibilityPredicate.changed(.elements())
                .resolve(in: .empty)
                .validate(against: result(success: true, trace: moved, completeness: .incomplete)).met,
            "two readings are a change with no element named and no notification needed"
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
