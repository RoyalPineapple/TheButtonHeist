import XCTest
import ThePlans
@testable import TheScore

final class AccessibilityPredicateTests: XCTestCase {

    // MARK: - Codable Round-Trip: presence

    func testPresentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.missing(ElementPredicate(label: "Loading")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Presence Evaluation

    func testPresentMatchesAnyValueFour() {
        let elements = [makeElement(label: "Counter", value: "4")]
        XCTAssertTrue(AccessibilityPredicate.State.exists(ElementPredicate(value: "4")).evaluatePresence(in: elements))
    }

    func testPresentNarrowsByIdentifierAndValue() {
        let elements = [
            makeElement(label: "Counter", value: "4", identifier: "slider"),
            makeElement(label: "Other", value: "4", identifier: "knob"),
        ]
        XCTAssertTrue(AccessibilityPredicate.State.exists(ElementPredicate(identifier: "slider", value: "4")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.exists(ElementPredicate(identifier: "slider", value: "5")).evaluatePresence(in: elements))
    }

    func testAbsentTrueOnlyWhenNoneMatch() {
        let elements = [makeElement(label: "Ready")]
        XCTAssertTrue(AccessibilityPredicate.State.missing(ElementPredicate(label: "Loading")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.missing(ElementPredicate(label: "Ready")).evaluatePresence(in: elements))
    }

    func testStatePredicateRequiresObservedTraceForActionResultValidation() {
        let action = ActionResult(success: true, method: .activate)
        let result = AccessibilityPredicate.state(.missing(ElementPredicate(label: "Loading"))).validate(against: action)

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "hello"))))),
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
            predicate: .change(.screen()),
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
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testScreenChangedUsesTraceEndpointProjection() {
        let before = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let after = makeTestInterface(elements: [
            HeistElement(
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

        let outcome = AccessibilityPredicate.change(.screen()).validate(against: result)

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

        let outcome = AccessibilityPredicate.change(.screen()).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noTrace")
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenDeltaIsNoChange() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 5))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedNotMetWhenScreenChanged() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(before: "3", after: "5")
        ))))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedNoFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(.any)))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedPassReportsObservedPropertyProof() {
        let delta = makeUpdateDelta(label: "Quantity", property: .value, old: "2", new: "3")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Quantity"),
            change: .value(before: "2", after: "3")
        ))))
        let result = predicate.validate(against: action)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testElementUpdatedDoesNotPassWhenCurrentValueAlreadyMatchedWithoutDeltaEvidence() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 1))
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Quantity"),
            change: .value(before: "3", after: "3")
        ))))
        let result = predicate.evaluate(
            currentElements: [makeElement(label: "Quantity", value: "3")],
            delta: delta
        )

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementUpdatedNotMetWhenNoMatch() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            makeUpdate(label: "Other", property: .value, old: "1", new: "5"),
            makeUpdate(label: "Counter", property: .value, old: "3", new: "5"),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(after: "5")
        ))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() {
        let delta = makeUpdateDelta(label: "Other", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(after: "5")
        ))))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(before: "3", after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForOldAndNewValues() {
        let delta = makeUpdateDelta(label: "cart", property: .value, old: "cart: empty", new: "3 items")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .value(before: .prefix("cart:"), after: .suffix("items"))
        ))))

        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForEveryModeAcrossBeforeAndAfter() {
        let delta = makeUpdateDelta(label: "Search Field", property: .value, old: "Search for tea", new: "John Smith")
        let action = makeResult(success: true, delta: delta)
        let predicates = [
            ElementUpdatePredicate(change: .value(before: .exact("Search for tea"), after: .exact("John Smith"))),
            ElementUpdatePredicate(change: .value(before: .contains("for"), after: .contains("Smith"))),
            ElementUpdatePredicate(change: .value(before: .prefix("Search"), after: .prefix("John"))),
            ElementUpdatePredicate(change: .value(before: .suffix("tea"), after: .suffix("Smith"))),
        ]

        for update in predicates {
            XCTAssertTrue(AccessibilityPredicate.change(.elements(.updatedElement(update))).validate(against: action).met)
        }
    }

    func testElementUpdatedMatchesTraitGainAndLossAcrossBeforeAndAfter() {
        let gained = makeTraitUpdate(label: "Favorites", beforeTraits: [.button], afterTraits: [.button, .selected])
        let lost = makeTraitUpdate(label: "Disabled", beforeTraits: [.button, .notEnabled], afterTraits: [.button])
        let action = makeResult(success: true, delta: .elementsChanged(.init(elementCount: 2, edits: ElementEdits(updated: [gained, lost]))))

        let selectedGain = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .traits(before: .exclude([.selected]), after: .include([.selected]))
        ))))
        let enabledLoss = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .traits(before: .include([.notEnabled]), after: .exclude([.notEnabled]))
        ))))

        XCTAssertTrue(selectedGain.validate(against: action).met)
        XCTAssertTrue(enabledLoss.validate(against: action).met)
    }

    func testElementUpdatedNoFiltersMetWhenAnyUpdatesExist() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "a", new: "b")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(.any)))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits(updated: [
            makeUpdate(label: "label", property: .value, old: "A", new: "B"),
            makeUpdate(label: "counter", property: .value, old: "3", new: "5"),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(
                before: makeElement(label: "Toggle", traits: [.button]),
                after: makeElement(label: "Toggle", value: "5", traits: [.button, .selected]),
                changes: [
                    PropertyChange(property: .traits, old: "", new: "selected"),
                    PropertyChange(property: .value, old: "3", new: "5"),
                ]
            ),
        ])))
        let action = makeResult(success: true, delta: delta)
        let element = ElementPredicate(label: "Toggle")
        let traitsResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(element: element, change: .traits()))))
            .validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valueResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: element,
            change: .value(after: "5")
        ))))
            .validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(element: element, change: .hint()))))
            .validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "btn_1", property: .value, old: "OFF", new: "ON"),
            ]))))
        )
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .value(before: "OFF", after: "ON")
        ))))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementUpdatedNoFilters() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "any", property: .value, old: "A", new: "B"),
            ]))))
        )
        XCTAssertTrue(AccessibilityPredicate.change(.elements(.updatedElement(.any))).validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits())))
        )
        let outcome = AccessibilityPredicate.change(.elements(.updatedElement(.any))).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "btn_1", property: .hint, old: "A", new: "B"),
            ]))))
        )
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value()))))
        XCTAssertFalse(predicate.validate(against: result).met)
    }

    // MARK: - final state predicates

    func testPresentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "New Task", traits: [.staticText]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testPresentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "No receipt", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "No receipt"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testPresentNotMetAgainstFinalInterfaceWhenAbsent() {
        let otherElement = makeElement(label: "New sale", traits: [.button])
        let newInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "No receipt"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, #"no element matches predicate(label="No receipt")"#)
    }

    func testAbsentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Old Item", traits: [.button]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "Done", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Recording payment"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testAbsentNotMetAgainstFinalInterfaceWhenStillPresent() {
        let sameElement = makeElement(label: "Header", traits: [.header])
        let newInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Header"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, #"still present: predicate(label="Header")"#)
    }

    // MARK: - Round-trip across cases

    func testAccessibilityPredicateRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .state(.exists(ElementPredicate(label: "Done"))),
            .state(.missing(ElementPredicate(label: "Loading"))),
            .change(.screen()),
            .change(.elements()),
            .change(.elements(.updatedElement(ElementUpdatePredicate(
                element: .label("btn"),
                change: .value(before: "A", after: "B")
            )))),
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

    func testRemovedElementTransitionPredicatesRejectAtCodableBoundary() {
        let json = Data(#"{"type":"appeared","element":{"label":"Save"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("appeared"), "\(error)")
        }
    }

    func testEmptyAllStateRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"all","states":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyStateAll.decodingDescription), "\(error)")
        }

        let predicate = AccessibilityPredicate.state(.all([]))
        XCTAssertThrowsError(try JSONEncoder().encode(predicate)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyStateAll.encodingDescription), "\(error)")
        }

        XCTAssertThrowsError(try JSONEncoder().encode(AccessibilityPredicate.State.all([]))) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyStateAll.encodingDescription), "\(error)")
        }
    }

    func testEmptyAllChangeScopeRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"change","scopes":[{"type":"all","scopes":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyChangeAllScope.decodingDescription), "\(error)")
        }

        let predicate = AccessibilityPredicate.change(.allScopes([]))
        XCTAssertThrowsError(try JSONEncoder().encode(predicate)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyChangeAllScope.encodingDescription), "\(error)")
        }

        XCTAssertThrowsError(try JSONEncoder().encode(AccessibilityPredicate.Change.allScopes([]))) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.emptyChangeAllScope.encodingDescription), "\(error)")
        }
    }

    func testNestedAnyChangeScopeRejectsAtCodableBoundary() {
        let predicate = AccessibilityPredicate.change(.allScopes([.any]))
        XCTAssertThrowsError(try JSONEncoder().encode(predicate)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.unsupportedAnyChangeScope.encodingDescription), "\(error)")
        }

        XCTAssertThrowsError(try JSONEncoder().encode(AccessibilityPredicate.Change.any)) { error in
            XCTAssertTrue("\(error)".contains(AccessibilityPredicateContract.Violation.unsupportedAnyChangeScope.encodingDescription), "\(error)")
        }
    }

    func testUnsupportedPredicateContractsEvaluateAsNotMet() {
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 1,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))

        let emptyState = AccessibilityPredicate.state(.all([])).evaluate(currentElements: [])
        XCTAssertFalse(emptyState.met)
        XCTAssertEqual(emptyState.actual, AccessibilityPredicateContract.Violation.emptyStateAll.evaluationDescription)

        let emptyAll = AccessibilityPredicate.change(.allScopes([])).evaluate(currentElements: [], delta: delta)
        XCTAssertFalse(emptyAll.met)
        XCTAssertEqual(emptyAll.actual, AccessibilityPredicateContract.Violation.emptyChangeAllScope.evaluationDescription)

        let nestedAny = AccessibilityPredicate.change(.allScopes([.any])).evaluate(currentElements: [], delta: delta)
        XCTAssertFalse(nestedAny.met)
        XCTAssertEqual(nestedAny.actual, AccessibilityPredicateContract.Violation.unsupportedAnyChangeScope.evaluationDescription)
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            description: label ?? "",
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }

    private func makeUpdateDelta(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        elementCount: Int = 5
    ) -> AccessibilityTrace.Delta {
        .elementsChanged(.init(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                makeUpdate(label: label, property: property, old: old, new: new),
            ])
        ))
    }

    private func makeUpdate(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait] = [],
        afterTraits: [HeistTrait] = []
    ) -> ElementUpdate {
        ElementUpdate(
            before: makeElementForUpdate(label: label, property: property, value: old, traits: beforeTraits),
            after: makeElementForUpdate(label: label, property: property, value: new, traits: afterTraits),
            changes: [PropertyChange(property: property, old: old, new: new)]
        )
    }

    private func makeTraitUpdate(
        label: String,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) -> ElementUpdate {
        ElementUpdate(
            before: makeElement(label: label, traits: beforeTraits),
            after: makeElement(label: label, traits: afterTraits),
            changes: [
                PropertyChange(
                    property: .traits,
                    old: beforeTraits.map(\.rawValue).joined(separator: ", "),
                    new: afterTraits.map(\.rawValue).joined(separator: ", ")
                ),
            ]
        )
    }

    private func makeElementForUpdate(
        label: String,
        property: ElementProperty,
        value: String?,
        traits: [HeistTrait]
    ) -> HeistElement {
        switch property {
        case .value:
            return makeElement(label: label, value: value, traits: traits)
        case .traits:
            return makeElement(label: label, traits: traits)
        case .hint:
            return makeElement(label: label, hint: value, traits: traits)
        default:
            return makeElement(label: label, value: value, traits: traits)
        }
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
