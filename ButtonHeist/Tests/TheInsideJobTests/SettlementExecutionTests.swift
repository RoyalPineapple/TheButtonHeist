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
            history: .events([.replayed(changed)])
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
    func testObservationProducerGracefullyStopsAfterSettlementMatch() async {
        let baseline = await commit(label: "Baseline")
        let reading = await commitSettling(label: "Changed")
        let changed = reading.changed
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            settling: reading.settled,
            history: .events([.replayed(changed)]),
            observationOnlyEvidence: true,
            longRunningObservationEffects: true
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        guard case .observation(.settled) = result else {
            return XCTFail("Expected observation to settle")
        }
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
            longRunningObservationEffects: true
        )

        // Timeout comes from a deadline that has already passed, not from a
        // fixture that fakes reaching one. Ticks and the deadline task are the
        // only clocks.
        let result = await Settlement.Executor(boundary: boundary)
            .execute(observationCommand(deadline: .elapsed))

        guard case .observation(.failed(let failure)) = result else {
            return XCTFail("Expected observation timeout")
        }
        XCTAssertEqual(failure.reason, .timedOut(.observation))
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
                [.finalize, .observationEffectsStopRequested, .observationEffectsRestored,
                 .observationEffectsJoined].contains($0)
            },
            [.finalize, .observationEffectsStopRequested, .observationEffectsRestored,
             .observationEffectsJoined]
        )
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsStopRequested }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsRestored }.count, 1)
        XCTAssertEqual(boundary.operations.filter { $0 == .observationEffectsJoined }.count, 1)
        XCTAssertEqual(boundary.viewportMutationCount, 0)
    }

    func testExecutorWaitsForBoundaryFinalizationBeforeReturningOrLogging() async {
        let baseline = await commit(label: "Baseline")
        let reading = await commitSettling(label: "Changed")
        let changed = reading.changed
        let gate = FinalizationGate()
        let probe = SettlementCompletionProbe()
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            settling: reading.settled,
            history: .events([.replayed(changed)]),
            observationOnlyEvidence: true,
            finalizationGate: gate
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

        XCTAssertEqual(boundary.operations.filter { $0 == .finalize }.count, 1)
        XCTAssertFalse(probe.didComplete)
        XCTAssertTrue(probe.logs.isEmpty)

        await gate.release()
        let result = await execution.value

        guard case .observation(.settled) = result else {
            return XCTFail("Expected observation to settle after finalization")
        }
        XCTAssertTrue(probe.didComplete)
        XCTAssertEqual(probe.logs.count, 1)
    }

    func testFailedViewportRestorationReplacesSettledObservationTruth() async {
        let baseline = await commit(label: "Baseline")
        let reading = await commitSettling(label: "Changed")
        let changed = reading.changed
        let probe = SettlementCompletionProbe()
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            settling: reading.settled,
            history: .events([.replayed(changed)]),
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
        // The current observation is the newest reading the run took, which is
        // the quiet one that followed the change.
        XCTAssertEqual(result.currentObservation?.moment, reading.settled.moment)
        XCTAssertEqual(probe.logs.count, 1)
        XCTAssertTrue(probe.logs[0].contains("viewportExitFailed(originUnavailable)"))
    }

    func testStaleCaptureGenerationIsRejectedBeforeAdmission() async {
        let baseline = await commit(label: "Baseline")
        let stale = await commit(label: "Stale")
        let currentReading = await commitSettling(label: "Current")
        let current = currentReading.changed
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: stale,
            settling: currentReading.settled,
            history: .events([.replayed(stale), .replayed(current)]),
            captureScenario: .invalidateOnce(current: current)
        )

        let result = await Settlement.Executor(boundary: boundary).execute(observationCommand())

        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected current capture generation to settle")
        }
        XCTAssertEqual(settled.handoff.event.moment, currentReading.settled.moment)
        XCTAssertEqual(boundary.admittedHandoffGenerations, [.init(rawValue: 1)])
    }

    func testRecaptureKeepsOnlyLatestGenerationWhileCaptureIsInFlight() async {
        let baseline = await commit(label: "Baseline")
        let stale = await commit(label: "Stale")
        let currentReading = await commitSettling(label: "Current")
        let current = currentReading.changed
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: stale,
            settling: currentReading.settled,
            history: .events([.replayed(stale), .replayed(current)]),
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
            history: .events([.replayed(changed)]),
            publishesAfterDisarm: true
        )

        let result = await Settlement.Executor(boundary: boundary)
            .execute(actionCommand(readiness: .zero))

        guard case .action(.failed(let failure)) = result else {
            return XCTFail("Expected action readiness timeout")
        }
        XCTAssertEqual(failure.reason, .timedOut(.actionReadiness))
        XCTAssertFalse(boundary.operations.contains(.evaluateObservation))
        XCTAssertTrue(boundary.captureGenerations.isEmpty)
    }

    func testFailedActionNotificationsAreNotClaimedByTheNextSuccessfulAction() async {
        let tripwire = TheTripwire()
        let screen = Locked(observation(label: "Before", heistId: "before"))
        let actionVault = TheVault(
            tripwire: tripwire,
            visibleObservationSource: { _ in screen.current }
        )
        defer { actionVault.semanticObservationStream.stop() }
        actionVault.semanticObservationStream.beforeVisibleReading = { [actionVault] in
            actionVault.observeInterface(screen.current)
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

        screen.set(observation(label: "After", heistId: "after"))
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

    /// The deadline turns the machine off and reports where it stopped.
    ///
    /// There is no partial credit and no per-phase negotiation: the run fails,
    /// and the value of the failure is the state at the moment it died — what
    /// the predicate was, what evidence had arrived, and what it was still
    /// waiting on. A timeout that reported nothing would leave an author with
    /// "it didn't work" and nowhere to look.
    func testDeadlineStopsTheRunAndReportsTheStateAtFailure() async {
        let baseline = await commit(label: "Baseline")
        let changed = await commit(label: "Changed")
        let boundary = ScriptedSettlementBoundary(
            baseline: baseline,
            changed: changed,
            history: .events([])
        )

        let result = await Settlement.Executor(boundary: boundary)
            .execute(observationCommand(deadline: .elapsed))

        guard case .observation(.failed(let failure)) = result else {
            return XCTFail("Expected an elapsed deadline to fail the run")
        }
        XCTAssertEqual(failure.reason, .timedOut(.observation))
        // The machine is off: it finalized exactly once and nothing ran after.
        XCTAssertEqual(boundary.operations.filter { $0 == .finalize }.count, 1)
        // The report carries the state at failure rather than a bare verdict.
        XCTAssertFalse(failure.attempt.outstanding.isEmpty)
        XCTAssertEqual(failure.attempt.boundary.moment, baseline.moment)
    }

    /// How far out a command's deadline sits.
    ///
    /// `.elapsed` is already in the past, so the executor's deadline task fires
    /// as soon as it is armed — a real timeout rather than a fixture pretending
    /// to reach one.
    enum TestDeadline {
        case elapsed
        case seconds(Int)

        var instant: ContinuousClock.Instant {
            switch self {
            case .elapsed: ContinuousClock.now.advanced(by: .seconds(-1))
            case .seconds(let count): ContinuousClock.now.advanced(by: .seconds(count))
            }
        }
    }

    private func observationCommand(
        deadline: TestDeadline = .seconds(1)
    ) -> Settlement.Command {
        .observation(
            predicate: Settlement.Predicate(
                authored: .elementsChanged,
                resolved: .elementsChanged([])
            ),
            deadline: .init(phase: .observation, instant: deadline.instant),
            baseline: .capture
        )
    }

    private func actionCommand(
        predicate: Settlement.Predicate? = nil,
        expectation: Duration? = nil,
        readiness: Duration = .seconds(5)
    ) -> Settlement.Command {
        .action(.init(
            command: .dismiss,
            predicate: predicate ?? expectation.map { _ in
                Settlement.Predicate(
                    authored: .elementsChanged,
                    resolved: .elementsChanged([])
                )
            },
            allowances: .init(readiness: readiness, expectation: expectation),
            baseline: .capture
        ))
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }
}

private actor FinalizationGate {
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
        case armObservationEffects
        case dispatch
        case evaluateAnnouncement
        case evaluateObservation
        case observationEffectsStarted
        case observationEffectsStopRequested
        case observationEffectsRestored
        case observationEffectsJoined
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
        var viewportMutationCount = 0
    }

    private let lock = NSLock()
    private var state = State()
    private let baseline: Observation.SnapshotEvent
    private let changed: Observation.SnapshotEvent
    private let settling: Observation.SnapshotEvent?
    private let announcement: Observation.AnnouncementEvent?
    private let history: Observation.EventsSince
    private let observationOnlyEvidence: Bool
    private let publishesAfterDisarm: Bool
    private let longRunningObservationEffects: Bool
    private let captureScenario: CaptureScenario
    private let liveObservationBoundary: LiveSettlementExecutionBoundary?
    private let finalizationGate: FinalizationGate?
    private let viewportExit: Navigation.ViewportExit.Outcome

    init(
        baseline: Observation.SnapshotEvent,
        changed: Observation.SnapshotEvent,
        settling: Observation.SnapshotEvent? = nil,
        announcement: Observation.AnnouncementEvent? = nil,
        history: Observation.EventsSince,
        observationOnlyEvidence: Bool = false,
        publishesAfterDisarm: Bool = false,
        longRunningObservationEffects: Bool = false,
        captureScenario: CaptureScenario = .none,
        liveObservationBoundary: LiveSettlementExecutionBoundary? = nil,
        finalizationGate: FinalizationGate? = nil,
        viewportExit: Navigation.ViewportExit.Outcome = .restored
    ) {
        self.baseline = baseline
        self.changed = changed
        self.settling = settling
        self.announcement = announcement
        self.history = history
        self.observationOnlyEvidence = observationOnlyEvidence
        self.publishesAfterDisarm = publishesAfterDisarm
        self.longRunningObservationEffects = longRunningObservationEffects
        self.captureScenario = captureScenario
        self.liveObservationBoundary = liveObservationBoundary
        self.finalizationGate = finalizationGate
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

    var viewportMutationCount: Int {
        lock.withLock { state.viewportMutationCount }
    }

    /// Resumes once arming has finished.
    ///
    /// `armObservationEffects` is the last arming step the boundary sees. The
    /// deadline is no longer one of them — the executor owns that clock — so
    /// waiting on a deadline here would wait forever.
    func waitUntilArmed() async {
        await withCheckedContinuation { continuation in
            let isArmed = lock.withLock {
                if state.operations.contains(.armObservationEffects) {
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
                     .invalidateTwice(let current):
                    if generation.rawValue > 0 {
                        // The recaptured handoff reaches the run as a reading:
                        // the change first, then the quiet one that proves the
                        // tree stopped. The run settles on the last tick, so the
                        // quiet reading has to arrive after the change.
                        observeReadingPair(changed: current)
                        return .admitted(current)
                    }
                }
            }
            return .admitted(changed)
        }
    }

    /// Delivers the changed reading, then the quiet one that follows it.
    ///
    /// A live tree keeps being read after it moves, and the reading that finds
    /// nothing new is the only proof of stillness there is — so a run needs it to
    /// settle. A boundary that stopped at the change would be scripting a tree
    /// that was still moving when the run ended.
    private func observeChangedThenQuiet(into sink: Settlement.ExecutionSink) {
        sink.observe(.read(changed, changed.derivedTick))
        observeQuietReading(into: sink)
    }

    /// Delivers `changed`, then the quiet reading that follows it.
    private func observeReadingPair(changed: Observation.SnapshotEvent) {
        guard let sink = lock.withLock({ state.sink }) else { return }
        sink.observe(.read(changed, changed.derivedTick))
        observeQuietReading(into: sink)
    }

    /// Delivers the quiet reading, if this boundary was given one.
    private func observeQuietReading(into sink: Settlement.ExecutionSink? = nil) {
        guard let settling,
              let sink = sink ?? lock.withLock({ state.sink }) else { return }
        sink.observe(.read(settling, settling.derivedTick))
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
        if liveObservationBoundary != nil {
            await liveObservationBoundary?.armReadiness(deadline, sink: sink)
            sink.observeReadiness(.established(
                observationBoundary: .including(changed.moment)
            ))
            return
        }
        if operations.contains(.dispatch) {
            observeChangedThenQuiet(into: sink)
            if let announcement {
                sink.observeAnnouncement(announcement)
            }
        } else if observationOnlyEvidence {
            observeChangedThenQuiet(into: sink)
        } else if case .none = captureScenario {
            return
        }
        sink.observeReadiness(.established(
            observationBoundary: observationOnlyEvidence
                ? .including(changed.moment)
                : .after(baseline.moment)
        ))
    }

    func armObservationEffects(_: Settlement.Arming) async {
        let waiters = lock.withLock {
            state.operations.append(.armObservationEffects)
            defer { state.armingWaiters.removeAll() }
            return state.armingWaiters
        }
        waiters.forEach { $0.resume() }
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

    func finalizeSettlement(
        _ arming: Settlement.Arming
    ) async -> Navigation.ViewportExit.Outcome {
        record(.finalize)
        await finalizationGate?.suspend()
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
            sink?.observe(.read(changed, changed.derivedTick))
            sink?.observeReadiness(.established(
                observationBoundary: .including(changed.moment)
            ))
        }
        let viewportExit = if let liveObservationBoundary {
            await liveObservationBoundary.finalizeSettlement(arming)
        } else {
            self.viewportExit
        }
        return viewportExit
    }

    @MainActor
    func dispatch(_: ResolvedHeistActionCommand) async -> TheSafecracker.ActionDispatchResult {
        record(.dispatch)
        return .success(payload: .dismiss)
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
        }
        for _ in 0..<invalidationCount {
            sink.observeReadiness(.invalidated)
            sink.observeReadiness(.established(
                observationBoundary: .after(baseline.moment)
            ))
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
