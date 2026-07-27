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
        let arriving = interface(["Checkout"])
        let ticks = TickLog.replacement(
            screen: ScreenFacts(idAfter: "Checkout"),
            arriving: arriving
        )

        XCTAssertEqual(ticks.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        XCTAssertEqual(ticks.last, .elementsChanged(arriving))
        guard case .elementsChanged(let emptied) = ticks[0] else {
            return XCTFail("Expected the departure tick to carry a tree")
        }
        XCTAssertTrue(emptied.interface.projectedElements.isEmpty, "The old screen empties first")
    }

    /// Order carries the meaning. A two-legged step does not read its after leg
    /// until the before leg drained, so the empty tree answers `missing` and only
    /// the arriving graph answers `exists`.
    func testAppearedDrainsAcrossAReplacementBecauseItsLegsReadDifferentTicks() throws {
        let ticks = TickLog.replacement(
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

    // MARK: - Steps

    /// A step's element diff is the same diff the capture-pair path produced.
    func testAStepsElementDiffMatchesTheCapturePairDiff() {
        let before = interface(["Total", "Pay"])
        let after = interface(["Total", "Spinner"])

        let viaStep = TickStep(.elementsChanged(before), .elementsChanged(after)).elementEdits
        let viaPair = AccessibilityTraceElementDiff.projectElementEdits(
            beforeRecords: before.interface.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: after.interface.projectedElementRecords.map(ElementDiffRecord.init)
        )

        XCTAssertEqual(viaStep, viaPair)
        XCTAssertEqual(viaStep.added.compactMap(\.label), ["Spinner"])
        XCTAssertEqual(viaStep.removed.compactMap(\.label), ["Pay"])
    }

    /// The boundary is read off the tick kind, not recomputed. Settlement already
    /// decided a replacement happened and said so by emitting the marker.
    func testAStepReadsTheBoundaryOffTheTickKindAndHasNoElementQuestion() {
        let step = TickStep(
            .elementsChanged(interface(["Cart"])),
            .screenChanged(ScreenFacts(idAfter: "Checkout"))
        )

        XCTAssertTrue(step.crossesScreenBoundary)
        XCTAssertNil(step.interfaces, "A screen-lane step compares no trees")
        XCTAssertTrue(step.elementEdits.isEmpty)
    }

    func testALogOfOneTickHasNoStepsBecauseNothingChanged() {
        var log = TickLog()
        log.append(.elementsChanged(interface(["Cart"])))

        XCTAssertTrue(log.steps.isEmpty)
        log.append(.noChange)
        XCTAssertEqual(log.steps.count, 1)
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
}
