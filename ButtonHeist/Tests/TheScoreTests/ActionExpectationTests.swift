import XCTest
@testable import TheScore

final class ActionExpectationTests: XCTestCase {

    // MARK: - Codable Round-Trip

    func testValueEncodeDecode() throws {
        let expectation = ActionExpectation.value("hello")
        let data = try JSONEncoder().encode(expectation)
        let decoded = try JSONDecoder().decode(ActionExpectation.self, from: data)
        XCTAssertEqual(decoded, expectation)
    }

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
        let result = ExpectationResult(met: false, expectation: .value("hello"), actual: "hell")
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

    // MARK: - Validation: value

    func testValueMetWhenMatches() {
        let action = makeResult(success: true, value: "hello")
        let result = ActionExpectation.value("hello").validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "hello")
    }

    func testValueNotMetWhenMismatch() {
        let action = makeResult(success: true, value: "hell")
        let result = ActionExpectation.value("hello").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "hell")
    }

    func testValueNotMetWhenNil() {
        let action = makeResult(success: true, value: nil)
        let result = ActionExpectation.value("hello").validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertNil(result.actual)
    }

    func testValueMetViaElementValue() {
        let action = makeResult(success: true, elementValue: "hello")
        let result = ActionExpectation.value("hello").validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "hello")
    }

    func testValueMetViaElementLabel() {
        let action = makeResult(success: true, elementLabel: "hello")
        let result = ActionExpectation.value("hello").validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "hello")
    }

    func testValuePrefersResultValueOverElementValue() {
        let action = makeResult(success: true, value: "a", elementValue: "b")
        let result = ActionExpectation.value("a").validate(against: action)
        XCTAssertTrue(result.met)
        XCTAssertEqual(result.actual, "a")
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
