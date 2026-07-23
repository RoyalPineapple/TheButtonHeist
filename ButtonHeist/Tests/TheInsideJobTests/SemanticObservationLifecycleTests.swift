#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationLifecycleTests: SemanticObservationStreamTestCase {
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

    func testStoreCommitAdvancesAllObservationTruthTogether() async throws {
        let screen = observation(label: "Published", heistId: "published")
        let notificationBatch = screenChangedBatch()
        let timestamp = Date(timeIntervalSince1970: 0)
        let interface = TheVault.WireConversion.toSemanticInterface(
            from: screen.tree,
            timestamp: timestamp
        )
        var store = Observation.Store()
        store.requireReplacement()

        let commit = try store.commitObservation(Observation.Admission(
            tree: screen.tree,
            captureID: screen.captureID,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineageEvidence: nil,
            scope: .visible,
            notificationAdmission: .action(.init(
                evidence: vault.resolveAccessibilityNotificationEvidence(
                    notificationBatch.events,
                    in: screen
                ),
                through: notificationBatch.through,
                scopedScreenChangedThrough: notificationBatch.scopedScreenChangedThrough,
                gap: notificationBatch.gap
            )),
            keyboardVisible: false,
            timestamp: timestamp
        ))

        XCTAssertEqual(commit.event.sequence, 1)
        XCTAssertEqual(commit.event.generation, ScreenGeneration.initial.advanced())
        XCTAssertEqual(commit.event.trace.captures.last?.interface, interface)
        XCTAssertEqual(store.interfaceTree, commit.tree)
        XCTAssertEqual(store.sequence, 1)
        XCTAssertEqual(store.notificationIndex, notificationBatch.through)
        XCTAssertEqual(store.scopedScreenChangedSequence, 1)
    }

    func testFirstPublicationInScopeKeepsGlobalPredecessor() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let visible = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let discovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        XCTAssertEqual(discovery.previousMoment, visible.moment)
        guard case .sameGeneration(let previous) = discovery.transition else {
            return XCTFail("Expected discovery publication to continue the global lineage")
        }
        XCTAssertEqual(previous, visible.moment)
    }

    func testLifecycleReplacementRetainsThePublishedEventAndItsExactLineage() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        await vault.semanticObservationStream.requireScreenReplacement()
        await vault.semanticObservationStream.requireScreenReplacement()
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let baseline = firstEvent.moment

        let history = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline)
        }
        XCTAssertEqual(history, .events([.snapshot(secondEvent)]))
        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(secondEvent.previousMoment, firstEvent.moment)
        guard case .screenBoundary(let previous) = secondEvent.transition else {
            return XCTFail("Expected lifecycle replacement to append a boundary")
        }
        XCTAssertEqual(previous, firstEvent.moment)
    }

    func testLifecycleResetPreservesTriggerEvidenceForNextBoundaryEntry() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let heist = vault.accessibilityNotifications.beginHeistScope()
        vault.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        vault.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        heist.cancel()

        await vault.semanticObservationStream.requireScreenReplacement()
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged, .elementChanged(.layout), .elementChanged(.value)]
        )
        guard case .screenBoundary = secondEvent.transition else {
            return XCTFail("Expected trigger evidence to be owned by the next screen boundary")
        }
    }

    func testFailedSettlementReleasesScreenChangedEvidenceForNextIdenticalCapture() async {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let lifecycle = LiveSettlementLifecycle()
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: vault.accessibilityNotifications.beginActionWindow()
        )
        vault.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        await lifecycle.quiesce()
        let didFinalize = await lifecycle.finalize()
        XCTAssertTrue(didFinalize)
        XCTAssertEqual(
            vault.accessibilityNotifications
                .checkpoint(after: .origin, selection: .unclaimedScoped)
                .events
                .map(\.kind),
            [.screenChanged]
        )
        let secondEvent = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(screen)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        guard case .screenBoundary(let previous) = secondEvent.transition else {
            return XCTFail("Expected released screen-change evidence to establish a boundary")
        }
        XCTAssertEqual(previous, firstEvent.moment)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
