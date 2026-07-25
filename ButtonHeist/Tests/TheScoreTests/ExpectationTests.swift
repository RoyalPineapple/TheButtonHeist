import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// An expectation is a list of predicates that evidence drains. It is met when
/// the list is empty; until the timeout fires, an outstanding list is not a
/// failure but a list of things still being waited on.
///
/// These tests are about the reduction — which predicates leave and in what
/// order. What a delta composes into is `ElementAssertionCompositionTests`.
final class ExpectationTests: XCTestCase {

    // MARK: - Order within a lane

    func testAnUnsatisfiedPredicateBlocksLaterOnesInItsLane() throws {
        var expectation = try Expectation([exists("Absent"), exists("Present")])

        expectation.snapshot(interface(["Present"]))

        XCTAssertEqual(
            expectation.outstandingCount, 3,
            "Absent blocks, so Present waits behind it and settlement behind that"
        )
    }

    func testThePredicateBehindABlockerDrainsOnceTheBlockerIsSatisfied() throws {
        var expectation = try Expectation([exists("Late"), exists("Early")])

        expectation.snapshot(interface(["Early"]))
        XCTAssertEqual(expectation.outstandingCount, 3)

        expectation.snapshot(interface(["Late", "Early"]))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet)
    }

    /// Evidence flows through the list until it hits a no. One settled tree can
    /// evidence several arrivals at once, so the walk keeps going — otherwise
    /// the verdict would depend on how finely the tripwire sampled.
    func testOneSnapshotSatisfiesConsecutivePredicatesUntilOneRefuses() throws {
        var expectation = try Expectation([
            exists("A"), exists("B"), exists("Never"), exists("C"),
        ])

        expectation.snapshot(interface(["A", "B", "C"]))

        XCTAssertEqual(
            expectation.outstandingCount, 3,
            "Never blocks, C waits behind it, settlement behind that"
        )
    }

    // MARK: - Lanes are independent

    func testAnUnsatisfiedAnnouncementDoesNotBlockAGraphPredicate() throws {
        var expectation = try Expectation([announcement("never spoken"), exists("Present")])

        expectation.snapshot(interface(["Present"]))

        XCTAssertEqual(
            expectation.outstandingCount, 2,
            "the graph predicate drained past the announcement"
        )
    }

    func testAnUnsatisfiedGraphPredicateDoesNotBlockAnAnnouncement() throws {
        var expectation = try Expectation([exists("Absent"), announcement("Saved")])

        expectation.announcement("Saved.")

        XCTAssertEqual(expectation.outstandingCount, 2)
    }

    func testAScreenTickDoesNotAnswerAGraphPredicate() throws {
        var expectation = try Expectation([exists("Detail")])

        expectation.screenChange(to: interface(["Detail"]))

        XCTAssertEqual(
            expectation.outstandingCount, 2,
            "a graph predicate is not in the screen lane"
        )
    }

    // MARK: - Deltas are pairs

    /// An appearance is two searches: the one that wants it gone, then the one
    /// that wants it there. Neither is a diff, and the list is what orders them.
    func testAnAppearanceDrainsAcrossTwoSnapshots() throws {
        var expectation = try Expectation([changed(.appeared(.label("Toast")))])

        XCTAssertEqual(expectation.outstandingCount, 3, "two searches plus settlement")

        expectation.snapshot(interface([]))
        XCTAssertEqual(expectation.outstandingCount, 2)

        expectation.snapshot(interface(["Toast"]))
        XCTAssertEqual(expectation.outstandingCount, 1)
    }

    /// The same element leaving and coming back — the case the ordered drain
    /// exists for. A model that asks "was this ever true" gets it wrong.
    func testALabelCanLeaveAndReturn() throws {
        var expectation = try Expectation([changed(
            .disappeared(.label("Ready")),
            .appeared(.label("Ready"))
        )])

        expectation.snapshot(interface(["Ready"]))
        expectation.snapshot(interface([]))
        expectation.snapshot(interface(["Ready"]))
        expectation.noChange()

        XCTAssertTrue(expectation.isMet)
    }

    // MARK: - The settlement predicate

    func testAnExpectationWithNothingAskedOfItStillWaitsForNoChange() {
        var expectation = Expectation()

        XCTAssertFalse(expectation.isMet)
        expectation.snapshot(interface(["Anything"]))
        XCTAssertFalse(expectation.isMet, "movement is not stillness")

        expectation.noChange()
        XCTAssertTrue(expectation.isMet)
    }

    /// A quiet tree is not an ending. Stillness satisfies nothing in the list —
    /// no predicate reads it — so an outstanding predicate stays outstanding and
    /// the expectation is not met, however still things get.
    func testNoChangeArrivingEarlySatisfiesNothing() throws {
        var expectation = try Expectation([exists("Late")])

        expectation.noChange()

        XCTAssertFalse(expectation.isMet)
        XCTAssertEqual(expectation.outstandingCount, 1, "the tree is still, but Late never arrived")
    }

    /// Settlement is last and never leaves, so every tick flips it: a tree that
    /// went quiet and then carried on is not settled, and the run waits for
    /// stillness to come back.
    func testMovementAfterStillnessUnsettlesTheRun() throws {
        var expectation = try Expectation([exists("Ready")])

        expectation.snapshot(interface(["Ready"]))
        expectation.noChange()
        XCTAssertTrue(expectation.isMet)

        expectation.snapshot(interface(["Ready", "Spinner"]))
        XCTAssertFalse(expectation.isMet, "the tree moved again")

        expectation.noChange()
        XCTAssertTrue(expectation.isMet)
    }

    func testTheRunEndsOnTheNoChangeAfterTheLastPredicateDrains() throws {
        var expectation = try Expectation([exists("Ready")])

        expectation.snapshot(interface(["Ready"]))
        XCTAssertFalse(expectation.isMet, "still waiting for the tree to stop")

        expectation.noChange()
        XCTAssertTrue(expectation.isMet)
    }

    // MARK: - Evidence that answers nothing

    func testASnapshotThatSatisfiesNothingLeavesTheListAlone() throws {
        var expectation = try Expectation([exists("Absent"), announcement("never spoken")])

        expectation.snapshot(interface(["Other"]))

        XCTAssertEqual(expectation.outstandingCount, 3)
    }

    // MARK: - Helpers

    private func exists(_ label: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.exists(.label(label)).resolve(in: .empty)
    }

    private func announcement(_ text: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.announcement(.contains(text)).resolve(in: .empty)
    }

    private func changed(
        _ assertions: ChangeDeclaration.ElementAssertion...
    ) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.changed(.elements(assertions)).resolve(in: .empty)
    }

    private func interface(_ labels: [String]) -> Interface {
        makeTestInterface(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
    }
}
