import XCTest
@testable import TheScore

// MARK: - Interface computed properties, slugify, isStableIdentifier

final class InterfaceComputedTests: XCTestCase {

    // MARK: - slugify

    func testSlugifyBasic() {
        XCTAssertEqual(slugify("Controls Demo"), "controls_demo")
    }

    func testSlugifyNilReturnsNil() {
        XCTAssertNil(slugify(nil))
    }

    func testSlugifyEmptyReturnsNil() {
        XCTAssertNil(slugify(""))
    }

    func testSlugifyAllSpecialCharsReturnsNil() {
        XCTAssertNil(slugify("!!!@@@###"))
    }

    func testSlugifyTrimsUnderscores() {
        XCTAssertEqual(slugify("  Hello World  "), "hello_world")
    }

    func testSlugifyCapsAt24() {
        let long = "This Is A Very Long Screen Name That Exceeds The Limit"
        let result = slugify(long)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result?.count ?? 0, 24)
    }

    func testSlugifyLowercase() {
        XCTAssertEqual(slugify("Settings"), "settings")
    }

    func testSlugifySpecialCharsBecomUnderscore() {
        XCTAssertEqual(slugify("foo-bar.baz"), "foo_bar_baz")
    }

    // MARK: - isStableIdentifier

    func testStableIdentifierReturnsTrueForNormal() {
        XCTAssertTrue(isStableIdentifier("save_button"))
        XCTAssertTrue(isStableIdentifier("btnSubmit"))
        XCTAssertTrue(isStableIdentifier("cell_0"))
    }

    func testStableIdentifierReturnsFalseForUUID() {
        XCTAssertFalse(isStableIdentifier("view-A1B2C3D4-E5F6-7890-ABCD-EF1234567890"))
        XCTAssertFalse(isStableIdentifier("12345678-1234-1234-1234-123456789abc"))
    }

    func testStableIdentifierPartialUUIDIsStable() {
        XCTAssertTrue(isStableIdentifier("12345678-1234"))
        XCTAssertTrue(isStableIdentifier("not-a-uuid-at-all"))
    }

    // MARK: - Interface.screenDescription

    func testScreenDescriptionWithHeaderAndButtons() {
        let elements = [
            makeElement(label: "Settings", traits: [.header]),
            makeElement(label: "Save", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "Settings — 2 buttons")
    }

    func testScreenDescriptionNoHeaderShowsCounts() {
        let elements = [
            makeElement(label: "Username", traits: [.textEntry]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "1 text field")
    }

    func testScreenDescriptionNoInteractiveElementsShowsCount() {
        let elements = [
            makeElement(label: "Hello", traits: [.staticText]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "1 elements")
    }

    func testScreenDescriptionHeaderNoInteractive() {
        let elements = [
            makeElement(label: "About", traits: [.header]),
            makeElement(label: "Version 1.0", traits: [.staticText]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "About")
    }

    func testScreenDescriptionAllTypes() {
        let elements = [
            makeElement(label: "Login", traits: [.header]),
            makeElement(label: "Email", traits: [.textEntry]),
            makeElement(label: "Password", traits: [.secureTextField]),
            makeElement(label: "Search", traits: [.searchField]),
            makeElement(label: "Submit", traits: [.button]),
            makeElement(label: "Dark Mode", traits: [.switchButton]),
            makeElement(label: "Volume", traits: [.adjustable]),
            makeElement(label: "Docs", traits: [.link]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertTrue(description.hasPrefix("Login — "))
        XCTAssertTrue(description.contains("1 text field"))
        XCTAssertTrue(description.contains("1 password field"))
        XCTAssertTrue(description.contains("1 search field"))
        XCTAssertTrue(description.contains("1 button"))
        XCTAssertTrue(description.contains("1 toggle"))
        XCTAssertTrue(description.contains("1 slider"))
        XCTAssertTrue(description.contains("1 link"))
    }

    func testScreenDescriptionBackButtonExcluded() {
        let elements = [
            makeElement(label: "Back", traits: [.button, .backButton]),
            makeElement(label: "Save", traits: [.button]),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "1 button")
    }

    func testScreenDescriptionEmpty() {
        let description = Interface.buildScreenDescription(from: [])
        XCTAssertEqual(description, "0 elements")
    }

    // MARK: - Interface.screenId

    func testScreenIdFromHeader() {
        let elements = [
            makeElement(label: "Controls Demo", traits: [.header]),
        ]
        let interface = Interface(timestamp: Date(), elements: elements)
        XCTAssertEqual(interface.screenId, "controls_demo")
    }

    func testScreenIdNilWhenNoHeader() {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
        ]
        let interface = Interface(timestamp: Date(), elements: elements)
        XCTAssertNil(interface.screenId)
    }

    // MARK: - ActionExpectation.summaryDescription

    func testSummaryDescriptionScreenChanged() {
        XCTAssertEqual(ActionExpectation.screenChanged.summaryDescription, "screen_changed")
    }

    func testSummaryDescriptionElementsChanged() {
        XCTAssertEqual(ActionExpectation.elementsChanged.summaryDescription, "elements_changed")
    }

    func testSummaryDescriptionElementUpdated() {
        let expectation = ActionExpectation.elementUpdated(heistId: "btn_1", property: .value, newValue: "ON")
        XCTAssertTrue(expectation.summaryDescription.contains("element_updated"))
        XCTAssertTrue(expectation.summaryDescription.contains("btn_1"))
        XCTAssertTrue(expectation.summaryDescription.contains("value"))
        XCTAssertTrue(expectation.summaryDescription.contains("ON"))
    }

    func testSummaryDescriptionElementAppeared() {
        let expectation = ActionExpectation.elementAppeared(ElementMatcher(label: "Done"))
        XCTAssertEqual(expectation.summaryDescription, "element_appeared(Done)")
    }

    func testSummaryDescriptionElementDisappeared() {
        let expectation = ActionExpectation.elementDisappeared(ElementMatcher(identifier: "spinner"))
        XCTAssertEqual(expectation.summaryDescription, "element_disappeared(spinner)")
    }

    func testSummaryDescriptionCompound() {
        let expectation = ActionExpectation.compound([.screenChanged, .elementsChanged])
        XCTAssertEqual(expectation.summaryDescription, "compound(2 expectations)")
    }

    // MARK: - Helpers

    private func makeElement(label: String?, traits: [HeistTrait]) -> HeistElement {
        HeistElement(
            description: label ?? "",
            label: label, value: nil, identifier: nil,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}
