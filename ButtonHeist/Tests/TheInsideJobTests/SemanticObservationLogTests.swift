#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationLogTests: XCTestCase {
    func testObservationCursorUsesCaptureTimestamp() {
        let settled = capture("capture", sequence: 42, generation: 3)

        XCTAssertEqual(settled.cursor.observedAt, Date(timeIntervalSince1970: 42))
    }

    func testCursorlessReadReturnsPendingBeforeAnyPublication() {
        let log = SemanticObservationLog()

        XCTAssertEqual(log.read(after: nil, scope: .visible), .pending)
    }

    func testCursorlessReadReturnsFirstRetainedEntry() throws {
        let log = SemanticObservationLog()
        let entry = initialEntry("A", sequence: 1, generation: 0)

        try publish(entry.event, to: log)

        XCTAssertEqual(log.read(after: nil, scope: .visible), .entry(entry))
    }

    func testReadAfterExplicitCursorReplaysRetainedEntriesInOrder() throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        let replayedB = log.read(after: entryA.cursor, scope: .visible)
        let replayedC = log.read(after: entryB.cursor, scope: .visible)

        XCTAssertEqual(replayedB, .entry(entryB))
        XCTAssertEqual(replayedC, .entry(entryC))
    }

    func testReadAfterExplicitCursorDoesNotShareProgressAcrossCallers() throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        XCTAssertEqual(log.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(log.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(log.read(after: entryB.cursor, scope: .visible), .entry(entryC))
        XCTAssertEqual(log.read(after: entryB.cursor, scope: .visible), .entry(entryC))
    }

    func testReadAfterLatestRetainedEntryReturnsPending() throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        try publish(entryA.event, to: log)

        XCTAssertEqual(log.read(after: entryA.cursor, scope: .visible), .pending)
    }

    func testReadRejectsCrossScopeCursor() throws {
        let log = SemanticObservationLog()
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        try publish(entryA.event, to: log)

        XCTAssertEqual(
            log.read(after: entryA.cursor, scope: .discovery),
            .failure(.scopeMismatch(cursor: .visible, requested: .discovery))
        )
    }

    func testEvictionReportsTypedIncompleteHistoryOnlyAfterAnEntryIsLost() throws {
        let log = SemanticObservationLog(retentionLimit: 2)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        let entryD = try sameGenerationEntry("D", sequence: 4, after: entryC)
        try publish(entryA.event, to: log)
        try publish(entryB.event, to: log)
        try publish(entryC.event, to: log)

        XCTAssertEqual(log.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(log.read(after: entryB.cursor, scope: .visible), .entry(entryC))

        try publish(entryD.event, to: log)
        XCTAssertEqual(
            log.read(after: entryA.cursor, scope: .visible),
            .failure(.historyEvicted(ObservationGap(
                reason: .historyEvicted,
                baseline: entryA.cursor,
                current: entryD.cursor
            )))
        )
        XCTAssertEqual(log.retainedEntries(scope: .visible), [entryC, entryD])
    }

    func testRetentionLimitAppliesIndependentlyToEachScope() throws {
        let log = SemanticObservationLog(retentionLimit: 2)
        let visibleA = event("visible-a", sequence: 1, generation: 0, scope: .visible)
        let discoveryA = event("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        try log.publish(publication(
            sourceScope: .discovery,
            events: [visibleA, discoveryA]
        ), tripwireSignal: .empty)
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

    func testObservationWindowWithoutRetainedEntriesContainsOnlyBaseline() throws {
        let baseline = capture("A", sequence: 1, generation: 0)
        let window = try ObservationWindow(baseline: baseline, retainedEntries: [])

        XCTAssertEqual(window.captures, [baseline])
    }

    func testSameGenerationTransitionRejectsCrossGenerationElementEdge() {
        let previous = capture("A", sequence: 1, generation: 0).cursor
        let replacement = capture("B", sequence: 2, generation: 1).cursor

        XCTAssertThrowsError(try SameGenerationTransition(from: previous, to: replacement)) { error in
            XCTAssertEqual(
                error as? ObservationTransitionValidationError,
                .generationMismatch(
                    from: ScreenGeneration(rawValue: 0),
                    to: ScreenGeneration(rawValue: 1)
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
                    from: ScreenGeneration(rawValue: 2),
                    to: ScreenGeneration(rawValue: 2)
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
        ), tripwireSignal: .empty)
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
        ), tripwireSignal: .empty)) { error in
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
        XCTAssertNil(log.cleanObservation(scope: .visible, after: nil))
        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [initial])

        let next = event("B", sequence: 2, generation: 0, previous: initial)
        try publish(next, to: log)

        XCTAssertFalse(log.latestSettledObservationInvalidated)
        XCTAssertEqual(log.cleanObservation(scope: .visible, after: initial.sequence)?.event, next)
        XCTAssertEqual(log.retainedEntries(scope: .visible).map(\.event), [initial, next])
    }

    func testCleanReadRejectsScopeRetainedFromAnOlderGeneration() throws {
        let log = SemanticObservationLog()
        let initialVisible = event("visible-a", sequence: 1, generation: 0, scope: .visible)
        let initialDiscovery = event("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        try log.publish(publication(
            sourceScope: .discovery,
            events: [initialVisible, initialDiscovery]
        ), tripwireSignal: .empty)
        XCTAssertEqual(
            log.cleanObservation(scope: .visible, after: nil),
            CleanSettledObservation(event: initialVisible, tripwireSignal: .empty)
        )
        let replacementVisible = event(
            "visible-b",
            sequence: 2,
            generation: 1,
            scope: .visible,
            previous: initialVisible
        )
        try publish(replacementVisible, to: log)

        XCTAssertEqual(log.cleanObservation(scope: .visible, after: nil)?.event, replacementVisible)
        XCTAssertNil(log.cleanObservation(scope: .discovery, after: nil))
        XCTAssertEqual(log.retainedEntries(scope: .discovery).map(\.event), [initialDiscovery])
    }

    func testBeginningScreenReplacementWithdrawsPublicationWithoutClearingHistory() throws {
        let log = SemanticObservationLog()
        let initial = event("A", sequence: 1, generation: 0)
        try publish(initial, to: log)

        log.beginScreenReplacement()

        XCTAssertTrue(log.latestSettledObservationInvalidated)
        XCTAssertNil(log.latestSourceEvent)
        XCTAssertNil(log.cleanObservation(scope: .visible, after: nil))
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
        _ event: SettledObservationEvent,
        to log: SemanticObservationLog
    ) throws {
        try log.publish(
            publication(sourceScope: event.scope, events: [event]),
            tripwireSignal: .empty
        )
    }

    private func publication(
        sourceScope: SemanticObservationScope,
        events: [SettledObservationEvent]
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
        previous: SettledObservationEvent? = nil
    ) -> SettledObservationEvent {
        let previousCapture = previous?.trace.captures.last
        let currentCapture = capture(
            name,
            sequence: sequence,
            generation: generation,
            scope: scope,
            parentHash: previousCapture?.hash
        ).capture
        let trace = AccessibilityTrace(captures: previousCapture.map {
            [$0, currentCapture]
        } ?? [currentCapture])
        let observation = SettledObservation(
            sequence: SettledObservationSequence(sequence),
            scope: scope,
            observation: .makeForTests(),
            semanticSignal: .empty
        )
        return SettledObservationEvent(
            generation: ScreenGeneration(rawValue: generation),
            continuity: previous.map { previous in
                previous.generation.rawValue == generation
                    ? .sameGeneration
                    : .replacement(.inferred(.semanticIdentityDisjoint))
            } ?? .sameGeneration,
            settledObservation: observation,
            previous: previous?.settledObservation,
            previousCursor: previous?.cursor,
            notificationSequence: sequence,
            trace: trace
        )
    }

    private func capture(
        _ name: String,
        sequence: UInt64,
        generation: UInt64,
        scope: SemanticObservationScope = .visible,
        parentHash: String? = nil
    ) -> SettledCapture {
        let traceCapture = AccessibilityTrace.Capture(
            sequence: Int(sequence),
            interface: Interface(
                timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
                tree: []
            ),
            parentHash: parentHash,
            context: AccessibilityTrace.Context(screenId: name)
        )
        return SettledCapture(
            cursor: ObservationCursor(
                generation: ScreenGeneration(rawValue: generation),
                scope: scope,
                sequence: SettledObservationSequence(sequence),
                capture: traceCapture,
                notificationSequence: sequence
            ),
            capture: traceCapture
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
