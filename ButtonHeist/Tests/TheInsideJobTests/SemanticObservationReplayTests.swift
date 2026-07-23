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
    func testReplayRelayDeliversEveryRetainedSnapshotInOrder() async {
        let stream = vault.semanticObservationStream
        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )
        var received: [Observation.Event] = []
        let relay = ObservationReplayRelay(
            receiveEvent: { received.append($0) },
            receiveUnavailable: { _ in XCTFail("Expected retained history") }
        )

        relay.replay(.events([.snapshot(first), .snapshot(second)]))

        XCTAssertEqual(received, [.snapshot(first), .snapshot(second)])
    }

    func testReplayRelayDeduplicatesSubscriptionHandoff() async {
        let stream = vault.semanticObservationStream
        let retained = await stream.commitVisibleObservationForTesting(
            observation(label: "Retained", heistId: "retained")
        )
        let raced = await stream.commitVisibleObservationForTesting(
            observation(label: "Raced", heistId: "raced")
        )
        var received: [Observation.Event] = []
        let relay = ObservationReplayRelay(
            receiveEvent: { received.append($0) },
            receiveUnavailable: { _ in XCTFail("Expected retained history") }
        )

        relay.receive(.snapshot(raced))
        relay.replay(.events([.snapshot(retained), .snapshot(raced)]))

        XCTAssertEqual(received, [.snapshot(retained), .snapshot(raced)])
    }

    func testReplayRelayReportsExpiredHistoryBeforeBufferedDelivery() async {
        let stream = vault.semanticObservationStream
        await stream.storeOwner.reset(retentionLimit: 2)
        let baseline = await stream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )
        let latest = await stream.commitVisibleObservationForTesting(
            observation(label: "Latest", heistId: "latest")
        )
        let history = await stream.events(since: baseline.moment, scope: .visible)
        guard case .expired = history else {
            return XCTFail("Expected baseline history to expire")
        }
        var received: [Observation.Event] = []
        var unavailable: [Observation.EventsSince] = []
        let relay = ObservationReplayRelay(
            receiveEvent: {
                XCTAssertEqual(unavailable.count, 1)
                received.append($0)
            },
            receiveUnavailable: { unavailable.append($0) }
        )

        relay.receive(.snapshot(latest))
        relay.replay(history)

        XCTAssertEqual(unavailable, [history])
        XCTAssertEqual(received, [.snapshot(latest)])
    }

    func testIndependentStreamReplaysDoNotShareProgress() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let baseline = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let first = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let firstEntries = [
            await vault.semanticObservationStream.waitForObservation(
                since: baseline.moment,
                scope: .visible,
                deadline: nil
            ),
            await vault.semanticObservationStream.waitForObservation(
                since: first.moment,
                scope: .visible,
                deadline: nil
            ),
        ].compactMap { result -> Observation.SnapshotEvent? in
            guard case .observation(let entry) = result else { return nil }
            return entry
        }
        let secondEntries = [
            await vault.semanticObservationStream.waitForObservation(
                since: baseline.moment,
                scope: .visible,
                deadline: nil
            ),
            await vault.semanticObservationStream.waitForObservation(
                since: first.moment,
                scope: .visible,
                deadline: nil
            ),
        ].compactMap { result -> Observation.SnapshotEvent? in
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

        let committed = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let received = await task.value
        XCTAssertEqual(received?.moment, committed.moment)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testCommitCompletesEveryRegisteredObservationWaiter() async {
        let tasks = (0..<2).map { _ in
            Task { @MainActor in
                await self.vault.semanticObservationStream.waitForObservation(
                    since: nil,
                    scope: .visible,
                    deadline: nil
                )
            }
        }
        await waitForObservationWaiterCount(2)

        let committed = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )
        for task in tasks {
            guard case .observation(let entry) = await task.value else {
                return XCTFail("Expected every registered waiter to receive the observation")
            }
            XCTAssertEqual(entry.moment, committed.moment)
        }
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }

    func testObservationWaiterResumesAfterRuntimeStateCommit() async throws {
        let stream = vault.semanticObservationStream
        let task = Task { @MainActor in
            let result = await stream.waitForObservation(
                since: nil,
                scope: .visible,
                deadline: nil
            )
            return (
                result: result,
                sequence: await stream.storeOwner.sequence(),
                notificationIndex: await stream.storeOwner.notificationIndex()
            )
        }
        await waitForObservationWaiterCount(1)

        let notificationBatch = AccessibilityNotificationBatch(
            events: [],
            through: AccessibilityNotificationCursor(sequence: 7),
            scopedScreenChangedThrough: 0,
            gap: nil
        )
        let committed = await stream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial"),
            notificationBatch: notificationBatch
        )

        let received = await task.value
        guard case .observation(let entry) = received.result else {
            return XCTFail("Expected waiter to receive the committed observation")
        }
        XCTAssertEqual(entry.moment, committed.moment)
        XCTAssertEqual(received.sequence, committed.sequence)
        XCTAssertEqual(received.notificationIndex, notificationBatch.through)
    }

    func testFreshDiscoveryCycleCompletesBeforeTimedReplayFallbackBegins() async throws {
        let initialDiscovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Initial Discovery", heistId: "initial_discovery")
        )
        let latestVisible = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Latest Visible", heistId: "latest_visible")
        )
        let freshDiscovery = observation(label: "Fresh Discovery", heistId: "fresh_discovery")
        let discoveryStarted = expectation(description: "Discovery cycle started")
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var didProduceFreshDiscovery = false

        await vault.semanticObservationStream.start {
            guard !didProduceFreshDiscovery else { return nil }
            await withCheckedContinuation { continuation in
                discoveryContinuation = continuation
                discoveryStarted.fulfill()
            }
            didProduceFreshDiscovery = true
            self.vault.observeInterface(freshDiscovery)
            let event = await self.vault.semanticObservationStream
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
            received.snapshot.observation.tree.orderedElements.first?.element.label,
            "Fresh Discovery"
        )
    }

    func testZeroTimeoutDiscoveryReturnsAfterEmptyCycle() async {
        _ = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Retained Discovery", heistId: "retained_discovery")
        )
        let discoveryCompleted = expectation(description: "Empty discovery cycle completed")
        var didRecordCompletion = false
        await vault.semanticObservationStream.start {
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
        let baseline = await vault.semanticObservationStream.commitVisibleObservationForTesting(
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

        _ = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Invalidated", heistId: "invalidated")
        )
        await vault.semanticObservationStream.invalidateLatestSettledObservation()
        await waitForObservationWaiterCount(1)

        let final = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Final", heistId: "final")
        )
        let received = await task.value

        XCTAssertEqual(received?.moment, final.moment)
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 0)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
