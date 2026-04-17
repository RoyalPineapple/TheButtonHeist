import XCTest
@testable import TheScore

final class ActionExpectationTests: XCTestCase {

    // MARK: - Codable Round-Trip

    func testScreenChangedEncodeDecode() throws {
        let expectation = ActionExpectation.screenChanged
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementsChangedEncodeDecode() throws {
        let expectation = ActionExpectation.elementsChanged
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(met: false, expectation: .elementUpdated(newValue: "hello"), actual: "counter: value: world → hell")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testExpectationResultWithNilExpectationEncodeDecode() throws {
        let result = ExpectationResult(met: true, expectation: nil, actual: "delivered")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    // MARK: - Implicit Delivery Validation

    func testDeliveryMetWhenSuccess() {
        let action = makeResult(success: true)
        let result = ActionExpectation.validateDelivery(action)
        XCTAssertTrue(result.met)
        XCTAssertNil(result.expectation)
        XCTAssertEqual(result.actual, "delivered")
    }

    func testDeliveryNotMetWhenFailed() {
        let action = makeResult(success: false, message: "element not found")
        let result = ActionExpectation.validateDelivery(action)
        XCTAssertFalse(result.met)
        XCTAssertNil(result.expectation)
        XCTAssertEqual(result.actual, "element not found")
    }

    // MARK: - Validation: screenChanged

    func testScreenChangedMetWhenDeltaIsScreenChanged() {
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.screenChanged.validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenDeltaIsElementsChanged() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.screenChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = ActionExpectation.screenChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    // MARK: - Validation: elementsChanged

    func testElementsChangedMetWhenDeltaIsElementsChanged() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 10)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementsChanged.validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenDeltaIsNoChange() {
        let delta = InterfaceDelta(kind: .noChange, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementsChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedMetWhenScreenChanged() {
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementsChanged.validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: elementUpdated

    func testElementUpdatedNewValueOnlyEncodeDecode() throws {
        let expectation = ActionExpectation.elementUpdated(newValue: "5")
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let expectation = ActionExpectation.elementUpdated(heistId: "counter", property: .value, oldValue: "3", newValue: "5")
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementUpdatedNoFieldsEncodeDecode() throws {
        let expectation = ActionExpectation.elementUpdated()
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    // MARK: - Validation: elementUpdated

    func testElementUpdatedMetWhenNewValueMatches() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementUpdatedNotMetWhenNoMatch() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "4")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
    }

    func testElementUpdatedMetWhenHeistIdAndNewValueMatch() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [
                ElementUpdate(heistId: "other", changes: [PropertyChange(property: .value, old: "1", new: "5")]),
                ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")]),
            ]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(heistId: "counter", newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementUpdatedNotMetWhenHeistIdDoesNotMatch() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "other", changes: [PropertyChange(property: .value, old: "3", new: "5")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(heistId: "counter", newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(oldValue: "3", newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementUpdatedNoFieldsMetWhenAnyUpdatesExist() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "a", new: "b")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated().validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementUpdatedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5, updated: [])
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "4")])]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 10,
            updated: [
                ElementUpdate(heistId: "label", changes: [PropertyChange(property: .value, old: "A", new: "B")]),
                ElementUpdate(heistId: "counter", changes: [PropertyChange(property: .value, old: "3", new: "5")]),
            ]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementUpdated(newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementUpdatedWithPropertyFilter() {
        let delta = InterfaceDelta(
            kind: .elementsChanged, elementCount: 5,
            updated: [ElementUpdate(heistId: "btn", changes: [
                PropertyChange(property: .traits, old: "", new: "selected"),
                PropertyChange(property: .value, old: "3", new: "5"),
            ])]
        )
        let action = makeResult(success: true, delta: delta)
        let traitsResult = ActionExpectation.elementUpdated(heistId: "btn", property: .traits).validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valueResult = ActionExpectation.elementUpdated(heistId: "btn", property: .value, newValue: "5").validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintResult = ActionExpectation.elementUpdated(heistId: "btn", property: .hint).validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    // MARK: - elementAppeared

    func testElementAppearedCodableRoundTrip() throws {
        let expectation = ActionExpectation.elementAppeared(
            ElementMatcher(label: "New Task", traits: [.staticText])
        )
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementAppearedMetWhenMatchFound() {
        let added = [makeElement(label: "New Task", traits: [.staticText])]
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5, added: added)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementAppeared(
            ElementMatcher(label: "New Task", traits: [.staticText])
        ).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementAppearedNotMetWhenNoMatch() {
        let added = [makeElement(label: "Other Item", traits: [.staticText])]
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5, added: added)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementAppeared(
            ElementMatcher(label: "New Task")
        ).validate(against: action)
        XCTAssertFalse(result.met)
    }

    func testElementAppearedNotMetWhenNoAdded() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.elementAppeared(
            ElementMatcher(label: "New Task")
        ).validate(against: action)
        XCTAssertFalse(result.met)
    }

    // MARK: - elementDisappeared

    func testElementDisappearedCodableRoundTrip() throws {
        let expectation = ActionExpectation.elementDisappeared(
            ElementMatcher(label: "Old Item", traits: [.button])
        )
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementDisappearedMetWhenMatchFound() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 3, removed: ["button_old"])
        let action = makeResult(success: true, delta: delta)
        let preAction: [String: HeistElement] = [
            "button_old": makeElement(label: "Old Item", traits: [.button]),
        ]
        let result = ActionExpectation.elementDisappeared(
            ElementMatcher(label: "Old Item", traits: [.button])
        ).validate(against: action, preActionElements: preAction)
        XCTAssertTrue(result.met)
    }

    func testElementDisappearedNotMetWithoutCache() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 3, removed: ["button_old"])
        let action = makeResult(success: true, delta: delta)
        // No pre-action cache — can't resolve removed heistIds
        let result = ActionExpectation.elementDisappeared(
            ElementMatcher(label: "Old Item")
        ).validate(against: action)
        XCTAssertFalse(result.met)
    }

    // MARK: - compound

    func testCompoundCodableRoundTrip() throws {
        let expectation = ActionExpectation.compound([
            .elementsChanged,
            .elementAppeared(ElementMatcher(label: "New", traits: [.staticText])),
        ])
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testCompoundAllMet() {
        let added = [makeElement(label: "New Task", traits: [.staticText])]
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5, added: added)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.compound([
            .elementsChanged,
            .elementAppeared(ElementMatcher(label: "New Task", traits: [.staticText])),
        ]).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testCompoundFailsIfAnyUnmet() {
        let added = [makeElement(label: "New Task", traits: [.staticText])]
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 5, added: added)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.compound([
            .elementsChanged,
            .elementAppeared(ElementMatcher(label: "Missing Element")),
        ]).validate(against: action)
        XCTAssertFalse(result.met)
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: "",
            description: label ?? "",
            label: label,
            value: nil,
            identifier: nil,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }

    private func makeResult(
        success: Bool,
        message: String? = nil,
        value: String? = nil,
        delta: InterfaceDelta? = nil,
        elementLabel: String? = nil,
        elementValue: String? = nil
    ) -> ActionResult {
        ActionResult(
            success: success,
            method: .syntheticTap,
            message: message,
            value: value,
            interfaceDelta: delta,
            elementLabel: elementLabel,
            elementValue: elementValue
        )
        // Note: animating param omitted (defaults to nil)
    }

    // MARK: - Wire Format: explicit `type` discriminator (protocol v7.0)

    func testWireFormatScreenChanged() throws {
        let data = try JSONEncoder().encode(ActionExpectation.screenChanged)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "screen_changed")
        XCTAssertEqual(dictionary?.count, 1, "screen_changed carries no payload fields")
    }

    func testWireFormatElementsChanged() throws {
        let data = try JSONEncoder().encode(ActionExpectation.elementsChanged)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "elements_changed")
        XCTAssertEqual(dictionary?.count, 1)
    }

    func testWireFormatElementUpdated() throws {
        let expectation = ActionExpectation.elementUpdated(
            heistId: "btn-Submit", property: .value, oldValue: "old", newValue: "new"
        )
        let data = try JSONEncoder().encode(expectation)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "element_updated")
        XCTAssertEqual(dictionary?["heistId"] as? String, "btn-Submit")
        XCTAssertEqual(dictionary?["property"] as? String, "value")
        XCTAssertEqual(dictionary?["oldValue"] as? String, "old")
        XCTAssertEqual(dictionary?["newValue"] as? String, "new")
    }

    func testWireFormatElementUpdatedOmitsMissingFields() throws {
        let expectation = ActionExpectation.elementUpdated(newValue: "only")
        let data = try JSONEncoder().encode(expectation)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "element_updated")
        XCTAssertEqual(dictionary?["newValue"] as? String, "only")
        XCTAssertNil(dictionary?["heistId"])
        XCTAssertNil(dictionary?["property"])
        XCTAssertNil(dictionary?["oldValue"])
    }

    func testWireFormatElementAppeared() throws {
        let matcher = ElementMatcher(label: "Sign In", traits: [.button])
        let data = try JSONEncoder().encode(ActionExpectation.elementAppeared(matcher))
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "element_appeared")
        XCTAssertNotNil(dictionary?["matcher"] as? [String: Any])
    }

    func testWireFormatElementDisappeared() throws {
        let matcher = ElementMatcher(identifier: "loading-spinner")
        let data = try JSONEncoder().encode(ActionExpectation.elementDisappeared(matcher))
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "element_disappeared")
        XCTAssertNotNil(dictionary?["matcher"] as? [String: Any])
    }

    func testWireFormatCompound() throws {
        let expectation = ActionExpectation.compound([.screenChanged, .elementsChanged])
        let data = try JSONEncoder().encode(expectation)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dictionary?["type"] as? String, "compound")
        let inner = dictionary?["expectations"] as? [[String: Any]]
        XCTAssertEqual(inner?.count, 2)
        XCTAssertEqual(inner?[0]["type"] as? String, "screen_changed")
        XCTAssertEqual(inner?[1]["type"] as? String, "elements_changed")
    }

    // MARK: - Round-Trip: associated-value and recursive cases

    func testElementAppearedRoundTrip() throws {
        let matcher = ElementMatcher(label: "OK", identifier: "btn-ok", traits: [.button])
        let expectation = ActionExpectation.elementAppeared(matcher)
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testElementDisappearedRoundTrip() throws {
        let matcher = ElementMatcher(value: "Loading…", excludeTraits: [.selected])
        let expectation = ActionExpectation.elementDisappeared(matcher)
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testCompoundRoundTrip() throws {
        let expectation = ActionExpectation.compound([
            .screenChanged,
            .elementUpdated(heistId: "counter", property: .value, newValue: "5"),
            .elementAppeared(ElementMatcher(label: "Success")),
        ])
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testNestedCompoundRoundTrip() throws {
        let expectation = ActionExpectation.compound([
            .compound([.screenChanged, .elementsChanged]),
            .elementAppeared(ElementMatcher(identifier: "deep")),
        ])
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    // MARK: - Decode Errors

    func testDecodeRejectsUnknownType() {
        let json = #"{"type": "rainbow"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ActionExpectation.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected .dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("rainbow"))
        }
    }

    func testDecodeRejectsMissingType() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ActionExpectation.self, from: json))
    }
}
