#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class DiagnosticsTests: XCTestCase {

    private typealias Diagnostics = TheVault.Diagnostics

    // MARK: - formatMatcher

    func testFormatMatcherLabelOnly() throws {
        let matcher = try resolvedPredicate(.label("Submit"))
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertEqual(formatted, "label=\"Submit\"")
    }

    func testFormatMatcherMultipleFields() throws {
        let matcher = try resolvedPredicate(.element(
            .label("Save"),
            .identifier("save-btn"),
            .value("enabled"),
            traits: [.button]
        ))
        let formatted = Diagnostics.formatMatcher(matcher)
        XCTAssertTrue(formatted.contains("label=\"Save\""))
        XCTAssertTrue(formatted.contains("identifier=\"save-btn\""))
        XCTAssertTrue(formatted.contains("value=\"enabled\""))
        XCTAssertTrue(formatted.contains("traits=[button]"))
    }

    // MARK: - compactElementSummary

    func testCompactSummaryEmptyScreen() {
        let summary = Diagnostics.compactElementSummary(
            treeElements: [],
            visibleHeistIds: []
        )
        XCTAssertTrue(summary.contains("empty"))
        XCTAssertTrue(summary.contains("Next:"))
    }

    func testCompactSummaryShowsElementCount() {
        let element = makeElement(label: "Hello")
        let treeElement = InterfaceTree.Element(
            heistId: "hello",
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: element)
            ),
            element: element
        )

        let summary = Diagnostics.compactElementSummary(
            treeElements: [treeElement],
            visibleHeistIds: ["hello"]
        )
        XCTAssertTrue(summary.contains("1 interface element"))
        XCTAssertTrue(summary.contains("Hello"))
        XCTAssertTrue(summary.contains("visible"))
        XCTAssertTrue(summary.contains("Next:"))
    }

    // MARK: - failureInterfaceSuggestion

    func testFailureInterfaceSuggestionUsesCapturedElementsForContainsSearch() throws {
        let accessibilityElement = AccessibilityElement.make(
            label: "Save Draft",
            value: "ready",
            identifier: "save_draft_button",
            traits: [.button],
            frame: CGRect(x: 0, y: 0, width: 100, height: 44)
        )
        let element = HeistElement(
            accessibilityElement: accessibilityElement,
            geometry: testGeometry(
                for: accessibilityElement,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: accessibilityElement)
            )
        )

        let suggestion = Diagnostics.failureInterfaceSuggestion(
            for: try resolvedPredicate(.element(.label("Save"), traits: [.button])),
            elements: [element]
        )

        XCTAssertTrue(suggestion?.contains("captured interface contains-match suggestion") == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"label="Save Draft""#) == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"predicate(label="Save Draft" traits=[button])"#) == true, suggestion ?? "")
        XCTAssertTrue(suggestion?.contains(#"predicate(label=contains("Save") traits=[button])"#) == true, suggestion ?? "")
    }

    func testFailureInterfaceSuggestionDoesNotRewriteAlreadyExplicitContainsPredicate() throws {
        let accessibilityElement = AccessibilityElement.make(
            label: "Save Draft",
            traits: [.button],
            frame: CGRect(x: 0, y: 0, width: 100, height: 44)
        )
        let element = HeistElement(
            accessibilityElement: accessibilityElement,
            geometry: testGeometry(
                for: accessibilityElement,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: accessibilityElement)
            )
        )

        let suggestion = Diagnostics.failureInterfaceSuggestion(
            for: try resolvedPredicate(.label(.contains("Save"))),
            elements: [element]
        )

        XCTAssertNil(suggestion)
    }

    // MARK: - Helpers

    private func makeElement(label: String) -> AccessibilityElement {
        .make(label: label, respondsToUserInteraction: false)
    }

    private func resolvedPredicate(_ authored: AccessibilityTarget) throws -> ResolvedElementPredicate {
        let resolved = try authored.resolve(in: .empty)
        guard case .predicate(let predicate, ordinal: nil) = resolved else {
            return try XCTUnwrap(nil as ResolvedElementPredicate?, "Expected an unqualified element predicate")
        }
        return predicate
    }
}

#endif
