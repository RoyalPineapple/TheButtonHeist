#if canImport(UIKit)
#if DEBUG
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationReplayTests: SemanticObservationStreamTestCase {
    func testHistoryRetainsEventsInPublicationOrder() async throws {
        let stream = vault.semanticObservationStream
        let start = vault.state.history.endIndex
        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )

        let events = try retainedEvents(after: start)

        XCTAssertEqual(events, first.events + second.events)
    }

    func testHistoryReportsGapAfterProtectedRangeIsReleased() async throws {
        let stream = vault.semanticObservationStream
        vault.state = TheVault.State(retentionLimit: 2)
        let start = vault.state.history.endIndex
        stream.protectHistory(from: start)

        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )
        let third = await stream.commitVisibleObservationForTesting(
            observation(label: "Third", heistId: "third")
        )

        let protectedEvents = try retainedEvents(after: start)
        XCTAssertEqual(protectedEvents, first.events + second.events + third.events)

        stream.releaseHistory(from: start)
        let releasedRead = stream.events(after: start)

        XCTAssertEqual(releasedRead, .failure(.rangeUnavailable))
    }

    func testIndependentHistoryReadsDoNotShareProgress() async {
        let stream = vault.semanticObservationStream
        let start = vault.state.history.endIndex
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )

        let firstRead = stream.events(after: start)
        let secondRead = stream.events(after: start)

        XCTAssertEqual(firstRead, secondRead)
    }

    func testEvidenceProjectsBoundarySnapshotsAndOrderedEventSuffix() async {
        let stream = vault.semanticObservationStream
        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let boundary = stream.observationBoundary(scope: .visible)
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after")
        )

        let evidence = vault.state.evidence(after: boundary)

        XCTAssertEqual(evidence.baseline, first.current.snapshot)
        XCTAssertEqual(evidence.current, second.current.snapshot)
        XCTAssertEqual(evidence.events, second.events)
        XCTAssertEqual(evidence.coverage, .complete)
    }

    func testCommitCompletesEveryObservationWaiterWithCurrentState() async {
        let stream = vault.semanticObservationStream
        stream.start()
        let start = vault.state.history.endIndex
        let tasks = (0..<2).map { _ in
            Task { @MainActor in
                await stream.waitForObservation(
                    after: start,
                    scope: .visible,
                    boundary: .cancellation
                )
            }
        }
        await waitForObservationWaiterCount(2)

        let publication = await stream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        for task in tasks {
            let result = await task.value
            XCTAssertEqual(result, .observation(publication.current))
        }
        XCTAssertEqual(stream.observationWaiterCount, 0)
    }

    func testCancellingObservationWaitRemovesWaiter() async {
        let stream = vault.semanticObservationStream
        stream.start()
        let start = vault.state.history.endIndex
        let task = Task { @MainActor in
            await stream.waitForObservation(
                after: start,
                scope: .visible,
                boundary: .cancellation
            )
        }
        await waitForObservationWaiterCount(1)

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(stream.observationWaiterCount, 0)
    }

    func testDiscoveryCycleCompletesWaiterWithoutInventingObservation() async {
        let stream = vault.semanticObservationStream
        stream.start()
        let start = vault.state.history.endIndex
        let task = Task { @MainActor in
            await stream.waitForObservation(
                after: start,
                scope: .discovery,
                boundary: .observationCycle
            )
        }
        await waitForObservationWaiterCount(1)

        stream.completeObservationWaiters(
            completedScope: .discovery,
            observationCommitted: false
        )
        let result = await task.value

        XCTAssertEqual(result, .cycleCompletedWithoutObservation)
        XCTAssertEqual(stream.observationWaiterCount, 0)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
