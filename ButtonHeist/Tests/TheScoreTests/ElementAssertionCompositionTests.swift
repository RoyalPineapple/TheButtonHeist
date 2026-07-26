import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// Every predicate is a question about the graph in front of it, and every
/// delta composes into a pair of the presence predicates that already exist.
/// Nothing is diffed and no baseline is held: what makes a match a *change* is
/// that the predicate before it already drained.
final class ElementAssertionCompositionTests: XCTestCase {

    // MARK: - Deltas are pairs

    func testAppearedIsAbsentThenPresent() throws {
        let composed = try assertion(.appeared(.label("Toast"))).composed

        XCTAssertEqual(composed.count, 2)
        XCTAssertTrue(composed[0].matches(emptyInterface))
        XCTAssertFalse(composed[0].matches(interface(labelled: "Toast")))
        XCTAssertTrue(composed[1].matches(interface(labelled: "Toast")))
    }

    func testDisappearedIsTheMirror() throws {
        let composed = try assertion(.disappeared(.label("Ready"))).composed

        XCTAssertEqual(composed.count, 2)
        XCTAssertTrue(composed[0].matches(interface(labelled: "Ready")))
        XCTAssertTrue(composed[1].matches(emptyInterface))
    }

    /// The same predicate reads as a departure or an arrival depending only on
    /// where the list has got to — which is what lets a label come back.
    func testTheSameTargetLeavesAndReturns() throws {
        let leaving = try assertion(.disappeared(.label("Ready"))).composed
        let returning = try assertion(.appeared(.label("Ready"))).composed

        XCTAssertEqual(leaving[1], returning[0], "both want Ready gone")
        XCTAssertEqual(leaving[0], returning[1], "both want Ready present")
    }

    // MARK: - The append rule

    /// `updated` is the anchor, then the anchor carrying what it became. The
    /// property is another conjunct on the target, not a change record.
    func testUpdatedIsTheAnchorThenTheAnchorPlusTheProperty() throws {
        let composed = try assertion(
            .updated(.label("Loading"), .value(after: "100%"))
        ).composed

        XCTAssertEqual(composed.count, 2)
        XCTAssertTrue(composed[0].matches(interface([element("Loading", value: "0%")])))
        XCTAssertFalse(
            composed[1].matches(interface([element("Loading", value: "0%")])),
            "the second search wants the new value"
        )
        XCTAssertTrue(composed[1].matches(interface([element("Loading", value: "100%")])))
    }

    func testAnOptionalBeforeValueConstrainsTheFirstSearch() throws {
        let composed = try assertion(
            .updated(.label("Loading"), .value(before: "0%", after: "100%"))
        ).composed

        XCTAssertTrue(composed[0].matches(interface([element("Loading", value: "0%")])))
        XCTAssertFalse(
            composed[0].matches(interface([element("Loading", value: "50%")])),
            "the first search asks for 0%"
        )
    }

    /// Traits take the same path as values: both are just another conjunct.
    func testATraitChangeUsesTheSameAppend() throws {
        let composed = try assertion(
            .updated(.label("Save"), .traits(after: .includes(.selected)))
        ).composed

        XCTAssertTrue(composed[1].matches(interface([
            element("Save", traits: [.button, .selected])
        ])))
        XCTAssertFalse(composed[1].matches(interface([
            element("Save", traits: [.button])
        ])))
    }

    /// An excluded trait is a check too — `.exclude` already wraps any check,
    /// so "no longer selected" needs no new vocabulary.
    func testAnExcludedTraitBecomesAnExcludeCheck() throws {
        let composed = try assertion(
            .updated(.label("Save"), .traits(after: .excludes(.selected)))
        ).composed

        XCTAssertTrue(composed[1].matches(interface([element("Save", traits: [.button])])))
        XCTAssertFalse(composed[1].matches(interface([
            element("Save", traits: [.button, .selected])
        ])))
    }

    // MARK: - Helpers

    private func assertion(
        _ assertion: ElementAssertion
    ) throws -> ResolvedElementAssertion {
        try assertion.resolve(in: .empty)
    }

    private func element(
        _ label: String,
        value: String? = nil,
        traits: [HeistTrait] = [.staticText]
    ) -> HeistElement {
        makeTestHeistElement(
            description: label,
            label: label,
            value: value,
            traits: traits
        )
    }

    private func interface(_ elements: [HeistElement]) -> Interface {
        makeTestInterface(elements: elements)
    }

    private func interface(labelled labels: String...) -> Interface {
        makeTestInterface(elements: labels.map { element($0) })
    }

    private var emptyInterface: Interface {
        makeTestInterface(elements: [])
    }
}
