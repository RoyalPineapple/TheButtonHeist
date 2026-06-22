import XCTest
import ThePlans
@testable import TheScore

final class ElementPredicateTests: XCTestCase {

    func testHasPredicatesIgnoresEmptyTraitArrays() {
        XCTAssertFalse(ElementPredicate(traits: []).hasPredicates)
        XCTAssertFalse(ElementPredicate(excludeTraits: []).hasPredicates)
        XCTAssertFalse(ElementPredicate(traits: [], excludeTraits: []).hasPredicates)
        XCTAssertTrue(ElementPredicate(label: "Save", traits: []).hasPredicates)
    }

    func testNonEmptyReturnsNilForEmptyPredicate() {
        XCTAssertNil(ElementPredicate().nonEmpty)
        XCTAssertNil(ElementPredicate(traits: []).nonEmpty)
        XCTAssertEqual(ElementPredicate(label: "Save").nonEmpty, ElementPredicate(label: "Save"))
    }

    func testElementPredicateDescriptionComposesFields() {
        let predicate = ElementPredicate(
            label: #"Save "Now""#,
            identifier: "primary.save",
            value: "Ready",
            traits: [.button, .selected],
            excludeTraits: [.notEnabled]
        )

        XCTAssertEqual(
            predicate.description,
            #"predicate(label="Save \"Now\"" identifier="primary.save" value="Ready" traits=[button, selected] excludeTraits=[notEnabled])"#
        )
    }

    func testElementPredicateDescriptionTreatsEmptyStringsAsUnset() {
        let predicate = ElementPredicate(label: "", identifier: "", value: "", traits: [])

        XCTAssertEqual(predicate.description, "predicate(*)")
    }

    func testElementPredicateRejectsUnknownFields() {
        let json = #"{"heistId":"save_button"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ElementPredicate.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, #"Unknown element predicate field "heistId""#)
        }
    }

    func testElementTargetDescriptionComposesPredicateAndOrdinal() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 1)

        XCTAssertEqual(target.description, #"target(predicate(label="Save" traits=[button]) ordinal=1)"#)
    }

    func testElementTargetRejectsOrdinalOnlySelector() throws {
        let data = Data(#"{"ordinal":1}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("requires a predicate"))
        }
    }

    func testElementTargetRejectsEmptyPredicateSelector() throws {
        let data = Data(#"{"traits":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("predicate requires"))
        }
    }

    func testElementTargetRejectsHeistIdKey() {
        // heistId is no longer a targeting field — it is an unknown key.
        let json = #"{"heistId":"save_button"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testElementTargetRejectsHeistIdAlongsidePredicate() {
        let json = #"{"heistId":"save_button","label":"Save"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testScrollToVisibleTargetWithElementTarget() {
        let target = ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Save")))
        guard case .predicate(let predicate, _) = target.elementTarget else {
            return XCTFail("Expected .predicate")
        }
        XCTAssertEqual(predicate.label, "Save")
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let predicate = ElementPredicate(
            label: "Save", identifier: "saveBtn",
            value: "active", traits: [.button], excludeTraits: [.notEnabled]
        )
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(ElementPredicate.self, from: data)
        XCTAssertEqual(predicate, decoded)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {"label":"Settings","traits":["header","button"],"excludeTraits":["notEnabled"]}
        """
        let data = Data(json.utf8)
        let predicate = try JSONDecoder().decode(ElementPredicate.self, from: data)
        XCTAssertEqual(predicate.label, "Settings")
        XCTAssertEqual(predicate.traits, [.header, .button])
        XCTAssertEqual(predicate.excludeTraits, [.notEnabled])
        XCTAssertNil(predicate.identifier)
        XCTAssertNil(predicate.value)
    }

    // MARK: - Empty String Handling

    func testEmptyStringLabelHasNoPredicates() {
        let predicate = ElementPredicate(label: "")
        XCTAssertFalse(predicate.hasPredicates)
        XCTAssertNil(predicate.nonEmpty)
    }

    func testEmptyStringIdentifierHasNoPredicates() {
        let predicate = ElementPredicate(identifier: "")
        XCTAssertFalse(predicate.hasPredicates)
    }

    func testEmptyStringValueHasNoPredicates() {
        let predicate = ElementPredicate(value: "")
        XCTAssertFalse(predicate.hasPredicates)
    }

    func testEmptyStringLabelMatchesNothing() {
        let element = HeistElement.stub(label: "Save")
        let predicate = ElementPredicate(label: "")
        XCTAssertFalse(element.matches(predicate), "Empty-string label should match nothing")
    }

    func testEmptyStringPredicateTreatedAsNoPredicate() {
        let predicate = ElementPredicate(label: "", identifier: "", value: "")
        XCTAssertFalse(predicate.hasPredicates, "All-empty-string predicate should have no predicates")
        XCTAssertNil(predicate.nonEmpty, "All-empty-string predicate should be nonEmpty == nil")
    }

    // MARK: - Exact-or-Miss Matching
    //
    // Client-side HeistElement.matches uses the same exact-or-miss semantics
    // as server-side resolution: case-insensitive equality with typography
    // folding on label, identifier, and value. No substring fallback.

    func testExactLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ElementPredicate(label: "Save")))
    }

    func testCaseInsensitiveLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ElementPredicate(label: "save")))
        XCTAssertTrue(element.matches(ElementPredicate(label: "SAVE")))
    }

    func testSubstringPartialDoesNotMatch() {
        // Exact-or-miss: "Sav" must not match "Save".
        let element = HeistElement.stub(label: "Save")
        XCTAssertFalse(element.matches(ElementPredicate(label: "Sav")))
        XCTAssertFalse(element.matches(ElementPredicate(label: "ave")))
    }

    func testSupersetLabelNoLongerMatches() {
        // "Save" is a substring of "Save Draft" — under substring matching the
        // pattern "Save" would have hit "Save Draft". Now it must not.
        let element = HeistElement.stub(label: "Save Draft")
        XCTAssertFalse(element.matches(ElementPredicate(label: "Save")))
        // The full label still matches.
        XCTAssertTrue(element.matches(ElementPredicate(label: "Save Draft")))
    }

    func testTypographyFoldingOnLabel() {
        // Smart apostrophe in label, ASCII apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don\u{2019}t skip")
        XCTAssertTrue(element.matches(ElementPredicate(label: "Don't skip")))
    }

    func testTypographyFoldingOnPattern() {
        // ASCII apostrophe in label, smart apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don't skip")
        XCTAssertTrue(element.matches(ElementPredicate(label: "Don\u{2019}t skip")))
    }

    func testEmDashFoldingOnLabel() {
        let element = HeistElement.stub(label: "wait \u{2014} stop")
        XCTAssertTrue(element.matches(ElementPredicate(label: "wait - stop")))
    }

    func testEllipsisFolding() {
        let element = HeistElement.stub(label: "Loading\u{2026}")
        XCTAssertTrue(element.matches(ElementPredicate(label: "Loading...")))
    }

    func testIdentifierExactMatch() {
        let element = HeistElement(
            description: "x", label: nil, value: nil,
            identifier: "save_btn", traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ElementPredicate(identifier: "save_btn")))
        XCTAssertFalse(element.matches(ElementPredicate(identifier: "save")))
        XCTAssertFalse(element.matches(ElementPredicate(identifier: "save_btn_extra")))
    }

    func testValueExactMatch() {
        let element = HeistElement(
            description: "x", label: nil, value: "50%",
            identifier: nil, traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ElementPredicate(value: "50%")))
        XCTAssertFalse(element.matches(ElementPredicate(value: "5")))
    }

    func testTraitsStillExactBitmaskComparison() {
        let element = HeistElement.stub(label: "Submit", traits: [.button])
        XCTAssertTrue(element.matches(ElementPredicate(traits: [.button])))
        XCTAssertFalse(element.matches(ElementPredicate(traits: [.button, .selected])))
    }

    func testExcludeTraitsStillWork() {
        let enabled = HeistElement.stub(label: "Submit", traits: [.button])
        let disabled = HeistElement.stub(label: "Submit", traits: [.button, .notEnabled])
        let predicate = ElementPredicate(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(enabled.matches(predicate))
        XCTAssertFalse(disabled.matches(predicate))
    }

    func testCompoundPredicateAllFieldsExact() {
        let element = HeistElement(
            description: "Dark Mode", label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        let predicate = ElementPredicate(
            label: "Dark Mode",
            identifier: "darkModeToggle",
            value: "ON",
            traits: [.button, .selected]
        )
        XCTAssertTrue(element.matches(predicate))
        // Wrong value — must miss
        let wrongValue = ElementPredicate(
            label: "Dark Mode", identifier: "darkModeToggle", value: "OFF",
            traits: [.button, .selected]
        )
        XCTAssertFalse(element.matches(wrongValue))
    }

    // MARK: - String Helpers

    func testStringEqualsCaseInsensitive() {
        XCTAssertTrue(ElementPredicate.stringEquals("Save", "save"))
        XCTAssertTrue(ElementPredicate.stringEquals("Save", "SAVE"))
        XCTAssertFalse(ElementPredicate.stringEquals("Save", "Save Draft"))
        XCTAssertFalse(ElementPredicate.stringEquals("Save", "Sav"))
    }

    func testStringEqualsTypographyFolded() {
        XCTAssertTrue(ElementPredicate.stringEquals("Don\u{2019}t", "Don't"))
        XCTAssertTrue(ElementPredicate.stringEquals("Page 1\u{2013}10", "Page 1-10"))
        XCTAssertTrue(ElementPredicate.stringEquals("Loading\u{2026}", "Loading..."))
    }

    func testStringContainsForSuggestions() {
        // The suggestion-only substring helper — used by diagnostics, never by resolution.
        XCTAssertTrue(ElementPredicate.stringContains("Save Draft", "Save"))
        XCTAssertTrue(ElementPredicate.stringContains("Save Draft", "Draft"))
        XCTAssertTrue(ElementPredicate.stringContains("Don\u{2019}t skip", "Don't"))
    }
}
