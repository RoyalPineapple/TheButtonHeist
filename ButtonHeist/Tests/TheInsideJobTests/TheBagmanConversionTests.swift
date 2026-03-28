#if canImport(UIKit)
import XCTest
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
        heistId: String = "",
        order: Int = 0,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        description: String = "",
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPointX: Double = 0,
        activationPointY: Double = 0,
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            order: order,
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            actions: actions
        )
    }

    private func snapshot(_ elements: [HeistElement]) -> [HeistElement] {
        elements
    }

    // MARK: - heistId: Developer Identifier Passthrough

    func testDeveloperIdentifierBecomesHeistId() {
        var elements = [makeElement(identifier: "loginButton", traits: [.button])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "loginButton")
    }

    func testEmptyIdentifierFallsToSynthesis() {
        var elements = [makeElement(label: "OK", identifier: "", traits: [.button])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_ok")
    }

    func testNilIdentifierFallsToSynthesis() {
        var elements = [makeElement(label: "OK", identifier: nil, traits: [.button])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_ok")
    }

    // MARK: - heistId: Trait Priority

    func testBackButtonTraitTakesPriority() {
        var elements = [makeElement(label: "Back", traits: [.button, .backButton])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "backButton_back")
    }

    func testSearchFieldBeatsButton() {
        var elements = [makeElement(label: "Find", traits: [.button, .searchField])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "searchField_find")
    }

    func testButtonBeatsLink() {
        var elements = [makeElement(label: "Go", traits: [.link, .button])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_go")
    }

    func testAdjustableBeatsButton() {
        var elements = [makeElement(label: "Volume", traits: [.button, .adjustable])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "adjustable_volume")
    }

    func testImageTraitUsed() {
        var elements = [makeElement(label: "Logo", traits: [.image])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "image_logo")
    }

    func testHeaderTraitUsed() {
        var elements = [makeElement(label: "Settings", traits: [.header])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "header_settings")
    }

    func testTabBarTraitUsed() {
        var elements = [makeElement(label: "Home", traits: [.tabBar])]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "tabBar_home")
    }

    // MARK: - heistId: Fallbacks

    func testStaticTextFallbackWhenLabelPresent() {
        var elements = [makeElement(label: "Hello World")]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "staticText_hello_world")
    }

    func testElementFallbackWhenNoLabelNoTrait() {
        var elements = [makeElement()]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "element")
    }

    func testValueExcludedFromSlug() {
        var elements = [makeElement(value: "50%")]
        bagman.assignHeistIds(&elements)
        // Value is excluded from heistId synthesis for stability
        XCTAssertEqual(elements[0].heistId, "element")
    }

    func testValueExcludedButDescriptionUsed() {
        var elements = [makeElement(value: "50%", description: "VolumeSlider")]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "element_volumeslider")
    }

    func testElementFallbackWithDescriptionSlug() {
        var elements = [makeElement(description: "UIView")]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "element_uiview")
    }

    func testSlugFallbackChainLabelThenDescription() {
        // label takes priority over description (value excluded for stability)
        var withLabel = [makeElement(label: "A", value: "B", description: "C", traits: [.button])]
        bagman.assignHeistIds(&withLabel)
        XCTAssertEqual(withLabel[0].heistId, "button_a")

        // value is skipped — description used when label is nil
        var withValue = [makeElement(value: "B", description: "C", traits: [.button])]
        bagman.assignHeistIds(&withValue)
        XCTAssertEqual(withValue[0].heistId, "button_c")

        // description used when label is nil
        var withDesc = [makeElement(description: "CView", traits: [.button])]
        bagman.assignHeistIds(&withDesc)
        XCTAssertEqual(withDesc[0].heistId, "button_cview")
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
        var elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
        ]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_ok_1")
        XCTAssertEqual(elements[1].heistId, "button_ok_2")
    }

    func testThreeDuplicatesGetSequentialSuffixes() {
        var elements = [
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
            makeElement(label: "Cell", traits: [.staticText]),
        ]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "staticText_cell_1")
        XCTAssertEqual(elements[1].heistId, "staticText_cell_2")
        XCTAssertEqual(elements[2].heistId, "staticText_cell_3")
    }

    func testCollidingDeveloperIdentifiersGetSuffixes() {
        var elements = [
            makeElement(identifier: "cell"),
            makeElement(identifier: "cell"),
        ]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "cell_1")
        XCTAssertEqual(elements[1].heistId, "cell_2")
    }

    func testUniqueElementsGetNoSuffix() {
        var elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_ok")
        XCTAssertEqual(elements[1].heistId, "button_cancel")
    }

    func testMixedUniqueAndDuplicates() {
        var elements = [
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "OK", traits: [.button]),
            makeElement(label: "Cancel", traits: [.button]),
        ]
        bagman.assignHeistIds(&elements)
        XCTAssertEqual(elements[0].heistId, "button_ok_1")
        XCTAssertEqual(elements[1].heistId, "button_ok_2")
        XCTAssertEqual(elements[2].heistId, "button_cancel")
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
        let traits = bagman.traitNames(UIAccessibilityTraits.backButton)
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
            makeElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeElement(heistId: "header_settings", label: "Settings", traits: [.header]),
        ]
        XCTAssertEqual(snapshot(elements).screenName, "Settings")
    }

    func testSnapshotScreenNameNilWhenNoHeader() {
        let elements = [makeElement(heistId: "button_ok", label: "OK", traits: [.button])]
        XCTAssertNil(snapshot(elements).screenName)
    }

    // MARK: - Trait Name Sync

    func testHeistElementKnownTraitsMatchParser() {
        let parserNames = UIAccessibilityTraits.knownTraitNames
        let wireNames = HeistElement.knownTraitNames
        XCTAssertEqual(wireNames, parserNames,
                       "HeistElement.knownTraitNames must match parser's knownTraitNames")
    }

    // MARK: - Delta: Identical Snapshots

    func testIdenticalSnapshotsReturnNoChange() {
        let elements = [makeElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = bagman.computeDelta(
            before: snapshot(elements),
            after: snapshot(elements),
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
        let delta = bagman.computeDelta(
            before: snapshot([]),
            after: snapshot([]),
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
        XCTAssertEqual(delta.elementCount, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() {
        let before = [makeElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
            makeElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        XCTAssertEqual(delta.removed, ["button_cancel"])
        XCTAssertNil(delta.added)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() {
        let before = [makeElement(heistId: "slider", value: "50%")]
        let after = [makeElement(heistId: "slider", value: "75%")]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "btn", traits: [.button])]
        let after = [makeElement(heistId: "btn", traits: [.button, .selected])]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeElement(heistId: "btn", hint: "Tap to go back")]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "btn", actions: [.activate])]
        let after = [makeElement(heistId: "btn", actions: [.activate, .increment, .decrement])]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .elementsChanged)
        let change = delta.updated?.first?.changes.first
        XCTAssertEqual(change?.property, .actions)
        XCTAssertEqual(change?.old, "activate")
        XCTAssertEqual(change?.new, "activate, increment, decrement")
    }

    func testFrameChangeProducesUpdate() {
        let before = [makeElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "btn", activationPointX: 50, activationPointY: 25)]
        let after = [makeElement(heistId: "btn", activationPointX: 75, activationPointY: 40)]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "loginButton", label: "Show More", identifier: "loginButton")]
        let after = [makeElement(heistId: "loginButton", label: "Show Less", identifier: "loginButton")]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        var before = [makeElement(label: nil, value: "0", traits: [.button])]
        bagman.assignHeistIds(&before)
        var after = [makeElement(label: nil, value: "1", traits: [.button])]
        bagman.assignHeistIds(&after)
        XCTAssertEqual(before[0].heistId, after[0].heistId)
    }

    func testSliderValueChangeDoesNotAffectHeistId() {
        var before = [makeElement(label: nil, value: "40", traits: [.adjustable])]
        bagman.assignHeistIds(&before)
        var after = [makeElement(label: nil, value: "41", traits: [.adjustable])]
        bagman.assignHeistIds(&after)
        XCTAssertEqual(before[0].heistId, after[0].heistId)
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() {
        let before = [makeElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        let before = [makeElement(heistId: "button_ok")]
        let after = [makeElement(heistId: "header_settings", label: "Settings", traits: [.header])]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
            makeElement(heistId: "cell_1", value: "A"),
            makeElement(heistId: "cell_1", value: "B"),
        ]
        let after = [
            makeElement(heistId: "cell_1", value: "X"),
            makeElement(heistId: "cell_1", value: "Y"),
        ]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
            makeElement(heistId: "cell", value: "A"),
            makeElement(heistId: "cell", value: "B"),
            makeElement(heistId: "cell", value: "C"),
        ]
        let after = [
            makeElement(heistId: "cell", value: "X"),
        ]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
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
        // Same elements, different object identity but equal values
        let el = makeElement(heistId: "btn", label: "OK", traits: [.button], actions: [])
        let before = [el]
        var afterEl = el
        afterEl.order = 0 // same order, same everything
        let after = [afterEl]

        let delta = bagman.computeDelta(
            before: snapshot(before),
            after: snapshot(after),
            afterTree: nil,
            isScreenChange: false
        )
        XCTAssertEqual(delta.kind, .noChange)
    }
}

#endif
