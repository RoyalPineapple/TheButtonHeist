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
        let uiTraits = UIAccessibilityTraits.fromNames(traits.map(\.rawValue))
        return AccessibilityElement(
            description: description ?? label ?? "",
            label: label,
            value: value,
            traits: uiTraits,
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
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
        XCTAssertEqual(ids[0], "button_ok")
    }

    func testNilIdentifierFallsToSynthesis() {
        let ids = assign([makeElement(label: "OK", identifier: nil, traits: [.button])])
        XCTAssertEqual(ids[0], "button_ok")
    }

    // MARK: - Trait Priority

    func testBackButtonTraitTakesPriority() {
        let ids = assign([makeElement(label: "Back", traits: [.button, .backButton])])
        XCTAssertEqual(ids[0], "backButton_back")
    }

    func testSearchFieldBeatsButton() {
        let ids = assign([makeElement(label: "Find", traits: [.button, .searchField])])
        XCTAssertEqual(ids[0], "searchField_find")
    }

    func testButtonBeatsLink() {
        let ids = assign([makeElement(label: "Go", traits: [.link, .button])])
        XCTAssertEqual(ids[0], "button_go")
    }

    func testAdjustableBeatsButton() {
        let ids = assign([makeElement(label: "Volume", traits: [.button, .adjustable])])
        XCTAssertEqual(ids[0], "adjustable_volume")
    }

    func testImageTraitUsed() {
        let ids = assign([makeElement(label: "Logo", traits: [.image])])
        XCTAssertEqual(ids[0], "image_logo")
    }

    func testHeaderTraitUsed() {
        let ids = assign([makeElement(label: "Settings", traits: [.header])])
        XCTAssertEqual(ids[0], "header_settings")
    }

    func testTabBarTraitUsed() {
        let ids = assign([makeElement(label: "Home", traits: [.tabBar])])
        XCTAssertEqual(ids[0], "tabBar_home")
    }

    // MARK: - Trait Prefix Deduplication

    func testSwitchButtonLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Switch Button Off", traits: [.switchButton])])
        XCTAssertEqual(ids[0], "switchButton_off")
    }

    func testButtonLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Button Submit", traits: [.button])])
        XCTAssertEqual(ids[0], "button_submit")
    }

    func testNoRedundancyWhenLabelDoesNotOverlap() {
        let ids = assign([makeElement(label: "Settings", traits: [.button])])
        XCTAssertEqual(ids[0], "button_settings")
    }

    func testRedundancyStrippingKeepsFullIdWhenRemainderEmpty() {
        let ids = assign([makeElement(label: "Button", traits: [.button])])
        XCTAssertEqual(ids[0], "button_button")
    }

    func testTextEntryLabelRedundancyStripped() {
        let ids = assign([makeElement(label: "Text Entry Email", traits: [.textEntry])])
        XCTAssertEqual(ids[0], "textEntry_email")
    }

    func testPartialPrefixMatchNotStripped() {
        let ids = assign([makeElement(label: "But More", traits: [.button])])
        XCTAssertEqual(ids[0], "button_but_more")
    }

    // MARK: - Fallbacks

    func testStaticTextFallbackWhenLabelPresent() {
        let ids = assign([makeElement(label: "Hello World")])
        XCTAssertEqual(ids[0], "staticText_hello_world")
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
        XCTAssertEqual(ids[0], "element_volumeslider")
    }

    func testElementFallbackWithDescriptionSlug() {
        let ids = assign([makeElement(description: "UIView")])
        XCTAssertEqual(ids[0], "element_uiview")
    }

    func testSlugFallbackChainLabelThenDescription() {
        let withLabel = assign([makeElement(label: "A", value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withLabel[0], "button_a")

        let withValue = assign([makeElement(value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withValue[0], "button_c")

        let withDesc = assign([makeElement(description: "CView", traits: [.button])])
        XCTAssertEqual(withDesc[0], "button_cview")
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
        XCTAssertEqual(ids[0], "button_ok_1")
        XCTAssertEqual(ids[1], "button_ok_2")
    }

    func testThreeDuplicatesGetSequentialSuffixes() {
        let ids = assign([
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
        ])
        XCTAssertEqual(ids[0], "staticText_cell_1")
        XCTAssertEqual(ids[1], "staticText_cell_2")
        XCTAssertEqual(ids[2], "staticText_cell_3")
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
        XCTAssertEqual(ids[0], "button_ok")
        XCTAssertEqual(ids[1], "button_cancel")
    }

    func testMixedUniqueAndDuplicates() {
        let ids = assign([
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ])
        XCTAssertEqual(ids[0], "button_ok_1")
        XCTAssertEqual(ids[1], "button_ok_2")
        XCTAssertEqual(ids[2], "button_cancel")
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
