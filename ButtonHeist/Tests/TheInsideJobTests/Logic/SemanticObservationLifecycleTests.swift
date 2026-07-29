#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationLifecycleTests: XCTestCase {
    private var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func testLifecycleOwnsRunningObservationAndCancellation() async {
        var state = SemanticObservationLifecycle.stopped
        let task = Task<Void, Never> { await Task.yield() }
        let initialDiscovery: SemanticObservationLifecycle.DiscoveryObservation = { nil }
        state.start(task: task, discovery: initialDiscovery)

        XCTAssertTrue(state.isRunning)
        XCTAssertNotNil(state.discovery)
        XCTAssertTrue(state.replaceDiscoveryIfRunning { nil })

        let stoppedTask = state.stop()
        stoppedTask?.cancel()

        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.discovery)
        XCTAssertFalse(state.replaceDiscoveryIfRunning { nil })
        XCTAssertTrue(task.isCancelled)
    }

    func testStreamRunningTruthIsLifecycle() async {
        let stream = vault.semanticObservationStream
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)

        await stream.start { nil }
        XCTAssertTrue(stream.isActive)
        XCTAssertTrue(stream.lifecycle.isRunning)

        stream.stop()
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)
    }

    func testVisibleCaptureReturnsTypedSourceFailure() async {
        let unavailableVault = TheVault(
            tripwire: TheTripwire(),
            visibleObservationSource: { _ in nil }
        )

        let outcome = await unavailableVault.semanticObservationStream
            .refreshVisibleObservation()

        XCTAssertEqual(outcome, .unavailable(.sourceTreeUnavailable))
    }

    func testVisibleCaptureReturnsTypedRuntimeFailureAfterVaultRelease() async {
        var releasedVault: TheVault? = TheVault(tripwire: TheTripwire())
        let stream = releasedVault!.semanticObservationStream
        releasedVault = nil

        let outcome = await stream.refreshVisibleObservation()

        XCTAssertEqual(outcome, .unavailable(.runtimeUnavailable))
    }

    func testVisibleCaptureReturnsTypedCancellation() async {
        let stream = vault.semanticObservationStream
        let capture = Task { @MainActor in
            await stream.refreshVisibleObservation()
        }
        capture.cancel()

        let outcome = await capture.value

        XCTAssertEqual(outcome, .unavailable(.cancelled))
    }

    func testSubscriptionPublishesVaultHistoryInAuthoredOrder() async throws {
        let stream = vault.semanticObservationStream
        let before = await stream.stateOwner.commitAdmission(admission())
        stream.publish(before)
        var received: [Observation.Event] = []
        var historyError: Observation.History.ReadError?

        let subscription = await stream.subscribe(
            scope: .visible,
            replayingAfter: 0,
            receive: { received.append($0) },
            historyUnavailable: { historyError = $0 }
        )
        await stream.stateOwner.discardCurrentObservation()
        let during = await stream.stateOwner.commitAdmission(admission())
        stream.publish(during)
        let expected = before.events + during.events
        let current = await stream.stateOwner.current()
        let history = try await stream.stateOwner.events(after: 0).get()

        XCTAssertNil(historyError)
        XCTAssertEqual(received, expected)
        XCTAssertEqual(
            during.historyRange,
            before.historyRange.upperBound..<(before.historyRange.upperBound + during.events.count)
        )
        XCTAssertEqual(current, during.current)
        XCTAssertEqual(history, expected)

        subscription.cancel()
        let afterCancellation = await stream.stateOwner.commitAdmission(admission())
        stream.publish(afterCancellation)
        let currentAfterCancellation = await stream.stateOwner.current()
        let historyAfterCancellation = try await stream.stateOwner.events(after: 0).get()

        XCTAssertEqual(received, expected)
        XCTAssertEqual(currentAfterCancellation, afterCancellation.current)
        XCTAssertEqual(historyAfterCancellation, expected + afterCancellation.events)
    }

    private func admission(
        scope: SemanticObservationScope = .visible
    ) -> Observation.Admission {
        let observation = InterfaceObservation.empty
        return Observation.Admission(
            tree: observation.tree,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .resting,
            scope: scope,
            notificationAdmission: .action(.init(
                admittedNotifications: [],
                through: .origin,
                scopedScreenChangedThrough: 0
            )),
            keyboardVisible: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            viewportFrames: observation.tree.viewportFrames,
            geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
