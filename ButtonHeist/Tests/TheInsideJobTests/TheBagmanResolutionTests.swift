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

    /// Register an element in both cachedElements and screenElements.
    private func register(_ element: AccessibilityElement, heistId: String, index: Int) {
        if index >= bagman.cachedElements.count {
            bagman.cachedElements.append(contentsOf:
                Array(repeating: element, count: index - bagman.cachedElements.count + 1)
            )
        }
        bagman.cachedElements[index] = element
        bagman.screenElements[heistId] = TheBagman.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            lastTraversalIndex: index,
            wire: HeistElement(
                heistId: heistId, description: element.description,
                label: element.label, value: element.value, identifier: element.identifier,
                hint: nil, traits: [], frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
                activationPointX: 0, activationPointY: 0, actions: []
            ),
            presented: true,
            object: nil,
            scrollView: nil
        )
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
        XCTAssertEqual(resolved.traversalIndex, 0)
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
        // Mark as not presented
        bagman.screenElements["button_ok"]?.presented = false

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

    // MARK: - elementNotFoundMessage Delegation

    func testElementNotFoundMessageDelegatesToResolveTarget() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let msg = bagman.elementNotFoundMessage(for: .matcher(ElementMatcher(label: "Save")))
        XCTAssertTrue(msg.contains("2 elements match"), "Should return ambiguous message: \(msg)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(.matcher(ElementMatcher(label: "Anything")))
        guard case .notFound(let diagnostics) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertTrue(diagnostics.contains("screen is empty"))
    }
}

#endif
