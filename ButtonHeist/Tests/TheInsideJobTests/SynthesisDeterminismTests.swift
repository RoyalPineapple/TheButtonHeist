#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Property + regression tests for `TheStash.IdAssignment.synthesizeBaseId(_:)`.
///
/// HeistId synthesis is wire-format. Changes to its output break recorded
/// heists and the agent's predict-the-heistId pattern that benchmarks rely
/// on. These tests lock the contract:
/// 1. Property: identical content produces identical heistIds across 200+
///    randomized permutations.
/// 2. Regression: a handful of known inputs produce specific known outputs.
@MainActor
final class SynthesisDeterminismTests: XCTestCase {

    private typealias IdAssignment = TheStash.IdAssignment

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: [HeistTrait] = []
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            identifier: identifier,
            heistTraits: traits
        )
    }

    // MARK: - Property: same content → same heistId

    func testSynthesisIsDeterministicAcrossRandomInputs() {
        // Seeded for reproducibility across runs / CI machines.
        var rng = SeededGenerator(seed: 0xBADC0FFE)
        let labelPool = ["Save", "Cancel", "OK", "Submit", "Edit", "Delete",
                          "Login", "Sign Up", "Continue", "Back", "Next",
                          "Search", "Settings", "Profile", "Home", nil]
        let valuePool: [String?] = ["on", "off", "0", "1", "selected", nil]
        let identifierPool: [String?] = [nil, "", "id1", "loginButton"]
        let traitPool: [[HeistTrait]] = [
            [], [.button], [.link], [.header], [.searchField],
            [.button, .selected], [.adjustable], [.image],
        ]

        for _ in 0..<200 {
            let element = makeElement(
                label: labelPool.randomElement(using: &rng) ?? nil,
                value: valuePool.randomElement(using: &rng) ?? nil,
                identifier: identifierPool.randomElement(using: &rng) ?? nil,
                traits: traitPool.randomElement(using: &rng) ?? []
            )
            let copy = makeElement(
                label: element.label,
                value: element.value,
                identifier: element.identifier,
                traits: traitPool.first { AccessibilityTraits.fromNames($0.map(\.rawValue)) == element.traits } ?? []
            )

            let first = IdAssignment.synthesizeBaseId(element)
            let second = IdAssignment.synthesizeBaseId(copy)
            let detail = "label=\(element.label ?? "nil") value=\(element.value ?? "nil") traits=\(element.traits.rawValue)"
            XCTAssertEqual(first, second,
                           "synthesizeBaseId must be content-deterministic: \(detail)")
        }
    }

    // MARK: - Regression: locked outputs for known inputs

    func testKnownInputsProduceKnownOutputs() {
        // Each tuple: (label, identifier, traits, expected heistId).
        // These are the wire-format contract. Modifying the expected outputs
        // is equivalent to bumping the wire format — only acceptable as part
        // of an explicit release with downstream coordination.
        let cases: [(label: String?, identifier: String?, traits: [HeistTrait], expected: String)] = [
            ("Save", nil, [.button], "save_button"),
            ("Cancel", nil, [.button], "cancel_button"),
            ("OK", nil, [.button], "ok_button"),
            ("Title", nil, [.header], "title_header"),
            ("Search", nil, [.searchField], "search_searchField"),
            // Static text fallback when no recognised trait
            ("Welcome", nil, [], "welcome_staticText"),
            // Adjustable trait
            ("Volume", nil, [.adjustable], "volume_adjustable"),
            // Image trait
            ("Logo", nil, [.image], "logo_image"),
            // Link trait
            ("Privacy Policy", nil, [.link], "privacy_policy_link"),
        ]

        for testCase in cases {
            let element = makeElement(
                label: testCase.label,
                identifier: testCase.identifier,
                traits: testCase.traits
            )
            let actual = IdAssignment.synthesizeBaseId(element)
            XCTAssertEqual(actual, testCase.expected,
                           "synthesizeBaseId wire-format regression: label=\(testCase.label ?? "nil") traits=\(testCase.traits.map(\.rawValue))")
        }
    }

    // MARK: - Regression: stripTraitSuffix wire-format contract
    //
    // `stripTraitSuffix` is wire format. Its output feeds the slug half of
    // `{slug}_{trait}` heistIds — any change in stripping behavior reshuffles
    // every synthesised id on screens whose labels duplicate their trait
    // name. The cases below pin the contract for single-word, multi-word,
    // partial, case-insensitive, and too-short inputs so regressions show up
    // at PR time, not after a release.

    func testStripTraitSuffixKnownInputsProduceKnownOutputs() {
        // Each tuple: (label, traitSuffix, expected). `nil` expected means
        // stripping is a no-op (the label IS the trait name, or doesn't
        // match the prefix, or is too short to strip).
        let cases: [(label: String?, traitSuffix: String, expected: String?)] = [
            // Single-word strip: label equals the trait suffix words → nil
            // (everything strips, the remainder is empty).
            ("Switch Button", "switchButton", nil),
            // Multi-word strip: leading words match suffix, remainder kept.
            ("Switch Button Off", "switchButton", "Off"),
            // Partial strip: second word doesn't match second suffix word → nil.
            ("Switch Off", "switchButton", nil),
            // Case-insensitive comparison preserves the original casing
            // of the remainder.
            ("SWITCH BUTTON Off", "switchButton", "Off"),
            // Too few words: label has fewer words than the suffix expands to → nil.
            ("Button", "backButton", nil),
            // Single-word camelCase suffix splits into one word.
            ("Image Logo", "image", "Logo"),
            // Multi-word remainder is preserved with single-space joiner.
            ("Text Entry Email Address", "textEntry", "Email Address"),
            // Three-word remainder, leading suffix words matched.
            ("Search Field Find My Phone", "searchField", "Find My Phone"),
            // Nil label is a no-op.
            (nil, "button", nil),
        ]

        for testCase in cases {
            let actual = IdAssignment.stripTraitSuffix(testCase.label, traitSuffix: testCase.traitSuffix)
            XCTAssertEqual(
                actual,
                testCase.expected,
                "stripTraitSuffix wire-format regression: label=\(testCase.label ?? "nil") suffix=\(testCase.traitSuffix)"
            )
        }
    }
}

// MARK: - Seeded RNG (deterministic)

/// Linear congruential generator with a fixed seed so the property test
/// produces the same sequence on every run. Don't use for crypto — this
/// only exists to make randomised tests reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &*= 6_364_136_223_846_793_005
        state &+= 1_442_695_040_888_963_407
        return state
    }
}

#endif // canImport(UIKit)
