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
    func testLifecycleOwnsRunningObservationAndCancellation() {
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

    func testStreamRunningTruthIsLifecycle() {
        let stream = vault.semanticObservationStream
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)

        stream.start { nil }
        XCTAssertTrue(stream.isActive)
        XCTAssertTrue(stream.lifecycle.isRunning)

        stream.stop()
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)
    }

    func testStoreCommitAdvancesAllObservationTruthTogether() throws {
        let screen = observation(label: "Published", heistId: "published")
        let interface = makeTestInterface(elements: [])
        let notificationBatch = screenChangedBatch()
        var store = SemanticObservationStore()
        store.requireReplacement()

        let commit = try store.commitObservation(
            .admittedForTesting(screen, tripwireSignal: .empty),
            scope: .visible,
            notificationBatch: notificationBatch,
            evidence: { _ in SemanticObservationStore.Evidence(
                interface: interface,
                accessibilityNotifications: [],
                firstResponder: nil
            ) }
        )

        XCTAssertEqual(commit.event.sequence, 1)
        XCTAssertEqual(commit.event.generation, ScreenGeneration.initial.advanced())
        XCTAssertEqual(commit.event.trace.captures.last?.interface, interface)
        XCTAssertEqual(store.interfaceTree, commit.interfaceObservation.tree)
        XCTAssertEqual(store.sequence, 1)
        XCTAssertEqual(store.notificationCursor, notificationBatch.through)
        XCTAssertEqual(store.scopedScreenChangedSequence, 1)
    }

    func testFirstPublicationInScopeDoesNotBorrowCrossScopePredecessor() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let discovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        XCTAssertNil(discovery.previousCursor)
        let entry = try XCTUnwrap(
            vault.semanticObservationStream.retainedObservationEntries(scope: .discovery).first
        )
        guard case .initial = entry.transition else {
            return XCTFail("Expected first discovery publication to begin its own scoped lineage")
        }
    }

    func testSettledCaptureRequiresExactScopeAndSequence() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let initialDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)
        let visibleCut = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        let resolved = try XCTUnwrap(vault.semanticObservationStream.settledCapture(
            scope: .discovery,
            at: initialDiscovery.sequence
        ))

        XCTAssertEqual(resolved.cursor, initialDiscovery.cursor)
        XCTAssertEqual(resolved.capture.hash, initialDiscovery.trace.captures.last?.hash)
        XCTAssertNil(vault.semanticObservationStream.settledCapture(
            scope: .discovery,
            at: visibleCut.sequence
        ))
    }

    func testLifecycleReplacementRetainsThePublishedEventAndItsExactLineage() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        vault.semanticObservationStream.requireScreenReplacement()
        vault.semanticObservationStream.requireScreenReplacement()
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let baseline = try XCTUnwrap(firstEvent.settledCapture)
        let window = try XCTUnwrap(vault.semanticObservationStream.observationWindow(
            from: baseline,
            through: secondEvent
        ))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(entries[1].event, secondEvent)
        XCTAssertEqual(secondEvent.previousCursor, firstEvent.cursor)
        XCTAssertEqual(window.trace, secondEvent.trace)
        guard case .screenBoundary(let transition) = entries[1].transition else {
            return XCTFail("Expected lifecycle replacement to append a boundary")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
    }

    func testLifecycleResetPreservesTriggerEvidenceForNextBoundaryEntry() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
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

        vault.semanticObservationStream.requireScreenReplacement()
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged, .elementChanged(.layout), .elementChanged(.value)]
        )
        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        guard case .screenBoundary = entries.last?.transition else {
            return XCTFail("Expected trigger evidence to be owned by the next screen boundary")
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
