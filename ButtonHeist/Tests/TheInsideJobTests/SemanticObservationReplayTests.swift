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
        let start = await stream.stateOwner.historyEndIndex()
        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )

        let events = try await retainedEvents(after: start)

        XCTAssertEqual(events, first.events + second.events)
    }

    func testHistoryReportsGapAfterProtectedRangeIsReleased() async throws {
        let stream = vault.semanticObservationStream
        await stream.stateOwner.reset(retentionLimit: 2)
        let start = await stream.stateOwner.historyEndIndex()
        await stream.stateOwner.protectHistory(from: start)

        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )
        let third = await stream.commitVisibleObservationForTesting(
            observation(label: "Third", heistId: "third")
        )

        let protectedEvents = try await retainedEvents(after: start)
        XCTAssertEqual(protectedEvents, first.events + second.events + third.events)

        await stream.stateOwner.releaseHistory(from: start)
        let releasedRead = await stream.stateOwner.events(after: start)

        XCTAssertEqual(releasedRead, .failure(.rangeUnavailable))
    }

    func testIndependentHistoryReadsDoNotShareProgress() async {
        let stream = vault.semanticObservationStream
        let start = await stream.stateOwner.historyEndIndex()
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "First", heistId: "first")
        )
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Second", heistId: "second")
        )

        let firstRead = await stream.stateOwner.events(after: start)
        let secondRead = await stream.stateOwner.events(after: start)

        XCTAssertEqual(firstRead, secondRead)
    }

    func testEvidenceProjectsBoundarySnapshotsAndOrderedEventSuffix() async {
        let stream = vault.semanticObservationStream
        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let boundary = await stream.stateOwner.observationBoundary(scope: .visible)
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after")
        )

        let evidence = await stream.stateOwner.evidence(after: boundary)

        XCTAssertEqual(evidence.baseline, first.current.snapshot)
        XCTAssertEqual(evidence.current, second.current.snapshot)
        XCTAssertEqual(evidence.events, second.events)
        XCTAssertEqual(evidence.completeness, .complete)
    }

    func testCommitCompletesEveryObservationWaiterWithCurrentState() async {
        let stream = vault.semanticObservationStream
        let start = await stream.stateOwner.historyEndIndex()
        let tasks = (0..<2).map { _ in
            Task { @MainActor in
                await stream.waitForObservation(
                    after: start,
                    scope: .visible,
                    deadline: nil
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
        let start = await stream.stateOwner.historyEndIndex()
        let task = Task { @MainActor in
            await stream.waitForObservation(
                after: start,
                scope: .visible,
                deadline: nil
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
        let start = await stream.stateOwner.historyEndIndex()
        let task = Task { @MainActor in
            await stream.waitForObservation(
                after: start,
                scope: .discovery,
                deadline: nil,
                completingAfterCurrentCycle: true
            )
        }
        await waitForObservationWaiterCount(1)

        await stream.completeObservationWaiters(completedScope: .discovery)
        let result = await task.value

        XCTAssertEqual(result, .cycleCompleted)
        XCTAssertEqual(stream.observationWaiterCount, 0)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
