#if canImport(UIKit)
#if DEBUG
import Foundation
import OSLog

import ThePlans
import TheScore

extension Settlement {
    internal enum CaptureAdmissionOutcome: Sendable {
        case admitted(Observation.SnapshotEvent)
        case failed(Capture.Failure)
    }

    internal struct CaptureCompletion: Sendable {
        internal let outcome: CaptureAdmissionOutcome
    }
}

extension Settlement.Readiness {
    internal enum Signal: Sendable, Equatable {
        case established(
            path: Path,
            observationBoundary: ObservationBoundary,
            delta: SettleDelta? = nil
        )
        case invalidated
    }
}

extension Settlement {
    internal enum ObservationEffectState: Sendable, Equatable {
        case active
        case stopRequested
        case completed(stopWasRequested: Bool)
    }

    /// Coordinates graceful completion of viewport-mutating observation work.
    /// `NSLock` protects the complete `state` value.
    internal final class ObservationEffectControl: @unchecked Sendable {
        private let lock = NSLock()
        private var state = ObservationEffectState.active

        internal var stopRequested: Bool {
            lock.withLock {
                switch state {
                case .active:
                    false
                case .stopRequested, .completed(stopWasRequested: true):
                    true
                case .completed(stopWasRequested: false):
                    false
                }
            }
        }

        internal var snapshot: ObservationEffectState {
            lock.withLock { state }
        }

        internal func requestStop() {
            lock.withLock {
                guard case .active = state else { return }
                state = .stopRequested
            }
        }

        internal func complete() {
            lock.withLock {
                switch state {
                case .active:
                    state = .completed(stopWasRequested: false)
                case .stopRequested:
                    state = .completed(stopWasRequested: true)
                case .completed:
                    break
                }
            }
        }
    }

    fileprivate enum ExecutionInput: Sendable {
        case observation(Observation.Event, ContinuousClock.Instant)
        case observationHistoryUnavailable(Observation.EventsSince)
        case announcement(Observation.AnnouncementEvent)
        case announcementHistoryUnavailable(AccessibilityNotificationGap)
        case readiness(Readiness.Signal)
        case deadlineReached(PhaseDeadline)
        case cancelled
        case dispatchCompleted(TheSafecracker.ActionDispatchResult, ContinuousClock.Instant)
        case captureCompleted(Capture.Request, CaptureCompletion, ContinuousClock.Instant)

    }

    fileprivate enum ExecutionCoalescingKey: Equatable {
        case readinessEstablished
        case readinessInvalidated
    }
}

internal protocol SettlementExecutionBoundary: Sendable {
    associatedtype CapturedObservation: Sendable

    @MainActor
    func capture(_ request: Settlement.Capture.Request) async -> CapturedObservation?

    func admit(
        _ capture: CapturedObservation,
        for request: Settlement.Capture.Request
    ) async -> Settlement.CaptureAdmissionOutcome

    func events(since moment: Observation.Moment) async -> Observation.EventsSince
    @MainActor
    func beginSettlement(_ arming: Settlement.Arming) async
    @MainActor
    func armObservations(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armAnnouncements(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armReadiness(
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async
    @MainActor
    func armDeadline(
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async
    @MainActor
    func armObservationEffects(_ arming: Settlement.Arming) async
    @MainActor
    func quiesceSettlement(_ arming: Settlement.Arming) async -> Navigation.ViewportExit.Outcome

    @MainActor
    func dispatch(
        _ command: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult

    @MainActor
    func dispatchDidComplete() async

    func elapsed() async -> ElapsedMilliseconds
}

extension SettlementExecutionBoundary {
    @MainActor
    internal func dispatchDidComplete() async {}
}

extension Settlement {
    /// `NSLock` protects `inputs`, `inputHead`, `continuation`, `isFinished`,
    /// and `readinessGeneration`; all other sink state is immutable.
    internal final class ExecutionSink: @unchecked Sendable {
        private let lock = NSLock()
        private var inputs: [ExecutionInput?] = []
        private var inputHead = 0
        private var continuation: CheckedContinuation<ExecutionInput?, Never>?
        private var isFinished = false
        private var readinessGeneration = Readiness.Generation.initial

        internal func observe(
            _ event: Observation.Event,
            at instant: ContinuousClock.Instant = RuntimeElapsed.now
        ) {
            record(.observation(event, instant))
        }

        internal func observeAnnouncement(_ event: Observation.AnnouncementEvent) {
            record(.announcement(event))
        }

        internal func observeAnnouncementHistoryUnavailable(
            _ gap: AccessibilityNotificationGap
        ) {
            record(.announcementHistoryUnavailable(gap))
        }

        internal func observeHistoryUnavailable(_ history: Observation.EventsSince) {
            record(.observationHistoryUnavailable(history))
        }

        internal func observeReadiness(_ signal: Readiness.Signal) {
            let input = ExecutionInput.readiness(signal)
            let continuation = lock.withLock {
                () -> CheckedContinuation<ExecutionInput?, Never>? in
                guard !isFinished else { return nil }
                if let key = input.coalescingKey,
                   lastQueuedCoalescingKey == key { return nil }
                return enqueueOrTakeContinuation(input)
            }
            continuation?.resume(returning: input)
        }

        internal func reachDeadline(_ deadline: PhaseDeadline) {
            record(.deadlineReached(deadline))
        }

        fileprivate func cancel() {
            record(.cancelled)
        }

        fileprivate func completeDispatch(
            _ result: TheSafecracker.ActionDispatchResult,
            at instant: ContinuousClock.Instant
        ) {
            record(.dispatchCompleted(result, instant))
        }

        fileprivate func completeCapture(
            _ request: Capture.Request,
            completion: CaptureCompletion,
            at instant: ContinuousClock.Instant = RuntimeElapsed.now
        ) {
            record(.captureCompleted(request, completion, instant))
        }

        fileprivate func next() async -> ExecutionInput? {
            await withCheckedContinuation { continuation in
                let immediate = lock.withLock { () -> ExecutionInput?? in
                    if let input = dequeue() {
                        return .some(input)
                    }
                    if isFinished {
                        return .some(nil)
                    }
                    precondition(self.continuation == nil, "Settlement sink permits one consumer")
                    self.continuation = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        }

        fileprivate func nextIfAvailable() -> ExecutionInput? {
            lock.withLock { dequeue() }
        }

        fileprivate func captureIsCurrent(_ request: Capture.Request) -> Bool {
            guard case .handoff(let handoff) = request else { return true }
            return lock.withLock {
                !isFinished && handoff.readinessGeneration == readinessGeneration
            }
        }

        fileprivate func advanceCaptureGeneration(to generation: Readiness.Generation) {
            lock.withLock {
                guard generation > readinessGeneration else { return }
                readinessGeneration = generation
            }
        }

        fileprivate func finish() {
            let continuation = lock.withLock {
                () -> CheckedContinuation<ExecutionInput?, Never>? in
                guard !isFinished else { return nil }
                isFinished = true
                inputs.removeAll()
                inputHead = 0
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: nil)
        }

        private func record(_ input: ExecutionInput) {
            let continuation = lock.withLock {
                () -> CheckedContinuation<ExecutionInput?, Never>? in
                guard !isFinished else { return nil }
                if let key = input.coalescingKey,
                   lastQueuedCoalescingKey == key { return nil }
                return enqueueOrTakeContinuation(input)
            }
            continuation?.resume(returning: input)
        }

        private func enqueueOrTakeContinuation(
            _ input: ExecutionInput
        ) -> CheckedContinuation<ExecutionInput?, Never>? {
            guard let continuation else {
                inputs.append(input)
                return nil
            }
            self.continuation = nil
            return continuation
        }

        private func dequeue() -> ExecutionInput? {
            guard inputHead < inputs.count else { return nil }
            let input = inputs[inputHead]
            inputs[inputHead] = nil
            inputHead += 1
            if inputHead >= 64, inputHead * 2 >= inputs.count {
                inputs.removeFirst(inputHead)
                inputHead = 0
            }
            return input
        }

        private var lastQueuedCoalescingKey: ExecutionCoalescingKey? {
            guard inputHead < inputs.count else { return nil }
            return inputs[inputs.count - 1]?.coalescingKey
        }
    }
}

private extension Settlement.ExecutionInput {
    var coalescingKey: Settlement.ExecutionCoalescingKey? {
        switch self {
        case .readiness(.established):
            .readinessEstablished
        case .readiness(.invalidated):
            .readinessInvalidated
        case .observation,
             .observationHistoryUnavailable,
             .announcement,
             .announcementHistoryUnavailable,
             .deadlineReached,
             .cancelled,
             .dispatchCompleted,
             .captureCompleted:
            nil
        }
    }
}

private enum FinalSemanticEvidenceMeasurement {
    case idle
    case measuring(RuntimeElapsed.Instant)

    mutating func begin() {
        guard case .idle = self else { return }
        self = .measuring(RuntimeElapsed.now)
    }

    mutating func complete() -> Settlement.ExecutionTiming? {
        guard case .measuring(let startedAt) = self else { return nil }
        self = .idle
        return Settlement.ExecutionTiming(
            finalSemanticEvidenceMs: RuntimeElapsed.milliseconds(since: startedAt)
        )
    }
}

private struct AdmittedSettlementFact {
    let fact: Settlement.Event.Fact
    let instant: ContinuousClock.Instant
}

extension Settlement {
    internal struct Executor<Boundary: SettlementExecutionBoundary>: Sendable {
        internal let boundary: Boundary
        private let terminalLogSink: Settlement.TerminalLogSink

        internal init(boundary: Boundary) {
            self.init(boundary: boundary) {
                insideJobLogger.debug("\($0, privacy: .public)")
            }
        }

        internal init(
            boundary: Boundary,
            terminalLogSink: @escaping Settlement.TerminalLogSink
        ) {
            self.boundary = boundary
            self.terminalLogSink = terminalLogSink
        }

        internal func execute(_ command: Command) async -> Result {
            let sink = ExecutionSink()
            let execution = Task {
                await execute(command, sink: sink)
            }
            return await withTaskCancellationHandler {
                await execution.value
            } onCancel: {
                sink.cancel()
            }
        }

        private func execute(_ command: Command, sink: ExecutionSink) async -> Result {
            let initial = Reducer.begin(command)
            var state = initial.state
            var effects = initial.effects
            var admittedMoments: [Observation.Moment] = []
            var activeCapture: Capture.Request?, pendingCapture: Capture.Request?
            var drainsArmingInputs = false
            var finalSemanticEvidence = FinalSemanticEvidenceMeasurement.idle

            return await withTaskGroup(of: Void.self, returning: Result.self) { tasks in
                while true {
                    if drainsArmingInputs {
                        if let input = sink.nextIfAvailable() {
                            let decision = await consume(input, state: state, sink: sink,
                                admittedMoments: &admittedMoments,
                                finalSemanticEvidence: &finalSemanticEvidence)
                            state = decision.state
                            effects += decision.effects
                            if state.result != nil {
                                drainsArmingInputs = false
                                continue
                            }
                            captureDidComplete(
                                input,
                                active: &activeCapture,
                                pending: &pendingCapture,
                                state: state,
                                sink: sink,
                                tasks: &tasks
                            )
                            continue
                        }
                        drainsArmingInputs = false
                    }

                    if case .terminal(let result) = state { return finish(result, sink: sink) }

                    if !effects.isEmpty {
                        let effect = effects.removeFirst()
                        switch effect {
                        case .capture(let request):
                            if case .baseline = request {
                                let decision = await captureBaseline(
                                    request,
                                    command: command,
                                    state: state
                                )
                                state = decision.state
                                effects += decision.effects
                            } else if activeCapture == nil {
                                activeCapture = request
                                launchCapture(request, sink: sink, tasks: &tasks)
                            } else {
                                pendingCapture = request
                            }

                        case .arm(let requestedArming):
                            let decision = await arm(requestedArming, state: state, sink: sink)
                            state = decision.state
                            effects += decision.effects
                            drainsArmingInputs = true

                        case .armReadiness(let deadline):
                            await boundary.armReadiness(deadline, sink: sink)

                        case .armDeadline(let request):
                            await boundary.armDeadline(request, sink: sink)

                        case .dispatchAction(let action):
                            tasks.addTask {
                                let result = await boundary.dispatch(action)
                                let instant = RuntimeElapsed.now
                                await boundary.dispatchDidComplete()
                                sink.completeDispatch(result, at: instant)
                            }

                        case .quiesce(let arming):
                            let decision = await quiesce(arming, state: state, sink: sink, tasks: &tasks)
                            state = decision.state
                            effects += decision.effects
                        }
                        continue
                    }

                    guard let input = await sink.next() else {
                        preconditionFailure("Settlement event delivery ended before a terminal result")
                    }
                    let decision = await consume(input, state: state, sink: sink,
                        admittedMoments: &admittedMoments,
                        finalSemanticEvidence: &finalSemanticEvidence)
                    state = decision.state
                    effects = decision.effects
                    captureDidComplete(
                        input,
                        active: &activeCapture,
                        pending: &pendingCapture,
                        state: state,
                        sink: sink,
                        tasks: &tasks
                    )
                }
            }
        }

        private func quiesce(
            _ arming: Arming,
            state: State,
            sink: ExecutionSink,
            tasks: inout TaskGroup<Void>
        ) async -> Decision {
            sink.finish()
            tasks.cancelAll()
            await tasks.waitForAll()
            let viewportExit = await boundary.quiesceSettlement(arming)
            return await reduce(state, fact: .quiesced(viewportExit))
        }

        private func finish(
            _ result: Result,
            sink: ExecutionSink
        ) -> Result {
            sink.finish()
            terminalLogSink(TerminalLog.render(result))
            return result
        }

        private func arm(
            _ arming: Arming,
            state: State,
            sink: ExecutionSink
        ) async -> Decision {
            await boundary.beginSettlement(arming)
            await boundary.armObservations(arming, sink: sink)
            await boundary.armAnnouncements(arming, sink: sink)
            await boundary.armObservationEffects(arming)
            return await reduce(state, fact: .channelsArmed)
        }

        private func consume(
            _ input: ExecutionInput,
            state: State,
            sink: ExecutionSink,
            admittedMoments: inout [Observation.Moment],
            finalSemanticEvidence: inout FinalSemanticEvidenceMeasurement
        ) async -> Decision {
            guard let admitted = await fact(
                for: input,
                state: state,
                sink: sink,
                admittedMoments: &admittedMoments
            ) else {
                return Decision(state: state, effects: [])
            }
            let fact = admitted.fact
            if case .readinessEstablished = fact,
               state.session?.readiness.isEstablished == false {
                finalSemanticEvidence.begin()
            }
            var decision = await reduce(
                state,
                fact: fact,
                instant: admitted.instant
            )
            if decision.state.concludesFinalSemanticEvidence
                || fact.endsFinalSemanticEvidenceAttempt {
                if let timing = finalSemanticEvidence.complete() {
                    decision = Settlement.Decision(
                        state: decision.state.recording(timing),
                        effects: decision.effects
                    )
                }
            }
            return decision
        }

        private func launchCapture(
            _ request: Capture.Request,
            sink: ExecutionSink,
            tasks: inout TaskGroup<Void>
        ) {
            tasks.addTask {
                guard let captured = await boundary.capture(request) else {
                    sink.completeCapture(request, completion: .init(
                        outcome: .failed(.unavailable)
                    ))
                    return
                }
                guard sink.captureIsCurrent(request), !Task.isCancelled else {
                    sink.completeCapture(request, completion: .init(
                        outcome: .failed(.admissionRejected)
                    ))
                    return
                }
                let outcome = await boundary.admit(captured, for: request)
                guard sink.captureIsCurrent(request), !Task.isCancelled else {
                    sink.completeCapture(request, completion: .init(
                        outcome: .failed(.admissionRejected)
                    ))
                    return
                }
                sink.completeCapture(request, completion: .init(
                    outcome: outcome
                ))
            }
        }

        private func captureDidComplete(
            _ input: ExecutionInput,
            active: inout Capture.Request?,
            pending: inout Capture.Request?,
            state: State,
            sink: ExecutionSink,
            tasks: inout TaskGroup<Void>
        ) {
            guard case .captureCompleted(let request, _, _) = input,
                  active == request else { return }
            active = nil
            guard state.result == nil, let next = pending else {
                pending = nil
                return
            }
            pending = nil
            guard sink.captureIsCurrent(next) else { return }
            active = next
            launchCapture(next, sink: sink, tasks: &tasks)
        }

        private func captureBaseline(
            _ request: Capture.Request,
            command _: Command,
            state: State
        ) async -> Decision {
            let startedAt = RuntimeElapsed.now
            switch await capture(request) {
            case .admitted(let event):
                return await reduce(
                    state,
                    fact: .baselineAdmitted(event),
                    timing: ExecutionTiming(
                        beforeObservationMs: RuntimeElapsed.milliseconds(since: startedAt)
                    )
                )
            case .failed(let failure):
                return await reduce(
                    state,
                    fact: .baselineUnavailable(failure),
                    timing: ExecutionTiming(
                        beforeObservationMs: RuntimeElapsed.milliseconds(since: startedAt)
                    )
                )
            }
        }

        private func capture(_ request: Capture.Request) async -> CaptureAdmissionOutcome {
            guard let captured = await boundary.capture(request) else {
                return .failed(.unavailable)
            }
            return await boundary.admit(captured, for: request)
        }

        private func fact(
            for input: ExecutionInput,
            state: State,
            sink: ExecutionSink,
            admittedMoments: inout [Observation.Moment]
        ) async -> AdmittedSettlementFact? {
            switch input {
            case .observation(.snapshot(let event), let instant):
                // Every observation in this session's window is a tick, so the
                // only thing turned away here is one from before the boundary,
                // or one already admitted by the handoff path. Whether the tree
                // moved is not asked: that is the observation's own answer, and
                // `admit` reads it to pick the tick.
                guard let baseline = state.session?.boundary.moment,
                      event.moment.isSameOrAfter(baseline),
                      !admittedMoments.contains(event.moment) else { return nil }
                admittedMoments.append(event.moment)
                return AdmittedSettlementFact(
                    fact: .observationAdmitted(.init(
                        event: event,
                        history: await boundary.events(since: baseline),
                        instant: instant
                    )),
                    instant: instant
                )
            case .observationHistoryUnavailable(let history):
                return AdmittedSettlementFact(
                    fact: .observationHistoryUnavailable(history),
                    instant: RuntimeElapsed.now
                )
            case .observation(.announcement(let event), _), .announcement(let event):
                return AdmittedSettlementFact(
                    fact: .announcementObserved(event),
                    instant: RuntimeElapsed.now
                )
            case .announcementHistoryUnavailable(let gap):
                return AdmittedSettlementFact(
                    fact: .announcementHistoryUnavailable(gap),
                    instant: RuntimeElapsed.now
                )
            case .readiness(.established(let path, let observationBoundary, let delta)):
                guard let generation = state.session?.readiness.generation else { return nil }
                return AdmittedSettlementFact(
                    fact: .readinessEstablished(.init(
                        generation: generation,
                        path: path,
                        observationBoundary: observationBoundary,
                        delta: delta
                    )),
                    instant: RuntimeElapsed.now
                )
            case .readiness(.invalidated):
                guard let session = state.session,
                      case .established(let readiness) = session.readiness else { return nil }
                let generation = readiness.generation.advanced()
                sink.advanceCaptureGeneration(to: generation)
                return AdmittedSettlementFact(
                    fact: .readinessInvalidated(generation),
                    instant: RuntimeElapsed.now
                )
            case .deadlineReached(let deadline):
                return AdmittedSettlementFact(
                    fact: .deadlineReached(deadline),
                    instant: deadline.instant
                )
            case .cancelled:
                return AdmittedSettlementFact(fact: .cancelled, instant: RuntimeElapsed.now)
            case .dispatchCompleted(let result, let instant):
                return AdmittedSettlementFact(
                    fact: .dispatchCompleted(result),
                    instant: instant
                )
            case .captureCompleted(.baseline, _, _):
                preconditionFailure("Baseline capture completion cannot enter armed delivery")
            case .captureCompleted(.handoff(let request), let completion, let instant):
                switch completion.outcome {
                case .admitted(let event):
                    guard let baseline = state.session?.boundary.moment,
                          !admittedMoments.contains(event.moment) else { return nil }
                    admittedMoments.append(event.moment)
                    return AdmittedSettlementFact(
                        fact: .observationAdmitted(.init(
                            event: event,
                            history: await boundary.events(since: baseline),
                            source: .handoffCapture(request.readinessGeneration),
                            instant: instant
                        )),
                        instant: instant
                    )
                case .failed(let failure):
                    return AdmittedSettlementFact(
                        fact: .handoffCaptureFailed(request.readinessGeneration, failure),
                        instant: instant
                    )
                }
            }
        }

        private func reduce(
            _ state: State,
            fact: Event.Fact,
            timing: ExecutionTiming = ExecutionTiming(),
            instant: ContinuousClock.Instant = RuntimeElapsed.now
        ) async -> Decision {
            Reducer.reduce(
                state,
                event: Event(
                    fact: fact,
                    timing: timing,
                    elapsed: await boundary.elapsed(),
                    instant: instant
                )
            )
        }
    }
}

private extension Settlement.State {
    var session: Settlement.Session? {
        switch self {
        case .armed(let session),
             .active(let session):
            session
        case .quiescing(let quiescence):
            quiescence.session
        case .awaitingBaseline, .terminal:
            nil
        }
    }

    var concludesFinalSemanticEvidence: Bool {
        let handoff: Settlement.Handoff.Evidence? = switch self {
        case .armed(let session),
             .active(let session):
            session.handoff
        case .quiescing(let quiescence):
            quiescence.session.handoff
        case .terminal:
            nil
        case .awaitingBaseline:
            nil
        }
        guard let handoff else { return false }
        switch handoff {
        case .admitted, .captureFailed:
            return true
        case .pending, .captureRequested:
            return false
        }
    }

    func recording(_ timing: Settlement.ExecutionTiming) -> Settlement.State {
        switch self {
        case .armed(var session):
            session.timing.merge(timing)
            return .armed(session)
        case .active(var session):
            session.timing.merge(timing)
            return .active(session)
        case .quiescing(let quiescence):
            var session = quiescence.session
            session.timing.merge(timing)
            return .quiescing(.init(
                session: session,
                intendedOutcome: quiescence.intendedOutcome,
                elapsed: quiescence.elapsed
            ))
        case .terminal(let result):
            return .terminal(result)
        case .awaitingBaseline:
            preconditionFailure("Final semantic evidence cannot precede baseline admission")
        }
    }
}

private extension Settlement.Event.Fact {
    var endsFinalSemanticEvidenceAttempt: Bool {
        switch self {
        case .readinessInvalidated,
             .deadlineReached,
             .cancelled,
             .quiesced:
            true
        case .baselineAdmitted,
             .baselineUnavailable,
             .channelsArmed,
             .dispatchCompleted,
             .observationAdmitted,
             .announcementObserved,
             .observationHistoryUnavailable,
             .announcementHistoryUnavailable,
             .readinessEstablished,
             .handoffCaptureFailed:
            false
        }
    }
}

internal struct LiveSettlementExecutionBoundary: SettlementExecutionBoundary {
    internal typealias CapturedObservation = Observation.SnapshotEvent
    internal typealias ActionDispatch = @MainActor @Sendable (
        ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult
    internal typealias ObservationEffects = @MainActor @Sendable (
        Settlement.ObservationEffectControl
    ) async -> Navigation.ViewportExit.Outcome

    private let command: Settlement.Command
    private let vault: TheVault
    private let tripwire: TheTripwire
    private let dispatchAction: ActionDispatch
    private let publishObservationEffects: ObservationEffects
    private let lifecycle: LiveSettlementLifecycle
    private let startedAt = RuntimeElapsed.now

    @MainActor
    internal init(
        command: Settlement.Command,
        vault: TheVault,
        tripwire: TheTripwire,
        dispatch: @escaping ActionDispatch,
        observationEffects: @escaping ObservationEffects
    ) {
        self.command = command
        self.vault = vault
        self.tripwire = tripwire
        self.dispatchAction = dispatch
        self.publishObservationEffects = observationEffects
        self.lifecycle = LiveSettlementLifecycle()
    }

    @MainActor
    internal func capture(
        _ request: Settlement.Capture.Request
    ) async -> Observation.SnapshotEvent? {
        let scope = switch request {
        case .baseline(let scope): scope
        case .handoff(let handoff): handoff.scope
        }
        switch scope {
        case .visible:
            guard let observation = vault.captureVisibleObservation() else { return nil }
            vault.observeInterface(observation)
            let admitted = CommittableInterfaceObservation.admitCaptured(
                observation,
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
            let notificationBatch: AccessibilityNotificationBatch? = switch request {
            case .baseline: nil
            case .handoff: lifecycle.captureNotificationBatch()
            }
            let outcome = await vault.semanticObservationStream.commitSettledVisibleObservation(
                admitted,
                notificationBatch: notificationBatch,
                notificationIdentityObservation: observation
            )
            if notificationBatch != nil, outcome.event != nil {
                lifecycle.requestNotificationWindowConsumption()
            }
            return outcome.event
        case .discovery:
            return await vault.semanticObservationStream.settledEvent(
                scope: .discovery,
                after: await vault.semanticObservationStream.latestCommittedEvent()?.sequence,
                timeout: 0
            )
        }
    }

    internal func admit(
        _ capture: Observation.SnapshotEvent,
        for _: Settlement.Capture.Request
    ) async -> Settlement.CaptureAdmissionOutcome {
        .admitted(capture)
    }

    internal func events(since moment: Observation.Moment) async -> Observation.EventsSince {
        await vault.semanticObservationStream.events(
            since: moment,
            scope: command.observationScope
        )
    }

    @MainActor
    internal func beginSettlement(_ arming: Settlement.Arming) async {
        await vault.semanticObservationStream.storeOwner.settlementDidArm(
            at: arming.boundary.moment
        )
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: vault.accessibilityNotifications.beginActionWindow(),
            boundary: arming.boundary.moment
        )
    }

    @MainActor
    internal func armObservations(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        let subscription = await vault.semanticObservationStream.subscribe(
            scope: arming.observationScope,
            replayingAfter: arming.boundary.moment,
            receive: { sink.observe($0) },
            historyUnavailable: sink.observeHistoryUnavailable
        )
        lifecycle.retain(subscription)
    }

    @MainActor
    internal func armAnnouncements(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        guard let predicate = command.predicate,
              case .announcement(let announcement) = predicate.resolved else { return }
        let notifications = vault.accessibilityNotifications
        lifecycle.retain(Task {
            switch await notifications.waitForAnnouncement(
                after: arming.boundary.announcementCursor,
                matching: announcement
            ) {
            case .matched(let announcement):
                sink.observeAnnouncement(.init(announcement: announcement))
            case .historyUnavailable(let gap):
                sink.observeAnnouncementHistoryUnavailable(gap)
            case .cancelled:
                break
            }
        })
    }

    /// One readiness path for every command: run the settle loop and report the
    /// diff it produced.
    ///
    /// Commands that dispatch wait for the refresh boundary recorded when
    /// dispatch completed; commands that only observe start from the current
    /// boundary. Both then read the same settle result, so the reducer sees the
    /// same shape of evidence either way.
    @MainActor
    internal func armReadiness(
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async {
        let dispatches = !(command.waitsForObservation || command.observationScope == .discovery)
        let baselineTripwireSignal = tripwire.tripwireSignal()
        lifecycle.armReadiness { [vault] in
            let stream = vault.semanticObservationStream
            guard let refreshBoundary = dispatches
                    ? lifecycle.visibleRefreshBoundaryAfterDispatch()
                    : stream.visibleRefreshBoundary()
            else { return }
            let timeout = ContinuousClock.now.duration(to: deadline.instant)
            guard timeout > .zero else { return }
            let settlement = await stream.refreshVisibleObservation(
                after: refreshBoundary,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: max(1, Int((timeout / .milliseconds(1)).rounded(.up)))
            )
            guard case .committed(let event) = settlement.commitOutcome,
                  settlement.settleResult.outcome.didSettleCleanly else { return }
            lifecycle.requestNotificationWindowConsumption()
            sink.observeReadiness(.established(
                path: .semanticStability,
                observationBoundary: .including(event.moment),
                delta: settlement.settleResult.delta
            ))
        }
    }

    @MainActor
    internal func armDeadline(
        _ deadline: Settlement.PhaseDeadline,
        sink: Settlement.ExecutionSink
    ) async {
        lifecycle.replaceDeadline(Task {
            do {
                try await ContinuousClock().sleep(until: deadline.instant)
                sink.reachDeadline(deadline)
            } catch {}
        })
    }

    @MainActor
    internal func armObservationEffects(_: Settlement.Arming) async {
        guard command.waitsForObservation else { return }
        let control = Settlement.ObservationEffectControl()
        let task = Task {
            let viewportExit = await publishObservationEffects(control)
            control.complete()
            return viewportExit
        }
        lifecycle.retainObservationEffect(control: control, task: task)
    }

    @MainActor
    internal func quiesceSettlement(
        _ arming: Settlement.Arming
    ) async -> Navigation.ViewportExit.Outcome {
        let viewportExit = await lifecycle.finalize()
        await vault.semanticObservationStream.storeOwner.settlementDidFinish(
            at: arming.boundary.moment
        )
        return viewportExit
    }

    @MainActor
    internal func dispatch(
        _ command: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult {
        await dispatchAction(command)
    }

    @MainActor
    internal func dispatchDidComplete() async {
        lifecycle.dispatchDidComplete(
            visibleRefreshBoundary: vault.semanticObservationStream.visibleRefreshBoundary()
        )
    }

    internal func elapsed() async -> ElapsedMilliseconds {
        RuntimeElapsed.milliseconds(since: startedAt)
    }
}

@MainActor
internal final class LiveSettlementLifecycle {
    private struct ObservationEffect {
        let control: Settlement.ObservationEffectControl
        let task: Task<Navigation.ViewportExit.Outcome, Never>
    }

    private struct ActiveResources {
        var demand: SemanticObservationDemand
        var notificationWindow: AccessibilityNotificationScopeLease?
        let boundary: Observation.Moment
        var notificationOutcome = AccessibilityNotificationScopeOutcome.released
        var observationSubscription: SemanticObservationSubscription?
        var tasks: [Task<Void, Never>] = []
        var observationEffect: ObservationEffect?
        var readinessTask: Task<Void, Never>?
        var deadlineTask: Task<Void, Never>?
        var dispatchVisibleRefreshBoundary: Observation.Stream.VisibleRefreshBoundary?
    }

    private struct FinalizationResources {
        var demand: SemanticObservationDemand
        var notificationWindow: AccessibilityNotificationScopeLease?
        var notificationOutcome: AccessibilityNotificationScopeOutcome
    }

    private struct Quiescence {
        let completion: Task<Navigation.ViewportExit.Outcome, Never>
        let finalization: FinalizationResources
    }

    private struct Quiesced {
        let viewportExit: Navigation.ViewportExit.Outcome
        let finalization: FinalizationResources
    }

    private enum Phase {
        case idle
        case active(ActiveResources)
        case quiescing(Quiescence)
        case quiesced(Quiesced)
        case finalized(Navigation.ViewportExit.Outcome)
    }

    private var phase = Phase.idle

    func begin(
        demand: SemanticObservationDemand,
        notificationWindow: AccessibilityNotificationScopeLease,
        boundary: Observation.Moment
    ) {
        guard case .idle = phase else {
            preconditionFailure("Settlement lifecycle is already active")
        }
        phase = .active(ActiveResources(
            demand: demand,
            notificationWindow: notificationWindow,
            boundary: boundary
        ))
    }

    func retain(_ subscription: SemanticObservationSubscription) {
        guard case .active(var resources) = phase else { return }
        precondition(
            resources.observationSubscription == nil,
            "Settlement observation is already armed"
        )
        resources.observationSubscription = subscription
        phase = .active(resources)
    }

    func retain(_ task: Task<Void, Never>) {
        guard case .active(var resources) = phase else {
            task.cancel()
            return
        }
        resources.tasks.append(task)
        phase = .active(resources)
    }

    func retainObservationEffect(
        control: Settlement.ObservationEffectControl,
        task: Task<Navigation.ViewportExit.Outcome, Never>
    ) {
        guard case .active(var resources) = phase else {
            preconditionFailure("Settlement observation effects require an active lifecycle")
        }
        precondition(
            resources.observationEffect == nil,
            "Settlement observation effects are already armed"
        )
        resources.observationEffect = ObservationEffect(control: control, task: task)
        phase = .active(resources)
    }

    internal func armReadiness(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard case .active(var resources) = phase else { return }
        precondition(resources.readinessTask == nil, "Settlement readiness is already armed")
        let task = Task { await operation() }
        resources.readinessTask = task
        phase = .active(resources)
    }

    internal func dispatchDidComplete(
        visibleRefreshBoundary: Observation.Stream.VisibleRefreshBoundary
    ) {
        guard case .active(var resources) = phase else { return }
        resources.dispatchVisibleRefreshBoundary = visibleRefreshBoundary
        phase = .active(resources)
    }

    internal func visibleRefreshBoundaryAfterDispatch() -> Observation.Stream.VisibleRefreshBoundary? {
        guard case .active(let resources) = phase else { return nil }
        return resources.dispatchVisibleRefreshBoundary
    }

    internal var boundaryMoment: Observation.Moment? {
        guard case .active(let resources) = phase else { return nil }
        return resources.boundary
    }

    internal func replaceDeadline(_ task: Task<Void, Never>) {
        guard case .active(var resources) = phase else {
            task.cancel()
            return
        }
        resources.deadlineTask?.cancel()
        resources.deadlineTask = task
        phase = .active(resources)
    }

    internal func captureNotificationBatch() -> AccessibilityNotificationBatch? {
        guard case .active(let resources) = phase else { return nil }
        return resources.notificationWindow?.capture()
    }

    internal func requestNotificationWindowConsumption() {
        guard case .active(var resources) = phase else { return }
        resources.notificationOutcome = .consumed
        phase = .active(resources)
    }

    internal func quiesce() async -> Navigation.ViewportExit.Outcome {
        let quiescence: Quiescence
        switch phase {
        case .active(let resources):
            resources.tasks.forEach { $0.cancel() }
            resources.readinessTask?.cancel()
            resources.deadlineTask?.cancel()
            resources.observationSubscription?.cancel()
            resources.observationEffect?.control.requestStop()
            let completion = Task {
                let viewportExit = await resources.observationEffect?.task.value ?? .restored
                await resources.readinessTask?.value
                await resources.deadlineTask?.value
                for task in resources.tasks {
                    await task.value
                }
                return viewportExit
            }
            quiescence = Quiescence(
                completion: completion,
                finalization: FinalizationResources(
                    demand: resources.demand,
                    notificationWindow: resources.notificationWindow,
                    notificationOutcome: resources.notificationOutcome
                )
            )
            phase = .quiescing(quiescence)
        case .quiescing(let existing):
            quiescence = existing
        case .quiesced(let quiesced):
            return quiesced.viewportExit
        case .finalized(let viewportExit):
            return viewportExit
        case .idle:
            return .restored
        }

        let viewportExit = await quiescence.completion.value
        if case .quiescing = phase {
            phase = .quiesced(.init(
                viewportExit: viewportExit,
                finalization: quiescence.finalization
            ))
        }
        return viewportExit
    }

    internal func finalize() async -> Navigation.ViewportExit.Outcome {
        let viewportExit = await quiesce()
        guard case .quiesced(let quiesced) = phase else { return viewportExit }
        switch quiesced.finalization.notificationOutcome {
        case .consumed:
            quiesced.finalization.notificationWindow?.consume()
        case .released:
            quiesced.finalization.notificationWindow?.cancel()
        }
        quiesced.finalization.demand.cancel()
        phase = .finalized(viewportExit)
        return viewportExit
    }
}

@MainActor
extension TheBrains {
    internal func executeSettlementCommand(
        _ command: Settlement.Command
    ) async -> Settlement.Result {
        let observationEffects: LiveSettlementExecutionBoundary.ObservationEffects
        switch command {
        case .observation(let predicate, let deadline, _):
            let start = RuntimeElapsed.now
            let discoveryDeadline = SemanticObservationDeadline(
                start: start,
                timeoutSeconds: deadline.remainingDuration(at: start) / .seconds(1)
            )
            observationEffects = { control in
                if case .announcement = predicate.resolved { return .restored }
                return await self.navigation.exploreForWait(
                    target: predicate.resolved.singularTarget,
                    deadline: discoveryDeadline,
                    stopWhen: { control.stopRequested }
                )
            }
        case .currentState, .action:
            observationEffects = { _ in .restored }
        }

        return await Settlement.Executor(boundary: LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: tripwire,
            dispatch: { command in
                await self.dispatchRuntimeAction(command)
            },
            observationEffects: observationEffects
        )).execute(command)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
