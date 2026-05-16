#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class DiagnosticsTests: XCTestCase {

    private typealias Diagnostics = TheStash.Diagnostics

    // MARK: - heistIdNotFound

    func testHeistIdNotFoundNoSimilar() {
        let message = Diagnostics.heistIdNotFound(
            "missing-button",
            knownIds: ["header", "footer", "nav"],
            knownCount: 3
        )
        XCTAssertTrue(message.contains("missing-button"))
        XCTAssertTrue(message.contains("3 known elements"))
        // When there's no near-miss, the message should hint at the stale-id
        // case and point at the recovery moves.
        XCTAssertTrue(message.contains("stale"))
        XCTAssertTrue(message.contains("get_interface"))
        XCTAssertTrue(message.contains("matcher"))
    }

    func testHeistIdNotFoundWithSubstringMatch() {
        let message = Diagnostics.heistIdNotFound(
            "button",
            knownIds: ["submit-button", "cancel-button", "header"],
            knownCount: 3
        )
        XCTAssertTrue(message.contains("did you mean"))
        XCTAssertTrue(message.contains("submit-button"))
        XCTAssertTrue(message.contains("cancel-button"))
        XCTAssertFalse(message.contains("header"))
        // The "did you mean" branch still offers a refetch fallback in case
        // none of the suggestions is what the agent meant.
        XCTAssertTrue(message.contains("get_interface"))
        // The near-miss branch already gives concrete heistIds, so the
        // "or target by label/identifier with a matcher" fallback is omitted.
        XCTAssertFalse(message.contains("matcher"))
    }

    func testHeistIdNotFoundReverseSubstringMatch() {
        let message = Diagnostics.heistIdNotFound(
            "submit-button-primary",
            knownIds: ["submit-button", "cancel"],
            knownCount: 2
        )
        XCTAssertTrue(message.contains("did you mean"))
        XCTAssertTrue(message.contains("submit-button"))
    }

    // MARK: - formatMatcher

    func testFormatMatcherLabelOnly() {
        let matcher = ElementMatcher(label: "Submit")
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertEqual(formatted, "label=\"Submit\"")
    }

    func testFormatMatcherMultipleFields() {
        let matcher = ElementMatcher(
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
        let matcher = ElementMatcher()
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
            element: element,
            object: nil,
            scrollView: nil
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

    // MARK: - Helpers

    private func makeElement(label: String) -> AccessibilityElement {
        .make(label: label, respondsToUserInteraction: false)
    }
}

#endif
