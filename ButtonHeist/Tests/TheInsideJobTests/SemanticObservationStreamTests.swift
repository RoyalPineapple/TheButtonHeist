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
    private var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func testObservationStreamRetainsEveryFastTransitionAfterCursor() async throws {
        let baseline = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let cursor = try XCTUnwrap(baseline.cursor)

        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(first)
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let publishedFirst = await vault.semanticObservationStream.waitForObservation(
            after: cursor,
            scope: .visible,
            deadline: nil
        )
        let publishedSecond = await vault.semanticObservationStream.waitForObservation(
            after: try XCTUnwrap(firstEvent.cursor),
            scope: .visible,
            deadline: nil
        )
        guard case .observation(let firstEntry) = publishedFirst,
              case .observation(let secondEntry) = publishedSecond else {
            return XCTFail("Expected retained visible observations")
        }
        XCTAssertEqual(firstEntry.cursor, firstEvent.cursor)
        XCTAssertEqual(secondEntry.cursor, secondEvent.cursor)
    }

    func testLifecycleResetClearsCommittedTruth() {
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before Reset", heistId: "before_reset")
        )

        vault.clearCache()

        XCTAssertEqual(vault.interfaceTree, .empty)
        XCTAssertEqual(vault.latestObservation.tree, InterfaceObservation.empty.tree)
    }

    func testConcurrentVisibleConsumersShareOneRefresh() async throws {
        let stream = vault.semanticObservationStream
        let signal = tripwireSignal(sequence: 1)
        var releaseSettle: CheckedContinuation<Void, Never>?
        let settleCount = installSettler(signal: { signal }, beforeSettle: {
            await withCheckedContinuation { releaseSettle = $0 }
        })
        defer { releaseSettle?.resume() }

        var firstEvidence: CleanSettledObservation?
        var secondEvidence: CleanSettledObservation?
        let firstTask = Task { @MainActor in
            firstEvidence = await stream.visibleEvidence(timeout: 1)
        }
        await waitForSettleCount(1, current: settleCount)
        let secondTask = Task { @MainActor in
            secondEvidence = await stream.visibleEvidence(timeout: 1)
        }
        await Task.yield()

        releaseSettle?.resume()
        releaseSettle = nil
        await firstTask.value
        await secondTask.value
        let first = try XCTUnwrap(firstEvidence)
        let second = try XCTUnwrap(secondEvidence)
        XCTAssertEqual(settleCount(), 1)
        XCTAssertEqual(first.event.sequence, second.event.sequence)
    }

    func testCleanStateIsReusedUntilTripInvalidationOrScreenReplacement() async throws {
        let stream = vault.semanticObservationStream
        let initialSignal = tripwireSignal(sequence: 1)
        let settleCount = installSettler(signal: { initialSignal })

        let initial = try await visibleEvidence()
        let reused = try await visibleEvidence()
        let changedSignal = tripwireSignal(sequence: 2)
        stream.readTripwireSignal = { changedSignal }
        let afterTrip = try await visibleEvidence()
        stream.invalidateLatestSettledObservation()
        let afterInvalidation = try await visibleEvidence()
        stream.requireScreenReplacement()
        let afterReplacement = try await visibleEvidence()

        XCTAssertEqual(settleCount(), 4)
        XCTAssertEqual(reused.event.sequence, initial.event.sequence)
        XCTAssertNotEqual(afterTrip.event.sequence, reused.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterTrip.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterReplacement.event.sequence)
    }

    func testSameCaptureInDifferentScopeGetsItsOwnPublication() {
        let screen = observation(label: "Shared", heistId: "shared")

        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        XCTAssertEqual(vault.semanticObservationStream.retainedObservationEntries(scope: .visible).count, 2)
        XCTAssertEqual(vault.semanticObservationStream.retainedObservationEntries(scope: .discovery).count, 1)
    }

    func testFirstCommittedScopeAppendsInitialEntry() throws {
        let event = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.cursor, event.cursor)
        guard case .initial = entry.transition else {
            return XCTFail("Expected the first visible entry to establish lineage")
        }
    }

    func testSecondCommitAppendsSameGenerationEntry() throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(firstEvent.generation, secondEvent.generation)
        guard case .sameGeneration(let transition) = entries[1].transition else {
            return XCTFail("Expected a same-generation transition")
        }
        XCTAssertEqual(transition.previousCursor, entries[0].cursor)
    }

    func testVisiblePublicationRetainsKnownGraphInStateAndTraceEvidence() throws {
        let visibleBefore = AccessibilityElement.make(
            label: "Anchor",
            value: "Before",
            identifier: "anchor",
            traits: .staticText
        )
        let visibleAfter = AccessibilityElement.make(
            label: "Anchor",
            value: "After",
            identifier: "anchor",
            traits: .staticText
        )
        let offViewport = AccessibilityElement.make(label: "Known Offscreen", traits: .button)
        let offViewportId: HeistId = "known_offscreen_button"
        let baseline = InterfaceObservation.makeForTests(
            elements: [(visibleBefore, "anchor")],
            offViewport: [.init(offViewport, heistId: offViewportId)]
        )
        let current = InterfaceObservation.makeForTests(elements: [(visibleAfter, "anchor")])

        let baselineEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let currentEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(current)

        XCTAssertEqual(currentEvent.generation, baselineEvent.generation)
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: offViewportId))
        XCTAssertTrue(
            currentEvent.trace.captures.last?.interface.projectedElements.contains {
                $0.label == "Known Offscreen"
            } == true
        )
        XCTAssertEqual(
            currentEvent.settledObservation.observation.tree.orderedElements.compactMap(\.element.label),
            currentEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label)
        )
    }

    func testScreenReplacementRetainsBoundaryAndBothCaptures() throws {
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after"),
            notificationBatch: screenChangedBatch()
        )

        let entries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)

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

    func testInferredReplacementResetsGraphAndRetainsClassifierProof() {
        let firstEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after")
        )

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.continuity,
            .replacement(.inferred(.primaryHeaderChanged))
        )
        XCTAssertEqual(vault.interfaceTree.elementIDs, ["after"])
    }

    func testPathOnlyScrollReplacementDiscardsPriorDiscoveryAndLiveEvidence() {
        let oldHeader = NSObject()
        let oldRow = NSObject()
        let newHeader = NSObject()
        let newRow = NSObject()
        let firstEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "old_header",
                rowLabel: "Orders",
                rowId: "old_row",
                headerObject: oldHeader,
                rowObject: oldRow
            )
        )
        let secondEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "new_header",
                rowLabel: "Products",
                rowId: "new_row",
                headerObject: newHeader,
                rowObject: newRow
            )
        )

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.continuity,
            .replacement(.inferred(.semanticIdentityDisjoint))
        )
        XCTAssertNil(vault.interfaceTree.findElement(heistId: "old_row"))
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: "new_row"))
        XCTAssertNil(vault.latestObservation.liveCapture.object(for: "old_row"))
        XCTAssertTrue(vault.latestObservation.liveCapture.object(for: "new_row") === newRow)
    }

    func testDiscoveryPublicationMaintainsIndependentScopeLineage() throws {
        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(first)
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let visibleEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let discoveryEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .discovery)

        XCTAssertEqual(visibleEntries.count, 2)
        XCTAssertEqual(discoveryEntries.count, 1)
        XCTAssertEqual(visibleEntries.map(\.cursor.scope), [.visible, .visible])
        XCTAssertEqual(discoveryEntries.map(\.cursor.scope), [.discovery])
        XCTAssertEqual(
            vault.semanticObservationStream.latestObservationCursor(scope: .visible),
            visibleEntries.last?.cursor
        )
        XCTAssertEqual(
            vault.semanticObservationStream.latestObservationCursor(scope: .discovery),
            discoveryEntries.last?.cursor
        )
    }

    func testDiscoveryPublicationCarriesCanonicalGraphAndEvidenceAcrossFulfilledScopes() throws {
        let visible = AccessibilityElement.make(label: "Visible", traits: .header)
        let offViewport = AccessibilityElement.make(label: "Off Viewport", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            [.init(visible, heistId: "visible")],
            offViewport: [.init(offViewport, heistId: "off_viewport")]
        )

        let discoveryEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(observation)
        let visibleEvent = try XCTUnwrap(
            vault.semanticObservationStream.retainedObservationEntries(scope: .visible).last?.event
        )

        XCTAssertEqual(discoveryEvent.settledObservation.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(discoveryEvent.settledObservation.observation.captureToken, observation.captureToken)
        XCTAssertEqual(
            discoveryEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(visibleEvent.settledObservation.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(visibleEvent.settledObservation.observation.captureToken, observation.captureToken)
        XCTAssertEqual(
            visibleEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(vault.latestObservation.captureToken, observation.captureToken)
    }

    func testDiscoverySettlementRejectsTripwireChangeBeforeCommit() {
        let observation = observation(label: "Candidate", heistId: "candidate")
        vault.recordParsedObservedEvidence(observation)
        let settledSignal = tripwireSignal(sequence: 1)
        let currentSignal = tripwireSignal(sequence: 2)
        vault.semanticObservationStream.readTripwireSignal = { currentSignal }
        let outcome = settleOutcome(
            .settled(timeMs: 1),
            observation: observation,
            tripwireSignal: settledSignal
        )

        let event = vault.semanticObservationStream.commitSettledDiscoveryObservation(
            outcome,
            discoveryCommitPolicy: .mergeIntoInterface,
            afterViewportMovement: true
        )

        XCTAssertNil(event)
        XCTAssertNil(vault.interfaceTree.findElement(heistId: "candidate"))
    }

    func testDiscoveryAfterVisibleReplacementUsesGlobalGenerationAndScopedPredecessor() throws {
        let initialDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "First Screen", heistId: "first_screen")
        )
        let replacementVisible = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen"),
            notificationBatch: screenChangedBatch()
        )
        let replacementDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen")
        )

        XCTAssertEqual(replacementVisible.generation, initialDiscovery.generation.advanced())
        XCTAssertEqual(replacementDiscovery.generation, replacementVisible.generation)
        XCTAssertEqual(replacementDiscovery.previousCursor, initialDiscovery.cursor)
        XCTAssertEqual(
            replacementDiscovery.trace.captures.first?.hash,
            initialDiscovery.trace.captures.last?.hash
        )

        let discoveryEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .discovery)
        XCTAssertEqual(discoveryEntries.count, 2)
        guard case .screenBoundary(let transition) = discoveryEntries[1].transition else {
            return XCTFail("Expected the skipped discovery scope to cross the retained screen boundary")
        }
        XCTAssertEqual(transition.previousCursor, discoveryEntries[0].cursor)
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
        XCTAssertEqual(state.lineage.admitting(.sameGeneration), .replacement(.screenChangedNotification))

        let stoppedTask = state.stop()
        stoppedTask?.cancel()

        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.discovery)
        XCTAssertFalse(state.replaceDiscoveryIfRunning { nil })
        XCTAssertTrue(task.isCancelled)
    }

    func testStreamRunningTruthIsRuntimeState() {
        let stream = vault.semanticObservationStream
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.runtimeState.isRunning)

        stream.start { nil }
        XCTAssertTrue(stream.isActive)
        XCTAssertTrue(stream.runtimeState.isRunning)

        stream.stop()
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.runtimeState.isRunning)
    }

    func testPublicationBuilderUsesOnlySuppliedEvidence() {
        let screen = observation(label: "Published", heistId: "published")
        let interface = makeTestInterface(elements: [])
        let notificationBatch = screenChangedBatch()
        let publication = SemanticObservationPublication.make(
            sourceScope: .visible,
            sequence: 1,
            notificationBatch: notificationBatch,
            observation: screen,
            semanticSignal: .empty,
            context: SemanticObservationPublication.Context(
                continuity: .replacement(.screenChangedNotification),
                generation: .initial,
                previousEvents: [:]
            ),
            evidence: SemanticObservationPublication.Evidence(
                interface: interface,
                accessibilityNotifications: [],
                firstResponder: nil
            )
        )
        var state = SemanticObservationRuntimeState()
        state.requireReplacement()
        state.commit(publication, notificationBatch: notificationBatch)

        XCTAssertEqual(publication.sourceEvent.sequence, 1)
        XCTAssertEqual(publication.sourceEvent.generation, ScreenGeneration.initial.advanced())
        XCTAssertEqual(publication.sourceEvent.trace.captures.last?.interface, interface)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.lineage, .continuous(publication.generation))
        XCTAssertEqual(state.notificationCursor, notificationBatch.through)
        XCTAssertEqual(state.scopedScreenChangedSequence, 1)
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
            self.vault.recordParsedObservedEvidence(freshDiscovery)
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

    func testPostActionAdmissionRejectsCleanProofFromSupersededCapture() async {
        let stale = observation(label: "Same Tree", heistId: "same")
        let current = observation(label: "Same Tree", heistId: "same")
        vault.recordParsedObservedEvidence(stale)
        vault.recordParsedObservedEvidence(current)

        let result = await vault.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(
                .settled(timeMs: 1),
                observation: stale,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .unavailable = result.result else {
            return XCTFail("A clean settle from a superseded capture must not commit")
        }
        XCTAssertEqual(vault.latestObservation.captureToken, current.captureToken)
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureToken, stale.captureToken)
    }

    func testPostActionAdmissionReturnsExactTimedOutObservationAsUnsettledEvidence() async {
        let screen = observation(label: "Unstable", heistId: "unstable")
        vault.recordParsedObservedEvidence(screen)

        let result = await vault.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(
                .timedOut(timeMs: 1),
                observation: screen,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .observedUnsettled(let observation, _) = result.result else {
            return XCTFail("A timeout with a final observation should return diagnostic unsettled evidence")
        }
        XCTAssertEqual(observation.captureToken, screen.captureToken)
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureToken, screen.captureToken)
    }

    func testPostActionAdmissionNeverReturnsCancelledObservationAsUsableEvidence() async {
        let screen = observation(label: "Cancelled", heistId: "cancelled")
        vault.recordParsedObservedEvidence(screen)

        let result = await vault.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: vault.tripwire.tripwireSignal(),
            settleOutcome: settleOutcome(
                .cancelled(timeMs: 1),
                observation: screen,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        )

        guard case .unavailable = result.result else {
            return XCTFail("Cancellation must not expose its last tree as usable action evidence")
        }
        XCTAssertEqual(vault.latestFailedSettleDiagnosticEvidence?.captureToken, screen.captureToken)
    }

    private func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }

    private func scrollObservation(
        headerId: HeistId,
        rowLabel: String,
        rowId: HeistId,
        headerObject: NSObject,
        rowObject: NSObject
    ) -> InterfaceObservation {
        let containerPath = TreePath([0])
        let headerPath = containerPath.appending(0)
        let rowPath = containerPath.appending(1)
        let header = AccessibilityElement.make(label: "Menu", traits: .header)
        let row = AccessibilityElement.make(label: rowLabel, traits: .button)
        let scroll = AccessibilityContainer(
            type: .list,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(x: 0, y: 80, width: 320, height: 560)
        )
        let membership = InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil)
        return InterfaceObservation.makeForTests(
            elements: [
                headerId: InterfaceTree.Element(
                    heistId: headerId,
                    scrollMembership: membership,
                    element: header
                ),
                rowId: InterfaceTree.Element(
                    heistId: rowId,
                    scrollMembership: membership,
                    element: row
                ),
            ],
            hierarchy: [
                .container(scroll, children: [
                    .element(header, traversalIndex: 0),
                    .element(row, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                headerPath: headerId,
                rowPath: rowId,
            ],
            elementRefs: [
                headerId: .init(object: headerObject, scrollView: nil),
                rowId: .init(object: rowObject, scrollView: nil),
            ],
            firstResponderHeistId: nil
        )
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
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal
    ) -> SettleSession.Result {
        SettleSession.Result(
            outcome: outcome,
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: tripwireSignal
        )
    }

    private func tripwireSignal(sequence: UInt64) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: sequence
        )
    }

    private func installSettler(
        signal: @escaping @MainActor () -> TheTripwire.TripwireSignal,
        beforeSettle: @escaping @MainActor () async -> Void = {}
    ) -> @MainActor () -> Int {
        var count = 0
        vault.semanticObservationStream.readTripwireSignal = signal
        vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            count += 1
            await beforeSettle()
            let observation = self.observation(label: "Stable", heistId: "stable")
            vault.recordParsedObservedEvidence(observation)
            return self.settleOutcome(
                .settled(timeMs: count),
                observation: observation,
                tripwireSignal: baseline
            )
        }
        return { count }
    }

    private func visibleEvidence() async throws -> CleanSettledObservation {
        let evidence = await vault.semanticObservationStream.visibleEvidence(timeout: 1)
        return try XCTUnwrap(evidence)
    }

    private func waitForSettleCount(
        _ expectedCount: Int,
        current: () -> Int
    ) async {
        for _ in 0..<1_000 {
            guard current() != expectedCount else { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) settle sessions")
    }

    private func waitForObservationWaiterCount(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard vault.semanticObservationStream.observationWaiterCount != expectedCount else {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation waiters")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
