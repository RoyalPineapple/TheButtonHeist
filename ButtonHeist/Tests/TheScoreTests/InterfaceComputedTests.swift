import XCTest
import ThePlans
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

    // MARK: - InterfaceSummary.screenDescription

    func testScreenDescriptionWithHeaderAndButtons() {
        let elements = [
            makeElement(label: "Settings", traits: [.header]),
            makeElement(label: "Save", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
        XCTAssertEqual(description, "Settings — 2 buttons")
    }

    func testScreenDescriptionNoHeaderShowsCounts() {
        let elements = [
            makeElement(label: "Username", traits: [.textEntry]),
        ]
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
        XCTAssertEqual(description, "1 text field")
    }

    func testScreenDescriptionNoInteractiveElementsShowsCount() {
        let elements = [
            makeElement(label: "Hello", traits: [.staticText]),
        ]
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
        XCTAssertEqual(description, "1 elements")
    }

    func testScreenDescriptionHeaderNoInteractive() {
        let elements = [
            makeElement(label: "About", traits: [.header]),
            makeElement(label: "Version 1.0", traits: [.staticText]),
        ]
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
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
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
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
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
        XCTAssertEqual(description, "Display")
    }

    func testScreenDescriptionBackButtonExcluded() {
        let elements = [
            makeElement(label: "Back", traits: [.button, .backButton]),
            makeElement(label: "Save", traits: [.button]),
        ]
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: elements, timestamp: Date()))
        XCTAssertEqual(description, "1 button")
    }

    func testScreenDescriptionEmpty() {
        let description = InterfaceSummary.screenDescription(for: makeTestInterface(elements: [], timestamp: Date()))
        XCTAssertEqual(description, "0 elements")
    }

    // MARK: - InterfaceSummary.screenId

    func testScreenIdFromHeader() {
        let elements = [
            makeElement(label: "Controls Demo", traits: [.header]),
        ]
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertEqual(InterfaceSummary.screenId(for: interface), "controls_demo")
    }

    func testScreenIdUsesTopmostHeader() {
        let elements = [
            makeElement(label: "Section Header Style", traits: [.header], frameY: 240),
            makeElement(label: "Display", traits: [.header], frameY: 72),
        ]
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertEqual(InterfaceSummary.screenId(for: interface), "display")
    }

    func testScreenIdNilWhenNoHeader() {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
        ]
        let interface = makeTestInterface(elements: elements, timestamp: Date())
        XCTAssertNil(InterfaceSummary.screenId(for: interface))
    }

    func testAccessibilityPredicateDescriptionComposesPredicate() {
        let predicate = AccessibilityPredicate.present(ElementPredicate(label: "Done", traits: [.button]))

        XCTAssertEqual(
            predicate.description,
            #"present(predicate(label="Done" traits=[button]))"#
        )
    }

    func testExpectationResultDescriptionComposesPredicateAndActual() {
        let result = ExpectationResult(
            met: false,
            predicate: .absent(ElementPredicate(identifier: "spinner")),
            actual: "still visible"
        )

        XCTAssertEqual(
            result.description,
            #"expectation(met=false expected=absent(predicate(identifier="spinner")) actual="still visible")"#
        )
    }

    func testScrollContainerMetricsEstimatePageScrollsUsingRuntimeOverlap() {
        XCTAssertEqual(
            ScrollContainerMetrics.estimatedVerticalPageScrolls(contentHeight: 1_200, viewportHeight: 400),
            3
        )
        XCTAssertEqual(
            ScrollContainerMetrics.estimatedHorizontalPageScrolls(contentWidth: 1_200, viewportWidth: 390),
            3
        )
        XCTAssertEqual(
            ScrollContainerMetrics.estimatedVerticalPageScrolls(contentHeight: 3_891_549, viewportHeight: 1_032),
            3_938
        )
        XCTAssertEqual(
            ScrollContainerMetrics.estimatedVerticalPageScrolls(contentHeight: 400, viewportHeight: 400),
            0
        )
    }

    func testScrollContainerMetricsDetectAxis() {
        XCTAssertEqual(
            ScrollContainerMetrics.axis(
                contentWidth: 1_200,
                contentHeight: 400,
                viewportWidth: 390,
                viewportHeight: 400
            ),
            .horizontal
        )
        XCTAssertEqual(
            ScrollContainerMetrics.axis(
                contentWidth: 390,
                contentHeight: 1_200,
                viewportWidth: 390,
                viewportHeight: 400
            ),
            .vertical
        )
        XCTAssertEqual(
            ScrollContainerMetrics.axis(
                contentWidth: 1_200,
                contentHeight: 1_200,
                viewportWidth: 390,
                viewportHeight: 400
            ),
            .both
        )
    }

    // MARK: - Helpers

    private func makeElement(
        label: String?,
        value: String? = nil,
        traits: [HeistTrait],
        frameX: Double = 0,
        frameY: Double = 0
    ) -> HeistElement {
        HeistElement(
            description: label ?? "",
            label: label, value: value, identifier: nil,
            traits: traits,
            frameX: frameX, frameY: frameY, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}
