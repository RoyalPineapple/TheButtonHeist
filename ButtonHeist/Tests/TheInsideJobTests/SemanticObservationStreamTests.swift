#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationStreamTests: XCTestCase {
    private var stash: TheStash!

    override func setUp() async throws {
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash.stopPassiveSemanticObservation()
        stash = nil
    }

    func testFirstCommittedScopeAppendsInitialEntry() throws {
        let event = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let entries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.cursor, event.cursor)
        guard case .initial = entry.transition else {
            return XCTFail("Expected the first visible entry to establish lineage")
        }
    }

    func testSecondCommitAppendsSameGenerationEntry() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let secondEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let entries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(firstEvent.generation, secondEvent.generation)
        guard case .sameGeneration(let transition) = entries[1].transition else {
            return XCTFail("Expected a same-generation transition")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
    }

    func testScreenReplacementRetainsBoundaryAndBothCaptures() throws {
        let firstEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after"),
            notificationBatch: screenChangedBatch()
        )

        let entries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            AccessibilityTrace(captures: entries.map(\.settledCapture.capture)).changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        guard case .screenBoundary(let transition) = entries[1].transition else {
            return XCTFail("Expected a retained screen boundary")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
        XCTAssertEqual(entries.map(\.cursor), [firstEvent.cursor, secondEvent.cursor].compactMap { $0 })
    }

    func testDiscoveryPublicationMaintainsIndependentScopeLineage() throws {
        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        _ = stash.semanticObservationStream.commitDiscoveryObservationForTesting(first)
        _ = stash.semanticObservationStream.commitVisibleObservationForTesting(second)

        let visibleEntries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let discoveryEntries = stash.semanticObservationStream.retainedObservationEntries(scope: .discovery)

        XCTAssertEqual(visibleEntries.count, 2)
        XCTAssertEqual(discoveryEntries.count, 1)
        XCTAssertEqual(visibleEntries.map(\.cursor.scope), [.visible, .visible])
        XCTAssertEqual(discoveryEntries.map(\.cursor.scope), [.discovery])
        XCTAssertEqual(
            stash.semanticObservationStream.latestObservationCursor(scope: .visible),
            visibleEntries.last?.cursor
        )
        XCTAssertEqual(
            stash.semanticObservationStream.latestObservationCursor(scope: .discovery),
            discoveryEntries.last?.cursor
        )
    }

    func testDiscoveryAfterVisibleReplacementUsesGlobalGenerationAndScopedPredecessor() throws {
        let initialDiscovery = stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "First Screen", heistId: "first_screen")
        )
        let replacementVisible = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen"),
            notificationBatch: screenChangedBatch()
        )
        let replacementDiscovery = stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen")
        )

        XCTAssertEqual(replacementVisible.generation, initialDiscovery.generation.advanced())
        XCTAssertEqual(replacementDiscovery.generation, replacementVisible.generation)
        XCTAssertEqual(replacementDiscovery.previousCursor, initialDiscovery.cursor)
        XCTAssertEqual(
            replacementDiscovery.trace.captures.first?.hash,
            initialDiscovery.trace.captures.last?.hash
        )

        let discoveryEntries = stash.semanticObservationStream.retainedObservationEntries(scope: .discovery)
        XCTAssertEqual(discoveryEntries.count, 2)
        guard case .screenBoundary(let transition) = discoveryEntries[1].transition else {
            return XCTFail("Expected the skipped discovery scope to cross the retained screen boundary")
        }
        XCTAssertEqual(transition.previousCursor, discoveryEntries[0].cursor)
    }

    func testGenerationClassifierUsesScopedPredecessorUntilGlobalGenerationAdvances() {
        let root = observation(label: "Root", heistId: "root")
        let menu = observation(label: "Menu", heistId: "menu")
        let checkout = observation(label: "Checkout", heistId: "checkout")
        let rootEvent = stash.semanticObservationStream.commitDiscoveryObservationForTesting(root)
        let menuEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(
            menu,
            notificationBatch: screenChangedBatch()
        )
        let sameGenerationMenuSource = menuEvent.replacingGeneration(rootEvent.generation)

        XCTAssertEqual(
            SemanticObservationGenerationClassifier.classify(
                currentGeneration: rootEvent.generation,
                previousInScope: rootEvent,
                latestSource: sameGenerationMenuSource,
                candidate: menu,
                scope: .discovery,
                notifications: []
            ),
            .inferredScreenChange(reason: .primaryHeaderChanged)
        )
        XCTAssertEqual(
            SemanticObservationGenerationClassifier.classify(
                currentGeneration: menuEvent.generation,
                previousInScope: rootEvent,
                latestSource: menuEvent,
                candidate: menu,
                scope: .discovery,
                notifications: []
            ),
            .sameGeneration
        )
        XCTAssertEqual(
            SemanticObservationGenerationClassifier.classify(
                currentGeneration: menuEvent.generation,
                previousInScope: rootEvent,
                latestSource: menuEvent,
                candidate: checkout,
                scope: .discovery,
                notifications: []
            ),
            .inferredScreenChange(reason: .primaryHeaderChanged)
        )
        XCTAssertEqual(
            SemanticObservationGenerationClassifier.classify(
                currentGeneration: menuEvent.generation,
                previousInScope: rootEvent,
                latestSource: menuEvent,
                candidate: menu,
                scope: .discovery,
                notifications: [.screenChanged]
            ),
            .screenChangedNotification
        )
    }

    func testRuntimeStateOwnsLifecycleReplacementAndCancellation() {
        var state = SemanticObservationRuntimeState()
        let task = Task<Void, Never> { await Task.yield() }
        let initialDiscovery: SemanticObservationRuntimeState.DiscoveryObservation = { nil }
        state.start(task: task, discovery: initialDiscovery)

        XCTAssertTrue(state.isRunning)
        XCTAssertNotNil(state.discovery)
        XCTAssertTrue(state.replaceDiscoveryIfRunning { nil })
        XCTAssertEqual(state.lineage, .continuous(.initial))

        state.requireReplacement()
        state.requireReplacement()

        XCTAssertEqual(state.lineage, .replacementRequired(.initial))
        XCTAssertEqual(state.lineage.admitting(.sameGeneration), .screenChangedNotification)

        let stoppedTask = state.stop()
        stoppedTask?.cancel()

        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.discovery)
        XCTAssertFalse(state.replaceDiscoveryIfRunning { nil })
        XCTAssertTrue(task.isCancelled)
    }

    func testPublicationBuilderUsesOnlySuppliedEvidence() {
        let screen = observation(label: "Published", heistId: "published")
        let interface = makeTestInterface(elements: [])
        let notificationBatch = screenChangedBatch()
        let publication = SemanticObservationPublication.make(
            sourceScope: .visible,
            sequence: 1,
            notificationBatch: notificationBatch,
            screen: screen,
            semanticSignal: .empty,
            context: SemanticObservationPublication.Context(
                generationClassification: .screenChangedNotification,
                generation: .initial,
                previousEvents: [:]
            ),
            evidenceByScope: [
                .visible: SemanticObservationPublication.Evidence(
                    interface: interface,
                    accessibilityNotifications: [],
                    firstResponder: nil
                ),
            ]
        )
        var state = SemanticObservationRuntimeState()
        state.requireReplacement()
        state.commit(publication, notificationBatch: notificationBatch, settledReading: nil)

        XCTAssertEqual(publication.sourceEvent.sequence, 1)
        XCTAssertEqual(publication.sourceEvent.generation, ObservationGeneration.initial.advanced())
        XCTAssertEqual(publication.sourceEvent.trace.captures.last?.interface, interface)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.lineage, .continuous(publication.generation))
        XCTAssertEqual(state.notificationCursor, notificationBatch.through)
        XCTAssertEqual(state.scopedScreenChangedSequence, 1)
    }

    func testFirstPublicationInScopeDoesNotBorrowCrossScopePredecessor() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        _ = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let discovery = stash.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        XCTAssertNil(discovery.previousCursor)
        let entry = try XCTUnwrap(
            stash.semanticObservationStream.retainedObservationEntries(scope: .discovery).first
        )
        guard case .initial = entry.transition else {
            return XCTFail("Expected first discovery publication to begin its own scoped lineage")
        }
    }

    func testSettledCaptureRequiresExactScopeAndSequence() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let initialDiscovery = stash.semanticObservationStream.commitDiscoveryObservationForTesting(screen)
        let visibleCut = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = stash.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        let resolved = try XCTUnwrap(stash.semanticObservationStream.settledCapture(
            scope: .discovery,
            at: initialDiscovery.sequence
        ))

        XCTAssertEqual(resolved.cursor, initialDiscovery.cursor)
        XCTAssertEqual(resolved.capture.hash, initialDiscovery.trace.captures.last?.hash)
        XCTAssertNil(stash.semanticObservationStream.settledCapture(
            scope: .discovery,
            at: visibleCut.sequence
        ))
    }

    func testLifecycleReplacementRetainsThePublishedEventAndItsExactLineage() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        stash.semanticObservationStream.requireScreenReplacement()
        stash.semanticObservationStream.requireScreenReplacement()
        let secondEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let entries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let baseline = try XCTUnwrap(firstEvent.settledCapture)
        let window = try XCTUnwrap(stash.semanticObservationStream.observationWindow(
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
        let firstEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let heist = stash.accessibilityNotifications.beginHeistScope()
        stash.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        stash.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        stash.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        heist.cancel()

        stash.semanticObservationStream.requireScreenReplacement()
        let secondEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged, .elementChanged(.layout), .elementChanged(.value)]
        )
        let entries = stash.semanticObservationStream.retainedObservationEntries(scope: .visible)
        guard case .screenBoundary = entries.last?.transition else {
            return XCTFail("Expected trigger evidence to be owned by the next screen boundary")
        }
    }

    func testIndependentStreamReplaysDoNotShareProgress() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let baseline = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let cursor = try XCTUnwrap(baseline.cursor)

        var first = stash.semanticObservationStream
            .observationEntries(after: cursor, scope: .visible)
            .makeAsyncIterator()
        var second = stash.semanticObservationStream
            .observationEntries(after: cursor, scope: .visible)
            .makeAsyncIterator()

        let firstEntries = [try await first.next(), try await first.next()].compactMap { $0 }
        let secondEntries = [try await second.next(), try await second.next()].compactMap { $0 }

        XCTAssertEqual(firstEntries.count, 2)
        XCTAssertEqual(firstEntries, secondEntries)
    }

    func testSettledEventSubscribedBeforeFirstCommitUsesReplaySequence() async throws {
        let task = Task { @MainActor in
            await self.stash.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: 1
            )
        }
        await waitForReplayWaiterCount(1)

        let committed = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let received = await task.value
        XCTAssertEqual(received?.cursor, committed.cursor)
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 0)
    }

    func testFreshDiscoveryCycleCompletesBeforeTimedReplayFallbackBegins() async throws {
        let initialDiscovery = stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Initial Discovery", heistId: "initial_discovery")
        )
        let latestVisible = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Latest Visible", heistId: "latest_visible")
        )
        let freshDiscovery = observation(label: "Fresh Discovery", heistId: "fresh_discovery")
        let discoveryStarted = expectation(description: "Discovery cycle started")
        var discoveryContinuation: CheckedContinuation<Void, Never>?
        var didProduceFreshDiscovery = false

        stash.startPassiveSemanticObservation {
            guard !didProduceFreshDiscovery else { return nil }
            await withCheckedContinuation { continuation in
                discoveryContinuation = continuation
                discoveryStarted.fulfill()
            }
            didProduceFreshDiscovery = true
            self.stash.recordParsedObservedEvidence(freshDiscovery)
            return Navigation.ExploredScreen(
                screen: freshDiscovery,
                manifest: .init(),
                generationDisposition: .preservesGeneration,
                discoveryCommitPolicy: .mergeIntoInterface
            )
        }
        defer { discoveryContinuation?.resume() }

        let task = Task { @MainActor in
            await self.stash.semanticObservationStream.settledEvent(
                scope: .discovery,
                after: nil,
                timeout: 1
            )
        }
        await fulfillment(of: [discoveryStarted], timeout: 5)

        XCTAssertNotNil(discoveryContinuation)
        XCTAssertEqual(stash.semanticObservationStream.cycleWaiterCount, 1)
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 0)

        discoveryContinuation?.resume()
        discoveryContinuation = nil
        let receivedValue = await task.value
        let received = try XCTUnwrap(receivedValue)

        XCTAssertGreaterThan(received.sequence, initialDiscovery.sequence)
        XCTAssertGreaterThan(received.sequence, latestVisible.sequence)
        XCTAssertEqual(
            received.observation.screen.orderedElements.first?.element.label,
            "Fresh Discovery"
        )
    }

    func testCancellingSettledEventRemovesReplayWaiter() async {
        let task = Task { @MainActor in
            await self.stash.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: nil
            )
        }
        await waitForReplayWaiterCount(1)

        task.cancel()

        let received = await task.value
        XCTAssertNil(received)
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 0)
    }

    func testStoppingStreamCancelsSettledEventReplayWaiters() async {
        let task = Task { @MainActor in
            await self.stash.semanticObservationStream.settledEvent(
                scope: .visible,
                after: nil,
                timeout: nil
            )
        }
        await waitForReplayWaiterCount(1)

        stash.semanticObservationStream.stop()

        let received = await task.value
        XCTAssertNil(received)
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 0)
    }

    func testSettledEventContinuesAfterInvalidatedRetainedEntry() async {
        let baseline = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let task = Task { @MainActor in
            await self.stash.semanticObservationStream.settledEvent(
                scope: .visible,
                after: baseline.sequence,
                timeout: 1
            )
        }
        await waitForReplayWaiterCount(1)

        _ = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Invalidated", heistId: "invalidated")
        )
        stash.semanticObservationStream.invalidateLatestSettledObservation()
        await waitForReplayWaiterCount(1)

        let final = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Final", heistId: "final")
        )
        let received = await task.value

        XCTAssertEqual(received?.cursor, final.cursor)
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 0)
    }

    func testPostActionAdmissionRejectsCleanProofFromSupersededCapture() async {
        let stale = observation(label: "Same Tree", heistId: "same")
        let current = observation(label: "Same Tree", heistId: "same")
        stash.recordParsedObservedEvidence(stale)
        stash.recordParsedObservedEvidence(current)

        let result = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: stash.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(.settled(timeMs: 1), screen: stale)
        )

        guard case .unavailable = result.result else {
            return XCTFail("A clean settle from a superseded capture must not commit")
        }
        XCTAssertEqual(stash.latestObservation.captureToken, current.captureToken)
        XCTAssertEqual(stash.latestFailedSettleDiagnosticEvidence?.tree, stale.tree)
        XCTAssertNil(stash.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "same"))
    }

    func testPostActionAdmissionReturnsOnlyTimedOutTreeAsUnsettledEvidence() async {
        let screen = observation(label: "Unstable", heistId: "unstable")
        stash.recordParsedObservedEvidence(screen)

        let result = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: stash.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(.timedOut(timeMs: 1), screen: screen)
        )

        guard case .observedUnsettled(let tree, _) = result.result else {
            return XCTFail("A timeout with a final tree should return diagnostic unsettled evidence")
        }
        XCTAssertEqual(tree, screen.tree)
        XCTAssertEqual(stash.latestFailedSettleDiagnosticEvidence?.tree, screen.tree)
    }

    func testPostActionAdmissionNeverReturnsCancelledTreeAsUsableEvidence() async {
        let screen = observation(label: "Cancelled", heistId: "cancelled")
        stash.recordParsedObservedEvidence(screen)

        let result = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: stash.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(.cancelled(timeMs: 1), screen: screen)
        )

        guard case .unavailable = result.result else {
            return XCTFail("Cancellation must not expose its last tree as usable action evidence")
        }
        XCTAssertEqual(stash.latestFailedSettleDiagnosticEvidence?.tree, screen.tree)
    }

    private func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }

    private func screenChangedBatch() -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: 1,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .scoped
            )],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: 1,
            gap: nil
        )
    }

    private func settleOutcome(
        _ outcome: SettleOutcome,
        screen: InterfaceObservation
    ) -> SettleSession.Outcome {
        SettleSession.Outcome(
            outcome: outcome,
            events: [],
            finalObservation: SettleSessionFinalObservation(screen: screen),
            elementsByKey: [:]
        )
    }

    private func waitForReplayWaiterCount(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard stash.semanticObservationStream.observationReplayWaiterCount != expectedCount else {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation replay waiters")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
