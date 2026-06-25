#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class DiagnosticsTests: XCTestCase {

    private typealias Diagnostics = TheStash.Diagnostics

    // MARK: - formatMatcher

    func testFormatMatcherLabelOnly() {
        let matcher = ElementPredicate(label: "Submit")
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertEqual(formatted, "label=\"Submit\"")
    }

    func testFormatMatcherMultipleFields() {
        let matcher = ElementPredicate(
            label: "Save",
            identifier: "save-btn",
            value: "enabled",
            traits: [.button]
        )
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertTrue(formatted.contains("label=\"Save\""))
        XCTAssertTrue(formatted.contains("identifier=\"save-btn\""))
        XCTAssertTrue(formatted.contains("value=\"enabled\""))
        XCTAssertTrue(formatted.contains("traits=[button]"))
    }

    func testFormatMatcherEmpty() {
        let matcher = ElementPredicate()
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertTrue(formatted.isEmpty)
    }

    // MARK: - compactElementSummary

    func testCompactSummaryEmptyScreen() {
        let summary = Diagnostics.compactElementSummary(
            screenElements: [],
            visibleHeistIds: []
        )
        XCTAssertTrue(summary.contains("empty"))
        XCTAssertTrue(summary.contains("Next:"))
    }

    func testCompactSummaryShowsElementCount() {
        let element = makeElement(label: "Hello")
        let screenElement = TheStash.ScreenElement(
            heistId: "hello",
            contentSpaceOrigin: nil,
            element: element
        )

        let summary = Diagnostics.compactElementSummary(
            screenElements: [screenElement],
            visibleHeistIds: ["hello"]
        )
        XCTAssertTrue(summary.contains("1 known element"))
        XCTAssertTrue(summary.contains("Hello"))
        XCTAssertTrue(summary.contains("visible"))
        XCTAssertTrue(summary.contains("Next:"))
    }

    // MARK: - failureInterfaceSuggestion

    func testFailureInterfaceSuggestionUsesCapturedElementsForContainsSearch() {
        let element = HeistElement(
            description: "Save Draft",
            label: "Save Draft",
            value: "ready",
            identifier: "save_draft_button",
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )

        let suggestion = Diagnostics.failureInterfaceSuggestion(
            for: ElementPredicate(label: "Save", traits: [.button]),
            elements: [element]
        )

        XCTAssertTrue(suggestion?.contains("captured interface contains-match suggestion") == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"label="Save Draft""#) == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"predicate(label="Save Draft" traits=[button])"#) == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"predicate(label=contains("Save") traits=[button])"#) == true, suggestion ?? "")
    }

    func testFailureInterfaceSuggestionDoesNotRewriteAlreadyExplicitContainsPredicate() {
        let element = HeistElement(
            description: "Save Draft",
            label: "Save Draft",
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )

        let suggestion = Diagnostics.failureInterfaceSuggestion(
            for: .label(.contains("Save")),
            elements: [element]
        )

        XCTAssertNil(suggestion)
    }

    // MARK: - Helpers

    private func makeElement(label: String) -> AccessibilityElement {
        .make(label: label, respondsToUserInteraction: false)
    }
}

#endif
