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

    func testLayoutChangedEncodeDecode() throws {
        let expectation = ActionExpectation.layoutChanged
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(met: false, expectation: .valueChanged(newValue: "hello"), actual: "counter: world → hell")
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

    func testScreenChangedNotMetWhenDeltaIsValuesChanged() {
        let delta = InterfaceDelta(kind: .valuesChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.screenChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "valuesChanged")
    }

    func testScreenChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = ActionExpectation.screenChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    // MARK: - Validation: layoutChanged

    func testLayoutChangedMetWhenDeltaIsElementsChanged() {
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 10)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.layoutChanged.validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testLayoutChangedNotMetWhenDeltaIsNoChange() {
        let delta = InterfaceDelta(kind: .noChange, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.layoutChanged.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testLayoutChangedMetWhenScreenChanged() {
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 5)
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.layoutChanged.validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: valueChanged

    func testValueChangedNewValueOnlyEncodeDecode() throws {
        let expectation = ActionExpectation.valueChanged(newValue: "5")
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testValueChangedAllFieldsEncodeDecode() throws {
        let expectation = ActionExpectation.valueChanged(heistId: "counter", oldValue: "3", newValue: "5")
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    func testValueChangedNoFieldsEncodeDecode() throws {
        let expectation = ActionExpectation.valueChanged()
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

    // MARK: - Validation: valueChanged

    func testValueChangedMetWhenNewValueMatches() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, heistId: "counter", oldValue: "3", newValue: "5")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testValueChangedNotMetWhenNoMatch() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, heistId: "counter", oldValue: "3", newValue: "4")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
    }

    func testValueChangedMetWhenHeistIdAndNewValueMatch() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [
                ValueChange(order: 0, heistId: "other", oldValue: "1", newValue: "5"),
                ValueChange(order: 1, heistId: "counter", oldValue: "3", newValue: "5"),
            ]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(heistId: "counter", newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testValueChangedNotMetWhenHeistIdDoesNotMatch() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, heistId: "other", oldValue: "3", newValue: "5")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(heistId: "counter", newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
    }

    func testValueChangedMetWhenOldAndNewValueMatch() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, heistId: "counter", oldValue: "3", newValue: "5")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(oldValue: "3", newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testValueChangedNoFieldsMetWhenAnyChangesExist() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, oldValue: "a", newValue: "b")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged().validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testValueChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no value changes")
    }

    func testValueChangedNotMetWhenEmptyValueChanges() {
        let delta = InterfaceDelta(kind: .valuesChanged, elementCount: 5, valueChanges: [])
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no value changes")
    }

    func testValueChangedDiagnosticOnMiss() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 5,
            valueChanges: [ValueChange(order: 0, heistId: "counter", oldValue: "3", newValue: "4")]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: 3 → 4")
    }

    func testValueChangedMatchesAnyAmongMultipleChanges() {
        let delta = InterfaceDelta(
            kind: .valuesChanged, elementCount: 10,
            valueChanges: [
                ValueChange(order: 0, heistId: "label", oldValue: "A", newValue: "B"),
                ValueChange(order: 1, heistId: "counter", oldValue: "3", newValue: "5"),
            ]
        )
        let action = makeResult(success: true, delta: delta)
        let result = ActionExpectation.valueChanged(newValue: "5").validate(against: action)
        XCTAssertTrue(result.met)
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
