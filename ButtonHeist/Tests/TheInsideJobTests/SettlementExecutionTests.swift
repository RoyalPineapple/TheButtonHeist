#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport
@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SettlementExecutionTests: SemanticObservationStreamTestCase {
    func testInitiallyIdleActionReadinessWaitsForDispatchStartedWork() async {
        let lifecycle = LiveSettlementLifecycle()
        let probe = DispatchReadinessProbe()
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: vault.accessibilityNotifications.beginActionWindow()
        )

        lifecycle.armReadiness(startAfterDispatch: true) {
            probe.observeReadiness()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertFalse(probe.didObserveReadiness)

        probe.startDispatchWork()
        lifecycle.dispatchDidComplete(
            visibleRefreshBoundary: vault.semanticObservationStream.visibleRefreshBoundary()
        )
        await probe.waitUntilReadinessObserved()

        XCTAssertTrue(probe.dispatchWorkStartedAtReadiness)
        await lifecycle.quiesce()
        let didFinalize = await lifecycle.finalize()
        let didFinalizeAgain = await lifecycle.finalize()
        XCTAssertTrue(didFinalize)
        XCTAssertFalse(didFinalizeAgain)
    }

    func testDeferredActionDeadlineStartsAtDispatchCompletionForEveryWaiter() async {
        let lifecycle = LiveSettlementLifecycle()
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: vault.accessibilityNotifications.beginActionWindow()
        )
        let timeout = Duration.milliseconds(250)
        let deadline = Settlement.Deadline(afterActionDispatch: timeout)
        let first = Task { await lifecycle.resolveDeadline(deadline) }
        let second = Task { await lifecycle.resolveDeadline(deadline) }
        let dispatchCompletedAt = ContinuousClock.now

        lifecycle.dispatchDidComplete(
            visibleRefreshBoundary: vault.semanticObservationStream.visibleRefreshBoundary(),
            at: dispatchCompletedAt
        )

        let expected = dispatchCompletedAt.advanced(by: timeout)
        let firstDeadline = await first.value
        let secondDeadline = await second.value
        XCTAssertEqual(firstDeadline, expected)
        XCTAssertEqual(secondDeadline, expected)
        await lifecycle.quiesce()
        let didFinalize = await lifecycle.finalize()
        XCTAssertTrue(didFinalize)
    }

    func testCommittedHandoffDefersNotificationConsumptionUntilChildLeaseCloses() async throws {
        let lifecycle = LiveSettlementLifecycle()
        let notifications = AccessibilityNotificationBus()
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: notifications.beginActionWindow()
        )
        let child = notifications.beginActionWindow()
        notifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )

        lifecycle.requestNotificationWindowConsumption()
        await lifecycle.quiesce()

        XCTAssertEqual(try XCTUnwrap(child.capture()).events.count, 1)
        child.cancel()
        let didFinalize = await lifecycle.finalize()
        let didFinalizeAgain = await lifecycle.finalize()

        XCTAssertTrue(didFinalize)
        XCTAssertFalse(didFinalizeAgain)
        XCTAssertTrue(
            notifications.checkpoint(
                after: .origin,
                selection: .unclaimedScoped
            ).events.isEmpty
        )
    }

    func testArmsObservationAnnouncementReadinessAndDeadlineBeforeDispatch() async throws {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let announcement = Observation.AnnouncementEvent(announcement: CapturedAnnouncement(
            sequence: 1,
            text: "Saved",
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .announcement
        ))
        let authored = AccessibilityPredicate.announcement("Saved")
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            announcement: announcement,
            history: .events([.snapshot(changed)])
        )
        let executor = Settlement.Executor(boundary: boundary)

        let result = await executor.execute(Settlement.Command(
            trigger: .action(.dismiss),
            predicate: predicate,
            deadline: Settlement.Deadline(
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            )
        ))

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(result.evidence.boundary.moment, baseline.moment)
        XCTAssertEqual(result.evidence.handoff.event?.moment, changed.moment)
        XCTAssertEqual(
            result.evidence.predicate.satisfiedTarget,
            .announcement(sequence: announcement.announcement.sequence)
        )
        XCTAssertEqual(boundary.operations, [
            .captureBaseline,
            .admitBaseline,
            .beginSettlement,
            .armObservation,
            .armAnnouncement,
            .armReadiness,
            .armDeadline,
            .armObservationEffects,
            .dispatch,
            .evaluateAnnouncement,
            .quiesce,
            .finalize,
        ])
    }

    func testObservationCommandNeverDispatches() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true
        )
        let executor = Settlement.Executor(boundary: boundary)

        let result = await executor.execute(Settlement.Command(
            trigger: .observation,
            predicate: nil,
            deadline: Settlement.Deadline(
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            )
        ))

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertFalse(boundary.operations.contains(.dispatch))
        XCTAssertEqual(result.evidence.handoff.event?.moment, changed.moment)
    }

    func testObservationCommandLatchesAnnouncementWithoutDispatch() async throws {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let announcement = Observation.AnnouncementEvent(announcement: CapturedAnnouncement(
            sequence: 1,
            text: "Saved",
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .announcement
        ))
        let authored = AccessibilityPredicate.announcement("Saved")
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            announcement: announcement,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(Settlement.Command(
            trigger: .observation,
            predicate: predicate,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1)))
        ))

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertFalse(boundary.operations.contains(.dispatch))
        XCTAssertEqual(
            result.evidence.predicate.satisfiedTarget,
            .announcement(sequence: announcement.announcement.sequence)
        )
    }

    func testObservationProducerGracefullyStopsAfterSettlementMatch() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true,
            longRunningObservationEffects: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(boundary.operations.filter { $0 == .quiesce }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .finalize }.count, 1)
        XCTAssertEqual(
            boundary.operations.filter { $0 == .observationEffectsStopRequested }.count,
            1
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsRestored }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsJoined }.count, 1)
        XCTAssertEqual(boundary.viewportMutationCount, 0)
    }

    func testObservationProducerGracefullyStopsAfterSettlementTimeout() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([]),
            deadlineOnArm: true,
            longRunningObservationEffects: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(boundary.operations.filter { $0 == .quiesce }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .finalize }.count, 1)
        XCTAssertEqual(
            boundary.operations.filter { $0 == .observationEffectsStopRequested }.count,
            1
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsRestored }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsJoined }.count, 1)
        XCTAssertEqual(boundary.viewportMutationCount, 0)
    }

    func testActiveSettlementBoundaryPreventsHistoryPruningUntilTerminalCleanup() async {
        await vault.semanticObservationStream.storeOwner.reset(retentionLimit: 2)
        let baseline = await commit(label: "Baseline")
        await vault.semanticObservationStream.storeOwner.settlementDidArm(
            at: baseline.moment
        )

        for index in 1...4 {
            _ = await commit(label: "Changed \(index)")
        }

        let retainedHistory = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline.moment)
        }
        guard case .events(let retained) = retainedHistory else {
            return XCTFail("Expected the active settlement boundary to retain its history")
        }
        XCTAssertEqual(retained.count, 4)

        await vault.semanticObservationStream.storeOwner.settlementDidFinish(
            at: baseline.moment
        )
        let prunedHistory = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline.moment)
        }
        guard case .expired = prunedHistory else {
            return XCTFail("Expected terminal cleanup to restore bounded retention")
        }
    }

    func testDeadlineReachedWhileArmingSkipsDispatchAndCleansUp() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([]),
            deadlineOnArm: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(
            Settlement.Command(
                trigger: .action(.dismiss),
                predicate: nil,
                deadline: Settlement.Deadline(instant: ContinuousClock.now)
            )
        )

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertFalse(boundary.operations.contains(.dispatch))
        XCTAssertEqual(Array(boundary.operations.suffix(2)), [.quiesce, .finalize])
    }

    func testEvidenceQueuedBeforeDeadlineSettlesInFIFOOrder() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true,
            deadlineOnArm: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(
            observationCommand()
        )

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(result.evidence.handoff.event?.moment, changed.moment)
    }

    func testCancellationTerminatesAndTearsDownLeases() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([]),
            longRunningObservationEffects: true
        )
        let execution = Task {
            await Settlement.Executor(boundary: boundary).execute(observationCommand())
        }
        await boundary.waitUntilArmed()

        execution.cancel()
        let result = await execution.value

        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(
            boundary.operations.filter {
                [.quiesce, .observationEffectsStopRequested, .observationEffectsRestored,
                 .observationEffectsJoined, .finalize].contains($0)
            },
            [.quiesce, .observationEffectsStopRequested, .observationEffectsRestored,
             .observationEffectsJoined, .finalize]
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsStopRequested }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsRestored }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsJoined }.count, 1)
        XCTAssertEqual(boundary.viewportMutationCount, 0)
    }

    func testDeadlineDuringSlowDispatchCancelsOwnedWorkBeforeReturning() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([]),
            slowDispatchDeadline: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(actionCommand())

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertTrue(boundary.operations.contains(.dispatchCancelled))
        XCTAssertTrue(boundary.operations.contains(.finalize))
    }

    func testTerminalTeardownClosesNestedDispatchBeforeFinalizingOwner() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([]),
            slowDispatchDeadline: true,
            publishesAfterDisarm: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(actionCommand())

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(
            boundary.operations.filter {
                [.childLeaseOpened, .quiesce, .dispatchCancelled,
                 .childLeaseClosed, .finalize].contains($0)
            },
            [.childLeaseOpened, .quiesce, .dispatchCancelled, .childLeaseClosed, .finalize]
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .finalize }.count, 1)
        XCTAssertEqual(boundary.activeChildLeaseCount, 0)
        XCTAssertFalse(boundary.operations.contains(.evaluateObservation))
        XCTAssertTrue(boundary.captureGenerations.isEmpty)
    }

    func testStaleCaptureGenerationIsRejectedBeforeAdmission() async {
        let baseline = await commit(label: "Baseline")
        let stale = await commit(label: "Stale")
        let current = await commit(label: "Current")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: stale,
            history: .events([.snapshot(stale), .snapshot(current)]),
            captureScenario: .invalidateOnce(current: current)
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(result.evidence.handoff.event?.moment, current.moment)
        XCTAssertEqual(boundary.admittedHandoffGenerations, [.init(rawValue: 1)])
    }

    func testRecaptureKeepsOnlyLatestGenerationWhileCaptureIsInFlight() async {
        let baseline = await commit(label: "Baseline")
        let stale = await commit(label: "Stale")
        let current = await commit(label: "Current")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: stale,
            history: .events([.snapshot(stale), .snapshot(current)]),
            captureScenario: .invalidateTwice(current: current)
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(boundary.captureGenerations, [.init(rawValue: 0), .init(rawValue: 2)])
        XCTAssertEqual(boundary.admittedHandoffGenerations, [.init(rawValue: 2)])
    }

    func testPostTerminalCallbacksCannotScheduleCaptureOrEvaluation() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            deadlineOnArm: true,
            publishesAfterDisarm: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(actionCommand())

        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertFalse(boundary.operations.contains(.evaluateObservation))
        XCTAssertTrue(boundary.captureGenerations.isEmpty)
    }

    func testFailedActionNotificationsAreNotClaimedByTheNextSuccessfulAction() async {
        let tripwire = TheTripwire()
        var visibleObservation = observation(label: "Before", heistId: "before")
        let actionVault = TheVault(
            tripwire: tripwire,
            visibleObservationSource: { _ in visibleObservation }
        )
        defer { actionVault.semanticObservationStream.stop() }
        actionVault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            vault.observeInterface(visibleObservation)
            return SettleSession.Result(
                outcome: .settled(timeMs: 1),
                finalObservation: SettleSessionFinalObservation(
                    observation: visibleObservation
                ),
                tripwireSignal: baseline,
                evidence: .semanticStability
            )
        }

        func executeAction(
            announcing announcement: String,
            result: TheSafecracker.ActionDispatchResult
        ) async -> Settlement.Result {
            let command = actionCommand()
            let boundary = LiveSettlementExecutionBoundary(
                command: command,
                vault: actionVault,
                tripwire: tripwire,
                dispatch: { _ in
                    actionVault.accessibilityNotifications.recordForTesting(
                        code: 1008,
                        notificationData: CapturedAccessibilityNotificationPayload(
                            announcement as NSString
                        ),
                        associatedElement: .none
                    )
                    return result
                },
                observationEffects: { _ in }
            )
            return await Settlement.Executor(boundary: boundary).execute(command)
        }

        let failed = await executeAction(
            announcing: "Action A",
            result: .failure(.dismiss, message: "Action A failed")
        )

        XCTAssertEqual(failed.outcome, .dispatchFailed)
        XCTAssertEqual(
            actionVault.accessibilityNotifications
                .checkpoint(after: .origin, selection: .all)
                .events
                .compactMap(\.capturedAnnouncement?.text),
            ["Action A"]
        )

        visibleObservation = observation(label: "After", heistId: "after")
        let successful = await executeAction(
            announcing: "Action B",
            result: .success(payload: .dismiss)
        )

        XCTAssertEqual(successful.outcome, .settled)
        XCTAssertEqual(
            successful.evidence.handoff.event?
                .trace.capturedAnnouncements.map(\.text),
            ["Action B"]
        )
        XCTAssertEqual(
            actionVault.accessibilityNotifications
                .checkpoint(after: .origin, selection: .all)
                .events
                .compactMap(\.capturedAnnouncement?.text),
            ["Action A", "Action B"]
        )
    }

    func testSuppliedBaselineReplaysObservationCommittedBeforeArmingToSatisfyPredicate() async throws {
        let baseline = await commit(label: "Baseline")
        let replayed = await commit(label: "Ready")
        let authored = AccessibilityPredicate.exists(.label("Ready"))
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let command = Settlement.Command(
            trigger: .observation,
            predicate: predicate,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1))),
            baseline: .supplied(.init(moment: baseline.moment))
        )
        let liveBoundary = LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: vault.tripwire,
            dispatch: { _ in
                preconditionFailure("Observation settlement cannot dispatch")
            },
            observationEffects: { _ in }
        )
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: replayed,
            history: .events([]),
            liveObservationBoundary: liveBoundary
        )

        let result = await Settlement.Executor(boundary: boundary).execute(command)

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertFalse(boundary.operations.contains(.captureBaseline))
        XCTAssertEqual(
            result.evidence.predicate.satisfiedTarget,
            .observation(replayed.moment)
        )
        XCTAssertEqual(result.evidence.handoff.event?.moment, replayed.moment)
    }

    private func observationCommand() -> Settlement.Command {
        Settlement.Command(
            trigger: .observation,
            predicate: nil,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1)))
        )
    }

    private func actionCommand() -> Settlement.Command {
        Settlement.Command(
            trigger: .action(.dismiss),
            predicate: nil,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1)))
        )
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }
}

@MainActor
final class SettlementExecutionPerformanceTests: SemanticObservationStreamTestCase {
    func testCoalescesWakeupsAndBoundsCaptureWorkToTheActiveLease() async throws {
        let baseline = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Baseline", heistId: "baseline")
        )
        let stale = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Stale", heistId: "stale")
        )
        let current = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Current", heistId: "current")
        )
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: stale,
            history: .events([.snapshot(stale), .snapshot(current)]),
            captureScenario: .coalescedBurst(current: current, duplicateCount: 64)
        )
        let command = Settlement.Command(
            trigger: .observation,
            predicate: nil,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1)))
        )

        let result = await Settlement.Executor(boundary: boundary).execute(command)

        XCTAssertEqual(result.outcome, .settled)
        XCTAssertEqual(result.evidence.handoff.event?.moment, current.moment)
        XCTAssertEqual(boundary.totalCaptureCount, 3)
        XCTAssertEqual(boundary.captureGenerations, [.initial, .initial.advanced()])
        XCTAssertEqual(boundary.maximumConcurrentCaptures, 1)
        XCTAssertEqual(boundary.readinessWakeupsOffered, 128)
        XCTAssertEqual(boundary.coalescedReadinessWakeupCount, 126)

        let budgets = SettlementPerformanceBudgets(
            baselineMainActorMs: 1_000,
            finalEvidenceMainActorMs: 1_000
        )
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(result.evidence.timing.beforeObservationMs).milliseconds,
            budgets.baselineMainActorMs
        )
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(result.evidence.timing.finalSemanticEvidenceMs).milliseconds,
            budgets.finalEvidenceMainActorMs
        )

        boundary.publishReadinessAfterTerminal(count: 128)
        for _ in 0..<8 {
            await Task.yield()
        }
        XCTAssertEqual(boundary.totalCaptureCount, 3)
        XCTAssertEqual(boundary.outsideLeaseWakeupCount, 128)
        XCTAssertEqual(boundary.maximumConcurrentCaptures, 1)
    }
}

private struct SettlementPerformanceBudgets {
    let baselineMainActorMs: Int
    let finalEvidenceMainActorMs: Int
}

@MainActor
private final class DispatchReadinessProbe {
    private(set) var didObserveReadiness = false
    private(set) var dispatchWorkStartedAtReadiness = false
    private var dispatchWorkStarted = false
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    func startDispatchWork() {
        dispatchWorkStarted = true
    }

    func observeReadiness() {
        dispatchWorkStartedAtReadiness = dispatchWorkStarted
        didObserveReadiness = true
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilReadinessObserved() async {
        guard !didObserveReadiness else { return }
        await withCheckedContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }
}

/// `NSLock` protects the complete mutable `state` value: operations, sink,
/// capture generations, admission generations, and arming continuations.
private final class ScriptedSettlementBoundary: SettlementExecutionBoundary, @unchecked Sendable {
    enum CaptureScenario: Sendable {
        case none
        case invalidateOnce(current: Observation.SnapshotEvent)
        case invalidateTwice(current: Observation.SnapshotEvent)
        case coalescedBurst(current: Observation.SnapshotEvent, duplicateCount: Int)
    }

    enum Capture: Sendable {
        case baseline
        case handoff(Settlement.Readiness.Generation)
    }

    enum Operation: Equatable {
        case captureBaseline
        case admitBaseline
        case beginSettlement
        case armObservation
        case armAnnouncement
        case armReadiness
        case armDeadline
        case armObservationEffects
        case dispatch
        case dispatchCancelled
        case evaluateAnnouncement
        case evaluateObservation
        case observationEffectsStarted
        case observationEffectsStopRequested
        case observationEffectsRestored
        case observationEffectsJoined
        case childLeaseOpened
        case childLeaseClosed
        case quiesce
        case finalize
    }

    private struct State {
        var operations: [Operation] = []
        var sink: Settlement.ExecutionSink?
        var captureGenerations: [Settlement.Readiness.Generation] = []
        var admittedHandoffGenerations: [Settlement.Readiness.Generation] = []
        var armingWaiters: [CheckedContinuation<Void, Never>] = []
        var observationEffectsTask: Task<Void, Never>?
        var observationEffectControl: Settlement.ObservationEffectControl?
        var finishedSink: Settlement.ExecutionSink?
        var totalCaptureCount = 0
        var capturesInFlight = 0
        var maximumConcurrentCaptures = 0
        var readinessWakeupsOffered = 0
        var readinessWakeupGroups = 0
        var outsideLeaseWakeupCount = 0
        var activeChildLeaseCount = 0
        var viewportMutationCount = 0
    }

    private let lock = NSLock()
    private var state = State()
    private let baseline: Observation.SnapshotEvent
    private let changed: Observation.SnapshotEvent
    private let announcement: Observation.AnnouncementEvent?
    private let history: Observation.EventsSince
    private let observationOnlyEvidence: Bool
    private let deadlineOnArm: Bool
    private let slowDispatchDeadline: Bool
    private let publishesAfterDisarm: Bool
    private let longRunningObservationEffects: Bool
    private let captureScenario: CaptureScenario
    private let liveObservationBoundary: LiveSettlementExecutionBoundary?

    init(
        baseline: Observation.SnapshotEvent,
        changed: Observation.SnapshotEvent,
        announcement: Observation.AnnouncementEvent? = nil,
        history: Observation.EventsSince,
        observationOnlyEvidence: Bool = false,
        deadlineOnArm: Bool = false,
        slowDispatchDeadline: Bool = false,
        publishesAfterDisarm: Bool = false,
        longRunningObservationEffects: Bool = false,
        captureScenario: CaptureScenario = .none,
        liveObservationBoundary: LiveSettlementExecutionBoundary? = nil
    ) {
        self.baseline = baseline
        self.changed = changed
        self.announcement = announcement
        self.history = history
        self.observationOnlyEvidence = observationOnlyEvidence
        self.deadlineOnArm = deadlineOnArm
        self.slowDispatchDeadline = slowDispatchDeadline
        self.publishesAfterDisarm = publishesAfterDisarm
        self.longRunningObservationEffects = longRunningObservationEffects
        self.captureScenario = captureScenario
        self.liveObservationBoundary = liveObservationBoundary
    }

    var operations: [Operation] {
        lock.withLock { state.operations }
    }

    var captureGenerations: [Settlement.Readiness.Generation] {
        lock.withLock { state.captureGenerations }
    }

    var admittedHandoffGenerations: [Settlement.Readiness.Generation] {
        lock.withLock { state.admittedHandoffGenerations }
    }

    var totalCaptureCount: Int {
        lock.withLock { state.totalCaptureCount }
    }

    var maximumConcurrentCaptures: Int {
        lock.withLock { state.maximumConcurrentCaptures }
    }

    var readinessWakeupsOffered: Int {
        lock.withLock { state.readinessWakeupsOffered }
    }

    var coalescedReadinessWakeupCount: Int {
        lock.withLock { state.readinessWakeupsOffered - state.readinessWakeupGroups }
    }

    var outsideLeaseWakeupCount: Int {
        lock.withLock { state.outsideLeaseWakeupCount }
    }

    var activeChildLeaseCount: Int {
        lock.withLock { state.activeChildLeaseCount }
    }

    var viewportMutationCount: Int {
        lock.withLock { state.viewportMutationCount }
    }

    func waitUntilArmed() async {
        await withCheckedContinuation { continuation in
            let isArmed = lock.withLock {
                if state.operations.contains(.armDeadline) {
                    return true
                }
                state.armingWaiters.append(continuation)
                return false
            }
            if isArmed {
                continuation.resume()
            }
        }
    }

    @MainActor
    func capture(_ request: Settlement.Capture.Request) async -> Capture? {
        lock.withLock {
            state.totalCaptureCount += 1
            state.capturesInFlight += 1
            state.maximumConcurrentCaptures = max(
                state.maximumConcurrentCaptures,
                state.capturesInFlight
            )
        }
        defer {
            lock.withLock { state.capturesInFlight -= 1 }
        }
        switch request {
        case .baseline:
            record(.captureBaseline)
            return .baseline
        case .handoff(let request):
            lock.withLock { state.captureGenerations.append(request.readinessGeneration) }
            await publishCaptureInvalidationsIfNeeded(request)
            return .handoff(request.readinessGeneration)
        }
    }

    func admit(
        _ capture: Capture,
        for _: Settlement.Capture.Request
    ) async -> Settlement.CaptureAdmissionOutcome {
        switch capture {
        case .baseline:
            record(.admitBaseline)
            return .admitted(baseline)
        case .handoff:
            if case .handoff(let generation) = capture {
                lock.withLock { state.admittedHandoffGenerations.append(generation) }
                switch captureScenario {
                case .none:
                    break
                case .invalidateOnce(let current),
                     .invalidateTwice(let current),
                     .coalescedBurst(let current, _):
                    if generation.rawValue > 0 {
                        return .admitted(current)
                    }
                }
            }
            return .admitted(changed)
        }
    }

    func events(since moment: Observation.Moment) async -> Observation.EventsSince {
        if let liveObservationBoundary {
            return await liveObservationBoundary.events(since: moment)
        }
        return history
    }

    func beginSettlement(_ arming: Settlement.Arming) async {
        if let liveObservationBoundary {
            await liveObservationBoundary.beginSettlement(arming)
        }
        record(.beginSettlement)
    }

    func armObservations(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        lock.withLock {
            state.sink = sink
            state.operations.append(.armObservation)
        }
        if let liveObservationBoundary {
            await liveObservationBoundary.armObservations(arming, sink: sink)
        }
    }

    func armAnnouncements(
        _: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        record(.armAnnouncement)
        if observationOnlyEvidence, let announcement {
            sink.observeAnnouncement(announcement)
        }
    }

    func armReadiness(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        record(.armReadiness)
        if liveObservationBoundary != nil {
            sink.observeReadiness(.established(
                path: .uikitIdle,
                observationBoundary: .including(changed.moment)
            ))
            XCTAssertEqual(arming.boundary.moment, baseline.moment)
            return
        }
        if observationOnlyEvidence {
            sink.observe(.snapshot(changed))
        } else if case .none = captureScenario {
            return
        }
        sink.observeReadiness(.established(
            path: .uikitIdle,
            observationBoundary: observationOnlyEvidence
                ? .including(changed.moment)
                : .after(baseline.moment)
        ))
        XCTAssertEqual(arming.boundary.moment, baseline.moment)
    }

    func armDeadline(
        _: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        let waiters = lock.withLock {
            state.operations.append(.armDeadline)
            defer { state.armingWaiters.removeAll() }
            return state.armingWaiters
        }
        waiters.forEach { $0.resume() }
        if deadlineOnArm {
            sink.reachDeadline()
        } else if slowDispatchDeadline {
            Task {
                while !self.operations.contains(.dispatch) {
                    await Task.yield()
                }
                sink.reachDeadline()
            }
        }
    }

    func armObservationEffects(_: Settlement.Arming) async {
        record(.armObservationEffects)
        guard longRunningObservationEffects else { return }
        let control = Settlement.ObservationEffectControl()
        let task = Task {
            self.lock.withLock {
                self.state.operations.append(.observationEffectsStarted)
                self.state.viewportMutationCount += 1
            }
            while !control.stopRequested {
                await Task.yield()
            }
            self.lock.withLock {
                self.state.viewportMutationCount -= 1
                self.state.operations.append(.observationEffectsRestored)
            }
            control.complete()
        }
        lock.withLock {
            state.observationEffectControl = control
            state.observationEffectsTask = task
        }
    }

    func quiesceSettlement(_ arming: Settlement.Arming) async {
        record(.quiesce)
        let (sink, control, observationEffectsTask) = lock.withLock {
            defer {
                state.finishedSink = state.sink
                state.sink = nil
            }
            defer {
                state.observationEffectControl = nil
                state.observationEffectsTask = nil
            }
            return (
                state.sink,
                state.observationEffectControl,
                state.observationEffectsTask
            )
        }
        if let control {
            record(.observationEffectsStopRequested)
            control.requestStop()
        }
        await observationEffectsTask?.value
        if observationEffectsTask != nil {
            record(.observationEffectsJoined)
        }
        if publishesAfterDisarm {
            sink?.observe(.snapshot(changed))
            sink?.observeReadiness(.established(
                path: .uikitIdle,
                observationBoundary: .including(changed.moment)
            ))
        }
        if let liveObservationBoundary {
            await liveObservationBoundary.quiesceSettlement(arming)
        }
    }

    func finalizeSettlement(_ arming: Settlement.Arming) async {
        if let liveObservationBoundary {
            await liveObservationBoundary.finalizeSettlement(arming)
        }
        record(.finalize)
    }

    func publishReadinessAfterTerminal(count: Int) {
        let sink = lock.withLock {
            state.outsideLeaseWakeupCount += count
            return state.finishedSink
        }
        for _ in 0..<count {
            sink?.observeReadiness(.established(
                path: .uikitIdle,
                observationBoundary: .after(baseline.moment)
            ))
        }
    }

    @MainActor
    func dispatch(_: ResolvedHeistActionCommand) async -> TheSafecracker.ActionDispatchResult {
        record(.dispatch)
        if slowDispatchDeadline {
            lock.withLock {
                state.activeChildLeaseCount += 1
                state.operations.append(.childLeaseOpened)
            }
            while !Task.isCancelled {
                await Task.yield()
            }
            record(.dispatchCancelled)
            lock.withLock {
                state.activeChildLeaseCount -= 1
                state.operations.append(.childLeaseClosed)
            }
            return .failure(.dismiss, message: "cancelled")
        }
        let sink = lock.withLock { state.sink }
        sink?.observe(.snapshot(changed))
        if let announcement {
            sink?.observeAnnouncement(announcement)
        }
        sink?.observeReadiness(.established(
            path: .uikitIdle,
            observationBoundary: .including(changed.moment)
        ))
        return .success(payload: .dismiss)
    }

    func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) async -> PredicateEvaluationResult {
        if case .announcement = request.evidence {
            record(.evaluateAnnouncement)
            return PredicateEvaluationResult(met: true)
        }
        record(.evaluateObservation)
        if let liveObservationBoundary {
            return await liveObservationBoundary.evaluate(request)
        }
        return PredicateEvaluationResult(met: false)
    }

    func elapsed() async -> ElapsedMilliseconds {
        RuntimeElapsed.admit(milliseconds: 1)
    }

    private func record(_ operation: Operation) {
        lock.withLock { state.operations.append(operation) }
    }

    @MainActor
    private func publishCaptureInvalidationsIfNeeded(
        _ request: Settlement.Capture.HandoffRequest
    ) async {
        guard request.readinessGeneration == .initial,
              let sink = lock.withLock({ state.sink }) else { return }
        let invalidationCount: Int
        switch captureScenario {
        case .none:
            return
        case .invalidateOnce:
            invalidationCount = 1
        case .invalidateTwice:
            invalidationCount = 2
        case .coalescedBurst:
            invalidationCount = 1
        }
        for _ in 0..<invalidationCount {
            let duplicateCount: Int
            if case .coalescedBurst(_, let count) = captureScenario {
                duplicateCount = count
            } else {
                duplicateCount = 1
            }
            lock.withLock {
                state.readinessWakeupsOffered += duplicateCount * 2
                state.readinessWakeupGroups += 2
            }
            for _ in 0..<duplicateCount {
                sink.observeReadiness(.invalidated)
            }
            for _ in 0..<duplicateCount {
                sink.observeReadiness(.established(
                    path: .uikitIdle,
                    observationBoundary: .after(baseline.moment)
                ))
            }
        }
        for _ in 0...invalidationCount {
            await Task.yield()
        }
    }
}

private extension Settlement.BoundaryEvidence {
    var moment: Observation.Moment? {
        guard case .established(let boundary) = self else { return nil }
        return boundary.moment
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
