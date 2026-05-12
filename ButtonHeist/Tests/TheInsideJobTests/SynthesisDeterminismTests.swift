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

    func testStripTraitSuffixIsDeterministicAcrossRepeatedCalls() {
        // Property: repeated calls with identical inputs must produce
        // identical outputs. Locks the regression-table contract above
        // against hidden statefulness creeping in.
        var rng = SeededGenerator(seed: 0xDEADBEEF)
        let labelPool: [String?] = [
            "Switch Button Off", "Switch Button", "Image Logo", "Button",
            "Text Entry Email", "Back Button Home", "Search Field Q", nil,
        ]
        let suffixPool = ["switchButton", "button", "image", "backButton",
                          "textEntry", "searchField", "header"]

        for _ in 0..<200 {
            let label = labelPool.randomElement(using: &rng) ?? nil
            guard let suffix = suffixPool.randomElement(using: &rng) else { continue }
            let first = IdAssignment.stripTraitSuffix(label, traitSuffix: suffix)
            let second = IdAssignment.stripTraitSuffix(label, traitSuffix: suffix)
            XCTAssertEqual(
                first,
                second,
                "stripTraitSuffix must be deterministic: label=\(label ?? "nil") suffix=\(suffix)"
            )
        }
    }
}

// MARK: - Regression: duplicate-heistId disambiguation through buildScreen
//
// `TheBurglar.buildScreen(from:)` is the only production caller of both
// disambiguation passes: `IdAssignment.assign` Phase 2 (`_N` suffix) and
// `TheBurglar.resolveHeistIds` (`_at_X_Y` content-position suffix). Both
// outputs are wire format — agents predict them when iterating over
// duplicated rows in scrollable lists.
//
// CONTRACT BOUNDARY (locked by the cases below): Phase 2 runs FIRST and
// adds `_1`/`_2` suffixes to every duplicate base id, including
// same-matcher elements that share content-space coordinates. Because
// Phase 2 has already distinct-ified the base ids, `resolveHeistIds`
// never observes a `seen[heistId]` collision through the live
// `buildScreen` pipeline — the `_at_X_Y` path is structurally
// unreachable for in-pipeline callers and acts as a defensive safety
// net for hypothetical future callers that bypass Phase 2.
//
// The cases below drive `TheBurglar.buildScreen(from:)` end-to-end with
// real `UIScrollView` instances and lock:
// 1. Two same-matcher duplicates at distinct origins → `_1` / `_2`.
// 2. Three same-matcher duplicates at distinct origins → `_1` / `_2` / `_3`.
// 3. Two same-matcher duplicates within the 0.5pt epsilon → still `_1` / `_2`
//    because Phase 2 fires on label/trait identity, not position. Both
//    entries survive in `screen.elements` (Phase 2 keeps them distinct).
// 4. Two different-matcher elements with the same synthesised base →
//    `_1` / `_2` and never `_at_X_Y`. Locks the boundary that Phase 2
//    owns this disambiguation, not the content-position path.
//
// If any test in this file ever produces an `_at_X_Y` suffix through
// `buildScreen`, the disambiguation contract has shifted and the change
// must be coordinated with downstream wire-format consumers.
@MainActor
final class HeistIdDisambiguationTests: XCTestCase {

    private typealias IdAssignment = TheStash.IdAssignment

    // MARK: - Helpers

    /// Anchor window kept alive for the lifetime of a test so the
    /// `scrollView.convert(_:from:)` calls in `TheBurglar` resolve against
    /// a deterministic window coordinate space.
    private var anchorWindow: UIWindow?

    override func setUp() async throws {
        try await super.setUp()
        anchorWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
    }

    override func tearDown() async throws {
        anchorWindow?.isHidden = true
        anchorWindow = nil
        try await super.tearDown()
    }

    /// Build a `ParseResult` with one scrollable container whose children are
    /// the given elements. The scroll view is parented to an anchor window
    /// at the origin so the content-space conversion is the identity
    /// transform — every element's `frame.origin` becomes its
    /// `contentSpaceOrigin` directly.
    private func makeScrollableParseResult(
        elements: [AccessibilityElement]
    ) -> TheBurglar.ParseResult {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
        scrollView.contentSize = CGSize(width: 320, height: 4000)
        anchorWindow?.addSubview(scrollView)

        let container = AccessibilityContainer(
            type: .scrollable(contentSize: scrollView.contentSize),
            frame: scrollView.frame
        )
        let children: [AccessibilityHierarchy] = elements.enumerated().map { index, element in
            .element(element, traversalIndex: index)
        }
        return TheBurglar.ParseResult(
            elements: elements,
            hierarchy: [.container(container, children: children)],
            objects: [:],
            scrollViews: [container: scrollView]
        )
    }

    private func makeButton(
        label: String,
        frame: CGRect,
        value: String? = nil
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            traits: .button,
            shape: .frame(frame),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            respondsToUserInteraction: true
        )
    }

    private func assertNoContentPositionSuffix(in screen: Screen, file: StaticString = #filePath, line: UInt = #line) {
        for heistId in screen.elements.keys {
            XCTAssertFalse(
                heistId.contains("_at_"),
                "buildScreen produced an `_at_X_Y` suffix — the disambiguation contract has shifted: \(heistId)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Regression table

    /// Two same-matcher elements at distinct content-space origins → Phase 2
    /// `_1` / `_2` suffixes. The `_at_X_Y` path is structurally unreachable
    /// through `buildScreen` because Phase 2 distinct-ifies first.
    func testTwoSameMatcherDuplicatesProducePhase2Suffixes() {
        let upper = makeButton(label: "Row", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let lower = makeButton(label: "Row", frame: CGRect(x: 0, y: 400, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [upper, lower])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2,
                       "Both elements should survive disambiguation")
        XCTAssertEqual(screen.heistIdByElement[upper], "row_button_1")
        XCTAssertEqual(screen.heistIdByElement[lower], "row_button_2")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Three same-matcher elements → `_1` / `_2` / `_3` in traversal order.
    func testThreeSameMatcherDuplicatesProduceSequentialPhase2Suffixes() {
        let first = makeButton(label: "Item", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let second = makeButton(label: "Item", frame: CGRect(x: 0, y: 100, width: 320, height: 44))
        let third = makeButton(label: "Item", frame: CGRect(x: 0, y: 250, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [first, second, third])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 3,
                       "All three same-matcher rows should produce distinct heistIds")
        XCTAssertEqual(screen.heistIdByElement[first], "item_button_1")
        XCTAssertEqual(screen.heistIdByElement[second], "item_button_2")
        XCTAssertEqual(screen.heistIdByElement[third], "item_button_3")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Two same-matcher elements within the 0.5pt epsilon → Phase 2 still
    /// applies its `_1` / `_2` suffix because Phase 2 keys on label/trait,
    /// not position. Both elements survive in `screen.elements`.
    func testSameMatcherDuplicatesWithinHalfPointEpsilonStillDisambiguatedByPhase2() {
        let first = makeButton(label: "Cell", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let second = makeButton(label: "Cell", frame: CGRect(x: 0, y: 0.3, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [first, second])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2,
                       "Phase 2 distinct-ifies before content-position epsilon collapse applies")
        XCTAssertEqual(screen.heistIdByElement[first], "cell_button_1")
        XCTAssertEqual(screen.heistIdByElement[second], "cell_button_2")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Two different-matcher elements that synthesise to the same base id
    /// → Phase 2 `_1` / `_2`, never `_at_X_Y`.
    ///
    /// Setup: both elements have nil label, no identifier, no recognised
    /// trait, and the same `description` of "thing" but distinct `value`s.
    /// `synthesizeBaseId` excludes value, so both → "thing_element".
    /// `hasSameMinimumMatcher` returns false because values differ when
    /// both label and identifier are empty — but `resolveHeistIds` never
    /// sees the collision because Phase 2 already distinct-ified the bases.
    func testDifferentMatcherCollisionUsesPhase2NotAtXY() {
        let firstFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        let secondFrame = CGRect(x: 0, y: 500, width: 100, height: 44)
        let first = AccessibilityElement.make(
            description: "thing",
            label: nil,
            value: "alpha",
            shape: .frame(firstFrame),
            activationPoint: CGPoint(x: firstFrame.midX, y: firstFrame.midY)
        )
        let second = AccessibilityElement.make(
            description: "thing",
            label: nil,
            value: "beta",
            shape: .frame(secondFrame),
            activationPoint: CGPoint(x: secondFrame.midX, y: secondFrame.midY)
        )

        let result = makeScrollableParseResult(elements: [first, second])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2)
        XCTAssertEqual(screen.heistIdByElement[first], "thing_element_1",
                       "Different-matcher collisions resolve via Phase 2 `_N` suffixes")
        XCTAssertEqual(screen.heistIdByElement[second], "thing_element_2")
        assertNoContentPositionSuffix(in: screen)
    }

    // MARK: - Determinism

    /// Property: identical inputs produce identical outputs across repeated
    /// calls. The disambiguation pipeline runs through dictionary
    /// iteration, which can pick up non-determinism if the implementation
    /// drifts; this guards against that.
    func testHeistIdDisambiguationIsDeterministic() {
        for _ in 0..<200 {
            let upper = makeButton(label: "Row", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let lower = makeButton(label: "Row", frame: CGRect(x: 0, y: 400, width: 320, height: 44))
            let first = TheBurglar.buildScreen(from: makeScrollableParseResult(elements: [upper, lower]))
            let second = TheBurglar.buildScreen(from: makeScrollableParseResult(elements: [upper, lower]))
            XCTAssertEqual(Set(first.elements.keys), Set(second.elements.keys),
                           "buildScreen must produce the same heistIds for the same inputs")
            XCTAssertEqual(first.heistIdByElement[upper], second.heistIdByElement[upper])
            XCTAssertEqual(first.heistIdByElement[lower], second.heistIdByElement[lower])
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
