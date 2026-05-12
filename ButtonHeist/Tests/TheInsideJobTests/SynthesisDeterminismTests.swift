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
                traits: traitPool.first { UIAccessibilityTraits.fromNames($0.map(\.rawValue)) == element.traits } ?? []
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
