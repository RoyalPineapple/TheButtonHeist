#if canImport(UIKit)
#if DEBUG
import Foundation

@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

struct AccessibilityNotificationFixture {
    let rawCode: UInt32
    let timestamp: Date
    let notificationData: CapturedAccessibilityNotificationPayload
    let associatedElement: CapturedAccessibilityNotificationPayload

    init(
        rawCode: UInt32 = 1008,
        timestamp: Date,
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload = .none
    ) {
        self.rawCode = rawCode
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
    }

    init(
        text: String,
        timestamp: Date,
        rawCode: UInt32 = 1008
    ) {
        self.init(
            rawCode: rawCode,
            timestamp: timestamp,
            notificationData: CapturedAccessibilityNotificationPayload(text as NSString)
        )
    }
}

enum DeterministicRuntimeActionDisposition {
    case result(TheSafecracker.ActionDispatchResult)
    case resultAfterAdvancingClock(
        TheSafecracker.ActionDispatchResult,
        by: Duration
    )
}

enum DeterministicRuntimeInput {
    case notification(AccessibilityNotificationFixture)
    case pulse(after: Duration, observation: InterfaceObservation?)
    case action(
        expected: ResolvedHeistActionCommand,
        disposition: DeterministicRuntimeActionDisposition
    )
    case cancel
}

enum DeterministicRuntimeDriverFailure: Error, CustomStringConvertible {
    case negativePulseElapsed(Duration)
    case unexpectedAction(index: Int, received: ResolvedHeistActionCommand)
    case mismatchedAction(
        index: Int,
        expected: ResolvedHeistActionCommand,
        received: ResolvedHeistActionCommand
    )
    case unconsumedAction(index: Int, received: ResolvedHeistActionCommand)
    case unconsumedPulse(index: Int)
    case scriptExhausted(inputIndex: Int)
    case unexpectedPlatformEffect(String)
    case unconsumedPlatformEffect(String)
    case runtime(Error)

    var description: String {
        switch self {
        case .negativePulseElapsed(let duration):
            "pulse elapsed time must be non-negative, got \(duration)"
        case .unexpectedAction(let index, let received):
            "script input \(index) received unexpected action effect \(received)"
        case .mismatchedAction(let index, let expected, let received):
            "script input \(index) expected action \(expected), received \(received)"
        case .unconsumedAction(let index, let received):
            "script input \(index) did not consume action effect \(received)"
        case .unconsumedPulse(let index):
            "script input \(index) did not produce its authored observation capture"
        case .scriptExhausted(let inputIndex):
            "script exhausted after input \(inputIndex) while the runtime awaited another authored pulse"
        case .unexpectedPlatformEffect(let effect):
            "runtime requested an unexpected platform effect: \(effect)"
        case .unconsumedPlatformEffect(let effect):
            "platform effect script did not consume \(effect)"
        case .runtime(let error):
            "runtime execution failed: \(error)"
        }
    }
}

enum DeterministicRuntimeEffect: Equatable {
    case action(ResolvedHeistActionCommand)
    case exploration(ResolvedAccessibilityTarget?)
    case failureCapture(HeistExecutionPath, ScreenCaptureMode)
}

private enum DeterministicRuntimeTerminal: Sendable {
    case execution(Result<HeistExecution.Completion, any Error>)
    case inputRequested
    case probeCancelled
}

@MainActor
struct DeterministicRuntimeScenarioResult {
    enum Outcome {
        case completed(HeistExecution.Completion)
        case cancelled
    }

    let outcome: Outcome
    let result: HeistResult?
    let report: HeistReport?
    let humanFailureDescription: String?
    let effectTranscript: [DeterministicRuntimeEffect]
}

@MainActor
final class DeterministicRuntimeScenarioDriver {
    @MainActor
    private final class VirtualElapsed {
        fileprivate enum DeadlineDelivery {
            case resume
            case retain
        }

        private struct DeadlineWaiter {
            let deadline: Duration
            let continuation: CheckedContinuation<Bool, Never>
        }

        private let origin = ContinuousClock.now
        private let requestProbe: ScriptInputProbe
        private var didReadNow = false
        private var firstReadWaiters: [CheckedContinuation<Void, Never>] = []
        private var elapsed = Duration.zero
        private var nextWaiterID: UInt64 = 0
        private var deadlineWaiters: [UInt64: DeadlineWaiter] = [:]
        private var retainedDeadlineWaiterIDs: Set<UInt64> = []

        init(requestProbe: ScriptInputProbe) {
            self.requestProbe = requestProbe
        }

        var currentElapsed: Duration { elapsed }

        func now() -> RuntimeElapsed.Instant {
            didReadNow = true
            firstReadWaiters.forEach { $0.resume() }
            firstReadWaiters.removeAll()
            return origin.advanced(by: elapsed)
        }

        func awaitFirstRead() async {
            guard !didReadNow else { return }
            await withCheckedContinuation { continuation in
                firstReadWaiters.append(continuation)
            }
        }

        fileprivate func advance(
            by duration: Duration,
            deadlineDelivery: DeadlineDelivery = .resume
        ) throws {
            guard duration >= .zero else {
                throw DeterministicRuntimeDriverFailure.negativePulseElapsed(duration)
            }
            elapsed += duration
            let ready = deadlineWaiters.filter { $0.value.deadline <= elapsed }
            switch deadlineDelivery {
            case .resume:
                resumeReadyDeadlineWaiters(ready, excluding: retainedDeadlineWaiterIDs)
            case .retain:
                retainedDeadlineWaiterIDs.formUnion(ready.keys)
            }
        }

        fileprivate func releaseRetainedDeadlineWaiters() {
            let retained = retainedDeadlineWaiterIDs
            retainedDeadlineWaiterIDs.removeAll()
            resumeReadyDeadlineWaiters(
                deadlineWaiters.filter { retained.contains($0.key) },
                excluding: []
            )
        }

        func wait(for duration: Duration) async -> Bool {
            guard !Task.isCancelled else { return false }
            let deadline = elapsed + duration
            guard deadline > elapsed else { return true }
            let id = nextWaiterID
            nextWaiterID += 1
            let clock = self
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: false)
                    } else if deadline <= elapsed {
                        continuation.resume(returning: true)
                    } else {
                        deadlineWaiters[id] = .init(
                            deadline: deadline,
                            continuation: continuation
                        )
                        requestProbe.recordRequest()
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    guard let waiter = clock.deadlineWaiters.removeValue(forKey: id) else {
                        return
                    }
                    clock.retainedDeadlineWaiterIDs.remove(id)
                    waiter.continuation.resume(returning: false)
                }
            }
        }

        func close() {
            closeWaiters()
        }

        private func closeWaiters() {
            let waiters = deadlineWaiters
            deadlineWaiters.removeAll()
            retainedDeadlineWaiterIDs.removeAll()
            for waiter in waiters.values {
                waiter.continuation.resume(returning: false)
            }
        }

        private func resumeReadyDeadlineWaiters(
            _ waiters: [UInt64: DeadlineWaiter],
            excluding excludedIDs: Set<UInt64>
        ) {
            for (id, waiter) in waiters where !excludedIDs.contains(id) {
                deadlineWaiters.removeValue(forKey: id)
                waiter.continuation.resume(returning: true)
            }
        }

    }

    @MainActor
    private final class ScriptInputProbe {
        private struct Waiter {
            let after: UInt64
            let continuation: CheckedContinuation<Bool, Never>
        }

        private var generation: UInt64 = 0
        private var nextWaiterID: UInt64 = 0
        private var waiters: [UInt64: Waiter] = [:]
        private var ignoredRegistrations = 0

        var currentGeneration: UInt64 { generation }

        func recordRequest() {
            if ignoredRegistrations > 0 {
                ignoredRegistrations -= 1
                return
            }
            generation += 1
            let ready = waiters.filter { $0.value.after < generation }
            for (id, waiter) in ready {
                waiters.removeValue(forKey: id)
                waiter.continuation.resume(returning: true)
            }
        }

        func ignoreNextRegistration() {
            ignoredRegistrations += 1
        }

        func waitForRequest(after generation: UInt64) async -> Bool {
            guard self.generation <= generation else { return true }
            let id = nextWaiterID
            nextWaiterID += 1
            let probe = self
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: false)
                    } else if self.generation > generation {
                        continuation.resume(returning: true)
                    } else {
                        waiters[id] = Waiter(after: generation, continuation: continuation)
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    guard let waiter = probe.waiters.removeValue(forKey: id) else { return }
                    waiter.continuation.resume(returning: false)
                }
            }
        }

        func close() {
            let active = waiters
            waiters.removeAll()
            active.values.forEach { $0.continuation.resume(returning: false) }
        }
    }

    @MainActor
    private final class ScriptedActionEffects {
        private struct PendingAction {
            let command: ResolvedHeistActionCommand
            let continuation: CheckedContinuation<TheSafecracker.ActionDispatchResult, Never>
        }

        private let inputProbe: ScriptInputProbe
        private let advanceClockBeforeEffectReturn: @MainActor (Duration) throws -> Void
        private var pending: PendingAction?
        private var actionRequestWaiter: CheckedContinuation<PendingAction, Error>?
        private var acknowledgement: CheckedContinuation<Void, Never>?
        private var effectReturned = false
        private var explorationOutcomes: [Navigation.ViewportExit.Outcome]
        private var failureCaptures: [HeistFailureCapture]
        private(set) var transcript: [DeterministicRuntimeEffect] = []
        private var failure: DeterministicRuntimeDriverFailure?

        init(
            inputProbe: ScriptInputProbe,
            explorationOutcomes: [Navigation.ViewportExit.Outcome],
            failureCaptures: [HeistFailureCapture],
            advanceClockBeforeEffectReturn: @escaping @MainActor (Duration) throws -> Void
        ) {
            self.inputProbe = inputProbe
            self.explorationOutcomes = explorationOutcomes
            self.failureCaptures = failureCaptures
            self.advanceClockBeforeEffectReturn = advanceClockBeforeEffectReturn
        }

        func dispatch(
            _ command: ResolvedHeistActionCommand,
            deadline _: SemanticObservationDeadline
        ) async -> TheSafecracker.ActionDispatchResult {
            transcript.append(.action(command))
            inputProbe.recordRequest()
            let effects = self
            let result = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    precondition(pending == nil, "Only one platform effect may be active")
                    let next = PendingAction(command: command, continuation: continuation)
                    pending = next
                    actionRequestWaiter?.resume(returning: next)
                    actionRequestWaiter = nil
                }
            } onCancel: {
                Task { @MainActor in
                    effects.cancelPendingAction()
                }
            }
            acknowledgeEffectReturn()
            return result
        }

        func release(
            at index: Int,
            expected: ResolvedHeistActionCommand,
            disposition: DeterministicRuntimeActionDisposition
        ) async throws {
            let pending = try await awaitPendingAction(at: index, expected: expected)
            guard pending.command == expected else {
                self.pending = nil
                pending.continuation.resume(returning: .failure(
                    .empty(for: pending.command.type),
                    message: "deterministic runtime action script did not match the requested command"
                ))
                await awaitEffectReturn()
                throw DeterministicRuntimeDriverFailure.mismatchedAction(
                    index: index,
                    expected: expected,
                    received: pending.command
                )
            }
            let result: TheSafecracker.ActionDispatchResult
            switch disposition {
            case .result(let dispositionResult):
                result = dispositionResult
            case .resultAfterAdvancingClock(let dispositionResult, let duration):
                try advanceClockBeforeEffectReturn(duration)
                result = dispositionResult
            }
            self.pending = nil
            pending.continuation.resume(returning: result)
            await awaitEffectReturn()
        }

        func assertNoPendingAction(at index: Int) throws {
            if let pending {
                throw DeterministicRuntimeDriverFailure.unconsumedAction(
                    index: index,
                    received: pending.command
                )
            }
        }

        func explore(_ target: ResolvedAccessibilityTarget?) -> Navigation.ViewportExit.Outcome {
            transcript.append(.exploration(target))
            guard !explorationOutcomes.isEmpty else {
                record(.unexpectedPlatformEffect(
                    "exploration \(target.map(String.init(describing:)) ?? "none")"
                ))
                return .failed(.originUnavailable)
            }
            return explorationOutcomes.removeFirst()
        }

        func captureFailure(
            path: HeistExecutionPath,
            mode: ScreenCaptureMode
        ) -> HeistFailureCapture {
            transcript.append(.failureCapture(path, mode))
            guard !failureCaptures.isEmpty else {
                record(.unexpectedPlatformEffect("failure capture at \(path)"))
                return .unavailable(
                    kind: .actionFailed,
                    message: "deterministic runtime failure capture was not scripted"
                )
            }
            return failureCaptures.removeFirst()
        }

        func validate() throws {
            if let failure { throw failure }
            if !explorationOutcomes.isEmpty {
                throw DeterministicRuntimeDriverFailure.unconsumedPlatformEffect("exploration")
            }
            if !failureCaptures.isEmpty {
                throw DeterministicRuntimeDriverFailure.unconsumedPlatformEffect("failure capture")
            }
        }

        private func awaitEffectReturn() async {
            guard !effectReturned else {
                effectReturned = false
                return
            }
            await withCheckedContinuation { continuation in
                acknowledgement = continuation
            }
        }

        private func acknowledgeEffectReturn() {
            if let acknowledgement {
                self.acknowledgement = nil
                acknowledgement.resume()
            } else {
                effectReturned = true
            }
        }

        private func awaitPendingAction(
            at index: Int,
            expected: ResolvedHeistActionCommand
        ) async throws -> PendingAction {
            if let pending { return pending }
            let effects = self
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    precondition(
                        actionRequestWaiter == nil,
                        "Only one scripted action input may await a platform effect"
                    )
                    actionRequestWaiter = continuation
                }
            } onCancel: {
                Task { @MainActor in
                    guard let actionRequestWaiter = effects.actionRequestWaiter else { return }
                    effects.actionRequestWaiter = nil
                    actionRequestWaiter.resume(throwing: CancellationError())
                }
            }
        }

        private func cancelPendingAction() {
            guard let pending else { return }
            self.pending = nil
            pending.continuation.resume(returning: .failure(
                .empty(for: pending.command.type),
                message: "deterministic runtime action effect was cancelled"
            ))
        }

        func close() {
            cancelPendingAction()
            if let actionRequestWaiter {
                self.actionRequestWaiter = nil
                actionRequestWaiter.resume(throwing: CancellationError())
            }
        }

        private func record(_ nextFailure: DeterministicRuntimeDriverFailure) {
            if case nil = failure {
                failure = nextFailure
            }
        }
    }

    private let plan: HeistPlan
    private let argument: HeistArgument
    private let timeout: HeistTimeout
    private let actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy
    private let failureEvidencePolicy: FailureEvidencePolicy
    private let explorationOutcomes: [Navigation.ViewportExit.Outcome]
    private let failureCaptures: [HeistFailureCapture]
    private let inputs: [DeterministicRuntimeInput]

    private struct PulseFixture {
        let inputIndex: Int
        let observation: InterfaceObservation?
    }

    private struct Session {
        let pulses: [PulseFixture]
        let source: VisibleObservationSourceFixture
        let clock: VirtualElapsed
        let clockProbe: ScriptInputProbe
        let inputProbe: ScriptInputProbe
        let effects: ScriptedActionEffects
        let brains: TheBrains
        let boundary: HeistExecution.Host.RuntimeBoundary
    }

    init(
        plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: HeistTimeout,
        actionExpectationTimeoutPolicy: ActionExpectationTimeoutPolicy = .default,
        failureEvidencePolicy: FailureEvidencePolicy = .hierarchy,
        explorationOutcomes: [Navigation.ViewportExit.Outcome] = [],
        failureCaptures: [HeistFailureCapture] = [],
        inputs: [DeterministicRuntimeInput]
    ) {
        self.plan = plan
        self.argument = argument
        self.timeout = timeout
        self.actionExpectationTimeoutPolicy = actionExpectationTimeoutPolicy
        self.failureEvidencePolicy = failureEvidencePolicy
        self.explorationOutcomes = explorationOutcomes
        self.failureCaptures = failureCaptures
        self.inputs = inputs
    }

    func run() async throws -> DeterministicRuntimeScenarioResult {
        let session = makeSession()
        let stream = session.brains.vault.semanticObservationStream
        stream.observationWaiterDidRegister = { session.inputProbe.recordRequest() }
        stream.start()
        defer {
            stream.observationWaiterDidRegister = nil
            stream.stop()
        }

        let execution = startExecution(using: session)
        defer {
            execution.cancel()
            session.effects.close()
            session.clock.close()
            session.clockProbe.close()
            session.inputProbe.close()
        }
        await session.clock.awaitFirstRead()
        let authorCancelled = try await executeInputs(
            using: session,
            stream: stream,
            execution: execution
        )
        let outcome = try await awaitTerminal(
            execution: execution,
            inputProbe: session.inputProbe,
            authorCancelled: authorCancelled
        )
        try validate(session: session)
        return try render(outcome: outcome, session: session)
    }

    private func makeSession() -> Session {
        let pulses = pulseFixtures()
        let source = pulses.isEmpty
            ? VisibleObservationSourceFixture(observation: nil)
            : VisibleObservationSourceFixture(sequence: pulses.map(\.observation))
        let inputProbe = ScriptInputProbe()
        let clockProbe = ScriptInputProbe()
        let clock = VirtualElapsed(requestProbe: clockProbe)
        let effects = ScriptedActionEffects(
            inputProbe: inputProbe,
            explorationOutcomes: explorationOutcomes,
            failureCaptures: failureCaptures,
            advanceClockBeforeEffectReturn: { duration in
                try clock.advance(by: duration, deadlineDelivery: .retain)
            }
        )
        let tripwire = TheTripwire()
        let brains = TheBrains(
            tripwire: tripwire,
            failureEvidencePolicy: failureEvidencePolicy,
            visibleObservationSource: source.capture,
            notificationIngress: .injected,
            pulseIngress: .injected
        )
        return Session(
            pulses: pulses,
            source: source,
            clock: clock,
            clockProbe: clockProbe,
            inputProbe: inputProbe,
            effects: effects,
            brains: brains,
            boundary: runtimeBoundary(clock: clock, effects: effects)
        )
    }

    private func pulseFixtures() -> [PulseFixture] {
        inputs.enumerated().compactMap { inputIndex, input in
            guard case .pulse(_, let observation) = input else { return nil }
            return PulseFixture(inputIndex: inputIndex, observation: observation)
        }
    }

    private func runtimeBoundary(
        clock: VirtualElapsed,
        effects: ScriptedActionEffects
    ) -> HeistExecution.Host.RuntimeBoundary {
        .init(
            now: { clock.now() },
            wait: { duration in await clock.wait(for: duration) },
            dispatch: { command, deadline in await effects.dispatch(command, deadline: deadline) },
            explore: { target, _ in effects.explore(target) },
            captureFailure: { path, mode in effects.captureFailure(path: path, mode: mode) }
        )
    }

    private func startExecution(
        using session: Session
    ) -> Task<HeistExecution.Completion, Error> {
        Task { @MainActor in
            try await HeistExecution.Host(
                brains: session.brains,
                runtimeBoundary: session.boundary
            ).execute(
                plan,
                argument: argument,
                timeout: timeout,
                actionExpectationTimeoutPolicy: actionExpectationTimeoutPolicy
            )
        }
    }

    private func executeInputs(
        using session: Session,
        stream: Observation.Stream,
        execution: Task<HeistExecution.Completion, Error>
    ) async throws -> Bool {
        var tick: UInt64 = 0
        var didSynchronizeInitialPulse = false
        var clockRequestGeneration: UInt64 = 0
        var observationRequestGeneration: UInt64 = 0
        var requiresObservationRequest = false
        for (index, input) in inputs.enumerated() {
            try await synchronizePulse(
                input,
                tick: tick,
                didSynchronize: &didSynchronizeInitialPulse,
                clockRequestGeneration: &clockRequestGeneration,
                observationRequestGeneration: &observationRequestGeneration,
                requiresObservationRequest: requiresObservationRequest,
                session: session
            )
            try await executeInput(
                input,
                at: index,
                tick: &tick,
                session: session,
                stream: stream,
                execution: execution
            )
            if case .pulse(let duration, _) = input, duration > .zero {
                requiresObservationRequest = true
            }
            if case .action(_, .resultAfterAdvancingClock) = input {
                requiresObservationRequest = true
                observationRequestGeneration = session.inputProbe.currentGeneration
            }
        }
        try session.effects.assertNoPendingAction(at: inputs.count)
        return lastInputCancelsExecution()
    }

    private func synchronizePulse(
        _ input: DeterministicRuntimeInput,
        tick: UInt64,
        didSynchronize: inout Bool,
        clockRequestGeneration: inout UInt64,
        observationRequestGeneration: inout UInt64,
        requiresObservationRequest: Bool,
        session: Session
    ) async throws {
        guard case .pulse(let duration, _) = input else { return }
        if !didSynchronize {
            guard await session.inputProbe.waitForRequest(after: 0) else {
                throw CancellationError()
            }
            guard await session.clockProbe.waitForRequest(after: 0) else {
                throw CancellationError()
            }
            didSynchronize = true
            clockRequestGeneration = session.clockProbe.currentGeneration
            observationRequestGeneration = session.inputProbe.currentGeneration
        }
        if requiresObservationRequest {
            guard await session.inputProbe.waitForRequest(
                after: observationRequestGeneration
            ) else {
                throw CancellationError()
            }
            observationRequestGeneration = session.inputProbe.currentGeneration
            session.clock.releaseRetainedDeadlineWaiters()
        }
        guard tick > 0, duration > .zero else { return }
        guard await session.clockProbe.waitForRequest(after: clockRequestGeneration) else {
            throw CancellationError()
        }
        clockRequestGeneration = session.clockProbe.currentGeneration
    }

    private func lastInputCancelsExecution() -> Bool {
        guard let input = inputs.last, case .cancel = input else { return false }
        return true
    }

    private func executeInput(
        _ input: DeterministicRuntimeInput,
        at index: Int,
        tick: inout UInt64,
        session: Session,
        stream: Observation.Stream,
        execution: Task<HeistExecution.Completion, Error>
    ) async throws {
        switch input {
        case .notification(let fixture):
            try session.effects.assertNoPendingAction(at: index)
            record(fixture, in: session.brains.vault)
        case .pulse(let after, _):
            try session.effects.assertNoPendingAction(at: index)
            try await deliverPulse(after: after, tick: &tick, session: session, stream: stream)
        case .action(let expected, let disposition):
            try await session.effects.release(at: index, expected: expected, disposition: disposition)
        case .cancel:
            try session.effects.assertNoPendingAction(at: index)
            execution.cancel()
        }
    }

    private func record(
        _ fixture: AccessibilityNotificationFixture,
        in vault: TheVault
    ) {
        vault.accessibilityNotifications.record(
            sequence: vault.accessibilityNotifications.latestSequence + 1,
            rawCode: fixture.rawCode,
            timestamp: fixture.timestamp,
            notificationData: fixture.notificationData.pendingPayload,
            associatedElement: fixture.associatedElement.pendingPayload
        )
    }

    private func deliverPulse(
        after duration: Duration,
        tick: inout UInt64,
        session: Session,
        stream: Observation.Stream
    ) async throws {
        try session.clock.advance(by: duration)
        tick += 1
        let historyIndex = session.brains.vault.state.history.endIndex
        stream.deliver(.init(
            tick: tick,
            elapsed: session.clock.currentElapsed,
            tripwireSignal: .init(
                topmostVC: nil,
                navigation: .empty,
                windowStack: .empty,
                accessibilityNotificationSequence: session.brains.vault.accessibilityNotifications.latestSequence
            )
        ))
        session.inputProbe.ignoreNextRegistration()
        _ = await stream.waitForObservation(
            after: historyIndex,
            scope: .visible,
            boundary: .observationCycle
        )
    }

    private func awaitTerminal(
        execution: Task<HeistExecution.Completion, Error>,
        inputProbe: ScriptInputProbe,
        authorCancelled: Bool
    ) async throws -> DeterministicRuntimeScenarioResult.Outcome {
        let inputGeneration = inputProbe.currentGeneration
        let terminal = await withTaskGroup(
            of: DeterministicRuntimeTerminal.self,
            returning: DeterministicRuntimeTerminal.self
        ) { group in
            group.addTask { .execution(await execution.result) }
            group.addTask {
                await inputProbe.waitForRequest(after: inputGeneration)
                    ? .inputRequested
                    : .probeCancelled
            }
            let first = await group.next() ?? .probeCancelled
            switch first {
            case .execution:
                break
            case .inputRequested, .probeCancelled:
                execution.cancel()
            }
            inputProbe.close()
            group.cancelAll()
            return first
        }
        switch terminal {
        case .execution(.success(let completion)):
            return .completed(completion)
        case .execution(.failure(let error)) where error is CancellationError && authorCancelled:
            return .cancelled
        case .execution(.failure(let error)) where error is CancellationError:
            throw DeterministicRuntimeDriverFailure.scriptExhausted(inputIndex: inputs.count)
        case .execution(.failure(let error)):
            throw DeterministicRuntimeDriverFailure.runtime(error)
        case .inputRequested:
            throw DeterministicRuntimeDriverFailure.scriptExhausted(inputIndex: inputs.count)
        case .probeCancelled:
            throw CancellationError()
        }
    }

    private func validate(session: Session) throws {
        try session.effects.validate()
        guard session.source.captureCount == session.pulses.count else {
            throw DeterministicRuntimeDriverFailure.unconsumedPulse(
                index: session.pulses[session.source.captureCount].inputIndex
            )
        }
    }

    private func render(
        outcome: DeterministicRuntimeScenarioResult.Outcome,
        session: Session
    ) throws -> DeterministicRuntimeScenarioResult {
        switch outcome {
        case .cancelled:
            return .init(
                outcome: outcome,
                result: nil,
                report: nil,
                humanFailureDescription: nil,
                effectTranscript: session.effects.transcript
            )
        case .completed(let completion):
            let result = try HeistResult(
                steps: completion.steps,
                failureCapture: completion.failureCapture,
                durationMs: RuntimeElapsed.admit(milliseconds: Int(
                    session.clock.currentElapsed / .milliseconds(1)
                ))
            )
            let report = HeistReport.project(result: result)
            let failureDescription = result.outcome == .passed
                ? nil
                : Heist.Failure(result).description
            return .init(
                outcome: outcome,
                result: result,
                report: report,
                humanFailureDescription: failureDescription,
                effectTranscript: session.effects.transcript
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
