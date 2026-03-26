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

    // MARK: - Helpers

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
}
