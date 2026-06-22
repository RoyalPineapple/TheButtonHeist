#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Server-side matching contract for `AccessibilityElement.matches(_:mode:)`.
///
/// The client side (`HeistElement.matches`) is exhaustively tested in
/// `TheScoreTests/ElementMatcherTests.swift`. Both sides share
/// `ElementPredicate.stringEquals`, so the cases below stay representative
/// (one per match dimension) and reverify the server-side call site
/// plumbs through to the same helper.
///
/// `mode: .exact` is the production resolution path. `mode: .substring`
/// is a diagnostic search mode used by `selectElements`.
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
        XCTAssertTrue(ElementPredicate(label: "Save").matches(element, mode: .exact))
        XCTAssertFalse(ElementPredicate(label: "Sav").matches(element, mode: .exact))
        XCTAssertFalse(ElementPredicate(label: "Save Draft").matches(element, mode: .exact))
    }

    func testLabelTypographyFolding() {
        // Curly quote in label, ASCII apostrophe in pattern — must match.
        // Shared helper coverage lives in TheScoreTests; this asserts the
        // server-side AccessibilityElement.matches plumbs through correctly.
        let element = element(label: "Don\u{2019}t skip")
        XCTAssertTrue(ElementPredicate(label: "Don't skip").matches(element, mode: .exact))
    }

    func testIdentifierExactMatch() {
        let element = element(identifier: "saveBtn")
        XCTAssertTrue(ElementPredicate(identifier: "saveBtn").matches(element, mode: .exact))
        XCTAssertFalse(ElementPredicate(identifier: "save").matches(element, mode: .exact))
    }

    func testValueExactMatch() {
        let element = element(value: "50%")
        XCTAssertTrue(ElementPredicate(value: "50%").matches(element, mode: .exact))
        XCTAssertFalse(ElementPredicate(value: "75%").matches(element, mode: .exact))
    }

    func testTraitsIncludeExactBitmask() {
        let element = element(traits: [.button, .selected])
        XCTAssertTrue(ElementPredicate(traits: [.button]).matches(element, mode: .exact))
        XCTAssertTrue(ElementPredicate(traits: [.button, .selected]).matches(element, mode: .exact))
        XCTAssertFalse(ElementPredicate(traits: [.button, .header]).matches(element, mode: .exact))
    }

    func testTraitsExclude() {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementPredicate(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(matcher.matches(enabled, mode: .exact))
        XCTAssertFalse(matcher.matches(disabled, mode: .exact))
    }

    func testCompoundAllFieldsMustMatch() {
        let element = element(
            label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected]
        )
        let matcher = ElementPredicate(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "ON", traits: [.button, .selected]
        )
        XCTAssertTrue(matcher.matches(element, mode: .exact))
        // Wrong value — must miss
        let wrongValue = ElementPredicate(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "OFF", traits: [.button, .selected]
        )
        XCTAssertFalse(wrongValue.matches(element, mode: .exact))
    }

    func testEmptyMatcherMatchesNothing() {
        XCTAssertFalse(ElementPredicate().matches(element(label: "Save", traits: .button), mode: .exact))
        XCTAssertFalse(ElementPredicate().matches(element(), mode: .exact))
    }

    // MARK: - Substring-Mode Sanity

    func testSubstringModeSanity() {
        // Production resolution uses `.exact`; substring matching is only
        // for explicit diagnostic search surfaces.
        let element = element(label: "Save Changes")
        XCTAssertTrue(ElementPredicate(label: "Save").matches(element, mode: .substring))
        XCTAssertTrue(ElementPredicate(label: "Changes").matches(element, mode: .substring))
        XCTAssertFalse(ElementPredicate(label: "Delete").matches(element, mode: .substring))
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
        let result = try XCTUnwrap(tree.firstMatch(ElementPredicate(label: "Target"), mode: .exact))
        XCTAssertEqual(result.label, "Target")
    }

    func testHierarchyContainerLabelDoesNotMatch() {
        // Container labels are not part of the matcher search space — only
        // leaf elements are considered.
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Settings", children: [
                .element(element(label: "Volume"), traversalIndex: 0)
            ])
        ]
        XCTAssertNil(tree.firstMatch(ElementPredicate(label: "Settings"), mode: .exact))
    }

    func testHierarchyMatchesReturnsMultipleHits() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "A", traits: .button), traversalIndex: 0),
            .element(element(label: "B", traits: .header), traversalIndex: 1),
            .element(element(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.matches(ElementPredicate(traits: [.button]), mode: .exact, limit: 100)
        XCTAssertEqual(results.map(\.label), ["A", "C"])
    }

    // MARK: - StableKey

    func testStableKeyEqualForSameProperties() {
        let a = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        let b = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        XCTAssertEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyFallsBackToFrameWhenNoSemanticIdentity() {
        let a = AccessibilityElement.make(
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 44, height: 44))),
            activationPoint: CGPoint(x: 22, y: 22)
        )
        let b = AccessibilityElement.make(
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 200, width: 44, height: 44))),
            activationPoint: CGPoint(x: 22, y: 222)
        )
        XCTAssertNotEqual(a.stableKey, b.stableKey, "Unlabeled elements at different positions must hash differently")
    }
}

#endif
