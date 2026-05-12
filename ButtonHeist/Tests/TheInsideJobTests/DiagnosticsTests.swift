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
            viewportCount: 3
        )
        XCTAssertTrue(message.contains("missing-button"))
        XCTAssertTrue(message.contains("3 elements"))
    }

    func testHeistIdNotFoundWithSubstringMatch() {
        let message = Diagnostics.heistIdNotFound(
            "button",
            knownIds: ["submit-button", "cancel-button", "header"],
            viewportCount: 3
        )
        XCTAssertTrue(message.contains("similar"))
        XCTAssertTrue(message.contains("submit-button"))
        XCTAssertTrue(message.contains("cancel-button"))
        XCTAssertFalse(message.contains("header"))
    }

    func testHeistIdNotFoundReverseSubstringMatch() {
        let message = Diagnostics.heistIdNotFound(
            "submit-button-primary",
            knownIds: ["submit-button", "cancel"],
            viewportCount: 2
        )
        XCTAssertTrue(message.contains("similar"))
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
            viewportHeistIds: [],
            traversalOrder: [:]
        )
        XCTAssertTrue(summary.contains("empty"))
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
            viewportHeistIds: ["hello"],
            traversalOrder: ["hello": 0]
        )
        XCTAssertTrue(summary.contains("1 elements"))
        XCTAssertTrue(summary.contains("Hello"))
    }

    // MARK: - Helpers

    private func makeElement(label: String) -> AccessibilityElement {
        .make(label: label, respondsToUserInteraction: false)
    }
}

#endif
