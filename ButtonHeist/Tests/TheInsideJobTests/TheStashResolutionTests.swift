#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheStashResolutionTests: XCTestCase {

    private var bagman: TheStash!

    override func setUp() async throws {
        bagman = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        bagman = nil
    }

    // MARK: - Helpers

    private func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: nil,
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

    /// Accumulated hierarchy nodes for matcher resolution.
    private var hierarchyNodes: [AccessibilityHierarchy] = []

    /// Register an element in the registry, currentHierarchy, and reverse index.
    private func register(_ element: AccessibilityElement, heistId: String, index: Int) {
        bagman.registry.insertForTesting(TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        ))
        // Add to hierarchy and reverse index for matcher resolution
        hierarchyNodes.append(.element(element, traversalIndex: index))
        bagman.currentHierarchy = hierarchyNodes
        bagman.registry.reverseIndex[element] = heistId
        bagman.registry.viewportIds.insert(heistId)
    }

    /// Register an element in the registry ONLY (not in currentHierarchy).
    /// Simulates an explored off-screen element that was discovered by full explore
    /// but is not currently visible in the viewport.
    private func registerOffScreen(_ element: AccessibilityElement, heistId: String) {
        bagman.registry.insertForTesting(TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        ))
        bagman.registry.reverseIndex[element] = heistId
    }

    // MARK: - heistId Resolution

    func testHeistIdResolvesPresented() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.heistId("button_ok"))
        guard let resolved = result.resolved else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "OK")
    }

    func testHeistIdNotFoundReturnsNotFound() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.heistId("button_nope"))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("Element not found"))
    }

    func testHeistIdNotFoundShowsSimilar() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.heistId("button"))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("button_ok"), "Should suggest similar heistId")
    }

    // MARK: - Matcher Resolution

    func testMatcherResolvesUniqueElement() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard let resolved = result.resolved else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    func testMatcherAmbiguousReturnsCandidates() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard case .ambiguous(let candidates, let diagnostics) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testMatcherAmbiguousCandidatesIncludeDetails() {
        let save1 = element(label: "Save", value: "draft", identifier: "save1")
        let save2 = element(label: "Save", value: "final", identifier: "save2")
        register(save1, heistId: "save1", index: 0)
        register(save2, heistId: "save2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard case .ambiguous(let candidates, _) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertTrue(candidates[0].contains("id=save1"))
        XCTAssertTrue(candidates[1].contains("id=save2"))
    }

    func testMatcherNoMatchReturnsNotFound() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Cancel")))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("No match for"))
    }

    func testMatcherNearMissDiagnostics() {
        let element = element(label: "Save", value: "draft")
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save", value: "final")))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("near miss"), "Should show near-miss: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("value"), "Should identify value as divergent field")
    }

    // MARK: - TargetResolution Convenience Properties

    func testResolvedPropertyReturnsNilForNotFound() {
        let result = bagman.resolveTarget(.heistId("nope"))
        XCTAssertNil(result.resolved)
    }

    func testResolvedPropertyReturnsNilForAmbiguous() {
        let save1 = element(label: "Save")
        let save2 = element(label: "Save")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        XCTAssertNil(result.resolved)
    }

    func testDiagnosticsEmptyForResolved() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(.heistId("button_ok"))
        XCTAssertEqual(result.diagnostics, "")
    }

    // MARK: - Ambiguous Matcher Diagnostics

    func testAmbiguousMatcherReturnsDiagnostics() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        XCTAssertTrue(result.diagnostics.contains("2 elements match"), "Should return ambiguous message: \(result.diagnostics)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Anything")))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("screen is empty"))
    }

    // MARK: - Ordinal Selection

    func testOrdinalSelectsNthMatch() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        let save3 = element(label: "Save", value: "archive")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)
        register(save3, heistId: "button_save_3", index: 2)

        let result0 = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: 0))
        XCTAssertEqual(result0.resolved?.element.value, "draft")

        let result1 = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: 1))
        XCTAssertEqual(result1.resolved?.element.value, "final")

        let result2 = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: 2))
        XCTAssertEqual(result2.resolved?.element.value, "archive")
    }

    func testOrdinalOutOfBoundsReturnsNotFound() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: 5))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("ordinal 5 requested"))
        XCTAssertTrue(diagnostics.contains("2 matches"))
    }

    func testOrdinalNilPreservesAmbiguousBehavior() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard case .ambiguous(_, let diagnostics) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("2 elements match"))
        XCTAssertTrue(diagnostics.contains("ordinal"), "Should hint about ordinal usage")
    }

    func testOrdinalZeroOnSingleMatchSucceeds() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: 0))
        XCTAssertNotNil(result.resolved)
        XCTAssertEqual(result.resolved?.element.label, "Save")
    }

    func testNegativeOrdinalReturnsNotFound() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"), ordinal: -1))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("non-negative"))
    }

    func testOrdinalZeroOnNoMatchReturnsNotFound() {
        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Nonexistent"), ordinal: 0))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("ordinal 0 requested"))
        XCTAssertTrue(diagnostics.contains("0 matches"))
    }

    // MARK: - Early-Exit Matching

    func testMatchesWithLimitStopsEarly() {
        let elements = (0..<10).map { index in
            element(label: "Item", value: "\(index)")
        }
        for (index, element) in elements.enumerated() {
            register(element, heistId: "item_\(index)", index: index)
        }

        let limit3 = bagman.currentHierarchy.matches(ElementMatcher(label: "Item"), mode: .substring, limit: 3)
        XCTAssertEqual(limit3.count, 3)
        XCTAssertEqual(limit3[0].element.value, "0")
        XCTAssertEqual(limit3[1].element.value, "1")
        XCTAssertEqual(limit3[2].element.value, "2")
    }

    func testMatchesWithLimitExceedingCountReturnsAll() {
        let element1 = element(label: "Save", value: "one")
        let element2 = element(label: "Save", value: "two")
        register(element1, heistId: "save_1", index: 0)
        register(element2, heistId: "save_2", index: 1)

        let results = bagman.currentHierarchy.matches(ElementMatcher(label: "Save"), mode: .substring, limit: 10)
        XCTAssertEqual(results.count, 2)
    }

    func testMatchesWithLimitZeroReturnsEmpty() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let results = bagman.currentHierarchy.matches(ElementMatcher(label: "Save"), mode: .substring, limit: 0)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Select + Mark Presented Tracking

    func testSelectElementsReturnsSortedByTraversalOrder() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.selectElements()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].heistId, "button_save")
    }

    func testSelectElementsIncludesOffScreenElements() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "OffScreen", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        register(offScreen, heistId: "button_offscreen", index: 1)

        // Simulate off-viewport: only "button_visible" is in the viewport set
        bagman.registry.viewportIds = Set(["button_visible"])

        let all = bagman.selectElements()
        XCTAssertEqual(all.count, 2, "Should return both visible and off-screen elements")
        let heistIds = all.map(\.heistId)
        XCTAssertTrue(heistIds.contains("button_visible"))
        XCTAssertTrue(heistIds.contains("button_offscreen"))
    }

    // MARK: - Off-Screen Matcher Fallback

    func testMatcherFallsBackToRegistryForOffScreenElement() {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        register(onScreen, heistId: "button_visible", index: 0)
        registerOffScreen(offScreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Long List", traits: [.button])))
        guard let resolved = result.resolved else {
            XCTFail("Expected .resolved from registry fallback, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Long List")
    }

    func testMatcherPrefersHierarchyOverRegistry() {
        let onScreen = element(label: "Save", traits: .button)
        let offScreen = element(label: "Save Offscreen", traits: .button)
        register(onScreen, heistId: "button_save", index: 0)
        registerOffScreen(offScreen, heistId: "button_save_offscreen")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard let resolved = result.resolved else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save", "Should prefer on-screen hierarchy match")
    }

    func testMatcherRegistryFallbackAmbiguous() {
        let offScreen1 = element(label: "Item", value: "one", traits: .button)
        let offScreen2 = element(label: "Item", value: "two", traits: .button)
        registerOffScreen(offScreen1, heistId: "item_1")
        registerOffScreen(offScreen2, heistId: "item_2")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Item")))
        guard case .ambiguous(let candidates, let diagnostics) = result else {
            XCTFail("Expected .ambiguous from registry fallback, got \(result)")
            return
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testMatcherRegistryFallbackWithOrdinal() {
        let offScreen1 = element(label: "Item", value: "first")
        let offScreen2 = element(label: "Item", value: "second")
        registerOffScreen(offScreen1, heistId: "item_1")
        registerOffScreen(offScreen2, heistId: "item_2")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Item"), ordinal: 0))
        XCTAssertNotNil(result.resolved, "Should resolve off-screen element with ordinal 0")
    }

    func testMatcherRegistryFallbackOrdinalUsesDeterministicHeistIdOrder() {
        let offScreenB = element(label: "Item", value: "b")
        let offScreenA = element(label: "Item", value: "a")
        registerOffScreen(offScreenB, heistId: "item_b")
        registerOffScreen(offScreenA, heistId: "item_a")

        let first = bagman.resolveTarget(.matcher(ElementMatcher(label: "Item"), ordinal: 0)).resolved
        let second = bagman.resolveTarget(.matcher(ElementMatcher(label: "Item"), ordinal: 1)).resolved

        XCTAssertEqual(first?.screenElement.heistId, "item_a")
        XCTAssertEqual(second?.screenElement.heistId, "item_b")
    }

    func testMatcherRegistryFallbackOrdinalOutOfBounds() {
        let offScreen = element(label: "Item", value: "only")
        registerOffScreen(offScreen, heistId: "item_1")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Item"), ordinal: 5))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("ordinal 5 requested"))
    }

    func testOffScreenMatcherResolvesViaRegistryFallback() {
        let offScreen = element(label: "Hidden Button", traits: .button)
        registerOffScreen(offScreen, heistId: "hidden_button")

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Hidden Button")))
        XCTAssertEqual(result.resolved?.element.label, "Hidden Button")
        XCTAssertEqual(result.resolved?.screenElement.heistId, "hidden_button")
    }

    func testHasTargetIgnoresOffScreenMatcherInRegistry() {
        let offScreen = element(label: "Below Fold", traits: .button)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        // hasTarget checks live hierarchy only — registry-only elements are invisible
        // so wait_for absent works correctly when elements leave the screen
        XCTAssertFalse(bagman.hasTarget(.matcher(ElementMatcher(label: "Below Fold"))))
    }

    func testHasTargetIgnoresOffScreenHeistIdInRegistry() {
        let offScreen = element(label: "Below Fold", traits: .button)
        registerOffScreen(offScreen, heistId: "below_fold_button")

        // heistId target resolution can still use persistent registry memory, but
        // wait_for presence/absence must reflect the current live accessibility tree.
        XCTAssertNotNil(bagman.resolveTarget(.heistId("below_fold_button")).resolved)
        XCTAssertFalse(bagman.hasTarget(.heistId("below_fold_button")))
    }

    func testHasTargetFindsLiveHeistIdInViewport() {
        let element = element(label: "Visible", traits: .button)
        register(element, heistId: "visible_button", index: 0)

        XCTAssertTrue(bagman.hasTarget(.heistId("visible_button")))
    }

    func testRegisteredElementResolvesWithoutMarkPresented() {
        let element = element(label: "Combobox", traits: .button)
        register(element, heistId: "button_combobox", index: 0)

        // Element resolves immediately — no markPresented gate
        let result = bagman.resolveTarget(.heistId("button_combobox"))
        XCTAssertNotNil(result.resolved)
    }

    // MARK: - Exact-or-Miss Contract (Task 1, Findings 4/5/8)

    /// A partial label that would have matched via the old substring fallback
    /// must now return `.notFound` with a near-miss suggestion. This is the
    /// product decision codified in the matcher contract: "exact or miss",
    /// suggestions on miss.
    func testSubstringPartialLabelReturnsNotFoundWithSuggestion() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Substring partial must not auto-resolve to exact-or-miss; got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("Save Draft"),
                      "Near-miss should surface the actual label as a suggestion: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("did you mean") || diagnostics.contains("near miss"),
                      "Diagnostic should look like a suggestion: \(diagnostics)")
    }

    /// Exact equality (after case-insensitive comparison) still resolves.
    func testExactLabelCaseInsensitiveResolves() {
        let save = element(label: "Save", traits: .button)
        register(save, heistId: "button_save", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(.matcher(ElementMatcher(label: "Save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(.matcher(ElementMatcher(label: "save"))).resolved)
        XCTAssertNotNil(bagman.resolveTarget(.matcher(ElementMatcher(label: "SAVE"))).resolved)
    }

    /// Typography folding still works under exact-or-miss: a label with a smart
    /// apostrophe resolves against an ASCII apostrophe matcher.
    func testTypographyFoldingPreservedUnderExactSemantics() {
        let dontSkip = element(label: "Don\u{2019}t skip", traits: .button)
        register(dontSkip, heistId: "button_dont_skip", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(.matcher(ElementMatcher(label: "Don't skip"))).resolved)
    }

    /// When two labels share a partial substring, exact must win outright
    /// (no ambiguity). This was Finding 5's regression case.
    func testExactMatchWinsOverPartialSiblings() {
        let save = element(label: "Save")
        let saveDraft = element(label: "Save Draft")
        register(save, heistId: "button_save", index: 0)
        register(saveDraft, heistId: "button_save_draft", index: 1)

        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Save")))
        guard let resolved = result.resolved else {
            XCTFail("Exact match should resolve uniquely, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    /// Near-miss surface for `wait_for absent` semantics: a substring-only match
    /// must NOT be considered present.
    func testHasTargetReportsAbsentForSubstringOnlyMatch() {
        let save = element(label: "Save Draft", traits: .button)
        register(save, heistId: "button_save_draft", index: 0)

        // "Save" is a substring of "Save Draft" but not equal — hasTarget must
        // return false so wait_for absent doesn't lie about the screen state.
        XCTAssertFalse(bagman.hasTarget(.matcher(ElementMatcher(label: "Save"))))
        // Exact label still resolves to present.
        XCTAssertTrue(bagman.hasTarget(.matcher(ElementMatcher(label: "Save Draft"))))
    }

    /// Server-side and client-side matchers must agree on the same input.
    /// Regression for Finding 4 (matcher contract drift).
    func testServerAndClientMatchersAgreeOnSameInput() {
        let element = element(label: "Save Draft", value: "x", identifier: "save_btn", traits: .button)
        let matcher = ElementMatcher(label: "Save Draft", traits: [.button])

        // Server-side: AccessibilityElement.matches with mode .exact
        let serverHit = element.matches(matcher, mode: .exact)

        // Client-side: HeistElement.matches (no mode — exact-or-miss is the only mode).
        let heistElement = HeistElement(
            heistId: "button_save_draft",
            description: "Save Draft",
            label: "Save Draft",
            value: "x",
            identifier: "save_btn",
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let clientHit = heistElement.matches(matcher)

        XCTAssertEqual(serverHit, clientHit, "Server and client must agree on the same matcher input")
        XCTAssertTrue(serverHit, "Both sides must hit on exact label+trait match")

        // Substring partial should miss on BOTH sides now.
        let partial = ElementMatcher(label: "Save")
        XCTAssertFalse(element.matches(partial, mode: .exact))
        XCTAssertFalse(heistElement.matches(partial))
    }

    /// Smart-quote labels must produce the same answer on both sides
    /// (Finding 4's typography divergence).
    func testServerAndClientAgreeOnSmartQuoteLabel() {
        let smart = element(label: "Don\u{2019}t skip")
        let heist = HeistElement(
            heistId: "btn",
            description: "x",
            label: "Don\u{2019}t skip",
            value: nil,
            identifier: nil,
            traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let asciiMatcher = ElementMatcher(label: "Don't skip")

        XCTAssertTrue(smart.matches(asciiMatcher, mode: .exact))
        XCTAssertTrue(heist.matches(asciiMatcher),
                      "Client-side must fold typography just like server-side")
    }
}

#endif
