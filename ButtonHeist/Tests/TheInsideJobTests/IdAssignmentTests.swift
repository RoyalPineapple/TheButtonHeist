#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class IdAssignerTests: XCTestCase {

    private typealias IdAssignment = TheStash.IdAssignment

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        description: String? = nil,
        traits: [HeistTrait] = []
    ) -> AccessibilityElement {
        .make(
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            heistTraits: traits
        )
    }

    private func assign(_ elements: [AccessibilityElement]) -> [String] {
        IdAssignment.assign(elements)
    }

    // MARK: - Developer Identifier Passthrough

    func testDeveloperIdentifierBecomesHeistId() {
        let ids = assign([makeElement(identifier: "loginButton", traits: [.button])])
        XCTAssertEqual(ids[0], "loginButton")
    }

    func testEmptyIdentifierFallsToSynthesis() {
        let ids = assign([makeElement(label: "OK", identifier: "", traits: [.button])])
        XCTAssertEqual(ids[0], "ok_button")
    }

    func testNilIdentifierFallsToSynthesis() {
        let ids = assign([makeElement(label: "OK", identifier: nil, traits: [.button])])
        XCTAssertEqual(ids[0], "ok_button")
    }

    // MARK: - Trait Priority

    func testBackButtonTraitTakesPriority() {
        let ids = assign([makeElement(label: "Back", traits: [.button, .backButton])])
        XCTAssertEqual(ids[0], "back_backButton")
    }

    func testSearchFieldBeatsButton() {
        let ids = assign([makeElement(label: "Find", traits: [.button, .searchField])])
        XCTAssertEqual(ids[0], "find_searchField")
    }

    func testButtonBeatsLink() {
        let ids = assign([makeElement(label: "Go", traits: [.link, .button])])
        XCTAssertEqual(ids[0], "go_button")
    }

    func testAdjustableBeatsButton() {
        let ids = assign([makeElement(label: "Volume", traits: [.button, .adjustable])])
        XCTAssertEqual(ids[0], "volume_adjustable")
    }

    func testImageTraitUsed() {
        let ids = assign([makeElement(label: "Logo", traits: [.image])])
        XCTAssertEqual(ids[0], "logo_image")
    }

    func testHeaderTraitUsed() {
        let ids = assign([makeElement(label: "Settings", traits: [.header])])
        XCTAssertEqual(ids[0], "settings_header")
    }

    func testTabBarTraitUsed() {
        let ids = assign([makeElement(label: "Home", traits: [.tabBar])])
        XCTAssertEqual(ids[0], "home_tabBar")
    }

    // MARK: - Trait Combinations (priority ordering)

    /// A tab bar item typically carries `.button` in its bitmask. The
    /// `tabBarItem` trait is the more identifying role and must win, otherwise
    /// every tab synthesizes as `*_button` and collides ambiguously with any
    /// regular button bearing the same label (audit Finding 7).
    func testTabBarItemTraitBeatsButton() {
        let ids = assign([makeElement(label: "Home", traits: [.button, .tabBarItem])])
        XCTAssertEqual(ids[0], "home_tabBarItem")
    }

    /// Section headers that are tappable to expand/collapse carry both
    /// `.header` and `.button`. The `header` role is more descriptive of the
    /// element's semantic identity than the generic `button` interaction
    /// (audit Finding 7).
    func testHeaderTraitBeatsButton() {
        let ids = assign([makeElement(label: "Settings", traits: [.header, .button])])
        XCTAssertEqual(ids[0], "settings_header")
    }

    /// Header also beats link for the same reason — semantic role over
    /// interaction role.
    func testHeaderTraitBeatsLink() {
        let ids = assign([makeElement(label: "Section", traits: [.header, .link])])
        XCTAssertEqual(ids[0], "section_header")
    }

    /// backButton stays at the top of the priority list — a `[.backButton,
    /// .button]` element synthesizes as `*_backButton`, not `*_button`.
    func testBackButtonBeatsButton() {
        let ids = assign([makeElement(label: "Back", traits: [.backButton, .button])])
        XCTAssertEqual(ids[0], "back_backButton")
    }

    // MARK: - Trait Suffix Deduplication

    func testSwitchButtonLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Switch Button Off", traits: [.switchButton])])
        XCTAssertEqual(ids[0], "off_switchButton")
    }

    func testButtonLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Button Submit", traits: [.button])])
        XCTAssertEqual(ids[0], "submit_button")
    }

    func testNoRedundancyWhenLabelDoesNotOverlap() {
        let ids = assign([makeElement(label: "Settings", traits: [.button])])
        XCTAssertEqual(ids[0], "settings_button")
    }

    func testRedundancyStrippingKeepsFullIdWhenRemainderEmpty() {
        let ids = assign([makeElement(label: "Button", traits: [.button])])
        XCTAssertEqual(ids[0], "button_button")
    }

    func testTextEntryLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Text Entry Email", traits: [.textEntry])])
        XCTAssertEqual(ids[0], "email_textEntry")
    }

    func testPartialPrefixMatchNotStripped() {
        let ids = assign([makeElement(label: "But More", traits: [.button])])
        XCTAssertEqual(ids[0], "but_more_button")
    }

    // MARK: - Fallbacks

    func testStaticTextFallbackWhenLabelPresent() {
        let ids = assign([makeElement(label: "Hello World")])
        XCTAssertEqual(ids[0], "hello_world_staticText")
    }

    func testElementFallbackWhenNoLabelNoTrait() {
        let ids = assign([makeElement()])
        XCTAssertEqual(ids[0], "element")
    }

    func testValueExcludedFromSlug() {
        let ids = assign([makeElement(value: "50%")])
        XCTAssertEqual(ids[0], "element")
    }

    func testValueExcludedButDescriptionUsed() {
        let ids = assign([makeElement(value: "50%", description: "VolumeSlider")])
        XCTAssertEqual(ids[0], "volumeslider_element")
    }

    func testElementFallbackWithDescriptionSlug() {
        let ids = assign([makeElement(description: "UIView")])
        XCTAssertEqual(ids[0], "uiview_element")
    }

    func testSlugFallbackChainLabelThenDescription() {
        let withLabel = assign([makeElement(label: "A", value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withLabel[0], "a_button")

        let withValue = assign([makeElement(value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withValue[0], "c_button")

        let withDesc = assign([makeElement(description: "CView", traits: [.button])])
        XCTAssertEqual(withDesc[0], "cview_button")
    }

    // MARK: - Slug Synthesis

    func testSlugifyLowercases() {
        XCTAssertEqual(IdAssignment.slugify("HELLO"), "hello")
    }

    func testSlugifyReplacesNonAlphanumericWithUnderscore() {
        XCTAssertEqual(IdAssignment.slugify("Hello World!"), "hello_world")
    }

    func testSlugifyCollapseConsecutiveSpecialChars() {
        XCTAssertEqual(IdAssignment.slugify("a---b___c   d"), "a_b_c_d")
    }

    func testSlugifyTrimsLeadingAndTrailingUnderscores() {
        XCTAssertEqual(IdAssignment.slugify("  hello  "), "hello")
    }

    func testSlugifyTruncatesTo24Characters() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789"
        let result = IdAssignment.slugify(long)
        XCTAssertEqual(result?.count, 24)
        XCTAssertEqual(result, "abcdefghijklmnopqrstuvwx")
    }

    func testSlugifyReturnsNilForNilInput() {
        XCTAssertNil(IdAssignment.slugify(nil))
    }

    func testSlugifyReturnsNilForEmptyString() {
        XCTAssertNil(IdAssignment.slugify(""))
    }

    func testSlugifyReturnsNilForAllPunctuation() {
        XCTAssertNil(IdAssignment.slugify("!!!???"))
    }

    func testSlugifyPreservesDigits() {
        XCTAssertEqual(IdAssignment.slugify("Item 42"), "item_42")
    }

    // MARK: - Duplicate Disambiguation

    func testTwoDuplicatesBothGetSuffixes() {
        let ids = assign([
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
        ])
        XCTAssertEqual(ids[0], "ok_button_1")
        XCTAssertEqual(ids[1], "ok_button_2")
    }

    func testThreeDuplicatesGetSequentialSuffixes() {
        let ids = assign([
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
        ])
        XCTAssertEqual(ids[0], "cell_staticText_1")
        XCTAssertEqual(ids[1], "cell_staticText_2")
        XCTAssertEqual(ids[2], "cell_staticText_3")
    }

    func testCollidingDeveloperIdentifiersGetSuffixes() {
        let ids = assign([
            makeElement(identifier: "cell"),
            makeElement(identifier: "cell"),
        ])
        XCTAssertEqual(ids[0], "cell_1")
        XCTAssertEqual(ids[1], "cell_2")
    }

    func testUniqueElementsGetNoSuffix() {
        let ids = assign([
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ])
        XCTAssertEqual(ids[0], "ok_button")
        XCTAssertEqual(ids[1], "cancel_button")
    }

    func testMixedUniqueAndDuplicates() {
        let ids = assign([
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ])
        XCTAssertEqual(ids[0], "ok_button_1")
        XCTAssertEqual(ids[1], "ok_button_2")
        XCTAssertEqual(ids[2], "cancel_button")
    }

    // MARK: - Value Stability

    func testValueChangeDoesNotAffectHeistId() {
        let beforeIds = assign([makeElement(label: nil, value: "0", traits: [.button])])
        let afterIds = assign([makeElement(label: nil, value: "1", traits: [.button])])
        XCTAssertEqual(beforeIds[0], afterIds[0])
    }

    func testSliderValueChangeDoesNotAffectHeistId() {
        let beforeIds = assign([makeElement(label: nil, value: "40", traits: [.adjustable])])
        let afterIds = assign([makeElement(label: nil, value: "41", traits: [.adjustable])])
        XCTAssertEqual(beforeIds[0], afterIds[0])
    }
}

#endif
