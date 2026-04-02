#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBagmanConversionTests: XCTestCase {

    private var bagman: TheBagman!

    override func setUp() {
        super.setUp()
        bagman = TheBagman(tripwire: TheTripwire())
    }

    override func tearDown() {
        bagman = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        description: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPointX: Double = 0,
        activationPointY: Double = 0
    ) -> AccessibilityElement {
        let uiTraits = UIAccessibilityTraits.fromNames(traits.map(\.rawValue))
        let frame = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        let activationPoint = CGPoint(x: activationPointX, y: activationPointY)
        return AccessibilityElement(
            description: description ?? label ?? "",
            label: label,
            value: value,
            traits: uiTraits,
            identifier: identifier,
            hint: hint,
            userInputLabels: nil,
            shape: .frame(frame),
            activationPoint: activationPoint,
            usesDefaultActivationPoint: activationPointX == 0 && activationPointY == 0,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    /// Assign heistIds and return the result array for assertion.
    private func assignAndGetIds(_ elements: [AccessibilityElement]) -> [String] {
        bagman.assignHeistIds(elements)
    }

    /// Create a ScreenElement for delta tests.
    private func makeScreenElement(
        heistId: String,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPointX: Double = 0,
        activationPointY: Double = 0
    ) -> TheBagman.ScreenElement {
        TheBagman.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: makeElement(
                label: label, value: value, identifier: identifier, hint: hint,
                traits: traits, frameX: frameX, frameY: frameY,
                frameWidth: frameWidth, frameHeight: frameHeight,
                activationPointX: activationPointX, activationPointY: activationPointY
            ),
            object: nil,
            scrollView: nil
        )
    }

    // MARK: - heistId: Developer Identifier Passthrough

    func testDeveloperIdentifierBecomesHeistId() {
        let elements = [makeElement(identifier: "loginButton", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "loginButton")
    }

    func testEmptyIdentifierFallsToSynthesis() {
        let elements = [makeElement(label: "OK", identifier: "", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_ok")
    }

    func testNilIdentifierFallsToSynthesis() {
        let elements = [makeElement(label: "OK", identifier: nil, traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_ok")
    }

    // MARK: - heistId: Trait Priority

    func testBackButtonTraitTakesPriority() {
        let elements = [makeElement(label: "Back", traits: [.button, .backButton])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "backButton_back")
    }

    func testSearchFieldBeatsButton() {
        let elements = [makeElement(label: "Find", traits: [.button, .searchField])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "searchField_find")
    }

    func testButtonBeatsLink() {
        let elements = [makeElement(label: "Go", traits: [.link, .button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_go")
    }

    func testAdjustableBeatsButton() {
        let elements = [makeElement(label: "Volume", traits: [.button, .adjustable])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "adjustable_volume")
    }

    func testImageTraitUsed() {
        let elements = [makeElement(label: "Logo", traits: [.image])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "image_logo")
    }

    func testHeaderTraitUsed() {
        let elements = [makeElement(label: "Settings", traits: [.header])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "header_settings")
    }

    func testTabBarTraitUsed() {
        let elements = [makeElement(label: "Home", traits: [.tabBar])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "tabBar_home")
    }

    // MARK: - heistId: Trait Prefix Deduplication

    func testSwitchButtonLabelRedundancyStripped() {
        let elements = [makeElement(label: "Switch Button Off", traits: [.switchButton])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "switchButton_off")
    }

    func testButtonLabelRedundancyStripped() {
        let elements = [makeElement(label: "Button Submit", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_submit")
    }

    func testNoRedundancyWhenLabelDoesNotOverlap() {
        let elements = [makeElement(label: "Settings", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_settings")
    }

    func testRedundancyStrippingKeepsFullIdWhenRemainderEmpty() {
        let elements = [makeElement(label: "Button", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_button")
    }

    func testTextEntryLabelRedundancyStripped() {
        let elements = [makeElement(label: "Text Entry Email", traits: [.textEntry])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "textEntry_email")
    }

    func testPartialPrefixMatchNotStripped() {
        // "but" starts with the slug of "button" prefix? No — "button" slug is "button",
        // "but_more" doesn't start with "button" or "button_"
        let elements = [makeElement(label: "But More", traits: [.button])]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_but_more")
    }

    // MARK: - heistId: Fallbacks

    func testStaticTextFallbackWhenLabelPresent() {
        let elements = [makeElement(label: "Hello World")]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "staticText_hello_world")
    }

    func testElementFallbackWhenNoLabelNoTrait() {
        let elements = [makeElement()]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "element")
    }

    func testValueExcludedFromSlug() {
        let elements = [makeElement(value: "50%")]
        let ids = assignAndGetIds(elements)
        // Value is excluded from heistId synthesis for stability
        XCTAssertEqual(ids[0], "element")
    }

    func testValueExcludedButDescriptionUsed() {
        let elements = [makeElement(value: "50%", description: "VolumeSlider")]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "element_volumeslider")
    }

    func testElementFallbackWithDescriptionSlug() {
        let elements = [makeElement(description: "UIView")]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "element_uiview")
    }

    func testSlugFallbackChainLabelThenDescription() {
        // label takes priority over description (value excluded for stability)
        let withLabel = assignAndGetIds([makeElement(label: "A", value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withLabel[0], "button_a")

        // value is skipped — description used when label is nil
        let withValue = assignAndGetIds([makeElement(value: "B", description: "C", traits: [.button])])
        XCTAssertEqual(withValue[0], "button_c")

        // description used when label is nil
        let withDesc = assignAndGetIds([makeElement(description: "CView", traits: [.button])])
        XCTAssertEqual(withDesc[0], "button_cview")
    }

    // MARK: - Slug Synthesis

    func testSlugifyLowercases() {
        XCTAssertEqual(bagman.slugify("HELLO"), "hello")
    }

    func testSlugifyReplacesNonAlphanumericWithUnderscore() {
        XCTAssertEqual(bagman.slugify("Hello World!"), "hello_world")
    }

    func testSlugifyCollapseConsecutiveSpecialChars() {
        XCTAssertEqual(bagman.slugify("a---b___c   d"), "a_b_c_d")
    }

    func testSlugifyTrimsLeadingAndTrailingUnderscores() {
        XCTAssertEqual(bagman.slugify("  hello  "), "hello")
    }

    func testSlugifyTruncatesTo24Characters() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789"
        let result = bagman.slugify(long)
        XCTAssertEqual(result?.count, 24)
        XCTAssertEqual(result, "abcdefghijklmnopqrstuvwx")
    }

    func testSlugifyReturnsNilForNilInput() {
        XCTAssertNil(bagman.slugify(nil))
    }

    func testSlugifyReturnsNilForEmptyString() {
        XCTAssertNil(bagman.slugify(""))
    }

    func testSlugifyReturnsNilForAllPunctuation() {
        XCTAssertNil(bagman.slugify("!!!???"))
    }

    func testSlugifyPreservesDigits() {
        XCTAssertEqual(bagman.slugify("Item 42"), "item_42")
    }

    // MARK: - heistId: Duplicate Disambiguation

    func testTwoDuplicatesBothGetSuffixes() {
        let elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
        ]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_ok_1")
        XCTAssertEqual(ids[1], "button_ok_2")
    }

    func testThreeDuplicatesGetSequentialSuffixes() {
        let elements = [
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
        ]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "staticText_cell_1")
        XCTAssertEqual(ids[1], "staticText_cell_2")
        XCTAssertEqual(ids[2], "staticText_cell_3")
    }

    func testCollidingDeveloperIdentifiersGetSuffixes() {
        let elements = [
            makeElement(identifier: "cell"),
            makeElement(identifier: "cell"),
        ]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "cell_1")
        XCTAssertEqual(ids[1], "cell_2")
    }

    func testUniqueElementsGetNoSuffix() {
        let elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_ok")
        XCTAssertEqual(ids[1], "button_cancel")
    }

    func testMixedUniqueAndDuplicates() {
        let elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        let ids = assignAndGetIds(elements)
        XCTAssertEqual(ids[0], "button_ok_1")
        XCTAssertEqual(ids[1], "button_ok_2")
        XCTAssertEqual(ids[2], "button_cancel")
    }

    // MARK: - Trait Mapping

    func testSingleTraitMapped() {
        let traits = bagman.traitNames(.button)
        XCTAssertEqual(traits, [.button])
    }

    func testMultipleTraitsMapped() {
        let traits = bagman.traitNames([.button, .selected])
        XCTAssertTrue(traits.contains(.button))
        XCTAssertTrue(traits.contains(.selected))
        XCTAssertEqual(traits.count, 2)
    }

    func testBackButtonPrivateTraitMapped() {
        let traits = bagman.traitNames(UIAccessibilityTraits(rawValue: 1 << 27))
        XCTAssertEqual(traits, [.backButton])
    }

    func testNoTraitsReturnsEmpty() {
        let traits = bagman.traitNames(.none)
        XCTAssertTrue(traits.isEmpty)
    }

    func testTraitMappingDeclarationOrder() {
        // button appears before selected in the mapping array
        let traits = bagman.traitNames([.button, .selected])
        XCTAssertEqual(traits[0], .button)
        XCTAssertEqual(traits[1], .selected)
    }

    // MARK: - Snapshot Screen Name

    func testSnapshotScreenNameFromHeaderElement() {
        let elements = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header]),
        ]
        XCTAssertEqual(elements.screenName, "Settings")
    }

    func testSnapshotScreenNameNilWhenNoHeader() {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        XCTAssertNil(elements.screenName)
    }

    // MARK: - Trait Name Sync

    func testHeistTraitAllCasesMatchParser() {
        let parserNames = UIAccessibilityTraits.knownTraitNames
        let wireNames = Set(HeistTrait.allCases.map(\.rawValue))
        XCTAssertEqual(wireNames, parserNames,
                       "HeistTrait.allCases must match parser's knownTraitNames")
    }

    // MARK: - Delta: Identical Snapshots

    func testIdenticalSnapshotsReturnNoChange() {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = bagman.computeDelta(
            before: elements,
            after: elements,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
        XCTAssertEqual(delta.elementCount, 1)
        XCTAssertNil(delta.added)
        XCTAssertNil(delta.removed)
        XCTAssertNil(delta.updated)
    }

    func testEmptySnapshotsReturnNoChange() {
        let empty: [TheBagman.ScreenElement] = []
        let delta = bagman.computeDelta(
            before: empty,
            after: empty,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
        XCTAssertEqual(delta.elementCount, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.added?.count, 1)
        XCTAssertEqual(delta.added?.first?.heistId, "button_cancel")
        XCTAssertNil(delta.removed)
    }

    // MARK: - Delta: Element Removed

    func testElementRemovedProducesElementsChanged() {
        let before = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["button_cancel"])
        XCTAssertNil(delta.added)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 1)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(change?.old, "50%")
        XCTAssertEqual(change?.new, "75%")
    }

    func testTraitsChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(change?.old, "button")
        XCTAssertEqual(change?.new, "button, selected")
    }

    func testHintChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(change?.old, "Tap to continue")
        XCTAssertEqual(change?.new, "Tap to go back")
    }

    func testActionsChangeProducesUpdate() {
        // Actions are now derived from element traits + live object. Test that
        // adjustable trait adds increment/decrement to the wire representation.
        let before = [makeScreenElement(heistId: "slider", traits: [.button])]
        let after = [makeScreenElement(heistId: "slider", traits: [.adjustable])]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        // Traits changed, which may also produce an action change
        XCTAssertNotNil(delta.updated)
    }

    func testFrameChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(change?.old, "0,0,100,50")
        XCTAssertEqual(change?.new, "10,20,100,50")
    }

    func testActivationPointChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", activationPointX: 50, activationPointY: 25)]
        let after = [makeScreenElement(heistId: "btn", activationPointX: 75, activationPointY: 40)]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(change?.old, "50,25")
        XCTAssertEqual(change?.new, "75,40")
    }

    func testMultiplePropertyChangesOnSameElement() {
        let before = [makeScreenElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeScreenElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.updated?.first?.changes.count, 2)
        let properties = delta.updated?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.hint) == true)
    }

    // MARK: - Delta: Label Change Tracking

    func testLabelChangeOnIdentifierMatchedElementProducesUpdate() {
        let before = [makeScreenElement(heistId: "loginButton", label: "Show More", identifier: "loginButton")]
        let after = [makeScreenElement(heistId: "loginButton", label: "Show Less", identifier: "loginButton")]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 1)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .label)
        XCTAssertEqual(change?.old, "Show More")
        XCTAssertEqual(change?.new, "Show Less")
    }

    // MARK: - heistId: Value Stability

    func testValueChangeDoesNotAffectHeistId() {
        // Checkbox toggling: value changes from "0" to "1"
        let beforeIds = assignAndGetIds([makeElement(label: nil, value: "0", traits: [.button])])
        let afterIds = assignAndGetIds([makeElement(label: nil, value: "1", traits: [.button])])
        XCTAssertEqual(beforeIds[0], afterIds[0])
    }

    func testSliderValueChangeDoesNotAffectHeistId() {
        let beforeIds = assignAndGetIds([makeElement(label: nil, value: "40", traits: [.adjustable])])
        let afterIds = assignAndGetIds([makeElement(label: nil, value: "41", traits: [.adjustable])])
        XCTAssertEqual(beforeIds[0], afterIds[0])
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["button_ok"])
        XCTAssertEqual(delta.added?.first?.heistId, "button_done")
        XCTAssertNil(delta.updated)
    }

    // MARK: - Delta: Screen Change

    func testScreenChangeReturnsFull() {
        let before = [makeScreenElement(heistId: "button_ok")]
        let after = [makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header])]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: true
        )
        XCTAssertEqual(delta.kind, .screenChanged)
        XCTAssertNotNil(delta.newInterface)
        XCTAssertEqual(delta.newInterface?.elements.count, 1)
        XCTAssertEqual(delta.elementCount, 1)
    }

    // MARK: - Delta: Duplicate heistId Pairing

    func testDuplicateHeistIdPairedByIndex() {
        let before = [
            makeScreenElement(heistId: "cell_1", value: "A"),
            makeScreenElement(heistId: "cell_1", value: "B"),
        ]
        let after = [
            makeScreenElement(heistId: "cell_1", value: "X"),
            makeScreenElement(heistId: "cell_1", value: "Y"),
        ]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.updated?.count, 2)
        XCTAssertNil(delta.added)
        XCTAssertNil(delta.removed)
    }

    func testDuplicateHeistIdExcessGoesToAddedRemoved() {
        let before = [
            makeScreenElement(heistId: "cell", value: "A"),
            makeScreenElement(heistId: "cell", value: "B"),
            makeScreenElement(heistId: "cell", value: "C"),
        ]
        let after = [
            makeScreenElement(heistId: "cell", value: "X"),
        ]

        let delta = bagman.computeDelta(
            before: before,
            after: after,
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        // 1 pair updated, 2 excess removed
        XCTAssertEqual(delta.updated?.count, 1)
        XCTAssertEqual(delta.removed?.count, 2)
    }

    // MARK: - Delta: Empty Diff Coerced to noChange

    func testNoDifferencesCoercedToNoChange() {
        let screenElement = makeScreenElement(heistId: "btn", label: "OK", traits: [.button])

        let delta = bagman.computeDelta(
            before: [screenElement],
            after: [screenElement],
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
    }
}

#endif
