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

        XCTAssertEqual(baseline.moment.snapshot, baseline.snapshot)
        XCTAssertEqual(store.log.events(since: baseline.moment), .events([.replayed(current)]))
        XCTAssertEqual(store.snapshotEvent(at: baseline.moment), baseline)
    }

    func testReadsFromOneMomentDoNotShareProgress() throws {
        var store = Observation.Store()
        let baseline = try read(scope: .visible, in: &store)
        let first = try read(scope: .visible, in: &store)
        let second = try read(scope: .visible, in: &store)

        let expected: Observation.EventsSince = .events([.replayed(first), .replayed(second)])
        XCTAssertEqual(store.log.events(since: baseline.moment), expected)
        XCTAssertEqual(store.log.events(since: baseline.moment), expected)
    }

    func testEvictionReportsTypedExpiredHistory() throws {
        var store = Observation.Store(retentionLimit: 2)
        let baseline = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        let current = try read(scope: .visible, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.moment),
            .expired(Observation.Gap(
                reason: .historyEvicted,
                baseline: baseline.moment,
                current: current.moment
            ))
        )
        XCTAssertEqual(store.latestReadEvent, current)
    }

    func testSourceScopeProjectsOneLogAcrossFulfilledScopes() throws {
        var store = Observation.Store()
        let discovery = try read(scope: .discovery, in: &store)
        let visible = try read(scope: .visible, in: &store)

        XCTAssertEqual(store.log.events(since: discovery.moment), .events([.replayed(visible)]))
        XCTAssertEqual(store.latestMoment(scope: .visible), visible.moment)
        XCTAssertEqual(store.latestMoment(scope: .discovery), discovery.moment)
    }

    func testHistoryProjectionKeepsOnlyEventsThatFulfillTheRequestedScope() throws {
        var store = Observation.Store()
        let baseline = try read(scope: .visible, in: &store)
        _ = try read(scope: .visible, in: &store)
        let discovery = try read(scope: .discovery, in: &store)

        XCTAssertEqual(
            store.log.events(since: baseline.moment).projected(for: .discovery),
            .events([.replayed(discovery)])
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

        XCTAssertEqual(Array(log), [.replayed(first), .replayed(second)])
        XCTAssertEqual(log.distance(from: log.startIndex, to: log.endIndex), 2)
        XCTAssertEqual(log.distance(from: log.endIndex, to: log.startIndex), -2)
        XCTAssertEqual(log[log.index(log.startIndex, offsetBy: 1)], .replayed(second))
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

        XCTAssertEqual(store.latestReadEvent, initial)
        XCTAssertNil(store.admittedObservation(scope: .visible, after: nil))
        XCTAssertEqual(store.interfaceTree, .empty)
    }

    func testStoreOwnerReadsValueAdmissionFromStructuredChild() async throws {
        let owner = Observation.StoreOwner()
        let admission = admission(scope: .visible)

        let read = try await withThrowingTaskGroup(
            of: (read: Observation.Store.ReadObservation, ticks: [Tick]).self
        ) { group in
            group.addTask {
                try await owner.readAdmission(admission)
            }
            return try await group.next()!
        }

        let latest = await owner.latestReadEvent()
        XCTAssertEqual(read.read.event.sequence, 1)
        XCTAssertEqual(latest, read.read.event)
        XCTAssertEqual(read.ticks.count, 1)
    }

    private func read(
        scope: SemanticObservationScope,
        in store: inout Observation.Store
    ) throws -> Observation.SnapshotEvent {
        try store.readObservation(admission(scope: scope)) { _ in }.event
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
            trace: AccessibilityTrace(capture: capture),
            viewportFrames: observation.tree.viewportFrames,
            placementTolerance: CoarseFrameComparison.currentTolerance
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
