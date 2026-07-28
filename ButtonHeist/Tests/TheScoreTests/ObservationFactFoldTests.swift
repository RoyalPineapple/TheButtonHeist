import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import XCTest
@testable import TheScore

/// Predicate state is a fold over ordered observation facts.
///
/// An expectation is determined by its authored predicates and the facts it has
/// seen, so the same log always folds to the same answer.
final class ObservationFactFoldTests: XCTestCase {

    /// Folding a log is feeding its facts one at a time. If these ever diverge,
    /// the fold is carrying state the step-by-step path does not.
    func testFoldingALogMatchesFeedingTheSameFactsOneAtATime() throws {
        let facts: [Observation.Fact] = [
            .elementsChanged(interface(["Cart"])),
            .elementsChanged(interface(["Pay"])),
            .noChange,
        ]

        var stepped = try Expectation([exists("Pay")])
        for fact in facts {
            stepped = stepped.folding([fact])
        }

        XCTAssertEqual(try Expectation([exists("Pay")]).folding(facts), stepped)
        XCTAssertTrue(stepped.isMet)
    }

    func testScreenReplacementFactsDrainInAuthoredOrder() {
        let facts = screenReplacementFacts(arriving: interface(["Checkout"]))

        guard case .elementsChanged(let departure) = facts[0],
              case .screenChanged(let screen) = facts[1],
              case .elementsChanged(let arrival) = facts[2]
        else {
            return XCTFail("Expected departure, screen boundary, and arrival facts")
        }
        XCTAssertTrue(departure.interface.projectedElements.isEmpty)
        XCTAssertEqual(screen, ScreenFacts(idAfter: "Checkout"))
        XCTAssertEqual(arrival, interface(["Checkout"]))
    }

    /// The empty departure answers `missing`; only the arrival answers `exists`.
    func testAppearedDrainsAcrossAReplacementBecauseItsLegsReadDifferentFacts() throws {
        let facts = screenReplacementFacts(arriving: interface(["Checkout"]))
        let appeared = try changed(.appeared(.label("Checkout")))

        XCTAssertTrue(Expectation([appeared]).folding(facts + [.noChange]).isMet)
        XCTAssertFalse(
            Expectation([appeared]).folding(facts.dropLast() + [.noChange]).isMet,
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

    private func screenReplacementFacts(
        arriving: AccessibilityTrace.Capture
    ) -> [Observation.Fact] {
        [
            .elementsChanged(.empty(at: Date(timeIntervalSince1970: 0))),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(arriving),
        ]
    }
}
