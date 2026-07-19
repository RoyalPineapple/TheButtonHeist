#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationStoreTests: XCTestCase {
    func testObservationCursorUsesCaptureTimestamp() {
        let settled = capture("capture", sequence: 42, generation: 3)

        XCTAssertEqual(settled.cursor.observedAt, Date(timeIntervalSince1970: 42))
    }

    func testCursorlessReadReturnsPendingBeforeAnyCommit() {
        let history = SemanticObservationHistory(retentionLimit: 2)

        XCTAssertEqual(history.read(after: nil, scope: .visible), .pending)
    }

    func testCursorlessReadReturnsFirstRetainedEntry() throws {
        var history = SemanticObservationHistory(retentionLimit: 2)
        let entry = initialEntry("A", sequence: 1, generation: 0)

        try history.append(entry.event)

        XCTAssertEqual(history.read(after: nil, scope: .visible), .entry(entry))
    }

    func testReadAfterExplicitCursorReplaysRetainedEntriesInOrder() throws {
        var history = SemanticObservationHistory(retentionLimit: 3)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try history.append(entryA.event)
        try history.append(entryB.event)
        try history.append(entryC.event)

        let replayedB = history.read(after: entryA.cursor, scope: .visible)
        let replayedC = history.read(after: entryB.cursor, scope: .visible)

        XCTAssertEqual(replayedB, .entry(entryB))
        XCTAssertEqual(replayedC, .entry(entryC))
    }

    func testReadAfterExplicitCursorDoesNotShareProgressAcrossCallers() throws {
        var history = SemanticObservationHistory(retentionLimit: 3)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try history.append(entryA.event)
        try history.append(entryB.event)
        try history.append(entryC.event)

        XCTAssertEqual(history.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(history.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(history.read(after: entryB.cursor, scope: .visible), .entry(entryC))
        XCTAssertEqual(history.read(after: entryB.cursor, scope: .visible), .entry(entryC))
    }

    func testReadAfterLatestRetainedEntryReturnsPending() throws {
        var history = SemanticObservationHistory(retentionLimit: 2)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        try history.append(entryA.event)

        XCTAssertEqual(history.read(after: entryA.cursor, scope: .visible), .pending)
    }

    func testReadRejectsCrossScopeCursor() throws {
        var history = SemanticObservationHistory(retentionLimit: 2)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        try history.append(entryA.event)

        XCTAssertEqual(
            history.read(after: entryA.cursor, scope: .discovery),
            .failure(.scopeMismatch(cursor: .visible, requested: .discovery))
        )
    }

    func testEvictionReportsTypedIncompleteHistoryOnlyAfterAnEntryIsLost() throws {
        var history = SemanticObservationHistory(retentionLimit: 2)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try sameGenerationEntry("B", sequence: 2, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        let entryD = try sameGenerationEntry("D", sequence: 4, after: entryC)
        try history.append(entryA.event)
        try history.append(entryB.event)
        try history.append(entryC.event)

        XCTAssertEqual(history.read(after: entryA.cursor, scope: .visible), .entry(entryB))
        XCTAssertEqual(history.read(after: entryB.cursor, scope: .visible), .entry(entryC))

        try history.append(entryD.event)
        XCTAssertEqual(
            history.read(after: entryA.cursor, scope: .visible),
            .failure(.historyEvicted(ObservationGap(
                reason: .historyEvicted,
                baseline: entryA.cursor,
                current: entryD.cursor
            )))
        )
        XCTAssertEqual(history.entries, [entryC, entryD])
    }

    func testRetentionLimitAppliesIndependentlyToEachScope() throws {
        var history = SemanticObservationHistory(retentionLimit: 2)
        let visibleA = initialEntry("visible-a", sequence: 1, generation: 0)
        let discoveryA = initialEntry("discovery-a", sequence: 1, generation: 0, scope: .discovery)
        let visibleB = try sameGenerationEntry("visible-b", sequence: 2, after: visibleA)
        let visibleC = try sameGenerationEntry("visible-c", sequence: 3, after: visibleB)

        try history.append(visibleA.event)
        try history.append(discoveryA.event)
        try history.append(visibleB.event)
        try history.append(visibleC.event)

        XCTAssertEqual(history.entries.filter { $0.cursor.scope == .visible }, [visibleB, visibleC])
        XCTAssertEqual(history.entries.filter { $0.cursor.scope == .discovery }, [discoveryA])
    }

    func testScreenBoundaryAndDestinationHistoryRemainRetained() throws {
        var history = SemanticObservationHistory(retentionLimit: 3)
        let entryA = initialEntry("A", sequence: 1, generation: 0)
        let entryB = try screenBoundaryEntry("B", sequence: 2, generation: 1, after: entryA)
        let entryC = try sameGenerationEntry("C", sequence: 3, after: entryB)
        try history.append(entryA.event)
        try history.append(entryB.event)
        try history.append(entryC.event)

        let retained = history.entries
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

    func testInvalidationPreservesLatestEventAndHistoryButBlocksAdmittedRead() throws {
        var store = SemanticObservationStore()
        let initial = try commit(scope: .visible, in: &store)

        store.invalidateCurrentObservation()

        XCTAssertTrue(store.latestSettledObservationInvalidated)
        XCTAssertEqual(store.latestCommittedEvent, initial)
        XCTAssertNil(store.admittedObservation(scope: .visible, after: nil))
        XCTAssertEqual(store.retainedEntries(scope: .visible).map(\.event), [initial])

        let next = try commit(scope: .visible, in: &store)

        XCTAssertFalse(store.latestSettledObservationInvalidated)
        XCTAssertEqual(store.admittedObservation(scope: .visible, after: initial.sequence)?.event, next)
        XCTAssertEqual(store.retainedEntries(scope: .visible).map(\.event), [initial, next])
    }

    func testAdmittedReadRejectsScopeRetainedFromAnOlderGeneration() throws {
        var store = SemanticObservationStore()
        let initialDiscovery = try commit(scope: .discovery, in: &store)
        let initialVisible = try XCTUnwrap(store.retainedEntries(scope: .visible).last?.event)
        XCTAssertEqual(
            store.admittedObservation(scope: .visible, after: nil),
            SemanticObservationStore.AdmittedObservation(event: initialVisible, tripwireSignal: .empty)
        )
        store.requireReplacement()
        let replacementVisible = try commit(scope: .visible, in: &store)

        XCTAssertEqual(store.admittedObservation(scope: .visible, after: nil)?.event, replacementVisible)
        XCTAssertNil(store.admittedObservation(scope: .discovery, after: nil))
        XCTAssertEqual(store.retainedEntries(scope: .discovery).map(\.event), [initialDiscovery])
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

    private func commit(
        scope: SemanticObservationScope,
        in store: inout SemanticObservationStore
    ) throws -> SettledObservationEvent {
        let observation = InterfaceObservation.makeForTests()
        return try store.commitObservation(
            .admittedForTesting(observation, tripwireSignal: .empty),
            scope: scope,
            notificationBatch: AccessibilityNotificationBatch(
                events: [],
                through: .origin,
                scopedScreenChangedThrough: 0,
                gap: nil
            ),
            evidence: { _ in SemanticObservationStore.Evidence(
                interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []),
                accessibilityNotifications: [],
                firstResponder: nil
            ) }
        ).event
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
