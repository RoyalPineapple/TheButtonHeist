#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBagmanResolutionTests: XCTestCase {

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

    /// Register an element in screenElements, currentHierarchy, and presentedHeistIds.
    private func register(_ element: AccessibilityElement, heistId: String, index: Int) {
        bagman.screenElements[heistId] = TheBagman.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        )
        bagman.presentedHeistIds.insert(heistId)
        // Add to hierarchy and reverse index for matcher resolution
        hierarchyNodes.append(.element(element, traversalIndex: index))
        bagman.currentHierarchy = hierarchyNodes
        bagman.elementToHeistId[element] = heistId
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

    func testHeistIdNotPresentedReturnsNotFound() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)
        // Remove from presented set
        bagman.presentedHeistIds.remove("button_ok")

        let result = bagman.resolveTarget(.heistId("button_ok"))
        guard case .notFound = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
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

        let limit3 = bagman.currentHierarchy.matches(ElementMatcher(label: "Item"), limit: 3)
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

        let results = bagman.currentHierarchy.matches(ElementMatcher(label: "Save"), limit: 10)
        XCTAssertEqual(results.count, 2)
    }

    func testMatchesWithLimitZeroReturnsEmpty() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let results = bagman.currentHierarchy.matches(ElementMatcher(label: "Save"), limit: 0)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Select + Mark Presented Tracking

    func testSelectElementsIsPureRead() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)
        bagman.presentedHeistIds.remove("button_save")

        let result = bagman.selectElements(.all)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].heistId, "button_save")
        XCTAssertFalse(bagman.presentedHeistIds.contains("button_save"),
                        "selectElements must not mutate presentedHeistIds")
    }

    func testMarkPresentedEnablesSubsequentHeistIdLookup() {
        let element = element(label: "Combobox", traits: .button)
        register(element, heistId: "button_combobox", index: 0)
        bagman.presentedHeistIds.remove("button_combobox")

        // Before marking, heistId lookup should fail
        let beforeResult = bagman.resolveTarget(.heistId("button_combobox"))
        XCTAssertNil(beforeResult.resolved, "Should not resolve unpresented element")

        // After markPresented, heistId lookup should succeed
        let selected = bagman.selectElements(.all)
        bagman.markPresented(selected)
        let afterResult = bagman.resolveTarget(.heistId("button_combobox"))
        XCTAssertNotNil(afterResult.resolved, "Should resolve after markPresented")
    }

    func testSelectAllIncludesOffScreenElements() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "OffScreen", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        register(offScreen, heistId: "button_offscreen", index: 1)

        // Simulate off-viewport: only "button_visible" is in the viewport set
        bagman.viewportHeistIds = Set(["button_visible"])

        let all = bagman.selectElements(.all)
        XCTAssertEqual(all.count, 2, "Should return both visible and off-screen elements")
        let heistIds = all.map(\.heistId)
        XCTAssertTrue(heistIds.contains("button_visible"))
        XCTAssertTrue(heistIds.contains("button_offscreen"))
    }

    func testMarkPresentedViewportDoesNotPresentOffScreen() {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "OffScreen", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        register(offScreen, heistId: "button_offscreen", index: 1)
        bagman.presentedHeistIds.removeAll()
        bagman.viewportHeistIds = Set(["button_visible"])

        let selected = bagman.selectElements(.viewport)
        bagman.markPresented(selected)
        XCTAssertTrue(bagman.presentedHeistIds.contains("button_visible"))
        XCTAssertFalse(bagman.presentedHeistIds.contains("button_offscreen"),
                        "markPresented(.viewport) must not present off-viewport elements")
    }
}

#endif
