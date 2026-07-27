import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

/// An expectation is a list of predicates that evidence drains. It is met when
/// the list is empty; until the timeout fires, an outstanding list is not a
/// failure but a list of things still being waited on.
///
/// These tests are about the reduction — which predicates leave, and when. An
/// authored list is a narrative: this happened, then this happened, then this
/// happened. A tick walks it from the front and stops at the first predicate
/// that refuses, so a beat holds every beat behind it. What a delta composes
/// into is `ElementAssertionCompositionTests`.
final class ExpectationTests: XCTestCase {

    // MARK: - The list is read in the order it was written

    /// A predicate the tree does not answer is a barrier. The one behind it is a
    /// later beat in the narrative, and a later beat cannot be evidenced by a
    /// tree that has not yet supplied the earlier one.
    func testAnUnsatisfiedPredicateBlocksTheOneBehindIt() throws {
        var expectation = try Expectation([exists("Absent"), exists("Present")])

        expectation = expectation.folding([.elementsChanged(interface(["Present"]))])

        XCTAssertEqual(
            expectation.outstanding.count, 2,
            "Absent never arrived, so Present is still waiting its turn"
        )
    }

    /// The head drains on the tick that answers it, and only then is the next
    /// beat asked anything.
    func testAPredicateDrainsOnTheTickThatAnswersIt() throws {
        var expectation = try Expectation([exists("Early"), exists("Late")])

        expectation = expectation.folding([.elementsChanged(interface(["Early"]))])
        XCTAssertEqual(expectation.outstanding.count, 1)

        expectation = expectation.folding([.elementsChanged(interface(["Early", "Late"]))])
        XCTAssertTrue(expectation.isMet)
    }

    /// One settled tree evidences every consecutive beat it holds, so the
    /// verdict does not depend on how finely the tripwire sampled.
    func testOneSnapshotSatisfiesEveryConsecutivePredicateItAnswers() throws {
        var expectation = try Expectation([
            exists("A"), exists("B"), exists("C"), exists("Never"),
        ])

        expectation = expectation.folding([.elementsChanged(interface(["A", "B", "C"]))])

        XCTAssertEqual(
            expectation.outstanding.count, 1,
            "A, B and C all drained from the one tree; only Never is left"
        )
    }

    /// The walk stops at the refusal rather than skipping it, so a beat the tree
    /// answers stays outstanding while an earlier one is unmet.
    func testAPredicateBehindARefusalWaitsEvenWhenTheTreeAnswersIt() throws {
        var expectation = try Expectation([
            exists("A"), exists("Never"), exists("C"),
        ])

        expectation = expectation.folding([.elementsChanged(interface(["A", "C"]))])

        XCTAssertEqual(
            expectation.outstanding.count, 2,
            "A drained; Never blocks, so C is held behind it"
        )
    }

    /// Tapping Submit swaps the button for a spinner in one frame, so both
    /// assertions are answered by the same two trees.
    func testTwoAssertionsDescribingOneFrameAreBothSatisfied() throws {
        var expectation = try Expectation([changed(
            .appeared(.label("Processing")),
            .disappeared(.label("Submit"))
        )])

        expectation = expectation.folding([.elementsChanged(interface(["Submit"]))])
        expectation = expectation.folding([.elementsChanged(interface(["Processing"]))])
        expectation = expectation.folding([.noChange])

        XCTAssertTrue(expectation.isMet, "outstanding: \(expectation.outstanding)")
    }

    /// The pair a delta composes into is the one place order still rules, and
    /// the reason chains exist: when only the first half has drained, the second
    /// must keep its own slot. A tree that never held the element cannot satisfy
    /// `disappeared` backwards.
    func testADeltaHalfCannotDrainAheadOfTheOneBeforeIt() throws {
        var expectation = try Expectation([changed(.disappeared(.label("Ghost")))])

        expectation = expectation.folding([.elementsChanged(interface(["Unrelated"]))])
        expectation = expectation.folding([.noChange])

        XCTAssertFalse(
            expectation.isMet,
            "Ghost was never seen present, so nothing disappeared"
        )
    }

    // MARK: - Lanes are independent

    func testAnUnsatisfiedAnnouncementDoesNotBlockAGraphPredicate() throws {
        var expectation = try Expectation([announcement("never spoken"), exists("Present")])

        expectation = expectation.folding([.elementsChanged(interface(["Present"]))])

        XCTAssertEqual(
            expectation.outstanding.count, 1,
            "the graph predicate drained past the announcement"
        )
    }

    func testAnUnsatisfiedGraphPredicateDoesNotBlockAnAnnouncement() throws {
        var expectation = try Expectation([exists("Absent"), announcement("Saved")])

        expectation = expectation.folding([.announcement("Saved.")])

        XCTAssertEqual(expectation.outstanding.count, 1)
    }

    func testAScreenTickDoesNotAnswerAGraphPredicate() throws {
        var expectation = try Expectation([exists("Detail")])

        expectation = expectation.folding([.screenChanged(ScreenFacts(idAfter: "Detail"))])

        XCTAssertEqual(
            expectation.outstanding.count, 1,
            "a graph predicate is not in the screen lane"
        )
    }

    // MARK: - Deltas are pairs

    /// An appearance is two searches: the one that wants it gone, then the one
    /// that wants it there. Neither is a diff, and the list is what orders them.
    func testAnAppearanceDrainsAcrossTwoSnapshots() throws {
        var expectation = try Expectation([changed(.appeared(.label("Toast")))])

        XCTAssertEqual(expectation.outstanding.count, 2, "one search per leg")

        expectation = expectation.folding([.elementsChanged(interface([]))])
        XCTAssertEqual(expectation.outstanding.count, 1)

        expectation = expectation.folding([.elementsChanged(interface(["Toast"]))])
        XCTAssertTrue(expectation.isMet)
    }

    /// The same element leaving and coming back — the case the ordered drain
    /// exists for. A model that asks "was this ever true" gets it wrong.
    func testALabelCanLeaveAndReturn() throws {
        var expectation = try Expectation([changed(
            .disappeared(.label("Ready")),
            .appeared(.label("Ready"))
        )])

        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        expectation = expectation.folding([.elementsChanged(interface([]))])
        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        expectation = expectation.folding([.noChange])

        XCTAssertTrue(expectation.isMet)
    }

    // MARK: - Met is the drain

    /// An expectation answers one question: has everything the caller asked for
    /// happened. An expectation asked for nothing is met from the start, and
    /// stays met however the tree moves.
    func testNothingAskedOfItIsMetImmediately() {
        var expectation = Expectation()

        XCTAssertTrue(expectation.isMet, "no predicate is owed, so nothing is outstanding")
        expectation = expectation.folding([.elementsChanged(interface(["Anything"]))])
        XCTAssertTrue(expectation.isMet, "movement owes nothing either")
    }

    /// A stillness tick answers no element question, so a predicate waiting on
    /// one stays outstanding through it.
    func testNoChangeArrivingEarlySatisfiesNothing() throws {
        var expectation = try Expectation([exists("Late")])

        expectation = expectation.folding([.noChange])

        XCTAssertFalse(expectation.isMet)
        XCTAssertEqual(expectation.outstanding.count, 1, "the tree is still, but Late never arrived")
    }

    /// Draining is monotonic: a predicate the tree answered stays answered, and
    /// later movement leaves that answer standing.
    func testAnAnsweredPredicateStaysAnsweredWhenTheTreeMovesAgain() throws {
        var expectation = try Expectation([exists("Ready")])

        expectation = expectation.folding([.elementsChanged(interface(["Ready"]))])
        XCTAssertTrue(expectation.isMet)

        expectation = expectation.folding([.elementsChanged(interface(["Ready", "Spinner"]))])
        XCTAssertTrue(expectation.isMet, "the tree moved, but Ready still arrived")
    }

    // MARK: - Evidence that answers nothing

    func testASnapshotThatSatisfiesNothingLeavesTheListAlone() throws {
        var expectation = try Expectation([exists("Absent"), announcement("never spoken")])

        expectation = expectation.folding([.elementsChanged(interface(["Other"]))])

        XCTAssertEqual(expectation.outstanding.count, 2)
    }

    // MARK: - Helpers

    private func exists(_ label: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.exists(.label(label)).resolve(in: .empty)
    }

    private func announcement(_ text: String) throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.announcement(.contains(text)).resolve(in: .empty)
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

    /// The same elements, drawn somewhere else.
    private func interface(
        _ labels: [String],
        movedBy offset: Double
    ) -> AccessibilityTrace.Capture {
        makeTestCapture(
            elements: labels.map {
                makeTestHeistElement(description: $0, label: $0, frameY: offset)
            }
        )
    }
}

/// What a predicate that names nothing is asking.
///
/// `elementsChanged` with no assertions is the weakest thing a heist can say:
/// something, anywhere, must differ. It still decomposes into two legs, because
/// one reading shows a state and a change needs two — so what separates the legs
/// is the reading, and which readings count as different is the whole question.
final class BarePredicateTests: XCTestCase {

    /// A frame moving is not something anybody asserted.
    ///
    /// The vault emits a tick for it, and it should: the tree is still moving
    /// and settlement needs to know. But nothing a predicate can name differs,
    /// so the change this predicate is waiting for has not happened yet.
    func testAGraphThatOnlyMovedIsNotAChange() throws {
        var expectation = try Expectation([bareChange()])

        expectation = expectation.folding([
            .elementsChanged(interface(["Add to Cart"])),
            .elementsChanged(interface(["Add to Cart"], movedBy: 40)),
        ])

        XCTAssertFalse(
            expectation.isMet,
            "Both readings say the same thing, so nothing an assertion could name changed"
        )
    }

    /// The same two ticks, with something a predicate could have named.
    func testAGraphWhoseElementsDifferIsAChange() throws {
        var expectation = try Expectation([bareChange()])

        expectation = expectation.folding([
            .elementsChanged(interface(["Add to Cart"])),
            .elementsChanged(interface(["Remove from Cart"])),
        ])

        XCTAssertTrue(expectation.isMet)
    }

    private func bareChange() throws -> ResolvedAccessibilityPredicate {
        try AccessibilityPredicate.elementsChanged([]).resolve(in: .empty)
    }

    private func interface(
        _ labels: [String],
        movedBy offset: Double = 0
    ) -> AccessibilityTrace.Capture {
        makeTestCapture(
            elements: labels.map {
                makeTestHeistElement(description: $0, label: $0, frameY: offset)
            }
        )
    }
}
