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

    private func resolvedPredicate(_ authored: AccessibilityTarget) throws -> ElementPredicate {
        let resolved = try authored.resolve(in: .empty)
        guard case .predicate(let predicate, ordinal: nil) = resolved else {
            return try XCTUnwrap(nil as ElementPredicate?, "Expected an unqualified element predicate")
        }
        return predicate
    }

    // MARK: - Match Dimensions (one each)

    func testLabelExactMatch() {
        let element = element(label: "Save")
        XCTAssertTrue(ElementPredicate.label("Save").matches(element))
        XCTAssertFalse(ElementPredicate.label("Sav").matches(element))
        XCTAssertFalse(ElementPredicate.label("Save Draft").matches(element))
    }

    func testLabelTypographyFolding() {
        // Curly quote in label, ASCII apostrophe in pattern — must match.
        // Shared helper coverage lives in TheScoreTests; this asserts the
        // server-side AccessibilityElement.matches plumbs through correctly.
        let element = element(label: "Don\u{2019}t skip")
        XCTAssertTrue(ElementPredicate.label("Don't skip").matches(element))
    }

    func testIdentifierExactMatch() {
        let element = element(identifier: "saveBtn")
        XCTAssertTrue(ElementPredicate.identifier("saveBtn").matches(element))
        XCTAssertFalse(ElementPredicate.identifier("save").matches(element))
    }

    func testValueExactMatch() {
        let element = element(value: "50%")
        XCTAssertTrue(ElementPredicate.value("50%").matches(element))
        XCTAssertFalse(ElementPredicate.value("75%").matches(element))
    }

    func testExplicitBroadStringMatches() throws {
        let element = element(label: "Save Changes", value: "3 changes", identifier: "save_changes_button")

        XCTAssertTrue(try resolvedPredicate(.label(.contains("Changes"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.label(.prefix("Save"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.label(.suffix("Changes"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.value(.contains("3 change"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.value(.suffix("changes"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.identifier(.contains("changes"))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.identifier(.prefix("save"))).matches(element))
        XCTAssertFalse(ElementPredicate.label("Changes").matches(element))
    }

    func testSemanticSurfacePredicatesMatchHintActionsCustomContentAndRotors() throws {
        let element = element(
            label: "Coke",
            identifier: "combo-choice-Coke",
            traits: .staticText,
            hint: "Double tap to edit",
            customActions: [AccessibilityElement.CustomAction(name: "Modify")],
            customContent: [AccessibilityElement.CustomContent(label: "Slot", value: "Main", isImportant: true)],
            customRotors: [AccessibilityElement.CustomRotor(name: "Actions")]
        )

        XCTAssertTrue(try resolvedPredicate(.label("Coke").and(.hint(.contains("edit")))).matches(element))
        XCTAssertTrue(ElementPredicate.actions([.custom("Modify")]).matches(element))
        XCTAssertTrue(try resolvedPredicate(.label("Coke").excluding(.actions([.custom("Sub")]))).matches(element))
        XCTAssertTrue(try resolvedPredicate(
            .label("Coke").and(.customContent(.init(label: "Slot", value: "Main")))
        ).matches(element))
        XCTAssertTrue(try resolvedPredicate(
            .label("Coke").excluding(.customContent(.init(label: "Discount")))
        ).matches(element))
        XCTAssertTrue(try resolvedPredicate(.label("Coke").and(.rotors(["Actions"]))).matches(element))
        XCTAssertTrue(try resolvedPredicate(.label("Coke").excluding(.rotors(["Headings"]))).matches(element))
        XCTAssertFalse(try resolvedPredicate(
            .label("Coke").excluding(.actions([.custom("Modify")]))
        ).matches(element))
        XCTAssertFalse(try resolvedPredicate(
            .label("Coke").and(.customContent(.init(label: "Slot", value: "Side")))
        ).matches(element))
        XCTAssertFalse(try resolvedPredicate(.label("Coke").and(.rotors(["Headings"]))).matches(element))
    }

    func testTextInputTraitsExposeTypeTextActionToMatcher() throws {
        let element = element(label: "Search", traits: .searchField)

        XCTAssertTrue(ElementPredicate.actions([.typeText]).matches(element))
        XCTAssertFalse(try resolvedPredicate(.label("Search").excluding(.actions([.typeText]))).matches(element))
    }

    func testTraitsIncludeExactBitmask() {
        let element = element(traits: [.button, .selected])
        XCTAssertTrue(ElementPredicate.traits([.button]).matches(element))
        XCTAssertTrue(ElementPredicate.traits([.button, .selected]).matches(element))
        XCTAssertFalse(ElementPredicate.traits([.button, .header]).matches(element))
    }

    func testTraitsExclude() throws {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = try resolvedPredicate(.label("Submit").excluding(.traits([.notEnabled])))
        XCTAssertTrue(matcher.matches(enabled))
        XCTAssertFalse(matcher.matches(disabled))
    }

    func testCompoundAllFieldsMustMatch() throws {
        let element = element(
            label: "Dark Mode", value: "ON",
            identifier: "darkModeToggle", traits: [.button, .selected]
        )
        let matcher = try resolvedPredicate(
            .label("Dark Mode").and(
                .identifier("darkModeToggle"),
                .value("ON"),
                .traits([.button, .selected])
            )
        )
        XCTAssertTrue(matcher.matches(element))
        // Wrong value — must miss
        let wrongValue = try resolvedPredicate(
            .label("Dark Mode").and(
                .identifier("darkModeToggle"),
                .value("OFF"),
                .traits([.button, .selected])
            )
        )
        XCTAssertFalse(wrongValue.matches(element))
    }

    func testEmptyMatcherMatchesNothing() {
        let empty = ElementPredicate([])
        XCTAssertFalse(empty.matches(element(label: "Save", traits: .button)))
        XCTAssertFalse(empty.matches(element()))
    }

}

#endif
