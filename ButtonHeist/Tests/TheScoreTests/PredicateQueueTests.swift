import ButtonHeistTestSupport
import Foundation
import ThePlans
import XCTest
@testable import TheScore

/// The predicate queue is a fold: list plus tick in, new list out. These are the
/// laws that fold obeys, stated as tests so the machine cannot drift from them.
final class PredicateQueueTests: XCTestCase {

    // MARK: - Ordering

    /// Blocking is the consumption step. Without it the list is a bag with
    /// order-flavoured tie-breaking, and a later predicate can be satisfied by
    /// an earlier event.
    func testUnsatisfiedPredicateBlocksEveryLaterPredicateOfItsKind() throws {
        let queue = PredicateQueue([
            try resolved(.exists(.label("Never"))),
            try resolved(.exists(.label("Present"))),
        ])

        let next = queue.advanced(by: snapshot(showing: ["Present"]))

        XCTAssertEqual(next.pending.count, 2, "The blocked predicate holds the walk")
    }

    /// The same list without the blocker drains, proving the block above is the
    /// blocking rule and not a matching failure.
    func testTheSamePredicateDrainsOnceTheBlockerIsGone() throws {
        let queue = PredicateQueue([try resolved(.exists(.label("Present")))])

        let next = queue.advanced(by: snapshot(showing: ["Present"]))

        XCTAssertTrue(next.isEmpty)
    }

    /// A tick is one settled snapshot, and a settled state can evidence several
    /// arrivals at once. Spending the tick per predicate would make the verdict
    /// depend on how finely the tripwire sampled.
    func testOneTickSatisfiesConsecutivePredicatesUntilOneRefuses() throws {
        let queue = PredicateQueue([
            try resolved(.exists(.label("A"))),
            try resolved(.exists(.label("B"))),
            try resolved(.exists(.label("Absent"))),
            try resolved(.exists(.label("C"))),
        ])

        let next = queue.advanced(by: snapshot(showing: ["A", "B", "C"]))

        XCTAssertEqual(next.pending.count, 2, "A and B drop; Absent blocks C")
    }

    // MARK: - Kind independence

    /// A predicate of another kind is not asked and does not block. This is the
    /// lane separation: two kinds never compete for one event.
    func testAnAnnouncementPredicateDoesNotBlockASnapshotTick() throws {
        let queue = PredicateQueue([
            try resolved(.announcement("Never spoken")),
            try resolved(.exists(.label("Present"))),
        ])

        let next = queue.advanced(by: snapshot(showing: ["Present"]))

        XCTAssertEqual(next.pending.count, 1, "The graph predicate drains past it")
        XCTAssertTrue(isAnnouncement(try XCTUnwrap(next.pending.first)))
    }

    /// The mirror: a graph predicate does not block a spoken tick.
    func testAGraphPredicateDoesNotBlockAnAnnouncementTick() throws {
        let queue = PredicateQueue([
            try resolved(.exists(.label("Never"))),
            try resolved(.announcement("Saved.")),
        ])

        let next = queue.advanced(by: .announcement("Saved."))

        XCTAssertEqual(next.pending.count, 1)
        XCTAssertFalse(isAnnouncement(try XCTUnwrap(next.pending.first)))
    }

    /// Within a kind, order is preserved and enforced — across kinds it is not
    /// asserted at all. Both halves in one case.
    func testOrderIsEnforcedWithinAKindAndIgnoredAcrossKinds() throws {
        let queue = PredicateQueue([
            try resolved(.announcement("Second")),
            try resolved(.exists(.label("First"))),
        ])

        let afterSnapshot = queue.advanced(by: snapshot(showing: ["First"]))
        XCTAssertEqual(afterSnapshot.pending.count, 1, "Authored later, satisfied first")

        let afterSpoken = afterSnapshot.advanced(by: .announcement("Second"))
        XCTAssertTrue(afterSpoken.isEmpty)
    }

    // MARK: - Announcement matching

    /// Announcements are not in the graph, so they match strings — through the
    /// shared matcher, not a bespoke comparison.
    func testAnnouncementsUseTheSharedStringMatcher() throws {
        let queue = PredicateQueue([try resolved(.announcement(.contains("saved")))])

        XCTAssertTrue(queue.advanced(by: .announcement("Ticket saved.")).isEmpty)
        XCTAssertEqual(queue.advanced(by: .announcement("Ticket lost.")).pending.count, 1)
    }

    // MARK: - Fold laws

    /// Satisfied is absence, not state, so the queue is a value and the session
    /// is a fold. Same ticks, same result — the property the report relies on.
    func testTheFoldIsReplayable() throws {
        let authored = PredicateQueue([
            try resolved(.exists(.label("A"))),
            try resolved(.announcement("Saved.")),
        ])
        let ticks: [PredicateTick] = [
            snapshot(showing: ["A"]),
            .announcement("Saved."),
        ]

        let once = ticks.reduce(authored) { $0.advanced(by: $1) }
        let twice = ticks.reduce(authored) { $0.advanced(by: $1) }

        XCTAssertEqual(once, twice)
        XCTAssertTrue(once.isEmpty)
        XCTAssertEqual(authored.pending.count, 2, "The original is untouched")
    }

    /// A tick that satisfies nothing leaves the queue as it was — so a quiet
    /// window cannot drain a step, and a wait does not return early.
    func testATickThatSatisfiesNothingIsIdentity() throws {
        let queue = PredicateQueue([try resolved(.exists(.label("Never")))])

        XCTAssertEqual(queue.advanced(by: snapshot(showing: ["Other"])), queue)
    }

    /// An empty queue is a fixed point: a step with nothing left stays done
    /// regardless of what arrives afterwards.
    func testAnEmptyQueueAbsorbsEveryTick() {
        let empty = PredicateQueue([])

        XCTAssertTrue(empty.advanced(by: snapshot(showing: ["A"])).isEmpty)
        XCTAssertTrue(empty.advanced(by: .announcement("Saved.")).isEmpty)
    }

    // MARK: - Helpers

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> ResolvedAccessibilityPredicate {
        try predicate.resolve(in: .empty)
    }

    private func isAnnouncement(_ predicate: ResolvedAccessibilityPredicate) -> Bool {
        if case .announcement = predicate { return true }
        return false
    }

    private func snapshot(showing labels: [String]) -> PredicateTick {
        let interface = makeTestInterface(
            elements: labels.map { makeTestHeistElement(description: $0, label: $0) }
        )
        let trace = AccessibilityTrace(first: interface)
        let evidence = AccessibilityTraceEvidence(trace: trace, completeness: .incomplete)
        return .snapshot(current: evidence!, baseline: nil)
    }
}
