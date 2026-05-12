#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Server-side matching contract for `AccessibilityElement.matches(_:mode:)`.
///
/// The client side (`HeistElement.matches`) is exhaustively tested in
/// `TheScoreTests/ElementMatcherTests.swift`. Both sides share
/// `ElementMatcher.stringEquals`, so the cases below stay representative
/// (one per match dimension) and reverify the server-side call site
/// plumbs through to the same helper.
///
/// `mode: .exact` is the production resolution path. `mode: .substring`
/// is a legacy mode kept for `selectElements` and diagnostic searches;
/// one sanity case below keeps it from bit-rotting.
@MainActor
final class ElementMatcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        hint: String? = nil
    ) -> AccessibilityElement {
        .make(label: label, value: value, identifier: identifier, hint: hint, traits: traits)
    }

    // MARK: - Match Dimensions (one each)

    func testLabelExactMatch() {
        let element = element(label: "Save")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save"), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Sav"), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Save Draft"), mode: .exact))
    }

    func testLabelTypographyFolding() {
        // Curly quote in label, ASCII apostrophe in pattern — must match.
        // Shared helper coverage lives in TheScoreTests; this asserts the
        // server-side AccessibilityElement.matches plumbs through correctly.
        let element = element(label: "Don\u{2019}t skip")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Don't skip"), mode: .exact))
    }

    func testIdentifierExactMatch() {
        let element = element(identifier: "saveBtn")
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "saveBtn"), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "save"), mode: .exact))
    }

    func testValueExactMatch() {
        let element = element(value: "50%")
        XCTAssertTrue(element.matches(ElementMatcher(value: "50%"), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(value: "75%"), mode: .exact))
    }

    func testTraitsIncludeExactBitmask() {
        let element = element(traits: [.button, .selected])
        XCTAssertTrue(element.matches(ElementMatcher(traits: [.button]), mode: .exact))
        XCTAssertTrue(element.matches(ElementMatcher(traits: [.button, .selected]), mode: .exact))
        XCTAssertFalse(element.matches(ElementMatcher(traits: [.button, .header]), mode: .exact))
    }

    func testTraitsExclude() {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementMatcher(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(enabled.matches(matcher, mode: .exact))
        XCTAssertFalse(disabled.matches(matcher, mode: .exact))
    }

    func testCompoundAllFieldsMustMatch() {
        let element = element(
            label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected]
        )
        let matcher = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "ON", traits: [.button, .selected]
        )
        XCTAssertTrue(element.matches(matcher, mode: .exact))
        // Wrong value — must miss
        let wrongValue = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "OFF", traits: [.button, .selected]
        )
        XCTAssertFalse(element.matches(wrongValue, mode: .exact))
    }

    func testEmptyMatcherMatchesEverything() {
        XCTAssertTrue(element(label: "Save", traits: .button).matches(ElementMatcher(), mode: .exact))
        XCTAssertTrue(element().matches(ElementMatcher(), mode: .exact))
    }

    // MARK: - Substring-Mode Sanity (legacy diagnostic path)

    func testSubstringModeSanity() {
        // `mode: .substring` is the legacy fall-through used by
        // `selectElements` and diagnostics. One sanity case keeps it from
        // bit-rotting; production resolution uses `.exact`.
        let element = element(label: "Save Changes")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save"), mode: .substring))
        XCTAssertTrue(element.matches(ElementMatcher(label: "Changes"), mode: .substring))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Delete"), mode: .substring))
    }

    // MARK: - Hierarchy Matching

    private func group(children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .semanticGroup(label: nil, value: nil, identifier: nil), frame: .zero),
            children: children
        )
    }

    private func labeledGroup(
        label: String,
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil, identifier: nil),
                frame: .zero
            ),
            children: children
        )
    }

    func testHierarchyFirstMatchFindsLeaf() throws {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                .element(element(label: "Target", traits: .button), traversalIndex: 0)
            ])
        ]
        let result = try XCTUnwrap(tree.firstMatch(ElementMatcher(label: "Target"), mode: .exact))
        XCTAssertEqual(result.element.label, "Target")
    }

    func testHierarchyContainerLabelDoesNotMatch() {
        // Container labels are not part of the matcher search space — only
        // leaf elements are considered.
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Settings", children: [
                .element(element(label: "Volume"), traversalIndex: 0)
            ])
        ]
        XCTAssertNil(tree.firstMatch(ElementMatcher(label: "Settings"), mode: .exact))
    }

    func testHierarchyMatchesReturnsMultipleHits() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "A", traits: .button), traversalIndex: 0),
            .element(element(label: "B", traits: .header), traversalIndex: 1),
            .element(element(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.matches(ElementMatcher(traits: [.button]), mode: .exact, limit: 100)
        XCTAssertEqual(results.map(\.element.label), ["A", "C"])
    }

    // MARK: - StableKey

    func testStableKeyEqualForSameProperties() {
        let a = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        let b = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        XCTAssertEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyFallsBackToFrameWhenNoSemanticIdentity() {
        let a = AccessibilityElement.make(
            shape: .frame(CGRect(x: 0, y: 0, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 22)
        )
        let b = AccessibilityElement.make(
            shape: .frame(CGRect(x: 0, y: 200, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 222)
        )
        XCTAssertNotEqual(a.stableKey, b.stableKey, "Unlabeled elements at different positions must hash differently")
    }
}

#endif
