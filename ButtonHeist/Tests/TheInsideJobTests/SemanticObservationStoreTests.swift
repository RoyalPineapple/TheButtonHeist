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
        let baseline = try commit(scope: .visible, in: &store)
        let current = try commit(scope: .visible, in: &store)

        XCTAssertEqual(baseline.moment.snapshot, baseline.snapshot)
        XCTAssertEqual(store.log.events(since: baseline.moment), .events([.snapshot(current)]))
        XCTAssertEqual(store.snapshotEvent(at: baseline.moment), baseline)
    }

    func testReadsFromOneMomentDoNotShareProgress() throws {
        var store = Observation.Store()
        let baseline = try commit(scope: .visible, in: &store)
        let first = try commit(scope: .visible, in: &store)
        let second = try commit(scope: .visible, in: &store)

        let expected: Observation.EventsSince = .events([.snapshot(first), .snapshot(second)])
        XCTAssertEqual(store.log.events(since: baseline.moment), expected)
        XCTAssertEqual(store.log.events(since: baseline.moment), expected)
    }

    func testEvictionReportsTypedExpiredHistory() throws {
        var store = Observation.Store(retentionLimit: 2)
        let baseline = try commit(scope: .visible, in: &store)
        _ = try commit(scope: .visible, in: &store)
        _ = try commit(scope: .visible, in: &store)
        let current = try commit(scope: .visible, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.moment),
            .expired(Observation.Gap(
                reason: .historyEvicted,
                baseline: baseline.moment,
                current: current.moment
            ))
        )
        XCTAssertEqual(store.latestCommittedEvent, current)
    }

    func testSourceScopeProjectsOneLogAcrossFulfilledScopes() throws {
        var store = Observation.Store()
        let discovery = try commit(scope: .discovery, in: &store)
        let visible = try commit(scope: .visible, in: &store)

        XCTAssertEqual(store.log.events(since: discovery.moment), .events([.snapshot(visible)]))
        XCTAssertEqual(store.latestMoment(scope: .visible), visible.moment)
        XCTAssertEqual(store.latestMoment(scope: .discovery), discovery.moment)
    }

    func testHistoryProjectionKeepsOnlyEventsThatFulfillTheRequestedScope() throws {
        var store = Observation.Store()
        let baseline = try commit(scope: .visible, in: &store)
        _ = try commit(scope: .visible, in: &store)
        let discovery = try commit(scope: .discovery, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.moment).projected(for: .discovery),
            .events([.snapshot(discovery)])
        )
    }

    func testSettlementBoundaryDerivesAnnouncementCursorFromItsMoment() throws {
        var log = Observation.Log(retentionLimit: 1)
        let event = try log.record(
            snapshot: snapshot(sequence: 4),
            continuity: .sameGeneration
        )

        XCTAssertEqual(
            Settlement.EvidenceBoundary(moment: event.moment).announcementCursor.sequence,
            event.notificationSequence
        )
    }

    func testLogConformsToCollectionWithOpaqueMonotonicIndices() throws {
        var log = Observation.Log(retentionLimit: 3)
        let first = try log.record(snapshot: snapshot(sequence: 1), continuity: .sameGeneration)
        let second = try log.record(snapshot: snapshot(sequence: 2), continuity: .sameGeneration)

        XCTAssertEqual(Array(log), [.snapshot(first), .snapshot(second)])
        XCTAssertEqual(log.distance(from: log.startIndex, to: log.endIndex), 2)
        XCTAssertEqual(log.distance(from: log.endIndex, to: log.startIndex), -2)
        XCTAssertEqual(log[log.index(log.startIndex, offsetBy: 1)], .snapshot(second))
    }

    func testInvalidationPreservesLogButBlocksAdmittedRead() throws {
        var store = Observation.Store()
        let initial = try commit(scope: .visible, in: &store)

        store.invalidateCurrentObservation()

        XCTAssertTrue(store.latestSettledObservationInvalidated)
        XCTAssertEqual(store.latestCommittedEvent, initial)
        XCTAssertNil(store.admittedObservation(scope: .visible, after: nil))
        XCTAssertEqual(store.latestCommittedEvent, initial)
    }

    func testStoreOwnerCommitsValueAdmissionFromStructuredChild() async throws {
        let owner = Observation.StoreOwner()
        let admission = admission(scope: .visible)

        let delivery = try await withThrowingTaskGroup(
            of: Observation.StoreOwner.CommittedDelivery.self
        ) { group in
            group.addTask {
                try await owner.commit(admission)
            }
            return try await group.next()!
        }

        let latest = await owner.latestCommittedEvent()
        XCTAssertEqual(delivery.committed.event.sequence, 1)
        XCTAssertEqual(latest, delivery.committed.event)
    }

    private func commit(
        scope: SemanticObservationScope,
        in store: inout Observation.Store
    ) throws -> Observation.SnapshotEvent {
        try store.commitObservation(admission(scope: scope)).event
    }

    private func admission(scope: SemanticObservationScope) -> Observation.Admission {
        let observation = InterfaceObservation.makeForTests()
        return Observation.Admission(
            tree: observation.tree,
            captureID: observation.captureID,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineageEvidence: nil,
            scope: scope,
            notificationAdmission: .action(.init(
                evidence: [],
                through: .origin,
                scopedScreenChangedThrough: 0,
                gap: nil
            )),
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private func snapshot(sequence: UInt64) -> Observation.Snapshot {
        let observation = InterfaceObservation.makeForTests()
        let capture = AccessibilityTrace.Capture(
            sequence: Int(sequence),
            interface: Interface(timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)), tree: []),
            context: AccessibilityTrace.Context(screenId: "screen")
        )
        return Observation.Snapshot(
            sequence: SettledObservationSequence(sequence),
            generation: .initial,
            sourceScope: .visible,
            observation: observation,
            semanticSignal: .empty,
            notificationSequence: sequence,
            trace: AccessibilityTrace(capture: capture)
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
