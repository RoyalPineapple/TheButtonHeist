#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationLogTests: XCTestCase {
    func testCursorlessIteratorReceivesFirstEntry() async throws {
        let log = SemanticObservationLog()
        let entry = initialEntry("A", sequence: 1, generation: 0)
        let task = Task { @MainActor in
            var iterator = log.entries(scope: .visible).makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForWaiterCount(1, in: log)

        try publish(entry.event, to: log)

        let received = try await task.value
        XCTAssertEqual(received, entry)
        XCTAssertEqual(log.waiterCount, 0)
    }

    func testCancellingCursorlessIteratorRemovesFirstEntryWaiter() async throws {
        let log = SemanticObservationLog()
        let task = Task { @MainActor in
            var iterator = log.entries(scope: .visible).makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForWaiterCount(1, in: log)

        task.cancel()

        let received = try await task.value
        XCTAssertNil(received)
        XCTAssertEqual(log.waiterCount, 0)
    }

    func testIteratorReplaysRetainedEntriesAfterExplicitCursor() async throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        var iterator = log.entries(after: entryA.cursor, scope: .visible).makeAsyncIterator()
        let replayedB = try await iterator.next()
        let replayedC = try await iterator.next()

        XCTAssertEqual(replayedB, entryB)
        XCTAssertEqual(replayedC, entryC)
    }

    func testIndependentIteratorsDoNotShareCursorProgress() async throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        var first = log.entries(after: entryA.cursor, scope: .visible).makeAsyncIterator()
        var second = log.entries(after: entryA.cursor, scope: .visible).makeAsyncIterator()

        let firstB = try await first.next()
        let firstC = try await first.next()
        let secondB = try await second.next()
        let secondC = try await second.next()

        XCTAssertEqual(firstB, entryB)
        XCTAssertEqual(firstC, entryC)
        XCTAssertEqual(secondB, entryB)
        XCTAssertEqual(secondC, entryC)
    }

    func testCancellingSuspendedIteratorRemovesWaiter() async throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        try publish(entryA.event, to: log)

        let task = Task { @MainActor in
            var iterator = log.entries(after: entryA.cursor, scope: .visible).makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForWaiterCount(1, in: log)

        task.cancel()
        let result = try await task.value

        XCTAssertNil(result)
        XCTAssertEqual(log.waiterCount, 0)
    }

    func testSuspendedIteratorReceivesAtoBtoCExactlyOnceInOrder() async throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)

        let task = Task { @MainActor in
            var iterator = log.entries(after: entryA.cursor, scope: .visible).makeAsyncIterator()
            var delivered: [ObservationEntry] = []
            for _ in 0..<2 {
                guard let entry = try await iterator.next() else { break }
                delivered.append(entry)
            }
            return delivered
        }
        await waitForWaiterCount(1, in: log)

        try publish(entryB.event, to: log)
        await waitForWaiterCount(1, in: log)
        try publish(entryC.event, to: log)
        let delivered = try await task.value

        XCTAssertEqual(delivered, [entryB, entryC])
        XCTAssertEqual(log.waiterCount, 0)
    }

    func testEvictionReportsTypedIncompleteHistoryOnlyAfterAnEntryIsLost() async throws {
        let log = SemanticObservationLog(retentionLimit: 2)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        let entryD = try sameGenerationEntry("D", sequence: 4, after: entryC)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        var completeIterator = log.entries(
            after: entryA.cursor,
            scope: .visible
        ).makeAsyncIterator()
        let replayedB = try await completeIterator.next()
        let replayedC = try await completeIterator.next()
        XCTAssertEqual(replayedB, entryB)
        XCTAssertEqual(replayedC, entryC)

        try publish(entryD.event, to: log)
        var incompleteIterator = log.entries(
            after: entryA.cursor,
            scope: .visible
        ).makeAsyncIterator()
        do {
            _ = try await incompleteIterator.next()
            XCTFail("Expected an eviction gap")
        } catch {
            XCTAssertEqual(
                error,
                .historyEvicted(ObservationGap(
                    reason: .historyEvicted,
                    baseline: entryA.cursor,
                    current: entryD.cursor
                ))
            )
        }
        XCTAssertEqual(log.retainedEntries(scope: .visible), [entryC, entryD])
    }

    func testRetentionLimitAppliesIndependentlyToEachScope() throws {
        let log = SemanticObservationLog(retentionLimit: 2)
        let visibleA = event("visible-a", sequence: 1, generation: 0, scope: .visible)
        let discoveryA = event("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        try log.publish(publication(
            sourceScope: .discovery,
            events: [visibleA, discoveryA]
        ))
        let visibleB = event(
            "visible-b",
            sequence: 2,
            generation: 0,
            scope: .visible,
            previous: visibleA
        )
        let visibleC = event(
            "visible-c",
            sequence: 3,
            generation: 0,
            scope: .visible,
            previous: visibleB
        )

        try publish(visibleB, to: log)
        try publish(visibleC, to: log)

        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [visibleB, visibleC])
        XCTAssertEqual(log.retainedEntries(scope: .discovery).map(\.event), [discoveryA])
    }

    func testScreenBoundaryAndDestinationHistoryRemainRetained() throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try screenBoundaryEntry("B", sequence: 2, generation: 1, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        let retained = log.retainedEntries(scope: .visible)
        let window = try ObservationWindow(
            baseline: entryA.settledCapture,
            retainedEntries: [entryB, entryC]
        )

        XCTAssertEqual(retained, [entryA, entryB, entryC])
        XCTAssertEqual(window.completeness, .complete)
        XCTAssertEqual(window.captures, [
            entryA.settledCapture,
            entryB.settledCapture,
            entryC.settledCapture,
        ])
        guard case .screenBoundary = entryB.transition else {
            return XCTFail("Expected a typed screen boundary")
        }
    }

    func testSameGenerationTransitionRejectsCrossGenerationElementEdge() {
        let previous = capture("A", sequence: 1, generation: 0).cursor
        let replacement = capture("B", sequence: 2, generation: 1).cursor

        XCTAssertThrowsError(try SameGenerationTransition(from: previous, to: replacement)) { error in
            XCTAssertEqual(
                error as? ObservationTransitionValidationError,
                .generationMismatch(
                    from: ObservationGeneration(rawValue: 0),
                    to: ObservationGeneration(rawValue: 1)
                )
            )
        }
    }

    func testScreenBoundaryAcceptsSkippedReplacementGenerations() throws {
        let previous = capture("A", sequence: 1, generation: 0).cursor
        let later = capture("C", sequence: 2, generation: 2).cursor

        let transition = try ScreenBoundaryTransition(from: previous, to: later)

        XCTAssertEqual(transition.previousCursor, previous)
    }

    func testScreenBoundaryRequiresGenerationToAdvance() {
        let previous = capture("A", sequence: 1, generation: 2).cursor
        let unchanged = capture("B", sequence: 2, generation: 2).cursor

        XCTAssertThrowsError(try ScreenBoundaryTransition(from: previous, to: unchanged)) { error in
            XCTAssertEqual(
                error as? ObservationTransitionValidationError,
                .replacementGenerationDidNotAdvance(
                    from: ObservationGeneration(rawValue: 2),
                    to: ObservationGeneration(rawValue: 2)
                )
            )
        }
    }

    func testPublicationRejectsAllScopeEntriesAtomically() throws {
        let log = SemanticObservationLog()
        let initialVisible = event("visible-a", sequence: 1, generation: 0, scope: .visible)
        let initialDiscovery = event("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        try log.publish(publication(
            sourceScope: .discovery,
            events: [initialVisible, initialDiscovery]
        ))
        let nextVisible = event(
            "visible-b",
            sequence: 2,
            generation: 0,
            scope: .visible,
            previous: initialVisible
        )
        let invalidDiscovery = event(
            "discovery-b",
            sequence: 2,
            generation: 0,
            scope: .discovery,
            previous: initialVisible
        )
        let initialDiscoveryCursor = try XCTUnwrap(initialDiscovery.cursor)
        let initialVisibleCursor = try XCTUnwrap(initialVisible.cursor)

        XCTAssertThrowsError(try log.publish(publication(
            sourceScope: .discovery,
            events: [nextVisible, invalidDiscovery]
        ))) { error in
            XCTAssertEqual(
                error as? SemanticObservationLogAppendError,
                .eventLineageMismatch(
                    scope: .discovery,
                    expected: initialDiscoveryCursor,
                    actual: initialVisibleCursor
                )
            )
        }
        XCTAssertEqual(
            log.retainedEntries(scope: .visible).map(\.event),
            [initialVisible]
        )
        XCTAssertEqual(
            log.retainedEntries(scope: .discovery).map(\.event),
            [initialDiscovery]
        )
        XCTAssertEqual(log.latestSourceEvent, initialDiscovery)
    }

    func testInvalidationPreservesLatestEventAndHistoryButBlocksCleanRead() throws {
        let log = SemanticObservationLog()
        let initial = event("A", sequence: 1, generation: 0)
        try publish(initial, to: log)

        log.invalidateCurrentPublication()

        XCTAssertTrue(log.latestSettledObservationInvalidated)
        XCTAssertEqual(log.latestSourceEvent, initial)
        XCTAssertNil(log.cleanEvent(scope: .visible, after: nil))
        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [initial])

        let next = event("B", sequence: 2, generation: 0, previous: initial)
        try publish(next, to: log)

        XCTAssertFalse(log.latestSettledObservationInvalidated)
        XCTAssertEqual(log.cleanEvent(scope: .visible, after: initial.sequence), next)
        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [initial, next])
    }

    func testCleanReadRejectsScopeRetainedFromAnOlderGeneration() throws {
        let log = SemanticObservationLog()
        let initialVisible = event("visible-a", sequence: 1, generation: 0, scope: .visible)
        let initialDiscovery = event("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        try log.publish(publication(
            sourceScope: .discovery,
            events: [initialVisible, initialDiscovery]
        ))
        let replacementVisible = event(
            "visible-b",
            sequence: 2,
            generation: 1,
            scope: .visible,
            previous: initialVisible
        )
        try publish(replacementVisible, to: log)

        XCTAssertEqual(log.cleanEvent(scope: .visible, after: nil), replacementVisible)
        XCTAssertNil(log.cleanEvent(scope: .discovery, after: nil))
        XCTAssertEqual(log.retainedEntries(scope: .discovery).map(\.event), [initialDiscovery])
    }

    func testBeginningScreenReplacementWithdrawsPublicationWithoutClearingHistory() throws {
        let log = SemanticObservationLog()
        let initial = event("A", sequence: 1, generation: 0)
        try publish(initial, to: log)

        log.beginScreenReplacement()

        XCTAssertTrue(log.latestSettledObservationInvalidated)
        XCTAssertNil(log.latestSourceEvent)
        XCTAssertNil(log.cleanEvent(scope: .visible, after: nil))
        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [initial])
    }

    private func initialEntry(
        _ name: String,
        sequence: UInt64,
        generation: UInt64,
        scope: SemanticObservationScope = .visible
    ) -> ObservationEntry {
        .initial(event(name, sequence: sequence, generation: generation, scope: scope))
    }

    private func sameGenerationEntry(
        _ name: String,
        sequence: UInt64,
        after previous: ObservationEntry
    ) throws -> ObservationEntry {
        try ObservationEntry.sameGeneration(
            event(
                name,
                sequence: sequence,
                generation: previous.cursor.generation.rawValue,
                scope: previous.cursor.scope,
                previous: previous.event
            ),
            after: previous.cursor
        )
    }

    private func screenBoundaryEntry(
        _ name: String,
        sequence: UInt64,
        generation: UInt64,
        after previous: ObservationEntry
    ) throws -> ObservationEntry {
        try ObservationEntry.screenBoundary(
            event(
                name,
                sequence: sequence,
                generation: generation,
                scope: previous.cursor.scope,
                previous: previous.event
            ),
            replacing: previous.cursor
        )
    }

    private func publish(
        _ event: SettledSemanticObservationEvent,
        to log: SemanticObservationLog
    ) throws {
        try log.publish(publication(sourceScope: event.scope, events: [event]))
    }

    private func publication(
        sourceScope: SemanticObservationScope,
        events: [SettledSemanticObservationEvent]
    ) -> SemanticObservationPublication {
        SemanticObservationPublication(
            sourceScope: sourceScope,
            events: Dictionary(uniqueKeysWithValues: events.map { ($0.scope, $0) })
        )
    }

    private func event(
        _ name: String,
        sequence: UInt64,
        generation: UInt64,
        scope: SemanticObservationScope = .visible,
        previous: SettledSemanticObservationEvent? = nil
    ) -> SettledSemanticObservationEvent {
        let currentCapture = capture(
            name,
            sequence: sequence,
            generation: generation,
            scope: scope
        ).capture
        let trace = AccessibilityTrace(captures: previous?.trace.captures.last.map {
            [$0, currentCapture]
        } ?? [currentCapture])
        let observation = SettledSemanticObservation(
            sequence: SettledObservationSequence(sequence),
            scope: scope,
            screen: .makeForTests(),
            semanticSignal: .empty
        )
        return SettledSemanticObservationEvent(
            generation: ObservationGeneration(rawValue: generation),
            sequence: SettledObservationSequence(sequence),
            scope: scope,
            observation: observation,
            previous: previous?.observation,
            previousCursor: previous?.cursor,
            notificationSequence: sequence,
            trace: trace
        )
    }

    private func capture(
        _ name: String,
        sequence: UInt64,
        generation: UInt64,
        scope: SemanticObservationScope = .visible
    ) -> SettledCapture {
        let traceCapture = AccessibilityTrace.Capture(
            sequence: Int(sequence),
            interface: Interface(
                timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
                tree: []
            ),
            hash: name
        )
        return SettledCapture(
            cursor: ObservationCursor(
                generation: ObservationGeneration(rawValue: generation),
                scope: scope,
                sequence: SettledObservationSequence(sequence),
                captureHash: traceCapture.hash,
                notificationSequence: sequence
            ),
            capture: traceCapture
        )
    }

    private func waitForWaiterCount(
        _ expectedCount: Int,
        in log: SemanticObservationLog
    ) async {
        for _ in 0..<1_000 {
            guard log.waiterCount != expectedCount else { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation iterator waiters")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
