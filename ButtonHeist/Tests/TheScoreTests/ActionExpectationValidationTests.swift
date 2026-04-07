import XCTest
@testable import TheScore

final class ActionExpectationValidationTests: XCTestCase {

    // MARK: - validateDelivery

    func testValidateDeliverySuccess() {
        let result = ActionResult(success: true, method: .activate)
        let expectation = ActionExpectation.validateDelivery(result)
        XCTAssertTrue(expectation.met)
        XCTAssertNil(expectation.expectation)
    }

    func testValidateDeliveryFailure() {
        let result = ActionResult(success: false, method: .activate, message: "element not found")
        let expectation = ActionExpectation.validateDelivery(result)
        XCTAssertFalse(expectation.met)
        XCTAssertEqual(expectation.actual, "element not found")
    }

    func testValidateDeliveryFailureNoMessage() {
        let result = ActionResult(success: false, method: .activate)
        let expectation = ActionExpectation.validateDelivery(result)
        XCTAssertFalse(expectation.met)
        XCTAssertEqual(expectation.actual, "failed")
    }

    // MARK: - screenChanged

    func testScreenChangedMet() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .screenChanged, elementCount: 5)
        )
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testScreenChangedNotMetByElementsChanged() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "elementsChanged")
    }

    func testScreenChangedNotMetByNoChange() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .noChange, elementCount: 5)
        )
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    func testScreenChangedNotMetByNilDelta() {
        let result = ActionResult(success: true, method: .activate)
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noChange")
    }

    // MARK: - elementsChanged (superset rule)

    func testElementsChangedMetByElementsChanged() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementsChangedMetByScreenChanged() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .screenChanged, elementCount: 5)
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementsChangedNotMetByNoChange() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .noChange, elementCount: 5)
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    // MARK: - elementUpdated

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                updated: [
                    ElementUpdate(heistId: "btn_1", changes: [
                        PropertyChange(property: .value, old: "OFF", new: "ON"),
                    ]),
                ]
            )
        )
        let expectation = ActionExpectation.elementUpdated(
            heistId: "btn_1", property: .value, oldValue: "OFF", newValue: "ON"
        )
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementUpdatedNoFilters() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                updated: [
                    ElementUpdate(heistId: "any", changes: [
                        PropertyChange(property: .label, old: "A", new: "B"),
                    ]),
                ]
            )
        )
        let expectation = ActionExpectation.elementUpdated()
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementUpdatedHeistIdMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                updated: [
                    ElementUpdate(heistId: "btn_2", changes: [
                        PropertyChange(property: .value, old: "A", new: "B"),
                    ]),
                ]
            )
        )
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1")
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1")
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                updated: [
                    ElementUpdate(heistId: "btn_1", changes: [
                        PropertyChange(property: .label, old: "A", new: "B"),
                    ]),
                ]
            )
        )
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1", property: .value)
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    // MARK: - elementAppeared

    func testElementAppearedMet() {
        let addedElement = HeistElement(
            heistId: "new_btn", description: "Done",
            label: "Done", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                added: [addedElement]
            )
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "Done"))
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementAppearedNoAddedElements() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "Done"))
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no elements added")
    }

    func testElementAppearedNoMatchInAdded() {
        let addedElement = HeistElement(
            heistId: "other", description: "Cancel",
            label: "Cancel", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                added: [addedElement]
            )
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "Done"))
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("Cancel") == true)
    }

    // MARK: - elementDisappeared

    func testElementDisappearedMet() {
        let preActionElements: [String: HeistElement] = [
            "old_btn": HeistElement(
                heistId: "old_btn", description: "Remove",
                label: "Remove", value: nil, identifier: nil,
                traits: [.button],
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: [.activate]
            ),
        ]
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 3,
                removed: ["old_btn"]
            )
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Remove"))
        let outcome = expectation.validate(against: result, preActionElements: preActionElements)
        XCTAssertTrue(outcome.met)
    }

    func testElementDisappearedNoRemovedElements() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Remove"))
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no elements removed")
    }

    func testElementDisappearedNoPreActionCache() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(
                kind: .elementsChanged, elementCount: 5,
                removed: ["unknown_id"]
            )
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Gone"))
        let outcome = expectation.validate(against: result, preActionElements: [:])
        XCTAssertFalse(outcome.met)
    }

    // MARK: - compound

    func testCompoundAllMet() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .screenChanged, elementCount: 5)
        )
        let expectation = ActionExpectation.compound([
            .screenChanged,
            .elementsChanged,
        ])
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testCompoundPartialFailure() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: InterfaceDelta(kind: .elementsChanged, elementCount: 5)
        )
        let expectation = ActionExpectation.compound([
            .elementsChanged,
            .screenChanged,
        ])
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("screen_changed") == true)
    }

    func testCompoundEmpty() {
        let result = ActionResult(success: true, method: .activate)
        let expectation = ActionExpectation.compound([])
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    // MARK: - ActionExpectation Codable

    func testActionExpectationRoundTrip() throws {
        let expectations: [ActionExpectation] = [
            .screenChanged,
            .elementsChanged,
            .elementUpdated(heistId: "btn", property: .value, oldValue: "A", newValue: "B"),
            .elementAppeared(ElementMatcher(label: "New")),
            .elementDisappeared(ElementMatcher(identifier: "old")),
            .compound([.screenChanged, .elementsChanged]),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for expectation in expectations {
            let data = try encoder.encode(expectation)
            let decoded = try decoder.decode(ActionExpectation.self, from: data)
            XCTAssertEqual(decoded, expectation)
        }
    }

    // MARK: - ExpectationResult Codable

    func testExpectationResultRoundTrip() throws {
        let result = ExpectationResult(
            met: false,
            expectation: .screenChanged,
            actual: "noChange"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }
}
