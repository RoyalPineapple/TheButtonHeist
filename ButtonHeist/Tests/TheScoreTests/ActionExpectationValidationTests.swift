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
            interfaceDelta: .screenChanged(.init(elementCount: 5, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])))
        )
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testScreenChangedNotMetByElementsChanged() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        )
        let outcome = ActionExpectation.screenChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "elementsChanged")
    }

    func testScreenChangedNotMetByNoChange() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .noChange(.init(elementCount: 5))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementsChangedMetByScreenChanged() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .screenChanged(.init(elementCount: 5, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])))
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementsChangedNotMetByNoChange() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .noChange(.init(elementCount: 5))
        )
        let outcome = ActionExpectation.elementsChanged.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    // MARK: - elementUpdated

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                    ElementUpdate(heistId: "btn_1", changes: [
                        PropertyChange(property: .value, old: "OFF", new: "ON"),
                    ]),
                ])))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                    ElementUpdate(heistId: "any", changes: [
                        PropertyChange(property: .label, old: "A", new: "B"),
                    ]),
                ])))
        )
        let expectation = ActionExpectation.elementUpdated()
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementUpdatedHeistIdMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                    ElementUpdate(heistId: "btn_2", changes: [
                        PropertyChange(property: .value, old: "A", new: "B"),
                    ]),
                ])))
        )
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1")
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        )
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1")
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                    ElementUpdate(heistId: "btn_1", changes: [
                        PropertyChange(property: .label, old: "A", new: "B"),
                    ]),
                ])))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: [addedElement])))
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "Done"))
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementAppearedNoAddedElements() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: [addedElement])))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 3, edits: ElementEdits(removed: ["old_btn"])))
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Remove"))
        let outcome = expectation.validate(against: result, preActionElements: preActionElements)
        XCTAssertTrue(outcome.met)
    }

    func testElementDisappearedNoRemovedElements() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Remove"))
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no elements removed")
    }

    func testElementDisappearedNoPreActionCache() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits(removed: ["unknown_id"])))
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Gone"))
        let outcome = expectation.validate(against: result, preActionElements: [:])
        XCTAssertFalse(outcome.met)
    }

    // MARK: - elementAppeared (screen change)

    func testElementAppearedMetOnScreenChange() {
        let newElement = HeistElement(
            heistId: "no_receipt", description: "No receipt",
            label: "No receipt", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let newInterface = Interface(
            timestamp: Date(), tree: [.element(newElement)]
        )
        let result = ActionResult(
            success: true, method: .waitForChange,
            interfaceDelta: .screenChanged(.init(elementCount: 1, newInterface: newInterface))
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "No receipt"))
        let outcome = expectation.validate(against: result)
        XCTAssertTrue(outcome.met)
    }

    func testElementAppearedNotMetOnScreenChangeWhenAbsent() {
        let otherElement = HeistElement(
            heistId: "new_sale", description: "New sale",
            label: "New sale", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let newInterface = Interface(
            timestamp: Date(), tree: [.element(otherElement)]
        )
        let result = ActionResult(
            success: true, method: .waitForChange,
            interfaceDelta: .screenChanged(.init(elementCount: 1, newInterface: newInterface))
        )
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "No receipt"))
        let outcome = expectation.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "screen changed but element not found in new interface")
    }

    // MARK: - elementDisappeared (screen change)

    func testElementDisappearedMetOnScreenChange() {
        let preActionElements: [String: HeistElement] = [
            "loading": HeistElement(
                heistId: "loading", description: "Recording payment",
                label: "Recording payment", value: nil, identifier: nil,
                traits: [.staticText],
                frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 44,
                actions: []
            ),
        ]
        let newElement = HeistElement(
            heistId: "done", description: "Done",
            label: "Done", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let newInterface = Interface(
            timestamp: Date(), tree: [.element(newElement)]
        )
        let result = ActionResult(
            success: true, method: .waitForChange,
            interfaceDelta: .screenChanged(.init(elementCount: 1, newInterface: newInterface))
        )
        let expectation = ActionExpectation.elementDisappeared(
            ElementMatcher(label: "Recording payment")
        )
        let outcome = expectation.validate(against: result, preActionElements: preActionElements)
        XCTAssertTrue(outcome.met)
    }

    func testElementDisappearedNotMetOnScreenChangeWhenStillPresent() {
        let preActionElements: [String: HeistElement] = [
            "persist": HeistElement(
                heistId: "persist", description: "Header",
                label: "Header", value: nil, identifier: nil,
                traits: [.header],
                frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 44,
                actions: []
            ),
        ]
        let sameElement = HeistElement(
            heistId: "persist", description: "Header",
            label: "Header", value: nil, identifier: nil,
            traits: [.header],
            frameX: 0, frameY: 0, frameWidth: 200, frameHeight: 44,
            actions: []
        )
        let newInterface = Interface(
            timestamp: Date(), tree: [.element(sameElement)]
        )
        let result = ActionResult(
            success: true, method: .waitForChange,
            interfaceDelta: .screenChanged(.init(elementCount: 1, newInterface: newInterface))
        )
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(label: "Header"))
        let outcome = expectation.validate(against: result, preActionElements: preActionElements)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "screen changed but element still present in new interface")
    }

    // MARK: - compound

    func testCompoundAllMet() {
        let result = ActionResult(
            success: true, method: .activate,
            interfaceDelta: .screenChanged(.init(elementCount: 5, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])))
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
            interfaceDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
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
