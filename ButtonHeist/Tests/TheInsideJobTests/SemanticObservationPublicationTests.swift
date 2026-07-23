#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationPublicationTests: SemanticObservationStreamTestCase {
    func testAdmittedSnapshotCommitsBeforeSinglePublish() async throws {
        var publishedEvents: [Observation.Event] = []
        var committedMomentAtPublication: Observation.Moment?
        let subscription = vault.semanticObservationStream.subscribe(scope: .visible) { event in
            publishedEvents.append(event)
            committedMomentAtPublication = self.vault.semanticObservationStream
                .latestDeliveredSnapshotEvent?.moment
        }
        defer { subscription.cancel() }

        let committed = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Committed", heistId: "committed")
        )

        XCTAssertEqual(publishedEvents, [.snapshot(committed)])
        XCTAssertEqual(committedMomentAtPublication, committed.moment)
        let latestCommittedEvent = await vault.semanticObservationStream.latestCommittedEvent()
        XCTAssertEqual(latestCommittedEvent, committed)
        XCTAssertEqual(vault.interfaceTree, committed.snapshot.observation.tree)
    }

    func testObservationStreamRetainsEveryFastTransitionAfterMoment() async {
        let baseline = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(first)
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let publishedFirst = await vault.semanticObservationStream.waitForObservation(
            since: baseline.moment,
            scope: .visible,
            deadline: nil
        )
        let publishedSecond = await vault.semanticObservationStream.waitForObservation(
            since: firstEvent.moment,
            scope: .visible,
            deadline: nil
        )
        guard case .observation(let firstEntry) = publishedFirst,
              case .observation(let secondEntry) = publishedSecond else {
            return XCTFail("Expected retained visible observations")
        }
        XCTAssertEqual(firstEntry.moment, firstEvent.moment)
        XCTAssertEqual(secondEntry.moment, secondEvent.moment)
    }

    func testLifecycleResetClearsCommittedTruth() async {
        _ = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before Reset", heistId: "before_reset")
        )

        await vault.resetInterfaceForLifecycle()

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

        var firstEvidence: Observation.Store.AdmittedObservation?
        var secondEvidence: Observation.Store.AdmittedObservation?
        let firstTask = Task { @MainActor in
            firstEvidence = await stream.admittedVisibleObservation(timeout: 1)
        }
        await waitForSettleCount(1, current: settleCount)
        let secondTask = Task { @MainActor in
            secondEvidence = await stream.admittedVisibleObservation(timeout: 1)
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

    func testPostDispatchRefreshRejectsCycleStartedBeforeBoundary() async {
        let stream = vault.semanticObservationStream
        let signal = tripwireSignal(sequence: 1)
        var releaseSettle: CheckedContinuation<Void, Never>?
        var shouldSuspend = true
        let settleCount = installSettler(signal: { signal }, beforeSettle: {
            guard shouldSuspend else { return }
            shouldSuspend = false
            await withCheckedContinuation { releaseSettle = $0 }
        })
        defer { releaseSettle?.resume() }

        let inFlight = Task { @MainActor in
            await stream.refreshVisibleObservation(timeoutMs: 1_000)
        }
        await waitForSettleCount(1, current: settleCount)
        let boundary = stream.visibleRefreshBoundary()
        let postDispatch = Task { @MainActor in
            await stream.refreshVisibleObservation(
                after: boundary,
                baselineTripwireSignal: signal,
                timeoutMs: 1_000
            )
        }

        releaseSettle?.resume()
        releaseSettle = nil
        let first = await inFlight.value
        let second = await postDispatch.value

        XCTAssertEqual(settleCount(), 2)
        guard case .committed(let firstEvent) = first.commitOutcome,
              case .committed(let secondEvent) = second.commitOutcome else {
            return XCTFail("Expected both refreshes to commit")
        }
        XCTAssertNotEqual(firstEvent.moment, secondEvent.moment)
    }

    func testPostDispatchRefreshSharesCycleStartedAfterBoundary() async {
        let stream = vault.semanticObservationStream
        let signal = tripwireSignal(sequence: 1)
        var releaseSettle: CheckedContinuation<Void, Never>?
        let settleCount = installSettler(signal: { signal }, beforeSettle: {
            await withCheckedContinuation { releaseSettle = $0 }
        })
        defer { releaseSettle?.resume() }

        let boundary = stream.visibleRefreshBoundary()
        let inFlight = Task { @MainActor in
            await stream.refreshVisibleObservation(timeoutMs: 1_000)
        }
        await waitForSettleCount(1, current: settleCount)
        let postDispatch = Task { @MainActor in
            await stream.refreshVisibleObservation(
                after: boundary,
                baselineTripwireSignal: signal,
                timeoutMs: 1_000
            )
        }

        releaseSettle?.resume()
        releaseSettle = nil
        let first = await inFlight.value
        let second = await postDispatch.value

        XCTAssertEqual(settleCount(), 1)
        guard case .committed(let firstEvent) = first.commitOutcome,
              case .committed(let secondEvent) = second.commitOutcome else {
            return XCTFail("Expected the shared refresh to commit")
        }
        XCTAssertEqual(firstEvent.moment, secondEvent.moment)
    }

    func testAdmittedStateIsReusedUntilTripInvalidationOrScreenReplacement() async throws {
        let stream = vault.semanticObservationStream
        let initialSignal = tripwireSignal(sequence: 1)
        let settleCount = installSettler(signal: { initialSignal })

        let initial = try await admittedVisibleObservation()
        let reused = try await admittedVisibleObservation()
        let changedSignal = tripwireSignal(sequence: 2)
        stream.readTripwireSignal = { changedSignal }
        let afterTrip = try await admittedVisibleObservation()
        await stream.invalidateLatestSettledObservation()
        let afterInvalidation = try await admittedVisibleObservation()
        await stream.requireScreenReplacement()
        let afterReplacement = try await admittedVisibleObservation()

        XCTAssertEqual(settleCount(), 4)
        XCTAssertEqual(reused.event.sequence, initial.event.sequence)
        XCTAssertNotEqual(afterTrip.event.sequence, reused.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterTrip.event.sequence)
        XCTAssertNotEqual(afterInvalidation.event.sequence, afterReplacement.event.sequence)
    }

    func testSameCaptureInDifferentScopeGetsItsOwnPublication() async {
        let screen = observation(label: "Shared", heistId: "shared")

        let visible = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let discovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(screen)

        let events = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: visible.moment)
        }
        XCTAssertEqual(
            events,
            .events([.snapshot(discovery)])
        )
    }

    func testFirstCommittedScopeAppendsInitialEntry() async throws {
        let event = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Initial", heistId: "initial")
        )

        let latestCommittedEvent = await vault.semanticObservationStream.latestCommittedEvent()
        XCTAssertEqual(latestCommittedEvent, event)
        guard case .initial = event.transition else {
            return XCTFail("Expected the first visible entry to establish lineage")
        }
    }

    func testSecondCommitAppendsSameGenerationEntry() async throws {
        let screen = observation(label: "Stable", heistId: "stable")
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(screen)

        let events = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: firstEvent.moment)
        }
        XCTAssertEqual(
            events,
            .events([.snapshot(secondEvent)])
        )
        XCTAssertEqual(firstEvent.generation, secondEvent.generation)
        guard case .sameGeneration(let previous) = secondEvent.transition else {
            return XCTFail("Expected a same-generation transition")
        }
        XCTAssertEqual(previous, firstEvent.moment)
    }

    func testVisiblePublicationRetainsKnownGraphInStateAndTraceEvidence() async throws {
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

        let baselineEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let currentEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(current)

        XCTAssertEqual(currentEvent.generation, baselineEvent.generation)
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: offViewportId))
        XCTAssertTrue(
            currentEvent.trace.captures.last?.interface.projectedElements.contains {
                $0.label == "Known Offscreen"
            } == true
        )
        XCTAssertEqual(
            currentEvent.snapshot.observation.tree.orderedElements.compactMap(\.element.label),
            currentEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label)
        )
    }

    func testScreenReplacementRetainsBoundaryAndBothCaptures() async throws {
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after"),
            notificationBatch: screenChangedBatch()
        )

        let events = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: firstEvent.moment)
        }
        XCTAssertEqual(
            events,
            .events([.snapshot(secondEvent)])
        )
        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            AccessibilityTrace(captures: [firstEvent.moment.capture, secondEvent.moment.capture])
                .changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        guard case .screenBoundary(let previous) = secondEvent.transition else {
            return XCTFail("Expected a retained screen boundary")
        }
        XCTAssertEqual(previous, firstEvent.moment)
    }

    func testInferredReplacementResetsGraphAndRetainsClassifierEvidence() async {
        let firstEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "before")
        )
        let secondEvent = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "after")
        )

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.continuity,
            .replacement(.inferred(.primaryHeaderChanged))
        )
        XCTAssertEqual(vault.interfaceTree.elementIDs, ["after"])
    }

    func testConcurrentAdmissionsConsumeNotificationEvidenceOnce() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryGate(blocking: [1])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(order: token.order)
        }
        let notificationScope = vault.accessibilityNotifications.beginActionWindow()
        vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        let notificationBatch = notificationScope.capture()
        let notificationSequence = vault.accessibilityNotifications.latestSequence
        guard let notificationBatch else {
            return XCTFail("Expected the action window to capture its notification")
        }

        let firstTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(
                self.observation(label: "First", heistId: "first"),
                notificationBatch: notificationBatch
            )
        }
        await gate.waitUntilEntered(order: 1)
        let secondTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(
                self.observation(label: "Second", heistId: "second"),
                notificationBatch: notificationBatch
            )
        }
        await gate.waitUntilEntered(order: 2)
        await gate.release(order: 1)
        let firstEvent = await firstTask.value
        let secondEvent = await secondTask.value
        notificationScope.consume()

        XCTAssertEqual(
            firstEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.sequence),
            [notificationSequence]
        )
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications,
            []
        )
    }

    func testConsumedActionEvidenceIsNotReleasedToPassiveLane() async {
        let stream = vault.semanticObservationStream
        let screen = observation(label: "Stable", heistId: "stable")
        _ = await stream.commitVisibleObservationForTesting(screen)
        let actionWindow = vault.accessibilityNotifications.beginActionWindow()
        vault.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        guard let actionBatch = actionWindow.capture() else {
            return XCTFail("Expected the action window to capture screen-change evidence")
        }

        let actionEvent = await stream.commitVisibleObservationForTesting(
            screen,
            notificationBatch: actionBatch
        )
        actionWindow.consume()
        let passiveEvent = await stream.commitVisibleObservationForTesting(screen)

        XCTAssertEqual(
            actionEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            passiveEvent.trace.captures.last?.transition.accessibilityNotifications,
            []
        )
        XCTAssertEqual(passiveEvent.generation, actionEvent.generation)
    }

    func testCommitDeliveryPublishesContiguousStoreOrder() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryGate(blocking: [1])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(order: token.order)
        }
        var publishedSequences: [SettledObservationSequence] = []
        let subscription = stream.subscribe(scope: .visible) { event in
            guard case .snapshot(let snapshot) = event else { return }
            publishedSequences.append(snapshot.sequence)
        }
        defer { subscription.cancel() }

        let firstTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(
                self.observation(label: "First", heistId: "first")
            )
        }
        await gate.waitUntilEntered(order: 1)
        let secondTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(
                self.observation(label: "Second", heistId: "second")
            )
        }
        await gate.waitUntilEntered(order: 2)

        XCTAssertEqual(publishedSequences, [])
        await gate.release(order: 1)
        let firstEvent = await firstTask.value
        let secondEvent = await secondTask.value
        XCTAssertEqual(publishedSequences, [firstEvent.sequence, secondEvent.sequence])
    }

    func testLifecycleResetDropsSuspendedDeliveryFromPriorGeneration() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryGate(blocking: [1])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(order: token.order)
        }
        var publishedEvents: [Observation.Event] = []
        let subscription = stream.subscribe(scope: .visible) { publishedEvents.append($0) }
        defer { subscription.cancel() }

        let commitTask = Task { @MainActor in
            await stream.commitVisibleObservationOutcomeForTesting(
                self.observation(label: "Stale", heistId: "stale")
            )
        }
        await gate.waitUntilEntered(order: 1)
        await vault.resetInterfaceForLifecycle()
        await gate.release(order: 1)
        let outcome = await commitTask.value

        guard case .superseded = outcome else {
            return XCTFail("Expected lifecycle reset to supersede the suspended delivery")
        }
        XCTAssertEqual(publishedEvents, [])
        XCTAssertNil(stream.latestDeliveredSnapshotEvent)
        XCTAssertEqual(vault.interfaceTree, .empty)
    }

    func testResetAfterActorResolutionSupersedesStaleMainActorEnqueue() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryGate(blocking: [1])
        stream.beforeResolvedDeliveryEnqueue = { token in
            await gate.suspend(order: token.order)
        }
        var publishedEvents: [Observation.Event] = []
        let subscription = stream.subscribe(scope: .visible) { publishedEvents.append($0) }
        defer { subscription.cancel() }
        let staleObject = NSObject()
        let currentObject = NSObject()
        let staleObservation = InterfaceObservation.makeForTests([
            .init(label: "Target", heistId: "target", traits: .button, object: staleObject),
        ])
        let currentObservation = InterfaceObservation.makeForTests([
            .init(label: "Target", heistId: "target", traits: .button, object: currentObject),
        ])

        let commitTask = Task { @MainActor in
            await stream.commitVisibleObservationOutcomeForTesting(staleObservation)
        }
        await gate.waitUntilEntered(order: 1)
        await vault.resetInterfaceForLifecycle()
        vault.observeInterface(currentObservation)
        await gate.release(order: 1)
        let outcome = await commitTask.value

        guard case .superseded = outcome else {
            return XCTFail("Expected reset to supersede delivery resolved in the prior generation")
        }
        XCTAssertEqual(publishedEvents, [])
        XCTAssertNil(stream.latestDeliveredSnapshotEvent)
        XCTAssertEqual(stream.publicationWaiterCount, 0)
        XCTAssertEqual(vault.interfaceTree, .empty)
        XCTAssertEqual(vault.latestObservation.captureID, currentObservation.captureID)
        XCTAssertTrue(vault.latestObservation.liveCapture.object(for: "target") === currentObject)
        XCTAssertFalse(vault.latestObservation.liveCapture.object(for: "target") === staleObject)
    }

    func testOlderDeliveryDoesNotOverwriteNewerLiveCapture() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryGate(blocking: [1])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(order: token.order)
        }
        let oldObject = NSObject()
        let newObject = NSObject()
        let oldObservation = InterfaceObservation.makeForTests([
            .init(label: "Target", heistId: "target", traits: .button, object: oldObject),
        ])
        let newObservation = InterfaceObservation.makeForTests([
            .init(label: "Target", heistId: "target", traits: .button, object: newObject),
        ])
        vault.observeInterface(oldObservation)

        let oldTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(oldObservation)
        }
        await gate.waitUntilEntered(order: 1)
        vault.observeInterface(newObservation)
        let newTask = Task { @MainActor in
            await stream.commitVisibleObservationForTesting(newObservation)
        }
        await gate.waitUntilEntered(order: 2)
        await gate.release(order: 1)
        _ = await oldTask.value
        _ = await newTask.value

        XCTAssertEqual(vault.latestObservation.captureID, newObservation.captureID)
        XCTAssertTrue(vault.latestObservation.liveCapture.object(for: "target") === newObject)
        XCTAssertFalse(vault.latestObservation.liveCapture.object(for: "target") === oldObject)
    }

    func testInvalidatedDeliveryReadmitsCurrentSourceOnce() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryAttemptGate(blocking: [1])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(token: token)
        }
        let notificationScope = vault.accessibilityNotifications.beginActionWindow()
        vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        guard let notificationBatch = notificationScope.capture() else {
            return XCTFail("Expected the action window to capture its notification")
        }
        let notificationSequence = vault.accessibilityNotifications.latestSequence
        let source = observation(label: "Current", heistId: "current")

        let commitTask = Task { @MainActor in
            await stream.commitVisibleObservationOutcomeForTesting(
                source,
                notificationBatch: notificationBatch
            )
        }
        await gate.waitUntilEntered(attempt: 1)
        await stream.invalidateLatestSettledObservation()
        await gate.release(attempt: 1)
        let outcome = await commitTask.value
        notificationScope.consume()

        guard case .delivered(let event) = outcome else {
            return XCTFail("Expected current source to be re-admitted after invalidation")
        }
        XCTAssertEqual(stream.latestDeliveredSnapshotEvent, event)
        XCTAssertEqual(vault.interfaceTree.elementIDs, ["current"])
        XCTAssertEqual(
            event.trace.captures.flatMap {
                $0.transition.accessibilityNotifications.map(\.sequence)
            },
            [notificationSequence]
        )
        let attemptCount = await gate.attemptCount()
        XCTAssertEqual(attemptCount, 2)
    }

    func testRepeatedInvalidationSupersedesBoundedReadmission() async {
        let stream = vault.semanticObservationStream
        let gate = CommitDeliveryAttemptGate(blocking: [1, 2])
        stream.beforeCommittedDelivery = { token in
            await gate.suspend(token: token)
        }

        let commitTask = Task { @MainActor in
            await stream.commitVisibleObservationOutcomeForTesting(
                self.observation(label: "Stale", heistId: "stale")
            )
        }
        await gate.waitUntilEntered(attempt: 1)
        await stream.invalidateLatestSettledObservation()
        await gate.release(attempt: 1)
        await gate.waitUntilEntered(attempt: 2)
        await stream.invalidateLatestSettledObservation()
        await gate.release(attempt: 2)
        let outcome = await commitTask.value

        guard case .superseded = outcome else {
            return XCTFail("Expected a second invalidation to supersede the bounded re-admission")
        }
        let attemptCount = await gate.attemptCount()
        XCTAssertEqual(attemptCount, 2)
        XCTAssertNil(stream.latestDeliveredSnapshotEvent)
        XCTAssertEqual(vault.interfaceTree, .empty)
    }

    func testStartInvalidationIsVisibleWhenStartReturns() async {
        let stream = vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Before Start", heistId: "before_start")
        )
        stream.settleVisibleObservation = { _, _, _, signal, _ in
            SettleSession.Result(
                outcome: .cancelled(timeMs: 0),
                events: [],
                finalObservation: nil,
                elementsByKey: [:],
                tripwireSignal: signal
            )
        }

        await stream.start { nil }
        defer { stream.stop() }

        let invalidated = await stream.latestSettledObservationInvalidated()
        let admitted = await stream.storeOwner.admittedObservation(scope: .visible, after: nil)
        XCTAssertTrue(invalidated)
        XCTAssertNil(admitted)
        XCTAssertEqual(vault.interfaceTree.elementIDs, ["before_start"])
    }
}

private actor CommitDeliveryGate {
    private var blockedOrders: Set<UInt64>
    private var enteredOrders: Set<UInt64> = []
    private var entryWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]

    init(blocking orders: Set<UInt64>) {
        blockedOrders = orders
    }

    func suspend(order: UInt64) async {
        enteredOrders.insert(order)
        entryWaiters.removeValue(forKey: order)?.forEach { $0.resume() }
        guard blockedOrders.contains(order) else { return }
        await withCheckedContinuation { continuation in
            if blockedOrders.contains(order) {
                releaseWaiters[order, default: []].append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    func waitUntilEntered(order: UInt64) async {
        guard !enteredOrders.contains(order) else { return }
        await withCheckedContinuation { continuation in
            entryWaiters[order, default: []].append(continuation)
        }
    }

    func release(order: UInt64) {
        guard blockedOrders.remove(order) != nil else { return }
        releaseWaiters.removeValue(forKey: order)?.forEach { $0.resume() }
    }
}

private actor CommitDeliveryAttemptGate {
    private var blockedAttempts: Set<Int>
    private var enteredAttempts = 0
    private var entryWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(blocking attempts: Set<Int>) {
        blockedAttempts = attempts
    }

    func suspend(token _: Observation.StoreOwner.DeliveryToken) async {
        enteredAttempts += 1
        let attempt = enteredAttempts
        entryWaiters.removeValue(forKey: attempt)?.forEach { $0.resume() }
        guard blockedAttempts.contains(attempt) else { return }
        await withCheckedContinuation { continuation in
            if blockedAttempts.contains(attempt) {
                releaseWaiters[attempt, default: []].append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    func waitUntilEntered(attempt: Int) async {
        guard enteredAttempts < attempt else { return }
        await withCheckedContinuation { continuation in
            entryWaiters[attempt, default: []].append(continuation)
        }
    }

    func release(attempt: Int) {
        guard blockedAttempts.remove(attempt) != nil else { return }
        releaseWaiters.removeValue(forKey: attempt)?.forEach { $0.resume() }
    }

    func attemptCount() -> Int {
        enteredAttempts
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
