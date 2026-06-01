import XCTest
@testable import TheScore

final class AccessibilityPredicateTests: XCTestCase {

    // MARK: - Codable Round-Trip: presence

    func testPresentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.absent(ElementPredicate(label: "Loading")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements)
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Presence Evaluation

    func testPresentMatchesAnyValueFour() {
        let elements = [makeElement(label: "Counter", value: "4")]
        XCTAssertTrue(AccessibilityPredicate.State.present(ElementPredicate(value: "4")).evaluatePresence(in: elements))
    }

    func testPresentNarrowsByIdentifierAndValue() {
        let elements = [
            makeElement(label: "Counter", value: "4", identifier: "slider"),
            makeElement(label: "Other", value: "4", identifier: "knob"),
        ]
        XCTAssertTrue(AccessibilityPredicate.State.present(ElementPredicate(identifier: "slider", value: "4")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.present(ElementPredicate(identifier: "slider", value: "5")).evaluatePresence(in: elements))
    }

    func testAbsentTrueOnlyWhenNoneMatch() {
        let elements = [makeElement(label: "Ready")]
        XCTAssertTrue(AccessibilityPredicate.State.absent(ElementPredicate(label: "Loading")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.absent(ElementPredicate(label: "Ready")).evaluatePresence(in: elements))
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .changed(.updated(ElementUpdatePredicate(to: "hello"))),
            actual: "counter: value: world → hell"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testExpectationResultWithNilPredicateEncodeDecode() throws {
        let result = ExpectationResult(met: true, predicate: nil, actual: "delivered")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testExpectationResultRoundTrip() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .changed(.screen()),
            actual: "noChange"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    // MARK: - Validation: screen changed

    func testScreenChangedMetWhenDeltaIsScreenChanged() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.changed(.screen()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.changed(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = AccessibilityPredicate.changed(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noTrace")
    }

    func testScreenChangedUsesTraceEndpointProjection() {
        let before = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let after = makeTestInterface(elements: [
            HeistElement(
                heistId: "settings_header",
                description: "Settings",
                label: "Settings",
                value: nil,
                identifier: nil,
                traits: [.header],
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            ),
        ])
        let first = AccessibilityTrace.Capture(
            sequence: 1,
            interface: before,
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let last = AccessibilityTrace.Capture(
            sequence: 2,
            interface: after,
            parentHash: first.hash,
            context: AccessibilityTrace.Context(screenId: "settings")
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: AccessibilityTrace(captures: [first, last])
        )

        let outcome = AccessibilityPredicate.changed(.screen()).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertEqual(outcome.actual, "screenChanged")
    }

    func testScreenChangedRequiresTraceEndpointEdge() {
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: AccessibilityTrace(interface: Interface(
                timestamp: Date(timeIntervalSince1970: 0),
                tree: []
            ))
        )

        let outcome = AccessibilityPredicate.changed(.screen()).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noTrace")
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.changed(.elements).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenDeltaIsNoChange() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 5))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.changed(.elements).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedMetWhenScreenChanged() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.changed(.elements).validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(
            element: ElementPredicate(label: "Counter"), property: .value, from: "3", to: "5"
        )))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedNoFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.updated(.any))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() {
        let delta = makeUpdateDelta(heistId: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenNoMatch() {
        let delta = makeUpdateDelta(heistId: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() {
        let baseline: [HeistId: HeistElement] = [
            "other": makeElement(label: "Other"),
            "counter": makeElement(label: "Counter"),
        ]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(heistId: "other", changes: [PropertyChange(property: .value, old: "1", new: "5")]),
            ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")]),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(
            element: ElementPredicate(label: "Counter"), to: "5"
        )))
        XCTAssertTrue(predicate.validate(against: action, preActionElements: baseline).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() {
        let baseline: [HeistId: HeistElement] = ["other": makeElement(label: "Other")]
        let delta = makeUpdateDelta(heistId: "other", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(
            element: ElementPredicate(label: "Counter"), to: "5"
        )))
        XCTAssertFalse(predicate.validate(against: action, preActionElements: baseline).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() {
        let delta = makeUpdateDelta(heistId: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(from: "3", to: "5")))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNoFiltersMetWhenAnyUpdatesExist() {
        let delta = makeUpdateDelta(heistId: "counter", property: .value, old: "a", new: "b")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(.any))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() {
        let delta = makeUpdateDelta(heistId: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits(updated: [
            ElementUpdate(heistId: "label", changes: [PropertyChange(property: .value, old: "A", new: "B")]),
            ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")]),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(to: "5")))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() {
        let baseline: [HeistId: HeistElement] = ["btn": makeElement(label: "Toggle")]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(heistId: "btn", changes: [
                PropertyChange(property: .traits, old: "", new: "selected"),
                PropertyChange(property: .value, old: "3", new: "5"),
            ]),
        ])))
        let action = makeResult(success: true, delta: delta)
        let element = ElementPredicate(label: "Toggle")
        let traitsResult = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(element: element, property: .traits)))
            .validate(against: action, preActionElements: baseline)
        XCTAssertTrue(traitsResult.met)
        let valueResult = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(element: element, property: .value, to: "5")))
            .validate(against: action, preActionElements: baseline)
        XCTAssertTrue(valueResult.met)
        let hintResult = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(element: element, property: .hint)))
            .validate(against: action, preActionElements: baseline)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "btn_1", changes: [PropertyChange(property: .value, old: "OFF", new: "ON")]),
            ]))))
        )
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(property: .value, from: "OFF", to: "ON")))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementUpdatedNoFilters() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "any", changes: [PropertyChange(property: .label, old: "A", new: "B")]),
            ]))))
        )
        XCTAssertTrue(AccessibilityPredicate.changed(.updated(.any)).validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits())))
        )
        let outcome = AccessibilityPredicate.changed(.updated(.any)).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "btn_1", changes: [PropertyChange(property: .label, old: "A", new: "B")]),
            ]))))
        )
        let predicate = AccessibilityPredicate.changed(.updated(ElementUpdatePredicate(property: .value)))
        XCTAssertFalse(predicate.validate(against: result).met)
    }

    // MARK: - element appeared

    func testElementAppearedCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "New Task", traits: [.staticText])))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementAppearedMetWhenMatchFound() {
        let added = [makeElement(label: "New Task", traits: [.staticText])]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: added)))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "New Task", traits: [.staticText])))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementAppearedNotMetWhenNoMatch() {
        let added = [makeElement(label: "Other Item", traits: [.staticText])]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: added)))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "New Task")))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementAppearedNotMetWhenNoAdded() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "New Task")))
        let outcome = predicate.validate(against: action)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no elements added")
    }

    func testElementAppearedNoMatchInAddedDiagnostic() {
        let added = [makeElement(label: "Cancel", traits: [.button])]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: added)))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "Done")))
        let outcome = predicate.validate(against: action)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("Cancel") == true)
    }

    func testElementAppearedMetOnScreenChange() {
        let newElement = makeElement(label: "No receipt", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "No receipt")))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementAppearedNotMetOnScreenChangeWhenAbsent() {
        let otherElement = makeElement(label: "New sale", traits: [.button])
        let newInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.changed(.appeared(ElementPredicate(label: "No receipt")))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "screen changed but element not found in new interface")
    }

    // MARK: - element disappeared

    func testElementDisappearedCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Old Item", traits: [.button])))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementDisappearedMetWhenMatchFound() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 3, edits: ElementEdits(removed: ["button_old"])))
        let action = makeResult(success: true, delta: delta)
        let baseline: [String: HeistElement] = ["button_old": makeElement(label: "Old Item", traits: [.button])]
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Old Item", traits: [.button])))
        XCTAssertTrue(predicate.validate(against: action, preActionElements: baseline).met)
    }

    func testElementDisappearedNotMetWithoutCache() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 3, edits: ElementEdits(removed: ["button_old"])))
        let action = makeResult(success: true, delta: delta)
        // No baseline cache — can't resolve removed ids to a predicate.
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Old Item")))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementDisappearedNoRemovedElements() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits())))
        )
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Remove")))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no elements removed")
    }

    func testElementDisappearedMetOnScreenChange() {
        let baseline: [HeistId: HeistElement] = ["loading": makeElement(label: "Recording payment", traits: [.staticText])]
        let newElement = makeElement(label: "Done", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Recording payment")))
        XCTAssertTrue(predicate.validate(against: result, preActionElements: baseline).met)
    }

    func testElementDisappearedNotMetOnScreenChangeWhenStillPresent() {
        let baseline: [HeistId: HeistElement] = ["persist": makeElement(label: "Header", traits: [.header])]
        let sameElement = makeElement(label: "Header", traits: [.header])
        let newInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.changed(.disappeared(ElementPredicate(label: "Header")))
        let outcome = predicate.validate(against: result, preActionElements: baseline)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "screen changed but element still present in new interface")
    }

    // MARK: - Round-trip across cases

    func testAccessibilityPredicateRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .state(.present(ElementPredicate(label: "Done"))),
            .state(.absent(ElementPredicate(label: "Loading"))),
            .changed(.screen()),
            .changed(.elements),
            .changed(.updated(ElementUpdatePredicate(element: ElementPredicate(label: "btn"), property: .value, from: "A", to: "B"))),
            .changed(.appeared(ElementPredicate(label: "New"))),
            .changed(.disappeared(ElementPredicate(identifier: "old"))),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for predicate in predicates {
            let data = try encoder.encode(predicate)
            let decoded = try decoder.decode(AccessibilityPredicate.self, from: data)
            XCTAssertEqual(decoded, predicate)
        }
    }

    // MARK: - Decode Errors

    func testDecodeRejectsUnknownType() {
        let json = Data(#"{"type": "rainbow"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected .dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("rainbow"))
        }
    }

    func testDecodeRejectsMissingType() {
        let json = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json))
    }

    func testAppearedElementRejectsUnknownFieldAtCodableBoundary() {
        let json = Data(#"{"type":"element_appeared","element":{"label":"Save","unexpectedTargetField":"button_save"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
        }
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: identifier ?? label ?? "",
            description: label ?? "",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }

    private func makeUpdateDelta(
        heistId: HeistId,
        property: ElementProperty,
        old: String?,
        new: String?,
        elementCount: Int = 5
    ) -> AccessibilityTrace.Delta {
        .elementsChanged(.init(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                ElementUpdate(
                    heistId: heistId,
                    changes: [PropertyChange(property: property, old: old, new: new)]
                ),
            ])
        ))
    }

    private func makeResult(
        success: Bool,
        message: String? = nil,
        value: String? = nil,
        delta: AccessibilityTrace.Delta? = nil
    ) -> ActionResult {
        ActionResult(
            success: success,
            method: .syntheticTap,
            message: message,
            payload: value.map { .value($0) },
            accessibilityTrace: delta.map(AccessibilityTrace.projectingForTests)
        )
    }
}
