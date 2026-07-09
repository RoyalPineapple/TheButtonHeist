#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Server-side matching contract for `AccessibilityElement` predicate matching.
///
/// The client side (`HeistElement.matches`) is exhaustively tested in
/// `TheScoreTests/ElementMatcherTests.swift`. Both sides share
/// `ElementPredicate.stringEquals`, so the cases below stay representative
/// (one per match dimension) and reverify the server-side call site
/// plumbs through to the same helper.
///
/// Plain strings match exactly, and explicit broad `StringMatch` modes are
/// honored. There is no hidden diagnostic substring mode.
@MainActor
final class ElementMatcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        hint: String? = nil,
        customActions: [AccessibilityElement.CustomAction] = [],
        customContent: [AccessibilityElement.CustomContent] = [],
        customRotors: [AccessibilityElement.CustomRotor] = []
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            customActions: customActions,
            customContent: customContent,
            customRotors: customRotors
        )
    }

    // MARK: - Match Dimensions (one each)

    func testLabelExactMatch() {
        let element = element(label: "Save")
        XCTAssertTrue(ElementPredicate(label: "Save").matches(element))
        XCTAssertFalse(ElementPredicate(label: "Sav").matches(element))
        XCTAssertFalse(ElementPredicate(label: "Save Draft").matches(element))
    }

    func testLabelTypographyFolding() {
        // Curly quote in label, ASCII apostrophe in pattern — must match.
        // Shared helper coverage lives in TheScoreTests; this asserts the
        // server-side AccessibilityElement.matches plumbs through correctly.
        let element = element(label: "Don\u{2019}t skip")
        XCTAssertTrue(ElementPredicate(label: "Don't skip").matches(element))
    }

    func testIdentifierExactMatch() {
        let element = element(identifier: "saveBtn")
        XCTAssertTrue(ElementPredicate(identifier: "saveBtn").matches(element))
        XCTAssertFalse(ElementPredicate(identifier: "save").matches(element))
    }

    func testValueExactMatch() {
        let element = element(value: "50%")
        XCTAssertTrue(ElementPredicate(value: "50%").matches(element))
        XCTAssertFalse(ElementPredicate(value: "75%").matches(element))
    }

    func testExplicitBroadStringMatches() {
        let element = element(label: "Save Changes", value: "3 changes", identifier: "save_changes_button")

        XCTAssertTrue(ElementPredicate(label: .contains("Changes")).matches(element))
        XCTAssertTrue(ElementPredicate(label: .prefix("Save")).matches(element))
        XCTAssertTrue(ElementPredicate(label: .suffix("Changes")).matches(element))
        XCTAssertTrue(ElementPredicate(value: .contains("3 change")).matches(element))
        XCTAssertTrue(ElementPredicate(value: .suffix("changes")).matches(element))
        XCTAssertTrue(ElementPredicate(identifier: .contains("changes")).matches(element))
        XCTAssertTrue(ElementPredicate(identifier: .prefix("save")).matches(element))
        XCTAssertFalse(ElementPredicate(label: "Changes").matches(element))
    }

    func testSemanticSurfacePredicatesMatchHintActionsCustomContentAndRotors() {
        let element = element(
            label: "Coke",
            identifier: "combo-choice-Coke",
            traits: .staticText,
            hint: "Double tap to edit",
            customActions: [AccessibilityElement.CustomAction(name: "Modify")],
            customContent: [AccessibilityElement.CustomContent(label: "Slot", value: "Main", isImportant: true)],
            customRotors: [AccessibilityElement.CustomRotor(name: "Actions")]
        )

        XCTAssertTrue(ElementPredicate.hint(.contains("edit")).matches(element))
        XCTAssertTrue(ElementPredicate.actions([.custom("Modify")]).matches(element))
        XCTAssertTrue(ElementPredicate.exclude(.actions([.custom("Sub")])).matches(element))
        XCTAssertTrue(ElementPredicate.customContent(.init(label: "Slot", value: "Main")).matches(element))
        XCTAssertTrue(ElementPredicate.exclude(.customContent(.init(label: "Discount"))).matches(element))
        XCTAssertTrue(ElementPredicate.rotors(["Actions"]).matches(element))
        XCTAssertTrue(ElementPredicate.exclude(.rotors(["Headings"])).matches(element))
        XCTAssertFalse(ElementPredicate.exclude(.actions([.custom("Modify")])).matches(element))
        XCTAssertFalse(ElementPredicate.customContent(.init(label: "Slot", value: "Side")).matches(element))
        XCTAssertFalse(ElementPredicate.rotors(["Headings"]).matches(element))
    }

    func testTraitsIncludeExactBitmask() {
        let element = element(traits: [.button, .selected])
        XCTAssertTrue(ElementPredicate(traits: [.button]).matches(element))
        XCTAssertTrue(ElementPredicate(traits: [.button, .selected]).matches(element))
        XCTAssertFalse(ElementPredicate(traits: [.button, .header]).matches(element))
    }

    func testTraitsExclude() {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementPredicate.element(
            .label("Submit"),
            .exclude(.traits([.notEnabled]))
        )
        XCTAssertTrue(matcher.matches(enabled))
        XCTAssertFalse(matcher.matches(disabled))
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
        XCTAssertTrue(matcher.matches(element))
        // Wrong value — must miss
        let wrongValue = ElementPredicate(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "OFF", traits: [.button, .selected]
        )
        XCTAssertFalse(wrongValue.matches(element))
    }

    func testEmptyMatcherMatchesNothing() {
        XCTAssertFalse(ElementPredicate().matches(element(label: "Save", traits: .button)))
        XCTAssertFalse(ElementPredicate().matches(element()))
    }

    // MARK: - Hierarchy Matching

    private func group(children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .semanticGroup(label: nil, value: nil), identifier: nil, frame: .zero),
            children: children
        )
    }

    private func labeledGroup(
        label: String,
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil), identifier: nil,
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
        let result = try XCTUnwrap(tree.firstMatch(ElementPredicate(label: "Target")))
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
        XCTAssertNil(tree.firstMatch(ElementPredicate(label: "Settings")))
    }

    func testHierarchyMatchesReturnsMultipleHits() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "A", traits: .button), traversalIndex: 0),
            .element(element(label: "B", traits: .header), traversalIndex: 1),
            .element(element(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.matches(ElementPredicate(traits: [.button]), limit: 100)
        XCTAssertEqual(results.map(\.label), ["A", "C"])
    }

}

#endif
