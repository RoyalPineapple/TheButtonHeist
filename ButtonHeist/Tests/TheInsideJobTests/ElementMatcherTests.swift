#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ElementMatcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        hint: String? = nil
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: hint,
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

    // MARK: - Label Matching

    func testMatchByLabelExact() {
        let element = element(label: "Save")
        let matcher = ElementMatcher(label: "Save")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testLabelMismatch() {
        let element = element(label: "Save")
        let matcher = ElementMatcher(label: "Cancel")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testLabelIsCaseInsensitive() {
        let element = element(label: "Save")
        XCTAssertTrue(element.matches(ElementMatcher(label: "save"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: "SAVE"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: "sAvE"), mode: .substring))
    }

    func testLabelSubstringMatch() {
        let element = element(label: "Save Changes")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: "Changes"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: "save changes"), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Delete"), mode: .substring))
    }

    func testLabelNilOnElementDoesNotMatchEmptyString() {
        let element = element(label: nil)
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testLabelEmptyStringMatches() {
        // Empty matcher label is a substring of any label — always matches
        let element = element(label: "")
        let matcher = ElementMatcher(label: "")
        // "".localizedCaseInsensitiveContains("") is false per Foundation
        // semantics, so empty-string matcher against empty-string label
        // does not match. Use a nil matcher label to match any element.
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testLabelWithUnicode() {
        let element = element(label: "🔴 Error")
        let matcher = ElementMatcher(label: "🔴 Error")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testLabelWithNewline() {
        let element = element(label: "Line 1\nLine 2")
        let matcher = ElementMatcher(label: "Line 1\nLine 2")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testLabelWithLeadingTrailingWhitespace() {
        // Substring matching — "Save" is found inside " Save "
        let element = element(label: " Save ")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: " Save "), mode: .substring))
    }

    // MARK: - Identifier Matching

    func testMatchByIdentifierExact() {
        let element = element(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.saveButton")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testIdentifierMismatch() {
        let element = element(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.cancelButton")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testIdentifierNilOnElement() {
        let element = element(identifier: nil)
        let matcher = ElementMatcher(identifier: "anything")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testIdentifierIsCaseInsensitive() {
        let element = element(identifier: "SaveBtn")
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "savebtn"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "SAVEBTN"), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "OtherBtn"), mode: .substring))
    }

    // MARK: - Value Matching

    func testMatchByValueExact() {
        let element = element(value: "50%")
        let matcher = ElementMatcher(value: "50%")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testValueMismatch() {
        let element = element(value: "50%")
        let matcher = ElementMatcher(value: "75%")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testValueNilOnElementDoesNotMatchEmptyString() {
        let element = element(value: nil)
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testValueEmptyStringMatchesEmptyString() {
        // Foundation: "".localizedCaseInsensitiveContains("") is false
        let element = element(value: "")
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    // MARK: - Trait Matching (Required)

    func testSingleTraitPresent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testSingleTraitAbsent() {
        let element = element(traits: .staticText)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testMultipleTraitsAllPresent() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: [.button, .selected])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testMultipleTraitsOneAbsent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button, .selected])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testTraitOrderDoesNotMatter() {
        let element = element(traits: [.header, .button])
        let matcherAB = ElementMatcher(traits: [.button, .header])
        let matcherBA = ElementMatcher(traits: [.header, .button])
        XCTAssertTrue(element.matches(matcherAB, mode: .substring))
        XCTAssertTrue(element.matches(matcherBA, mode: .substring))
    }

    func testElementHasExtraTraitsStillMatches() {
        let element = element(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testEmptyTraitsArrayMatchesAnything() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testTraitsNilMatchesAnything() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: nil)
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testNoTraitsDoesNotMatchRequiredTrait() {
        let element = element(traits: .none)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testBackButtonTrait() {
        let element = element(traits: UIAccessibilityTraits(rawValue: 0x8000000))
        let matcher = ElementMatcher(traits: [.backButton])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testAdjustableTrait() {
        let element = element(traits: .adjustable)
        let matcher = ElementMatcher(traits: [.adjustable])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testSearchFieldTrait() {
        let element = element(traits: .searchField)
        let matcher = ElementMatcher(traits: [.searchField])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testNotEnabledTrait() {
        let element = element(traits: .notEnabled)
        let matcher = ElementMatcher(traits: [.notEnabled])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    // MARK: - Trait Exclusion

    func testExcludeSingleTraitAbsent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(excludeTraits: [.selected])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testExcludeSingleTraitPresent() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testExcludeMultipleTraitsNonePresent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(excludeTraits: [.selected, .notEnabled])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testExcludeMultipleTraitsOnePresent() {
        let element = element(traits: [.button, .notEnabled])
        let matcher = ElementMatcher(excludeTraits: [.selected, .notEnabled])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testExcludeEmptyArrayMatchesAnything() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testExcludeNilMatchesAnything() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: nil)
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    // MARK: - Combined Trait Include + Exclude

    func testIncludeAndExcludeBothSatisfied() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testIncludeSatisfiedButExcludeViolated() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testIncludeViolatedExcludeSatisfied() {
        let element = element(traits: .staticText)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testSameTraitInIncludeAndExcludeAlwaysFails() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.button])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    // MARK: - Compound Predicate (Multiple Fields)

    func testLabelAndIdentifier() {
        let element = element(label: "Save", identifier: "saveBtn")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Save", identifier: "saveBtn"), mode: .substring))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Save", identifier: "cancelBtn"), mode: .substring))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Cancel", identifier: "saveBtn"), mode: .substring))
    }

    func testLabelAndValue() {
        let element = element(label: "Volume", value: "50%")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Volume", value: "50%"), mode: .substring))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Volume", value: "75%"), mode: .substring))
    }

    func testLabelAndTraits() {
        let element = element(label: "Settings", traits: .header)
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Settings", traits: [.header]), mode: .substring))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Settings", traits: [.button]), mode: .substring))
    }

    func testLabelIdentifierValueTraits() {
        let element = element(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        let matcher = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "ON", traits: [.button, .selected]
        )
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testAllFieldsMustMatchAndOneDoesNot() {
        let element = element(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        // Wrong value
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Dark Mode", identifier: "darkModeToggle", value: "OFF", traits: [.button, .selected])
        , mode: .substring))
    }

    func testLabelAndExcludeTraits() {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementMatcher(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(enabled.matches(matcher, mode: .substring))
        XCTAssertFalse(disabled.matches(matcher, mode: .substring))
    }

    // MARK: - Wildcard Fields (nil = match anything)

    func testEmptyMatcherMatchesEverything() {
        let matcher = ElementMatcher()
        XCTAssertTrue(element(label: "Save", traits: .button).matches(matcher, mode: .substring))
        XCTAssertTrue(element(label: nil, traits: .none).matches(matcher, mode: .substring))
        XCTAssertTrue(element(value: "100%", identifier: "slider").matches(matcher, mode: .substring))
    }

    func testNilFieldsAreWildcards() {
        let element = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        // Only label specified — value, identifier, traits are wildcards
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save"), mode: .substring))
        // Only identifier specified
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "btn"), mode: .substring))
        // Only value specified
        XCTAssertTrue(element.matches(ElementMatcher(value: "draft"), mode: .substring))
        // Only traits specified
        XCTAssertTrue(element.matches(ElementMatcher(traits: [.button]), mode: .substring))
    }

    func testHasPredicatesIgnoresEmptyTraitArrays() {
        XCTAssertFalse(ElementMatcher(traits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(excludeTraits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(traits: [], excludeTraits: []).hasPredicates)
        XCTAssertTrue(ElementMatcher(label: "Save", traits: []).hasPredicates)
    }

    func testNonEmptyReturnsNilForEmptyMatcher() {
        XCTAssertNil(ElementMatcher().nonEmpty)
        XCTAssertNil(ElementMatcher(traits: []).nonEmpty)
        XCTAssertEqual(ElementMatcher(label: "Save").nonEmpty, ElementMatcher(label: "Save"))
    }

    func testElementTargetMatcherInitializerDropsEmptyMatcher() {
        XCTAssertNil(ElementTarget(matcher: ElementMatcher()))

        let target = ElementTarget(heistId: "save_button", matcher: ElementMatcher())
        guard case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    func testScrollToVisibleTargetWithElementTarget() {
        let empty = ScrollToVisibleTarget()
        XCTAssertNil(empty.elementTarget)

        let withId = ScrollToVisibleTarget(elementTarget: .heistId("save_button"))
        guard case .heistId(let id) = withId.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    // MARK: - Typographic Punctuation Normalization

    // Smart/typographic punctuation with an ASCII equivalent is folded on
    // both candidate and pattern, so callers don't have to care which form
    // appears in either string. Real Unicode without an ASCII equivalent
    // (emoji, accents, CJK) passes through untouched.

    func testCurlyApostropheLabelMatchesStraightQuotePattern() {
        let element = element(label: "Don\u{2019}t skip modifier item")
        let matcher = ElementMatcher(label: "Don't skip modifier item")
        XCTAssertTrue(element.matches(matcher, mode: .exact))
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testStraightApostropheLabelMatchesCurlyQuotePattern() {
        let element = element(label: "Don't skip modifier item")
        let matcher = ElementMatcher(label: "Don\u{2019}t skip modifier item")
        XCTAssertTrue(element.matches(matcher, mode: .exact))
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testCurlyDoubleQuoteMatchesStraightDoubleQuote() {
        let element = element(label: "He said \u{201C}hi\u{201D} loudly")
        let matcher = ElementMatcher(label: "\"hi\"")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testEnDashMatchesHyphen() {
        let element = element(label: "Page 1\u{2013}10")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Page 1-10"), mode: .exact))
        XCTAssertTrue(element.matches(ElementMatcher(label: "1-10"), mode: .substring))
    }

    func testEmDashMatchesHyphen() {
        let element = element(label: "wait \u{2014} stop")
        XCTAssertTrue(element.matches(ElementMatcher(label: "wait - stop"), mode: .exact))
    }

    func testHyphenPatternMatchesEnDashLabel() {
        let element = element(label: "1\u{2013}10")
        XCTAssertTrue(element.matches(ElementMatcher(label: "1-10"), mode: .exact))
    }

    func testHorizontalEllipsisMatchesThreeDots() {
        let element = element(label: "Loading\u{2026}")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Loading..."), mode: .exact))
        XCTAssertTrue(element.matches(ElementMatcher(label: "..."), mode: .substring))
    }

    func testThreeDotsMatchHorizontalEllipsis() {
        let element = element(label: "Loading...")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Loading\u{2026}"), mode: .exact))
    }

    func testNonBreakingSpaceMatchesRegularSpace() {
        let element = element(label: "Save\u{00A0}As")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save As"), mode: .exact))
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save As"), mode: .substring))
    }

    func testNormalizationAppliesToIdentifier() {
        let element = element(identifier: "user\u{2019}s-button")
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "user's-button"), mode: .exact))
    }

    func testNormalizationAppliesToValue() {
        let element = element(value: "Page 1\u{2013}10")
        XCTAssertTrue(element.matches(ElementMatcher(value: "Page 1-10"), mode: .exact))
    }

    func testEmojiPreservedAndStillMatches() {
        let element = element(label: "🔴 Don\u{2019}t skip 🚀")
        // Emoji unchanged on both sides; apostrophe folded.
        XCTAssertTrue(element.matches(ElementMatcher(label: "🔴 Don't skip 🚀"), mode: .exact))
        XCTAssertTrue(element.matches(ElementMatcher(label: "🚀"), mode: .substring))
    }

    func testAccentsPreservedAndStillMatch() {
        // Accented characters have no ASCII equivalent — they must match exactly,
        // not get stripped to plain letters.
        let element = element(label: "café")
        XCTAssertTrue(element.matches(ElementMatcher(label: "café"), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(label: "cafe"), mode: .exact))
    }

    func testCJKPreservedAndStillMatches() {
        let element = element(label: "保存")
        XCTAssertTrue(element.matches(ElementMatcher(label: "保存"), mode: .exact))
    }

    func testMixedTypographyDoesNotAlterRealUnicode() {
        // Curly quote + emoji + accent in one label; pattern uses straight quote.
        let element = element(label: "Café — Don\u{2019}t close 🔴")
        let matcher = ElementMatcher(label: "Café - Don't close 🔴")
        XCTAssertTrue(element.matches(matcher, mode: .exact))
    }

    // MARK: - Unknown Trait Names

    func testUnknownTraitNameNeverMatches() {
        let element = element(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: [.unknown("madeUpTrait")])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    func testUnknownExcludeTraitNeverMatches() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [.unknown("madeUpTrait")])
        XCTAssertFalse(element.matches(matcher, mode: .substring))
    }

    // MARK: - Edge Cases

    func testVeryLongLabel() {
        let longLabel = String(repeating: "a", count: 10_000)
        let element = element(label: longLabel)
        let matcher = ElementMatcher(label: longLabel)
        XCTAssertTrue(element.matches(matcher, mode: .substring))
    }

    func testLabelWithNullCharacter() {
        let element = element(label: "before\0after")
        let matcher = ElementMatcher(label: "before\0after")
        XCTAssertTrue(element.matches(matcher, mode: .substring))
        // Substring matching — "before" is found inside "before\0after"
        XCTAssertTrue(element.matches(ElementMatcher(label: "before"), mode: .substring))
    }

    func testAllFieldsNilOnElement() {
        let element = element()
        XCTAssertTrue(element.matches(ElementMatcher(), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(label: "anything"), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "anything"), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(value: "anything"), mode: .substring))
    }

    // MARK: - Hierarchy Matching

    private func group(children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .semanticGroup(label: nil, value: nil, identifier: nil), frame: .zero),
            children: children
        )
    }

    func testHierarchyMatchFindsLeaf() {
        let leaf = AccessibilityHierarchy.element(element(label: "Target", traits: .button), traversalIndex: 3)
        let matcher = ElementMatcher(label: "Target")
        let result = [leaf].firstMatch(matcher, mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Target")
    }

    func testHierarchyMatchSkipsContainer() {
        let container = group(children: [
            .element(element(label: "Child", traits: .button), traversalIndex: 0)
        ])
        let matcher = ElementMatcher(label: "Child")
        let result = [container].firstMatch(matcher, mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Child")
    }

    func testHierarchyMatchReturnsNilWhenNoMatch() {
        let leaf = AccessibilityHierarchy.element(element(label: "Other"), traversalIndex: 0)
        let matcher = ElementMatcher(label: "Target")
        XCTAssertNil([leaf].firstMatch(matcher, mode: .substring))
    }

    func testHierarchyArrayFirstMatch() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "First", traits: .header), traversalIndex: 0),
            .element(element(label: "Second", traits: .button), traversalIndex: 1),
            .element(element(label: "Third", traits: .button), traversalIndex: 2),
        ]
        let matcher = ElementMatcher(traits: [.button])
        let result = tree.firstMatch(matcher, mode: .substring)
        XCTAssertEqual(result?.element.label, "Second")
    }

    func testHierarchyArrayMultipleMatches() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "A", traits: .button), traversalIndex: 0),
            .element(element(label: "B", traits: .header), traversalIndex: 1),
            .element(element(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.matches(ElementMatcher(traits: [.button]), mode: .substring, limit: 100)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].element.label, "A")
        XCTAssertEqual(results[1].element.label, "C")
    }

    func testHierarchyNestedContainerSearch() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                group(children: [
                    .element(element(label: "Deep Target", identifier: "deep"), traversalIndex: 5)
                ])
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(identifier: "deep"), mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Deep Target")
    }

    func testHierarchyContainerLabelDoesNotMatch() {
        // Container has label "Settings" but only leaf elements should match
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(type: .semanticGroup(label: "Settings", value: nil, identifier: nil), frame: .zero),
                children: [
                    .element(element(label: "Volume"), traversalIndex: 0)
                ]
            )
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Settings"), mode: .substring)
        XCTAssertNil(result)
    }

    func testHierarchyHasMatchOnEmptyTree() {
        let tree: [AccessibilityHierarchy] = []
        XCTAssertFalse(tree.hasMatch(ElementMatcher(label: "Anything"), mode: .substring))
    }

    // MARK: - StableKey

    func testStableKeyEqualForSameProperties() {
        let a = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        let b = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        XCTAssertEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnLabel() {
        let a = element(label: "Save")
        let b = element(label: "Cancel")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnIdentifier() {
        let a = element(label: "Save", identifier: "a")
        let b = element(label: "Save", identifier: "b")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnValue() {
        let a = element(label: "Slider", value: "50%")
        let b = element(label: "Slider", value: "75%")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnTraits() {
        let a = element(label: "Save", traits: .button)
        let b = element(label: "Save", traits: [.button, .selected])
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeySetDeduplicates() {
        let elements = [
            element(label: "Save", traits: .button),
            element(label: "Save", traits: .button),
            element(label: "Cancel", traits: .button),
        ]
        let keys = Set(elements.map(\.stableKey))
        XCTAssertEqual(keys.count, 2)
    }

    func testStableKeyFallsBackToFrameWhenNoSemanticIdentity() {
        let a = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 0, y: 0, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 22),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        let b = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 0, y: 200, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 222),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        XCTAssertNotEqual(a.stableKey, b.stableKey, "Unlabeled elements at different positions must hash differently")
    }

    func testStableKeySameFrameSameKeyWhenNoSemanticIdentity() {
        let a = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 10, y: 10, width: 44, height: 44)),
            activationPoint: CGPoint(x: 32, y: 32),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        let b = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 10, y: 10, width: 44, height: 44)),
            activationPoint: CGPoint(x: 32, y: 32),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        XCTAssertEqual(a.stableKey, b.stableKey, "Same frame + no semantics = same key")
    }

    // MARK: - Absent Flag

    // absent is handled at the wait_for level (WaitForTarget.absent),
    // not on ElementMatcher itself. See WaitForTarget tests in TheScoreTests.

    // MARK: - Hierarchy Tree Matching

    private func labeledGroup(
        label: String,
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil, identifier: nil),
                frame: .zero
            ),
            children: children
        )
    }

    func testHierarchyMatchesLeafElement() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "Save"), traversalIndex: 0)
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Save"), mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Save")
    }

    func testHierarchySkipsContainers() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Nav", children: [
                .element(element(label: "Item"), traversalIndex: 0)
            ])
        ]
        // Container label "Nav" should not match — only leaf elements match
        XCTAssertNil(tree.firstMatch(ElementMatcher(label: "Nav"), mode: .substring))
    }

    func testHierarchyRecursesIntoContainersToFindLeaves() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(element(label: "Target"), traversalIndex: 0)
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Target"), mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Target")
    }

    func testHierarchyDeepNesting() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Outer", children: [
                labeledGroup(label: "Inner", children: [
                    .element(element(label: "Leaf"), traversalIndex: 0)
                ])
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Leaf"), mode: .substring)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Leaf")
    }

    func testMatchesFindsMultipleLeavesInContainer() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(element(label: "Item"), traversalIndex: 0),
                .element(element(label: "Item"), traversalIndex: 1),
            ])
        ]
        let results = tree.matches(ElementMatcher(label: "Item"), mode: .substring, limit: 100)
        XCTAssertEqual(results.count, 2)
    }
}

#endif
