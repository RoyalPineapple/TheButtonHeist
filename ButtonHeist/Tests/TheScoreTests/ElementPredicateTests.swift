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

    func testAuthoredPredicateMustResolveBeforeMatching() throws {
        XCTAssertThrowsError(try ElementPredicate().resolve(in: .empty))

        let authored = ElementPredicate.label("Save")
        XCTAssertEqual(try authored.resolve(in: .empty), .label("Save"))
    }

    func testElementPredicateDescriptionComposesFields() throws {
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
        XCTAssertEqual(try predicate.resolve(in: .empty).description, predicate.description)
    }

    func testElementPredicateTraitPayloadsAreStoredAsSets() {
        let first = ElementPredicate(traits: [.selected, .button])
        let second = ElementPredicate(traits: [.button, .selected, .button])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.description, "predicate(traits=[button, selected])")
        XCTAssertEqual(first.checks, [.traits([.button, .selected])])
    }

    func testElementPredicateTraitEncodingUsesCanonicalArrays() throws {
        let predicate = try ElementPredicate.element(
            .traits([.selected, .button, .button]),
            .exclude(.traits([.notEnabled, .header, .notEnabled]))
        ).resolve(in: .empty)

        let encoded = try JSONEncoder().encode(predicate)
        let wire = try JSONDecoder().decode(EncodedPredicateWire.self, from: encoded)

        XCTAssertEqual(wire.checks.map(\.kind), ["traits", "exclude"])
        XCTAssertEqual(wire.checks[0].values, ["button", "selected"])
        XCTAssertEqual(wire.checks[1].check?.kind, "traits")
        XCTAssertEqual(wire.checks[1].check?.values, ["header", "notEnabled"])
        XCTAssertEqual(try JSONDecoder().decode(ResolvedElementPredicate.self, from: encoded), predicate)
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

        let encoded = try JSONEncoder().encode(first)
        let wire = try JSONDecoder().decode(EncodedTraitSetMatchWire.self, from: encoded)
        XCTAssertEqual(wire.include, ["button", "selected"])
        XCTAssertEqual(wire.exclude, ["header", "notEnabled"])
    }

    func testElementPredicateRejectsEmptyAuthoredStringsAtResolution() {
        let predicate = ElementPredicate(label: "", identifier: "", value: "", traits: [])

        XCTAssertThrowsError(try predicate.resolve(in: .empty))
    }

    func testElementPredicateRejectsUnknownFields() {
        let json = #"{"heistId":"save_button"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ResolvedElementPredicate.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, #"Unknown element predicate field "heistId""#)
        }
    }

    func testAccessibilityTargetDescriptionComposesPredicateAndOrdinal() {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 1)

        XCTAssertEqual(target.description, #"target(predicate(label="Save" traits=[button]) ordinal=1)"#)
    }

    func testAccessibilityTargetRejectsOrdinalOnlySelector() throws {
        let data = Data(#"{"ordinal":1}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTarget.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("AccessibilityTarget predicate requires"))
        }
    }

    func testAccessibilityTargetRejectsEmptyPredicateSelector() throws {
        let data = Data(#"{"checks":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTarget.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("predicate requires"))
        }
    }

    func testAccessibilityTargetRejectsHeistIdKey() {
        // heistId is no longer a targeting field — it is an unknown key.
        let json = #"{"heistId":"save_button"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testAccessibilityTargetRejectsHeistIdAlongsidePredicate() {
        let json = #"{"heistId":"save_button","checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testScrollToVisibleTargetWithAccessibilityTarget() {
        let target = ScrollToVisibleTarget(target: .predicate(ElementPredicate(label: "Save")))
        guard case .predicate(let predicate, _) = target.target else {
            return XCTFail("Expected .predicate")
        }
        XCTAssertEqual(predicate.checks, [.label(.exact("Save"))])
    }

    // MARK: - Codable Round-Trip

    func testEncodeDecodeAllFields() throws {
        let predicate = try ElementPredicate.element(
            .label("Save"),
            .identifier("saveBtn"),
            .value("active"),
            .exclude(.traits([.notEnabled])),
            traits: [.button]
        ).resolve(in: .empty)
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(ResolvedElementPredicate.self, from: data)
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
        let predicate = try JSONDecoder().decode(ResolvedElementPredicate.self, from: data)
        XCTAssertEqual(
            predicate,
            try ElementPredicate([
                .label("Settings"),
                .traits([.header, .button]),
                .exclude(.traits([.notEnabled])),
            ]).resolve(in: .empty)
        )
    }

    // MARK: - Empty String Handling

    func testEmptyStringTemplatesCannotProduceResolvedPredicates() {
        XCTAssertThrowsError(try ElementPredicate.label("").resolve(in: .empty))
        XCTAssertThrowsError(try ElementPredicate.identifier("").resolve(in: .empty))
        XCTAssertThrowsError(try ElementPredicate.value("").resolve(in: .empty))
        XCTAssertThrowsError(
            try ElementPredicate(label: "", identifier: "", value: "").resolve(in: .empty)
        )
    }

    // MARK: - String Matching
    //
    // Client-side HeistElement.matches uses the same semantics as server-side
    // resolution: exact by default, explicit broad StringMatch modes when
    // authored, case-insensitive with typography folding.

    func testExactLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("Save")))
    }

    func testStringMatchUnlabeledInitializerDefaultsToExact() {
        XCTAssertEqual(StringMatch("Save"), .exact("Save"))
    }

    func testStringMatchStringLiteralSugarStillCreatesExactMatch() {
        let match: StringMatch = "Save"

        XCTAssertEqual(match, .exact("Save"))
    }

    func testStringMatchCanonicalObjectJSONRoundTrips() throws {
        let cases: [(json: String, match: StringMatch)] = [
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
                StringMatch.self,
                from: Data(testCase.json.utf8)
            )
            XCTAssertEqual(decoded, testCase.match)

            let encoded = try XCTUnwrap(String(data: encoder.encode(decoded), encoding: .utf8))
            XCTAssertEqual(encoded, testCase.json)
            XCTAssertEqual(
                try JSONDecoder().decode(StringMatch.self, from: Data(encoded.utf8)),
                testCase.match
            )
        }
    }

    func testStringMatchRejectsRawStringJSON() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(StringMatch.self, from: Data(#""Save""#.utf8))
        )
    }

    func testCaseInsensitiveLabelMatches() {
        let element = HeistElement.stub(label: "Save")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("save")))
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("SAVE")))
    }

    func testSubstringPartialDoesNotMatch() {
        // Exact-or-miss: "Sav" must not match "Save".
        let element = HeistElement.stub(label: "Save")
        XCTAssertFalse(element.matches(ResolvedElementPredicate.label("Sav")))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.label("ave")))
    }

    func testSupersetLabelNoLongerMatches() {
        // "Save" is a substring of "Save Draft" — under substring matching the
        // pattern "Save" would have hit "Save Draft". Now it must not.
        let element = HeistElement.stub(label: "Save Draft")
        XCTAssertFalse(element.matches(ResolvedElementPredicate.label("Save")))
        // The full label still matches.
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("Save Draft")))
    }

    func testExplicitBroadStringMatchesLabelIdentifierAndValue() throws {
        let element = HeistElement(
            description: "No results found",
            label: "No results found",
            value: "0 results",
            identifier: "empty_search_results_message",
            traits: [.staticText],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )

        XCTAssertTrue(element.matches(try ElementPredicate(label: .contains("results")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(label: .prefix("No results")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(label: .suffix("found")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(identifier: .contains("search_results")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(identifier: .prefix("empty")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(identifier: .suffix("message")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(value: .contains("0 result")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(value: .prefix("0")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate(value: .suffix("results")).resolve(in: .empty)))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.label("results")))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.value("0 result")))
    }

    func testIsEmptyStringMatchMatchesNilAndEmptyStrings() throws {
        let valuedElement = HeistElement(
            description: "Delete",
            label: "Delete",
            value: "Discount",
            identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )

        let emptyLabel = try ElementPredicate(label: .isEmpty).resolve(in: .empty)
        let nonEmptyValue = try ElementPredicate.exclude(.value(.isEmpty)).resolve(in: .empty)
        XCTAssertTrue(HeistElement.stub(label: "").matches(emptyLabel))
        XCTAssertFalse(HeistElement.stub(label: "Save").matches(emptyLabel))
        XCTAssertTrue(HeistElement.stub().matches(emptyLabel))
        XCTAssertTrue(emptyLabel.hasPredicates)
        XCTAssertTrue(valuedElement.matches(nonEmptyValue))
        XCTAssertFalse(HeistElement.stub(label: "Delete").matches(nonEmptyValue))
    }

    func testSemanticSurfacePredicatesMatchHintActionsCustomContentAndRotors() throws {
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

        XCTAssertTrue(element.matches(try ElementPredicate.hint(.contains("edit")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.actions([.custom("Modify")]).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.exclude(.actions([.custom("Sub")])).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.customContent(.init(label: "Slot", value: "Main")).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.exclude(.customContent(.init(label: "Discount"))).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.rotors(["Actions"]).resolve(in: .empty)))
        XCTAssertTrue(element.matches(try ElementPredicate.exclude(.rotors(["Headings"])).resolve(in: .empty)))
        XCTAssertFalse(element.matches(try ElementPredicate.exclude(.actions([.custom("Modify")])).resolve(in: .empty)))
        XCTAssertFalse(element.matches(try ElementPredicate.customContent(.init(label: "Slot", value: "Side")).resolve(in: .empty)))
        XCTAssertFalse(element.matches(try ElementPredicate.rotors(["Headings"]).resolve(in: .empty)))
    }

    func testMultipleStringMatchesForSamePropertyMustAllMatch() throws {
        let element = HeistElement.stub(label: "foobarbaz")
        let predicate = try ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz"))
        ).resolve(in: .empty)

        XCTAssertTrue(element.matches(predicate))
        XCTAssertFalse(element.matches(try ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("qux"))
        ).resolve(in: .empty)))
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

        let predicate = try JSONDecoder().decode(ResolvedElementPredicate.self, from: data)

        XCTAssertEqual(
            predicate,
            try ElementPredicate([
                .label(.prefix("foo")),
                .label(.contains("bar")),
                .label(.suffix("baz")),
                .traits([.button]),
            ]).resolve(in: .empty)
        )
        XCTAssertTrue(HeistElement.stub(label: "foobarbaz", traits: [.button]).matches(predicate))

        let encoded = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(ResolvedElementPredicate.self, from: encoded)
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

        XCTAssertThrowsError(try JSONDecoder().decode(ResolvedElementPredicate.self, from: labelWithValues)) { error in
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

        XCTAssertThrowsError(try JSONDecoder().decode(ResolvedElementPredicate.self, from: traitsWithMatch)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("match is not valid for traits"))
        }
    }

    func testTypographyFoldingOnLabel() {
        // Smart apostrophe in label, ASCII apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don\u{2019}t skip")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("Don't skip")))
    }

    func testTypographyFoldingOnPattern() {
        // ASCII apostrophe in label, smart apostrophe in pattern — must match.
        let element = HeistElement.stub(label: "Don't skip")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("Don\u{2019}t skip")))
    }

    func testEmDashFoldingOnLabel() {
        let element = HeistElement.stub(label: "wait \u{2014} stop")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("wait - stop")))
    }

    func testEllipsisFolding() {
        let element = HeistElement.stub(label: "Loading\u{2026}")
        XCTAssertTrue(element.matches(ResolvedElementPredicate.label("Loading...")))
    }

    func testIdentifierExactMatch() {
        let element = HeistElement(
            description: "x", label: nil, value: nil,
            identifier: "save_btn", traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ResolvedElementPredicate.identifier("save_btn")))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.identifier("save")))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.identifier("save_btn_extra")))
    }

    func testValueExactMatch() {
        let element = HeistElement(
            description: "x", label: nil, value: "50%",
            identifier: nil, traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        XCTAssertTrue(element.matches(ResolvedElementPredicate.value("50%")))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.value("5")))
    }

    func testTraitsStillExactBitmaskComparison() {
        let element = HeistElement.stub(label: "Submit", traits: [.button])
        XCTAssertTrue(element.matches(ResolvedElementPredicate.traits([.button])))
        XCTAssertFalse(element.matches(ResolvedElementPredicate.traits([.button, .selected])))
    }

    func testExcludePredicateWorksForTraits() throws {
        let enabled = HeistElement.stub(label: "Submit", traits: [.button])
        let disabled = HeistElement.stub(label: "Submit", traits: [.button, .notEnabled])
        let predicate = try ElementPredicate([
            .label("Submit"),
            .exclude(.traits([.notEnabled])),
        ]).resolve(in: .empty)
        XCTAssertTrue(enabled.matches(predicate))
        XCTAssertFalse(disabled.matches(predicate))
    }

    func testCompoundPredicateAllFieldsExact() throws {
        let element = HeistElement(
            description: "Dark Mode", label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
        )
        let predicate = try ElementPredicate(
            label: "Dark Mode",
            identifier: "darkModeToggle",
            value: "ON",
            traits: [.button, .selected]
        ).resolve(in: .empty)
        XCTAssertTrue(element.matches(predicate))
        // Wrong value — must miss
        let wrongValue = try ElementPredicate(
            label: "Dark Mode", identifier: "darkModeToggle", value: "OFF",
            traits: [.button, .selected]
        ).resolve(in: .empty)
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
