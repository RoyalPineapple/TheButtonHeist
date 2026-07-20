#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationReplayTests: SemanticObservationStreamTestCase {
    func testIndependentStreamReplaysDoNotShareProgress() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let baseline = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let cursor = try XCTUnwrap(baseline.cursor)

        let firstEntries = [
            await vault.semanticObservationStream.waitForObservation(
                after: cursor,
                scope: .visible,
                deadline: nil
            ),
            await vault.semanticObservationStream.waitForObservation(
                after: vault.semanticObservationStream.retainedObservationEntries(scope: .visible)[1].cursor,
                scope: .visible,
                deadline: nil
            ),
        ].compactMap { result -> ObservationEntry? in
            guard case .observation(let entry) = result else { return nil }
            return entry
        }
        let secondEntries = [
            await vault.semanticObservationStream.waitForObservation(
                after: cursor,
                scope: .visible,
                deadline: nil
            ),
            await vault.semanticObservationStream.waitForObservation(
                after: vault.semanticObservationStream.retainedObservationEntries(scope: .visible)[1].cursor,
                scope: .visible,
                deadline: nil
            ),
        ].compactMap { result -> ObservationEntry? in
            guard case .observation(let entry) = result else { return nil }
            return entry
        }

        XCTAssertEqual(firstEntries.count, 2)
        XCTAssertEqual(firstEntries, secondEntries)
    }

    func testSettledEventSubscribedBeforeFirstCommitUsesReplaySequence() async throws {
        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: 1
            )
        }
        await waitForObservationWaiterCount(1)

        let committed = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let received = await task.value
        XCTAssertEqual(received?.cursor, committed.cursor)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCommitCompletesEveryRegisteredObservationWaiter() async {
        let tasks = (0..<2).map { _ in
            Task { @MainActor in
                await self.vault.semanticObservationStream.waitForObservation(
                    after: nil,
                    scope: .visible,
                    deadline: nil
                )
            }
        }
        await waitForObservationWaiterCount(2)

        let committed = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )
        for task in tasks {
            guard case .observation(let entry) = await task.value else {
                return XCTFail("Expected every registered waiter to receive the observation")
            }
            XCTAssertEqual(entry.cursor, committed.cursor)
        }
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testObservationWaiterResumesAfterRuntimeStateCommit() async throws {
        let stream = vault.semanticObservationStream
        let task = Task { @MainActor in
            let result = await stream.waitForObservation(
                after: nil,
                scope: .visible,
                deadline: nil
            )
            return (
                result: result,
                sequence: stream.observationStore.sequence,
                notificationCursor: stream.observationStore.notificationCursor
            )
        }
        await waitForObservationWaiterCount(1)

        let notificationBatch = AccessibilityNotificationBatch(
            events: [],
            through: AccessibilityNotificationCursor(sequence: 7),
            scopedScreenChangedThrough: 0,
            gap: nil
        )
        let committed = stream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial"),
            notificationBatch: notificationBatch
        )

        let received = await task.value
        guard case .observation(let entry) = received.result else {
            return XCTFail("Expected waiter to receive the committed observation")
        }
        XCTAssertEqual(entry.cursor, committed.cursor)
        XCTAssertEqual(received.sequence, committed.sequence)
        XCTAssertEqual(received.notificationCursor, notificationBatch.through)
    }

    func testFreshDiscoveryCycleCompletesBeforeTimedReplayFallbackBegins() async throws {
        let initialDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Initial Discovery", heistId: "initial_discovery")
        )
        let latestVisible = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Latest Visible", heistId: "latest_visible")
        )
        let freshDiscovery = observation(label: "Fresh Discovery", heistId: "fresh_discovery")
        let discoveryStarted = expectation(description: "Discovery cycle started")
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var didProduceFreshDiscovery = false

        vault.semanticObservationStream.start {
            guard !didProduceFreshDiscovery else { return nil }
            await withCheckedContinuation { continuation in
                discoveryContinuation = continuation
                discoveryStarted.fulfill()
            }
            didProduceFreshDiscovery = true
            self.vault.observeInterface(freshDiscovery)
            let event = self.vault.semanticObservationStream
                .commitDiscoveryObservationForTesting(freshDiscovery)
            return Navigation.InterfaceExplorationResult(
                event: event,
                progress: .init()
            )
        }
        defer { discoveryContinuation?.resume() }

        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .discovery,
                after: nil,
                timeout: 1
            )
        }
        await fulfillment(of: [discoveryStarted], timeout: 5)

        XCTAssertNotNil(discoveryContinuation)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 1)

        discoveryContinuation?.resume()
        discoveryContinuation = nil
        let receivedValue = await task.value
        let received = try XCTUnwrap(receivedValue)

        XCTAssertGreaterThan(received.sequence, initialDiscovery.sequence)
        XCTAssertGreaterThan(received.sequence, latestVisible.sequence)
        XCTAssertEqual(
            received.settledObservation.observation.tree.orderedElements.first?.element.label,
            "Fresh Discovery"
        )
    }

    func testZeroTimeoutDiscoveryReturnsAfterEmptyCycle() async {
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Retained Discovery", heistId: "retained_discovery")
        )
        let discoveryCompleted = expectation(description: "Empty discovery cycle completed")
        var didRecordCompletion = false
        vault.semanticObservationStream.start {
            if !didRecordCompletion {
                didRecordCompletion = true
                discoveryCompleted.fulfill()
            }
            return nil
        }

        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .discovery,
                after: nil,
                timeout: 0
            )
        }
        await fulfillment(of: [discoveryCompleted], timeout: 5)

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCancellingSettledEventRemovesReplayWaiter() async {
        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: nil
            )
        }
        await waitForObservationWaiterCount(1)

        task.cancel()

        let received = await task.value
        XCTAssertNil(received)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testStoppingStreamCancelsSettledEventReplayWaiters() async {
        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: nil
            )
        }
        await waitForObservationWaiterCount(1)

        vault.semanticObservationStream.stop()

        let received = await task.value
        XCTAssertNil(received)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testSettledEventContinuesAfterInvalidatedRetainedEntry() async {
        let baseline = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let task = Task { @MainActor in
            await self.vault.semanticObservationStream.settledEvent(
                scope: .visible,
                after: baseline.sequence,
                timeout: 1
            )
        }
        await waitForObservationWaiterCount(1)

        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Invalidated", heistId: "invalidated")
        )
        vault.semanticObservationStream.invalidateLatestSettledObservation()
        await waitForObservationWaiterCount(1)

        let final = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Final", heistId: "final")
        )
        let received = await task.value

        XCTAssertEqual(received?.cursor, final.cursor)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
