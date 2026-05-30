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

    func testScreenDescriptionUsesTopmostHeader() {
        let elements = [
            makeElement(label: "Section Header Style", traits: [.header], frameY: 240),
            makeElement(label: "Display", traits: [.header], frameY: 72),
            makeElement(label: "Favorite star", traits: [.image], frameY: 180),
        ]
        let description = Interface.buildScreenDescription(from: elements)
        XCTAssertEqual(description, "Display")
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
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertEqual(interface.screenId, "controls_demo")
    }

    func testScreenIdUsesTopmostHeader() {
        let elements = [
            makeElement(label: "Section Header Style", traits: [.header], frameY: 240),
            makeElement(label: "Display", traits: [.header], frameY: 72),
        ]
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertEqual(interface.screenId, "display")
    }

    func testScreenIdNilWhenNoHeader() {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
        ]
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertNil(interface.screenId)
    }

    func testActionExpectationDescriptionComposesMatchers() {
        let expectation = ActionExpectation.compound([
            .elementAppeared(ElementMatcher(label: "Done", traits: [.button])),
            .elementUpdated(heistId: "status", property: .value, oldValue: "Off", newValue: "On"),
        ])

        XCTAssertEqual(
            expectation.description,
            #"compound(element_appeared(matcher(label="Done" traits=[button])), element_updated(heistId="status" property=value oldValue="Off" newValue="On"))"#
        )
    }

    func testExpectationResultDescriptionComposesExpectationAndActual() {
        let result = ExpectationResult(
            met: false,
            expectation: .elementDisappeared(ElementMatcher(identifier: "spinner")),
            actual: "still visible"
        )

        XCTAssertEqual(
            result.description,
            #"expectation(met=false expected=element_disappeared(matcher(identifier="spinner")) actual="still visible")"#
        )
    }

    // MARK: - Interface.navigation

    func testNavigationScreenTitleFromHeader() {
        let elements = [
            makeElement(label: "Checkout", traits: [.header]),
            makeElement(label: "Pay Now", traits: [.button]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.screenTitle, "Checkout")
        XCTAssertNil(navigation.backButton)
        XCTAssertNil(navigation.tabBarItems)
    }

    func testNavigationScreenTitleUsesTopmostHeader() {
        let elements = [
            makeElement(label: "Section Header Style", traits: [.header], frameY: 240),
            makeElement(label: "Display", traits: [.header], frameY: 72),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.screenTitle, "Display")
    }

    func testNavigationBackButton() {
        let elements = [
            makeElement(heistId: "back_button", label: "Settings", traits: [.button, .backButton]),
            makeElement(label: "Profile", traits: [.header]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.screenTitle, "Profile")
        XCTAssertEqual(navigation.backButton?.heistId, "back_button")
        XCTAssertEqual(navigation.backButton?.label, "Settings")
    }

    func testNavigationTabBarItems() {
        let elements = [
            makeElement(label: "Checkout", traits: [.header]),
            makeElement(heistId: "cart", label: "Checkout", traits: [.button, .tabBarItem, .selected]),
            makeElement(heistId: "list", label: "Transactions", traits: [.button, .tabBarItem]),
            makeElement(heistId: "person", label: "Account", traits: [.button, .tabBarItem]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.tabBarItems?.count, 3)
        XCTAssertEqual(navigation.tabBarItems?[0].heistId, "cart")
        XCTAssertEqual(navigation.tabBarItems?[0].label, "Checkout")
        XCTAssertEqual(navigation.tabBarItems?[0].selected, true)
        XCTAssertEqual(navigation.tabBarItems?[1].selected, false)
        XCTAssertEqual(navigation.tabBarItems?[2].heistId, "person")
    }

    func testNavigationTabBarItemWithValue() {
        let elements = [
            makeElement(heistId: "inbox", label: "Inbox", value: "3", traits: [.button, .tabBarItem, .selected]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.tabBarItems?[0].value, "3")
    }

    func testNavigationBackButtonAndTabs() {
        let elements = [
            makeElement(heistId: "back", label: "Home", traits: [.button, .backButton]),
            makeElement(label: "Settings", traits: [.header]),
            makeElement(heistId: "tab_general", label: "General", traits: [.button, .tabBarItem, .selected]),
            makeElement(heistId: "tab_privacy", label: "Privacy", traits: [.button, .tabBarItem]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertEqual(navigation.screenTitle, "Settings")
        XCTAssertEqual(navigation.backButton?.heistId, "back")
        XCTAssertEqual(navigation.backButton?.label, "Home")
        XCTAssertEqual(navigation.tabBarItems?.count, 2)
    }

    func testNavigationEmptyElements() {
        let navigation = Interface.buildNavigation(from: [])
        XCTAssertNil(navigation.screenTitle)
        XCTAssertNil(navigation.backButton)
        XCTAssertNil(navigation.tabBarItems)
    }

    func testNavigationNoNavChrome() {
        let elements = [
            makeElement(label: "Hello", traits: [.staticText]),
            makeElement(label: "Save", traits: [.button]),
        ]
        let navigation = Interface.buildNavigation(from: elements)
        XCTAssertNil(navigation.screenTitle)
        XCTAssertNil(navigation.backButton)
        XCTAssertNil(navigation.tabBarItems)
    }

    // MARK: - Helpers

    private func makeElement(
        heistId: HeistId = "",
        label: String?,
        value: String? = nil,
        traits: [HeistTrait],
        frameX: Double = 0,
        frameY: Double = 0
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? "",
            label: label, value: value, identifier: nil,
            traits: traits,
            frameX: frameX, frameY: frameY, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}
