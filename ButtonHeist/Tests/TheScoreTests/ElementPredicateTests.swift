import XCTest
import ThePlans
@testable import TheScore

final class ElementPredicateTests: XCTestCase {

    func testHasPredicatesIgnoresEmptyTraitArrays() {
        XCTAssertFalse(ElementPredicate(traits: []).hasPredicates)
        XCTAssertFalse(ElementPredicate.exclude(.traits([])).hasPredicates)
        XCTAssertFalse(ElementPredicate.element(.exclude(.traits([])), traits: []).hasPredicates)
        XCTAssertTrue(ElementPredicate(label: "Save", traits: []).hasPredicates)
    }

    func testNonEmptyReturnsNilForEmptyPredicate() {
        XCTAssertNil(ElementPredicate().nonEmpty)
        XCTAssertNil(ElementPredicate(traits: []).nonEmpty)
        XCTAssertEqual(ElementPredicate(label: "Save").nonEmpty, ElementPredicate(label: "Save"))
    }

    func testElementPredicateDescriptionComposesFields() {
        let predicate = ElementPredicate.element(
            .label(#"Save "Now""#),
            .identifier("primary.save"),
            .value("Ready"),
            .exclude(.traits([.notEnabled])),
            traits: [.button, .selected]
        )

        XCTAssertEqual(
            predicate.description,
            #"predicate(label="Save \"Now\"" identifier="primary.save" value="Ready" exclude(traits=[notEnabled]) traits=[button, selected])"#
        )
    }

    func testElementPredicateTraitPayloadsAreStoredAsSets() {
        let first = ElementPredicate(traits: [.selected, .button])
        let second = ElementPredicate(traits: [.button, .selected, .button])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.description, "predicate(traits=[button, selected])")
        XCTAssertEqual(first.checks, [.traits([.button, .selected])])
    }

    func testElementPredicateTraitEncodingUsesCanonicalArrays() throws {
        let predicate = ElementPredicate.element(
            .traits([.selected, .button, .button]),
            .exclude(.traits([.notEnabled, .header, .notEnabled]))
        )

        let encoded = try JSONEncoder().encode(predicate)
        let wire = try JSONDecoder().decode(EncodedPredicateWire.self, from: encoded)

        XCTAssertEqual(wire.checks.map(\.kind), ["traits", "exclude"])
        XCTAssertEqual(wire.checks[0].values, ["button", "selected"])
        XCTAssertEqual(wire.checks[1].check?.kind, "traits")
        XCTAssertEqual(wire.checks[1].check?.values, ["header", "notEnabled"])
        XCTAssertEqual(try JSONDecoder().decode(ElementPredicate.self, from: encoded), predicate)
    }

    func testElementPredicateTemplateTraitPayloadsAreStoredAsSets() throws {
        let first = ElementPredicateTemplate(traits: [.selected, .button])
        let second = ElementPredicateTemplate(traits: [.button, .selected, .button])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.description, "predicate(traits=[button, selected])")

        let encoded = try JSONEncoder().encode(first)
        let wire = try JSONDecoder().decode(EncodedPredicateWire.self, from: encoded)
        XCTAssertEqual(wire.checks.first?.values, ["button", "selected"])
    }

    func testTraitSetMatchStoresSetsAndEncodesCanonicalArrays() throws {
        let first = TraitSetMatch(
            include: [.selected, .button, .button],
            exclude: [.notEnabled, .header, .notEnabled]
        )
        let second = TraitSetMatch(
            include: [.button, .selected],
            exclude: [.header, .notEnabled]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.description, "traits(include=[.button, .selected] exclude=[.header, .notEnabled])")

        let encoded = try JSONEncoder().encode(first)
        let wire = try JSONDecoder().decode(EncodedTraitSetMatchWire.self, from: encoded)
        XCTAssertEqual(wire.include, ["button", "selected"])
        XCTAssertEqual(wire.exclude, ["header", "notEnabled"])
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
        let data = Data(#"{"checks":[]}"#.utf8)

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
        let json = #"{"heistId":"save_button","checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]}"#

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
        XCTAssertEqual(predicate.checks, [.label(.exact("Save"))])
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let predicate = ElementPredicate.element(
            .label("Save"),
            .identifier("saveBtn"),
            .value("active"),
            .exclude(.traits([.notEnabled])),
            traits: [.button]
        )
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(ElementPredicate.self, from: data)
        XCTAssertEqual(predicate, decoded)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
          "checks": [
            { "kind": "label", "match": { "mode": "exact", "value": "Settings" } },
            { "kind": "traits", "values": ["header", "button"] },
            { "kind": "exclude", "check": { "kind": "traits", "values": ["notEnabled"] } }
          ]
        }
        """
        let data = Data(json.utf8)
        let predicate = try JSONDecoder().decode(ElementPredicate.self, from: data)
        XCTAssertEqual(predicate.checks, [
            .label(.exact("Settings")),
            .traits([.header, .button]),
            .exclude(.traits([.notEnabled])),
        ])
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

    func testEmptyStringTemplatePredicateTreatedAsNoPredicate() {
        let predicate = ElementPredicateTemplate(label: "", identifier: "", value: "")
        XCTAssertFalse(predicate.hasPredicates, "All-empty-string template predicate should have no predicates")
    }

    // MARK: - String Matching
    //
    // Client-side HeistElement.matches uses the same semantics as server-side
    // resolution: exact by default, explicit broad StringMatch modes when
    // authored, case-insensitive with typography folding.

    func testExactLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ElementPredicate(label: "Save")))
    }

    func testStringMatchUnlabeledInitializerDefaultsToExact() {
        XCTAssertEqual(StringMatch<String>("Save"), .exact("Save"))
    }

    func testStringMatchStringLiteralSugarStillCreatesExactMatch() {
        let match: StringMatch<String> = "Save"

        XCTAssertEqual(match, .exact("Save"))
    }

    func testStringMatchCanonicalObjectJSONRoundTrips() throws {
        let cases: [(json: String, match: StringMatch<String>)] = [
            (#"{"mode":"exact","value":"Save"}"#, .exact("Save")),
            (#"{"mode":"contains","value":"Save"}"#, .contains("Save")),
            (#"{"mode":"prefix","value":"Save"}"#, .prefix("Save")),
            (#"{"mode":"suffix","value":"Save"}"#, .suffix("Save")),
            (#"{"mode":"isEmpty"}"#, .isEmpty),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for testCase in cases {
            let decoded = try JSONDecoder().decode(
                StringMatch<String>.self,
                from: Data(testCase.json.utf8)
            )
            XCTAssertEqual(decoded, testCase.match)

            let encoded = try XCTUnwrap(String(data: encoder.encode(decoded), encoding: .utf8))
            XCTAssertEqual(encoded, testCase.json)
            XCTAssertEqual(
                try JSONDecoder().decode(StringMatch<String>.self, from: Data(encoded.utf8)),
                testCase.match
            )
        }
    }

    func testStringMatchRejectsRawStringJSON() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(StringMatch<String>.self, from: Data(#""Save""#.utf8))
        )
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

    func testExplicitBroadStringMatchesLabelIdentifierAndValue() {
        let element = HeistElement(
            description: "No results found",
            label: "No results found",
            value: "0 results",
            identifier: "empty_search_results_message",
            traits: [.staticText],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )

        XCTAssertTrue(element.matches(ElementPredicate(label: .contains("results"))))
        XCTAssertTrue(element.matches(ElementPredicate(label: .prefix("No results"))))
        XCTAssertTrue(element.matches(ElementPredicate(label: .suffix("found"))))
        XCTAssertTrue(element.matches(ElementPredicate(identifier: .contains("search_results"))))
        XCTAssertTrue(element.matches(ElementPredicate(identifier: .prefix("empty"))))
        XCTAssertTrue(element.matches(ElementPredicate(identifier: .suffix("message"))))
        XCTAssertTrue(element.matches(ElementPredicate(value: .contains("0 result"))))
        XCTAssertTrue(element.matches(ElementPredicate(value: .prefix("0"))))
        XCTAssertTrue(element.matches(ElementPredicate(value: .suffix("results"))))
        XCTAssertFalse(element.matches(ElementPredicate(label: "results")))
        XCTAssertFalse(element.matches(ElementPredicate(value: "0 result")))
    }

    func testIsEmptyStringMatchMatchesNilAndEmptyStrings() {
        let valuedElement = HeistElement(
            description: "Delete",
            label: "Delete",
            value: "Discount",
            identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )

        XCTAssertTrue(HeistElement.stub(label: "").matches(ElementPredicate(label: .isEmpty)))
        XCTAssertFalse(HeistElement.stub(label: "Save").matches(ElementPredicate(label: .isEmpty)))
        XCTAssertTrue(HeistElement.stub().matches(ElementPredicate(label: .isEmpty)))
        XCTAssertTrue(ElementPredicate(label: .isEmpty).hasPredicates)
        XCTAssertTrue(valuedElement.matches(ElementPredicate.exclude(.value(.isEmpty))))
        XCTAssertFalse(HeistElement.stub(label: "Delete").matches(ElementPredicate.exclude(.value(.isEmpty))))
    }

    func testSemanticSurfacePredicatesMatchHintActionsCustomContentAndRotors() {
        let element = HeistElement(
            description: "Combo row",
            label: "Coke",
            value: nil,
            identifier: "combo-choice-Coke",
            hint: "Double tap to edit",
            traits: [.staticText],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            customContent: [
                HeistCustomContent(label: "Slot", value: "Main", isImportant: true)
            ],
            rotors: [
                HeistRotor(name: "Actions")
            ],
            actions: [.activate, .custom("Modify")]
        )

        XCTAssertTrue(element.matches(ElementPredicate.hint(.contains("edit"))))
        XCTAssertTrue(element.matches(ElementPredicate.actions([.custom("Modify")])))
        XCTAssertTrue(element.matches(ElementPredicate.exclude(.actions([.custom("Sub")]))))
        XCTAssertTrue(element.matches(ElementPredicate.customContent(.match(label: "Slot", value: "Main"))))
        XCTAssertTrue(element.matches(ElementPredicate.exclude(.customContent(.match(label: "Discount")))))
        XCTAssertTrue(element.matches(ElementPredicate.rotors(["Actions"])))
        XCTAssertTrue(element.matches(ElementPredicate.exclude(.rotors(["Headings"]))))
        XCTAssertFalse(element.matches(ElementPredicate.exclude(.actions([.custom("Modify")]))))
        XCTAssertFalse(element.matches(ElementPredicate.customContent(.match(label: "Slot", value: "Side"))))
        XCTAssertFalse(element.matches(ElementPredicate.rotors(["Headings"])))
    }

    func testMultipleStringMatchesForSamePropertyMustAllMatch() {
        let element = HeistElement.stub(label: "foobarbaz")
        let predicate = ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz"))
        )

        XCTAssertTrue(element.matches(predicate))
        XCTAssertEqual(predicate.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
        ])
        XCTAssertFalse(element.matches(ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("qux"))
        )))
        XCTAssertFalse(HeistElement.stub(label: "foobarqux").matches(predicate))
    }

    func testRepeatedStringMatchesDecodeFromArrayJSON() throws {
        let data = Data(#"""
        {
          "checks": [
            { "kind": "label", "match": { "mode": "prefix", "value": "foo" } },
            { "kind": "label", "match": { "mode": "contains", "value": "bar" } },
            { "kind": "label", "match": { "mode": "suffix", "value": "baz" } },
            { "kind": "traits", "values": ["button"] }
          ]
        }
        """#.utf8)

        let predicate = try JSONDecoder().decode(ElementPredicate.self, from: data)

        XCTAssertEqual(predicate.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
            .traits([.button]),
        ])
        XCTAssertTrue(HeistElement.stub(label: "foobarbaz", traits: [.button]).matches(predicate))

        let encoded = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(ElementPredicate.self, from: encoded)
        XCTAssertEqual(decoded, predicate)
    }

    func testOrderedCheckDecodingRejectsFieldsThatDoNotMatchKind() {
        let labelWithValues = Data(#"""
        {
          "checks": [
            { "kind": "label", "match": { "mode": "exact", "value": "Save" }, "values": ["button"] }
          ]
        }
        """#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ElementPredicate.self, from: labelWithValues)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("values is not valid for label"))
        }

        let traitsWithMatch = Data(#"""
        {
          "checks": [
            { "kind": "traits", "match": { "mode": "exact", "value": "button" }, "values": ["button"] }
          ]
        }
        """#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ElementPredicate.self, from: traitsWithMatch)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("match is not valid for traits"))
        }
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

    func testExcludePredicateWorksForTraits() {
        let enabled = HeistElement.stub(label: "Submit", traits: [.button])
        let disabled = HeistElement.stub(label: "Submit", traits: [.button, .notEnabled])
        let predicate = ElementPredicate([.label("Submit"), .exclude(.traits([.notEnabled]))])
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

    func testStringContainsForExplicitMatchesAndSuggestions() {
        XCTAssertTrue(ElementPredicate.stringContains("Save Draft", "Save"))
        XCTAssertTrue(ElementPredicate.stringContains("Save Draft", "Draft"))
        XCTAssertTrue(ElementPredicate.stringContains("Don\u{2019}t skip", "Don't"))
    }
}

private struct EncodedPredicateWire: Decodable {
    let checks: [EncodedPredicateCheckWire]
}

private final class EncodedPredicateCheckWire: Decodable {
    let kind: String
    let values: [String]?
    let check: EncodedPredicateCheckWire?
}

private struct EncodedTraitSetMatchWire: Decodable {
    let include: [String]?
    let exclude: [String]?
}
