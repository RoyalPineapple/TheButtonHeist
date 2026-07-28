#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationStoreTests: XCTestCase {
    func testMomentIncludesSnapshotAndStartsAtFollowingLogFact() throws {
        var store = Observation.Store()
        let baseline = try read(scope: .visible, in: &store)
        let current = try read(scope: .visible, in: &store)

        XCTAssertEqual(baseline.event.moment.snapshot, baseline.event.snapshot)
        XCTAssertEqual(store.log.events(since: baseline.event.moment), .events(current.events))
        XCTAssertEqual(store.snapshotEvent(at: baseline.event.moment), baseline.event)
    }

    func testReadsFromOneMomentDoNotShareProgress() throws {
        var store = Observation.Store()
        let baseline = try read(scope: .visible, in: &store)
        let first = try read(scope: .visible, in: &store)
        let second = try read(scope: .visible, in: &store)

        let expected: Observation.EventsSince = .events(first.events + second.events)
        XCTAssertEqual(store.log.events(since: baseline.event.moment), expected)
        XCTAssertEqual(store.log.events(since: baseline.event.moment), expected)
    }

    func testEvictionReportsTypedExpiredHistory() throws {
        var store = Observation.Store(retentionLimit: 2)
        let baseline = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        let current = try read(scope: .visible, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.event.moment),
            .expired(Observation.Gap(
                reason: .historyEvicted,
                baseline: baseline.event.moment,
                current: current.event.moment
            ))
        )
        XCTAssertEqual(store.latestReadEvent, current.event)
    }

    func testSourceScopeProjectsOneLogAcrossFulfilledScopes() throws {
        var store = Observation.Store()
        let discovery = try read(scope: .discovery, in: &store)
        let visible = try read(scope: .visible, in: &store)

        XCTAssertEqual(store.log.events(since: discovery.event.moment), .events(visible.events))
        XCTAssertEqual(store.latestMoment(scope: .visible), visible.event.moment)
        XCTAssertEqual(store.latestMoment(scope: .discovery), discovery.event.moment)
    }

    func testHistoryProjectionKeepsOnlyEventsThatFulfillTheRequestedScope() throws {
        var store = Observation.Store()
        let baseline = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        let discovery = try read(scope: .discovery, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.event.moment).projected(for: .discovery),
            .events(discovery.events)
        )
    }

    func testSettlementBoundaryDerivesAnnouncementCursorFromItsMoment() throws {
        var log = Observation.Log(retentionLimit: 1)
        let recorded = try log.record(
            snapshot: snapshot(sequence: 4),
            continuity: .sameGeneration
        )

        XCTAssertEqual(
            Settlement.EvidenceBoundary(moment: recorded.snapshot.moment).announcementCursor.sequence,
            recorded.snapshot.notificationSequence
        )
    }

    func testLogConformsToCollectionWithOpaqueMonotonicIndices() throws {
        var log = Observation.Log(retentionLimit: 3)
        let first = try log.record(snapshot: snapshot(sequence: 1), continuity: .sameGeneration)
        let second = try log.record(snapshot: snapshot(sequence: 2), continuity: .sameGeneration)
        let events = first.events + second.events

        XCTAssertEqual(Array(log), events)
        XCTAssertEqual(log.distance(from: log.startIndex, to: log.endIndex), 2)
        XCTAssertEqual(log.distance(from: log.endIndex, to: log.startIndex), -2)
        XCTAssertEqual(log[log.index(log.startIndex, offsetBy: 1)], second.events[0])
        XCTAssertLessThan(events[0].cursor, events[1].cursor)
    }

    func testScreenReplacementRecordsDepartureScreenAndArrivalInOrder() throws {
        var log = Observation.Log(retentionLimit: 4)
        let initial = try log.record(
            snapshot: snapshot(sequence: 1),
            continuity: .sameGeneration
        )
        let replacement = try log.record(
            snapshot: snapshot(sequence: 2, generation: .initial.advanced()),
            continuity: .replacement(.screenChangedNotification)
        )

        XCTAssertEqual(log.events(since: initial.snapshot.moment), .events(replacement.events))
        XCTAssertEqual(replacement.events.count, 3)
        XCTAssertLessThan(replacement.events[0].cursor, replacement.events[1].cursor)
        XCTAssertLessThan(replacement.events[1].cursor, replacement.events[2].cursor)
        XCTAssertNil(replacement.events[0].snapshotEvent)
        XCTAssertNil(replacement.events[1].snapshotEvent)
        XCTAssertEqual(replacement.events[2].snapshotEvent, replacement.snapshot)

        guard case .elementsChanged(let departure) = replacement.events[0].fact else {
            return XCTFail("Expected the old screen to depart first")
        }
        guard case .screenChanged = replacement.events[1].fact else {
            return XCTFail("Expected the screen identity change second")
        }
        guard case .elementsChanged(let arrival) = replacement.events[2].fact else {
            return XCTFail("Expected the new screen to arrive last")
        }
        XCTAssertTrue(departure.interface.projectedElements.isEmpty)
        XCTAssertEqual(arrival, replacement.snapshot.moment.capture)
        XCTAssertEqual(replacement.snapshot.currentFact, replacement.events[2].fact)
    }

    func testAnnouncementIsRetainedAsItsAuthoredFact() {
        var log = Observation.Log(retentionLimit: 1)
        let announcement = CapturedAnnouncement(
            sequence: 7,
            text: "Saved",
            timestamp: Date(timeIntervalSince1970: 8),
            kind: .announcement
        )

        let event = log.record(announcement: announcement)

        XCTAssertEqual(Array(log), [event])
        XCTAssertEqual(event.fact, .announcement(announcement))
        XCTAssertNil(event.snapshotEvent)
    }

    func testBoundedAnnouncementHistoryDoesNotEraseCurrentSnapshotTruth() throws {
        var log = Observation.Log(retentionLimit: 1)
        let current = try log.record(
            snapshot: snapshot(sequence: 1),
            continuity: .sameGeneration
        ).snapshot

        _ = log.record(announcement: CapturedAnnouncement(
            sequence: 1,
            text: "First",
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .announcement
        ))
        _ = log.record(announcement: CapturedAnnouncement(
            sequence: 2,
            text: "Second",
            timestamp: Date(timeIntervalSince1970: 2),
            kind: .announcement
        ))

        XCTAssertEqual(log.latestSnapshotEvent, current)
        XCTAssertEqual(log.latestSnapshot(fulfilling: .visible), current)
        XCTAssertEqual(log.readSnapshot(after: nil, fulfilling: .visible), .event(current))
    }

    /// A discard leaves the log alone and takes the tree.
    ///
    /// The log is a recording, so what was read stays read. What goes is the
    /// tree the next reading would have continued from, which is why there is
    /// nothing left to admit.
    func testDiscardKeepsTheLogAndTakesTheTree() throws {
        var store = Observation.Store()
        let initial = try read(scope: .visible, in: &store)

        store.discardCurrentObservation()

        XCTAssertEqual(store.latestReadEvent, initial.event)
        XCTAssertNil(store.admittedObservation(scope: .visible, after: nil))
        XCTAssertEqual(store.interfaceTree, .empty)
    }

    func testStoreOwnerReturnsTheEventsAuthoredByAnAdmission() async throws {
        let owner = Observation.StoreOwner()
        let admission = admission(scope: .visible)

        let read = try await owner.readAdmission(admission)

        let latest = await owner.latestReadEvent()
        XCTAssertEqual(read.event.sequence, 1)
        XCTAssertEqual(latest, read.event)
        XCTAssertEqual(read.events.count, 1)
        XCTAssertEqual(read.events[0].snapshotEvent, read.event)
        XCTAssertEqual(read.events[0].fact, read.event.currentFact)
    }

    private func read(
        scope: SemanticObservationScope,
        in store: inout Observation.Store
    ) throws -> Observation.Store.ReadObservation {
        try store.readObservation(admission(scope: scope))
    }

    private func admission(scope: SemanticObservationScope) -> Observation.Admission {
        let observation = InterfaceObservation.makeForTests()
        return Observation.Admission(
            tree: observation.tree,
            captureID: observation.captureID,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .resting,
            scope: scope,
            notificationAdmission: .action(.init(
                evidence: [],
                through: .origin,
                scopedScreenChangedThrough: 0,
                gap: nil
            )),
            keyboardVisible: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            viewportFrames: observation.tree.viewportFrames,
            placementTolerance: CoarseFrameComparison.currentTolerance
        )
    }

    private func snapshot(
        sequence: UInt64,
        generation: ScreenGeneration = .initial
    ) -> Observation.Snapshot {
        let observation = InterfaceObservation.makeForTests()
        let capture = AccessibilityTrace.Capture(
            sequence: Int(sequence),
            interface: Interface(timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)), tree: []),
            context: AccessibilityTrace.Context(screenId: "screen")
        )
        return Observation.Snapshot(
            sequence: SettledObservationSequence(sequence),
            generation: generation,
            sourceScope: .visible,
            observation: observation,
            semanticSignal: .empty,
            notificationSequence: sequence,
            trace: AccessibilityTrace(capture: capture),
            viewportFrames: observation.tree.viewportFrames,
            placementTolerance: CoarseFrameComparison.currentTolerance
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
