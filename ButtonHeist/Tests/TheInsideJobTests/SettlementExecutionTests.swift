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
    func testCommittedHandoffDefersNotificationConsumptionUntilChildLeaseCloses() async throws {
        let lifecycle = LiveSettlementLifecycle()
        let notifications = AccessibilityNotificationBus()
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: notifications.beginActionWindow(),
            boundary: (await commit(label: "Baseline")).moment
        )
        let child = notifications.beginActionWindow()
        notifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )

        XCTAssertEqual(try XCTUnwrap(child.capture()).events.count, 1)
        child.cancel()
        lifecycle.requestNotificationWindowConsumption()
        let finalizedExit = await lifecycle.finalize()
        let repeatedExit = await lifecycle.finalize()

        XCTAssertEqual(finalizedExit, .restored)
        XCTAssertEqual(repeatedExit, .restored)
        XCTAssertTrue(
            notifications.checkpoint(
                after: .origin,
                selection: .unclaimedScoped
            ).events.isEmpty
        )
    }

    func testCurrentStateCapturesExactlyOnceWithoutArming() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)])
        )
        let executor = Settlement.Executor(boundary: boundary)

        let result = await executor.execute(.currentState(scope: .visible))

        guard case .currentState(.captured(let capture)) = result else {
            return XCTFail("Expected current-state capture")
        }
        XCTAssertFalse(boundary.operations.contains(.dispatch))
        XCTAssertEqual(capture.event.moment, baseline.moment)
        XCTAssertEqual(boundary.totalCaptureCount, 1)
        XCTAssertEqual(boundary.operations, [.captureBaseline, .admitBaseline])
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

        let result = await Settlement.Executor(boundary: boundary).execute(.observation(
            predicate: predicate,
            deadline: .init(
                phase: .observation,
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            ),
            baseline: .capture
        ))

        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected announcement observation to settle")
        }
        XCTAssertFalse(boundary.operations.contains(.dispatch))
        XCTAssertEqual(
            settled.evaluation.target,
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

        guard case .observation(.settled) = result else {
            return XCTFail("Expected observation to settle")
        }
        XCTAssertEqual(boundary.operations.filter { $0 == .quiesce }.count, 1)
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

        guard case .observation(.failed(let failure)) = result else {
            return XCTFail("Expected observation timeout")
        }
        XCTAssertEqual(failure.reason, .timedOut(.observation))
        XCTAssertEqual(boundary.operations.filter { $0 == .quiesce }.count, 1)
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

        guard case .observation(.failed(let failure)) = result else {
            return XCTFail("Expected cancelled observation")
        }
        XCTAssertEqual(failure.reason, .cancelled)
        XCTAssertEqual(
            boundary.operations.filter {
                [.quiesce, .observationEffectsStopRequested, .observationEffectsRestored,
                 .observationEffectsJoined].contains($0)
            },
            [.quiesce, .observationEffectsStopRequested, .observationEffectsRestored,
             .observationEffectsJoined]
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsStopRequested }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsRestored }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsJoined }.count, 1)
        XCTAssertEqual(boundary.viewportMutationCount, 0)
    }

    func testExecutorWaitsForBoundaryQuiescenceBeforeReturningOrLogging() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let gate = QuiescenceGate()
        let probe = SettlementCompletionProbe()
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true,
            quiescenceGate: gate
        )
        let execution = Task {
            let result = await Settlement.Executor(
                boundary: boundary,
                terminalLogSink: probe.record
            ).execute(observationCommand())
            probe.recordCompletion()
            return result
        }

        await gate.waitUntilEntered()

        XCTAssertEqual(boundary.operations.filter { $0 == .quiesce }.count, 1)
        XCTAssertFalse(probe.didComplete)
        XCTAssertTrue(probe.logs.isEmpty)

        await gate.release()
        let result = await execution.value

        guard case .observation(.settled) = result else {
            return XCTFail("Expected observation to settle after quiescence")
        }
        XCTAssertTrue(probe.didComplete)
        XCTAssertEqual(probe.logs.count, 1)
    }

    func testFailedViewportRestorationReplacesSettledObservationTruth() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let probe = SettlementCompletionProbe()
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([.snapshot(changed)]),
            observationOnlyEvidence: true,
            viewportExit: .failed(.originUnavailable)
        )

        let result = await Settlement.Executor(
            boundary: boundary,
            terminalLogSink: probe.record
        ).execute(observationCommand())

        guard case .observation(.failed(let failed)) = result else {
            return XCTFail("Expected failed restoration to replace settled observation")
        }
        XCTAssertEqual(failed.reason, .viewportExitFailed(.originUnavailable))
        XCTAssertEqual(result.currentObservation?.moment, changed.moment)
        XCTAssertEqual(probe.logs.count, 1)
        XCTAssertTrue(probe.logs[0].contains("viewportExitFailed(originUnavailable)"))
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

        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected current capture generation to settle")
        }
        XCTAssertEqual(settled.handoff.event.moment, current.moment)
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

        guard case .observation(.settled) = result else {
            return XCTFail("Expected recaptured observation to settle")
        }
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

        guard case .action(.failed(let failure)) = result else {
            return XCTFail("Expected action readiness timeout")
        }
        XCTAssertEqual(failure.reason, .timedOut(.actionReadiness))
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
                tripwireSignal: baseline.tripwireSignal,
                delta: .unchanged
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
                observationEffects: { _ in .restored }
            )
            return await Settlement.Executor(boundary: boundary).execute(command)
        }

        let failed = await executeAction(
            announcing: "Action A",
            result: .failure(.dismiss, message: "Action A failed")
        )

        guard case .action(.failed(let failedAction)) = failed else {
            return XCTFail("Expected failed action result")
        }
        XCTAssertEqual(failedAction.reason, .dispatchFailed)
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

        guard case .action(.settled(let settledAction)) = successful else {
            return XCTFail("Expected successful action settlement")
        }
        XCTAssertEqual(
            settledAction.handoff.event
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
        let command = Settlement.Command.observation(
            predicate: predicate,
            deadline: .init(
                phase: .observation,
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            ),
            baseline: .supplied(.init(moment: baseline.moment))
        )
        let liveBoundary = LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: vault.tripwire,
            dispatch: { _ in
                preconditionFailure("Observation settlement cannot dispatch")
            },
            observationEffects: { _ in .restored }
        )
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: replayed,
            history: .events([]),
            liveObservationBoundary: liveBoundary
        )

        let result = await Settlement.Executor(boundary: boundary).execute(command)

        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected replayed observation to settle")
        }
        XCTAssertFalse(boundary.operations.contains(.captureBaseline))
        XCTAssertEqual(
            settled.evaluation.target,
            .observation(replayed.moment)
        )
        XCTAssertEqual(settled.handoff.event.moment, replayed.moment)
    }

    func testIssue1395SettlesPostReadinessTransitionThroughOrderedSink() async {
        let baseline = await commit(label: "Baseline")
        let ready = await commit(label: "Ready")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: ready,
            history: .events([.snapshot(ready), .snapshot(changed)]),
            readinessScript: { sink, deadline in
                sink.observeReadiness(.established(
                    path: .semanticStability,
                    observationBoundary: .including(ready.moment)
                ))
                sink.observe(
                    .snapshot(ready),
                    at: deadline.instant.advanced(by: .milliseconds(-1_800))
                )
            },
            deadlineScript: { sink, deadline in
                sink.observe(
                    .snapshot(changed),
                    at: deadline.instant.advanced(by: .milliseconds(-300))
                )
                sink.reachDeadline(.init(phase: deadline.phase, instant: deadline.instant))
            },
            evaluate: {
                PredicateEvaluationResult(
                    met: $0.target == .observation(changed.moment)
                )
            }
        )

        let result = await Settlement.Executor(boundary: boundary).execute(
            actionCommand(expectation: .seconds(1))
        )

        guard case .action(.settled(let settled)) = result else {
            return XCTFail("Expected post-readiness transition to settle")
        }
        XCTAssertEqual(settled.boundary.moment, baseline.moment)
        XCTAssertEqual(settled.handoff.event.moment, ready.moment)
        XCTAssertEqual(settled.evaluation?.target, .observation(changed.moment))
        XCTAssertEqual(boundary.armedDeadlines.map(\.phase), [
            .actionReadiness,
            .actionExpectation,
        ])
        XCTAssertEqual(
            boundary.armedDeadlines[1].instant,
            boundary.armedDeadlines[0].instant.advanced(by: .milliseconds(-800))
        )
    }

    func testPendingAnnouncementUsesOrderedExpectationDeadline() async throws {
        let baseline = await commit(label: "Baseline")
        let ready = await commit(label: "Ready")
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

        for eventFirst in [true, false] {
            let boundary = ScriptedSettlementBoundary(
                baseline: baseline,
                changed: ready,
                history: .events([.snapshot(ready)]),
                readinessScript: { sink, deadline in
                    sink.observeReadiness(.established(
                        path: .semanticStability,
                        observationBoundary: .including(ready.moment)
                    ))
                    sink.observe(
                        .snapshot(ready),
                        at: deadline.instant.advanced(by: .milliseconds(-1_800))
                    )
                    sink.reachDeadline(.init(phase: deadline.phase, instant: deadline.instant))
                },
                deadlineScript: { sink, deadline in
                    if eventFirst {
                        sink.observeAnnouncement(announcement)
                    }
                    sink.reachDeadline(.init(phase: deadline.phase, instant: deadline.instant))
                    if !eventFirst {
                        sink.observeAnnouncement(announcement)
                    }
                }
            )

            let result = await Settlement.Executor(boundary: boundary).execute(
                actionCommand(predicate: predicate, expectation: .seconds(1))
            )

            if eventFirst {
                guard case .action(.settled) = result else {
                    return XCTFail("Expected in-window announcement to settle")
                }
            } else {
                guard case .action(.failed(let failed)) = result else {
                    return XCTFail("Expected late announcement to time out")
                }
                XCTAssertEqual(failed.reason, .timedOut(.actionExpectation))
            }
            XCTAssertEqual(boundary.armedDeadlines.map(\.phase), [
                .actionReadiness,
                .actionExpectation,
            ])
            XCTAssertEqual(
                boundary.operations.filter { $0 == .evaluateAnnouncement }.count,
                eventFirst ? 1 : 0
            )
        }
    }

    private func observationCommand() -> Settlement.Command {
        .observation(
            predicate: Settlement.Predicate(
                authored: .changed(.elements()),
                resolved: .changed(.elements([]))
            ),
            deadline: .init(
                phase: .observation,
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            ),
            baseline: .capture
        )
    }

    private func actionCommand(
        predicate: Settlement.Predicate? = nil,
        expectation: Duration? = nil
    ) -> Settlement.Command {
        .action(.init(
            command: .dismiss,
            predicate: predicate ?? expectation.map { _ in
                Settlement.Predicate(
                    authored: .changed(.elements()),
                    resolved: .changed(.elements([]))
                )
            },
            allowances: .init(readiness: .seconds(5), expectation: expectation),
            baseline: .capture
        ))
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
        let command = Settlement.Command.observation(
            predicate: Settlement.Predicate(
                authored: .changed(.elements()),
                resolved: .changed(.elements([]))
            ),
            deadline: .init(
                phase: .observation,
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            ),
            baseline: .capture
        )

        let result = await Settlement.Executor(boundary: boundary).execute(command)

        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected coalesced observation to settle")
        }
        XCTAssertEqual(settled.handoff.event.moment, current.moment)
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
            try XCTUnwrap(settled.timing.execution.beforeObservationMs).milliseconds,
            budgets.baselineMainActorMs
        )
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(settled.timing.execution.finalSemanticEvidenceMs).milliseconds,
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

private actor QuiescenceGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private final class SettlementCompletionProbe: @unchecked Sendable {
    private struct State {
        var logs: [String] = []
        var didComplete = false
    }

    private let lock = NSLock()
    private var state = State()

    var logs: [String] {
        lock.withLock { state.logs }
    }

    var didComplete: Bool {
        lock.withLock { state.didComplete }
    }

    func record(_ log: String) {
        lock.withLock { state.logs.append(log) }
    }

    func recordCompletion() {
        lock.withLock { state.didComplete = true }
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
        case evaluateAnnouncement
        case evaluateObservation
        case observationEffectsStarted
        case observationEffectsStopRequested
        case observationEffectsRestored
        case observationEffectsJoined
        case quiesce
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
        var viewportMutationCount = 0
        var armedDeadlines: [Settlement.PhaseDeadline] = []
    }

    private let lock = NSLock()
    private var state = State()
    private let baseline: Observation.SnapshotEvent
    private let changed: Observation.SnapshotEvent
    private let announcement: Observation.AnnouncementEvent?
    private let history: Observation.EventsSince
    private let observationOnlyEvidence: Bool
    private let deadlineOnArm: Bool
    private let publishesAfterDisarm: Bool
    private let longRunningObservationEffects: Bool
    private let captureScenario: CaptureScenario
    private let liveObservationBoundary: LiveSettlementExecutionBoundary?
    private let readinessScript: (@Sendable (Settlement.ExecutionSink, Settlement.PhaseDeadline) -> Void)?
    private let deadlineScript: (@Sendable (Settlement.ExecutionSink, Settlement.PhaseDeadline) -> Void)?
    private let evaluateRequest: (@Sendable (Settlement.Predicate.EvaluationRequest) -> PredicateEvaluationResult)?
    private let quiescenceGate: QuiescenceGate?
    private let viewportExit: Navigation.ViewportExit.Outcome

    init(
        baseline: Observation.SnapshotEvent,
        changed: Observation.SnapshotEvent,
        announcement: Observation.AnnouncementEvent? = nil,
        history: Observation.EventsSince,
        observationOnlyEvidence: Bool = false,
        deadlineOnArm: Bool = false,
        publishesAfterDisarm: Bool = false,
        longRunningObservationEffects: Bool = false,
        captureScenario: CaptureScenario = .none,
        liveObservationBoundary: LiveSettlementExecutionBoundary? = nil,
        readinessScript: (@Sendable (Settlement.ExecutionSink, Settlement.PhaseDeadline) -> Void)? = nil,
        deadlineScript: (@Sendable (Settlement.ExecutionSink, Settlement.PhaseDeadline) -> Void)? = nil,
        evaluate: (@Sendable (Settlement.Predicate.EvaluationRequest) -> PredicateEvaluationResult)? = nil,
        quiescenceGate: QuiescenceGate? = nil,
        viewportExit: Navigation.ViewportExit.Outcome = .restored
    ) {
        self.baseline = baseline
        self.changed = changed
        self.announcement = announcement
        self.history = history
        self.observationOnlyEvidence = observationOnlyEvidence
        self.deadlineOnArm = deadlineOnArm
        self.publishesAfterDisarm = publishesAfterDisarm
        self.longRunningObservationEffects = longRunningObservationEffects
        self.captureScenario = captureScenario
        self.liveObservationBoundary = liveObservationBoundary
        self.readinessScript = readinessScript
        self.deadlineScript = deadlineScript
        self.evaluateRequest = evaluate
        self.quiescenceGate = quiescenceGate
        self.viewportExit = viewportExit
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

    var viewportMutationCount: Int {
        lock.withLock { state.viewportMutationCount }
    }

    var armedDeadlines: [Settlement.PhaseDeadline] {
        lock.withLock { state.armedDeadlines }
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
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async {
        record(.armReadiness)
        if deadlineOnArm {
            return
        }
        if let readinessScript {
            readinessScript(sink, deadline)
            return
        }
        if liveObservationBoundary != nil {
            await liveObservationBoundary?.armReadiness(deadline, sink: sink)
            sink.observeReadiness(.established(
                path: .semanticStability,
                observationBoundary: .including(changed.moment)
            ))
            return
        }
        if operations.contains(.dispatch) {
            sink.observe(.snapshot(changed))
            if let announcement {
                sink.observeAnnouncement(announcement)
            }
        } else if observationOnlyEvidence {
            sink.observe(.snapshot(changed))
        } else if case .none = captureScenario {
            return
        }
        sink.observeReadiness(.established(
            path: .semanticStability,
            observationBoundary: observationOnlyEvidence
                ? .including(changed.moment)
                : .after(baseline.moment)
        ))
    }

    func armDeadline(
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async {
        let waiters = lock.withLock {
            state.operations.append(.armDeadline)
            state.armedDeadlines.append(deadline)
            defer { state.armingWaiters.removeAll() }
            return state.armingWaiters
        }
        waiters.forEach { $0.resume() }
        if let deadlineScript, deadline.phase == .actionExpectation {
            deadlineScript(sink, deadline)
            return
        }
        if deadlineOnArm {
            sink.reachDeadline(deadline)
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

    func quiesceSettlement(
        _ arming: Settlement.Arming
    ) async -> Navigation.ViewportExit.Outcome {
        record(.quiesce)
        await quiescenceGate?.suspend()
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
                path: .semanticStability,
                observationBoundary: .including(changed.moment)
            ))
        }
        let viewportExit = if let liveObservationBoundary {
            await liveObservationBoundary.quiesceSettlement(arming)
        } else {
            self.viewportExit
        }
        return viewportExit
    }

    func publishReadinessAfterTerminal(count: Int) {
        let sink = lock.withLock {
            state.outsideLeaseWakeupCount += count
            return state.finishedSink
        }
        for _ in 0..<count {
            sink?.observeReadiness(.established(
                path: .semanticStability,
                observationBoundary: .after(baseline.moment)
            ))
        }
    }

    @MainActor
    func dispatch(_: ResolvedHeistActionCommand) async -> TheSafecracker.ActionDispatchResult {
        record(.dispatch)
        return .success(payload: .dismiss)
    }

    func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) -> PredicateEvaluationResult {
        if case .announcement = request.evidence {
            record(.evaluateAnnouncement)
            return PredicateEvaluationResult(met: true)
        }
        record(.evaluateObservation)
        if let evaluateRequest { return evaluateRequest(request) }
        if let liveObservationBoundary {
            return liveObservationBoundary.evaluate(request)
        }
        return PredicateEvaluationResult(met: true)
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
                    path: .semanticStability,
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
