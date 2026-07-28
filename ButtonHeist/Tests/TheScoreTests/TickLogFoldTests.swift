import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import XCTest
@testable import TheScore

/// Predicate state is a fold over the ordered ticks.
///
/// An expectation is determined by its authored predicates and the ticks it has
/// seen, so the same log always folds to the same answer.
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
        let ticks = replacement(arriving: interface(["Checkout"]))

        guard case .elementsChanged(let emptied) = ticks[0],
              case .screenChanged = ticks[1],
              case .elementsChanged = ticks[2] else {
            return XCTFail("A replacement departs, moves identity, then arrives")
        }
        XCTAssertTrue(emptied.interface.projectedElements.isEmpty, "The old screen empties first")
    }

    /// Order carries the meaning. A two-legged step does not read its after leg
    /// until the before leg drained, so the empty tree answers `missing` and only
    /// the arriving graph answers `exists`.
    func testAppearedDrainsAcrossAReplacementBecauseItsLegsReadDifferentTicks() throws {
        let ticks = replacement(arriving: interface(["Checkout"]))
        let appeared = try changed(.appeared(.label("Checkout")))

        XCTAssertTrue(Expectation([appeared]).folding(ticks + [.noChange]).isMet)
        XCTAssertFalse(
            Expectation([appeared]).folding(ticks.dropLast() + [.noChange]).isMet,
            "Without the arrival tick the after leg has nothing to drain on"
        )
    }

    func testRunsOfStillnessCoalesceIntoOneTick() {
        var log = TickLog()
        log.append(.elementsChanged(interface(["Cart"])))
        log.append(.noChange)
        log.append(.noChange)
        log.append(contentsOf: [.noChange, .noChange])

        XCTAssertEqual(
            log.ticks,
            [.elementsChanged(interface(["Cart"])), .noChange],
            "A still tree restated is the same fact, so only the first is logged"
        )

        // Stillness withdrawn and regained is two facts, not one.
        log.append(.elementsChanged(interface(["Cart", "Pay"])))
        log.append(.noChange)
        XCTAssertEqual(log.ticks.count, 4)
    }

    // MARK: - Helpers

    /// The three ticks a screen replacement emits, in order.
    ///
    /// The vault mints these as one reading passes through its three moments —
    /// the old screen's nodes depart, the identity moves, the new screen's nodes
    /// arrive. Written out here as values, so a fold can be asked about the
    /// sequence without a vault to produce it.
    private func replacement(arriving: AccessibilityTrace.Capture) -> [Tick] {
        [
            .elementsChanged(.empty(at: Date(timeIntervalSince1970: 0))),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(arriving),
        ]
    }

    private func exists(_ label: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.exists(.label(label)).resolve(in: .empty)
    }

    private func changed(
        _ assertions: ElementAssertion...
    ) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.elementsChanged(assertions).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> AccessibilityTrace.Capture {
        makeTestCapture(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
