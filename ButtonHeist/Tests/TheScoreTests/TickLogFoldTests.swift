import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import XCTest
@testable import TheScore

/// Predicate state is a fold over the ordered ticks.
///
/// That is the whole claim these tests hold down: an expectation is determined
/// by its authored predicates and the ticks it has seen, so the same log always
/// folds to the same answer. Nothing has to remember where a drain got to, which
/// is what lets the tick log be the durable artifact and everything else be
/// derived from it.
final class TickLogFoldTests: XCTestCase {

    /// Folding a log is feeding its ticks one at a time. If these ever diverge,
    /// the fold is carrying state the step-by-step path does not.
    func testFoldingALogMatchesFeedingTheSameTicksOneAtATime() throws {
        let ticks: [Tick] = [
            .elementsChanged(interface(["Cart"])),
            .elementsChanged(interface(["Pay"])),
            .noChange,
        ]

        var stepped = try Expectation([exists("Pay")])
        for tick in ticks {
            stepped = stepped.folding([tick])
        }

        XCTAssertEqual(try Expectation([exists("Pay")]).folding(ticks), stepped)
        XCTAssertTrue(stepped.isMet)
    }

    func testAReplacementIsThreeOrderedTicks() {
        let arriving = interface(["Checkout"])
        let ticks = TickLog.replacement(
            emptiedAt: Date(timeIntervalSince1970: 0),
            screen: ScreenFacts(idAfter: "Checkout"),
            arriving: arriving
        )

        XCTAssertEqual(ticks.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        XCTAssertEqual(ticks.last, .elementsChanged(arriving))
        guard case .elementsChanged(let emptied) = ticks[0] else {
            return XCTFail("Expected the departure tick to carry a tree")
        }
        XCTAssertTrue(emptied.projectedElements.isEmpty, "The old screen empties first")
    }

    /// Order carries the meaning. A two-legged step does not read its after leg
    /// until the before leg drained, so the empty tree answers `missing` and only
    /// the arriving graph answers `exists`.
    func testAppearedDrainsAcrossAReplacementBecauseItsLegsReadDifferentTicks() throws {
        let ticks = TickLog.replacement(
            emptiedAt: Date(timeIntervalSince1970: 0),
            screen: ScreenFacts(idAfter: "Checkout"),
            arriving: interface(["Checkout"])
        )
        let appeared = try changed(.appeared(.label("Checkout")))

        XCTAssertTrue(Expectation([appeared]).folding(ticks + [.noChange]).isMet)
        XCTAssertFalse(
            Expectation([appeared]).folding(ticks.dropLast() + [.noChange]).isMet,
            "Without the arrival tick the after leg has nothing to drain on"
        )
    }

    /// Stillness says whether the tick that just arrived was stillness, so a tree
    /// that starts moving again withdraws it. That keeps the fold total.
    func testStillnessIsTheLastTickNotALatch() {
        let still = Expectation().folding([.noChange])

        XCTAssertTrue(still.isMet)
        XCTAssertFalse(still.folding([.elementsChanged(interface(["Cart"]))]).isMet)
    }

    // MARK: - Helpers

    private func exists(_ label: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.exists(.label(label)).resolve(in: .empty)
    }

    private func changed(
        _ assertions: ElementAssertion...
    ) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.elementsChanged(assertions).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> Interface {
        makeTestInterface(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
