import XCTest
@testable import TheScore

final class ElementMatcherTests: XCTestCase {

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
        // No element target
        let empty = ScrollToVisibleTarget()
        XCTAssertNil(empty.elementTarget)

        // With heistId
        let withId = ScrollToVisibleTarget(elementTarget: .heistId("save_button"))
        guard case .heistId(let id) = withId.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let matcher = ElementMatcher(
            label: "Save", identifier: "saveBtn",
            value: "active", traits: [.button], excludeTraits: [.unknown("disabled")]
        )
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testEncodeDecodeMinimal() throws {
        let matcher = ElementMatcher(label: "Save")
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testEncodeDecodeEmpty() throws {
        let matcher = ElementMatcher()
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher, decoded)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {"label":"Settings","traits":["header","button"],"excludeTraits":["notEnabled"]}
        """
        let data = Data(json.utf8)
        let matcher = try JSONDecoder().decode(ElementMatcher.self, from: data)
        XCTAssertEqual(matcher.label, "Settings")
        XCTAssertEqual(matcher.traits, [.header, .button])
        XCTAssertEqual(matcher.excludeTraits, [.notEnabled])
        XCTAssertNil(matcher.identifier)
        XCTAssertNil(matcher.value)
    }

    // MARK: - Equatable

    func testEqualMatchers() {
        let a = ElementMatcher(label: "Save", traits: [.button])
        let b = ElementMatcher(label: "Save", traits: [.button])
        XCTAssertEqual(a, b)
    }

    func testUnequalMatchers() {
        let a = ElementMatcher(label: "Save")
        let b = ElementMatcher(label: "Cancel")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Empty String Handling

    func testEmptyStringLabelHasNoPredicates() {
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(matcher.hasPredicates)
        XCTAssertNil(matcher.nonEmpty)
    }

    func testEmptyStringIdentifierHasNoPredicates() {
        let matcher = ElementMatcher(identifier: "")
        XCTAssertFalse(matcher.hasPredicates)
    }

    func testEmptyStringValueHasNoPredicates() {
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(matcher.hasPredicates)
    }

    func testEmptyStringLabelMatchesNothing() {
        let element = HeistElement.stub(label: "Save")
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(element.matches(matcher), "Empty-string label should match nothing")
    }

    func testEmptyStringMatcherTreatedAsNoPredicate() {
        let matcher = ElementMatcher(label: "", identifier: "", value: "")
        XCTAssertFalse(matcher.hasPredicates, "All-empty-string matcher should have no predicates")
        XCTAssertNil(matcher.nonEmpty, "All-empty-string matcher should be nonEmpty == nil")
    }

    // MARK: - Exact-or-Miss Matching (Task 2)
    //
    // Client-side HeistElement.matches uses the same exact-or-miss semantics
    // as server-side resolution: case-insensitive equality with typography
    // folding on label, identifier, and value. No substring fallback.

    func testExactLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save")))
    }

    func testCaseInsensitiveLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ElementMatcher(label: "save")))
        XCTAssertTrue(element.matches(ElementMatcher(label: "SAVE")))
    }

    func testSubstringPartialNoLongerMatches() {
        // Old behavior: "Sav" was a substring of "Save" and matched.
        // New behavior: exact-or-miss — "Sav" misses, agent gets suggestions.
        let element = HeistElement.stub(label: "Save")
        XCTAssertFalse(element.matches(ElementMatcher(label: "Sav")))
        XCTAssertFalse(element.matches(ElementMatcher(label: "ave")))
    }

    func testSupersetLabelNoLongerMatches() {
        // "Save" is a substring of "Save Draft" — under substring matching the
        // pattern "Save" would have hit "Save Draft". Now it must not.
        let element = HeistElement.stub(label: "Save Draft")
        XCTAssertFalse(element.matches(ElementMatcher(label: "Save")))
        // The full label still matches.
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save Draft")))
    }

    func testTypographyFoldingOnLabel() {
        // Smart apostrophe in label, ASCII apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don\u{2019}t skip")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Don't skip")))
    }

    func testTypographyFoldingOnPattern() {
        // ASCII apostrophe in label, smart apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don't skip")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Don\u{2019}t skip")))
    }

    func testEmDashFoldingOnLabel() {
        let element = HeistElement.stub(label: "wait \u{2014} stop")
        XCTAssertTrue(element.matches(ElementMatcher(label: "wait - stop")))
    }

    func testEllipsisFolding() {
        let element = HeistElement.stub(label: "Loading\u{2026}")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Loading...")))
    }

    func testIdentifierExactMatch() {
        let element = HeistElement(
            heistId: "x", description: "x", label: nil, value: nil,
            identifier: "save_btn", traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "save_btn")))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "save")))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "save_btn_extra")))
    }

    func testValueExactMatch() {
        let element = HeistElement(
            heistId: "x", description: "x", label: nil, value: "50%",
            identifier: nil, traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ElementMatcher(value: "50%")))
        XCTAssertFalse(element.matches(ElementMatcher(value: "5")))
    }

    func testTraitsStillExactBitmaskComparison() {
        let element = HeistElement.stub(label: "Submit", traits: [.button])
        XCTAssertTrue(element.matches(ElementMatcher(traits: [.button])))
        XCTAssertFalse(element.matches(ElementMatcher(traits: [.button, .selected])))
    }

    func testExcludeTraitsStillWork() {
        let enabled = HeistElement.stub(label: "Submit", traits: [.button])
        let disabled = HeistElement.stub(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementMatcher(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(enabled.matches(matcher))
        XCTAssertFalse(disabled.matches(matcher))
    }

    func testCompoundMatcherAllFieldsExact() {
        let element = HeistElement(
            heistId: "x", description: "Dark Mode", label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        let matcher = ElementMatcher(
            label: "Dark Mode",
            identifier: "darkModeToggle",
            value: "ON",
            traits: [.button, .selected]
        )
        XCTAssertTrue(element.matches(matcher))
        // Wrong value — must miss
        let wrongValue = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle", value: "OFF",
            traits: [.button, .selected]
        )
        XCTAssertFalse(element.matches(wrongValue))
    }

    // MARK: - String Helpers

    func testStringEqualsCaseInsensitive() {
        XCTAssertTrue(ElementMatcher.stringEquals("Save", "save"))
        XCTAssertTrue(ElementMatcher.stringEquals("Save", "SAVE"))
        XCTAssertFalse(ElementMatcher.stringEquals("Save", "Save Draft"))
        XCTAssertFalse(ElementMatcher.stringEquals("Save", "Sav"))
    }

    func testStringEqualsTypographyFolded() {
        XCTAssertTrue(ElementMatcher.stringEquals("Don\u{2019}t", "Don't"))
        XCTAssertTrue(ElementMatcher.stringEquals("Page 1\u{2013}10", "Page 1-10"))
        XCTAssertTrue(ElementMatcher.stringEquals("Loading\u{2026}", "Loading..."))
    }

    func testStringContainsForSuggestions() {
        // The suggestion-only substring helper — used by diagnostics, never by resolution.
        XCTAssertTrue(ElementMatcher.stringContains("Save Draft", "Save"))
        XCTAssertTrue(ElementMatcher.stringContains("Save Draft", "Draft"))
        XCTAssertTrue(ElementMatcher.stringContains("Don\u{2019}t skip", "Don't"))
    }
}
