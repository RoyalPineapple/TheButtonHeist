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
        case established(path: Path, observationBoundary: ObservationBoundary)
        case invalidated
    }
}

extension Settlement {
    internal typealias DiagnosisSink = @Sendable (Diagnosis) -> Void

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
        case observation(Observation.Event)
        case announcement(Observation.AnnouncementEvent)
        case announcementHistoryUnavailable(AccessibilityNotificationGap)
        case readiness(Readiness.Signal)
        case deadlineReached
        case cancelled
        case dispatchCompleted(TheSafecracker.ActionDispatchResult)
        case predicateEvaluated(Predicate.EvaluationResponse)
        case captureCompleted(Capture.Request, CaptureCompletion)

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

    func announcementCursor() async -> AccessibilityNotificationCursor
    func events(since moment: Observation.Moment) async -> Observation.EventsSince
    @MainActor
    func beginSettlement(_ arming: Settlement.Arming) async
    @MainActor
    func armObservations(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armAnnouncements(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armReadiness(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armDeadline(_ arming: Settlement.Arming, sink: Settlement.ExecutionSink) async
    @MainActor
    func armObservationEffects(_ arming: Settlement.Arming) async
    @MainActor
    func quiesceSettlement(_ arming: Settlement.Arming) async
    @MainActor
    func finalizeSettlement(_ arming: Settlement.Arming) async

    @MainActor
    func dispatch(
        _ command: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult

    func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) async -> PredicateEvaluationResult

    func elapsed() async -> ElapsedMilliseconds
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

        internal func observe(_ event: Observation.Event) {
            record(.observation(event))
        }

        internal func observeAnnouncement(_ event: Observation.AnnouncementEvent) {
            record(.announcement(event))
        }

        internal func observeAnnouncementHistoryUnavailable(
            _ gap: AccessibilityNotificationGap
        ) {
            record(.announcementHistoryUnavailable(gap))
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

        internal func reachDeadline() {
            record(.deadlineReached)
        }

        fileprivate func cancel() {
            record(.cancelled)
        }

        fileprivate func completeDispatch(_ result: TheSafecracker.ActionDispatchResult) {
            record(.dispatchCompleted(result))
        }

        fileprivate func completeEvaluation(_ response: Predicate.EvaluationResponse) {
            record(.predicateEvaluated(response))
        }

        fileprivate func completeCapture(
            _ request: Capture.Request,
            completion: CaptureCompletion
        ) {
            record(.captureCompleted(request, completion))
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
             .announcement,
             .announcementHistoryUnavailable,
             .deadlineReached,
             .cancelled,
             .dispatchCompleted,
             .predicateEvaluated,
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

extension Settlement {
    internal struct Executor<Boundary: SettlementExecutionBoundary>: Sendable {
        internal let boundary: Boundary
        private let diagnosisSink: Settlement.DiagnosisSink

        internal init(boundary: Boundary) {
            self.init(boundary: boundary, diagnosisSink: SettlementDiagnosisLogger.record)
        }

        internal init(
            boundary: Boundary,
            diagnosisSink: @escaping Settlement.DiagnosisSink
        ) {
            self.boundary = boundary
            self.diagnosisSink = diagnosisSink
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
            var arming: Arming?
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
                            mergeDrained(decision, state: &state, effects: &effects)
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
                            arming = requestedArming
                            let decision = await arm(requestedArming, state: state, sink: sink)
                            state = decision.state
                            effects += decision.effects
                            drainsArmingInputs = true

                        case .dispatchAction(let action):
                            tasks.addTask {
                                let result = await boundary.dispatch(action)
                                sink.completeDispatch(result)
                            }

                        case .evaluatePredicate(let request):
                            tasks.addTask {
                                let result = await boundary.evaluate(request)
                                sink.completeEvaluation(.init(target: request.target, result: result))
                            }

                        case .finish(let result):
                            sink.finish()
                            if let arming {
                                await boundary.quiesceSettlement(arming)
                            }
                            tasks.cancelAll()
                            await tasks.waitForAll()
                            if let arming {
                                await boundary.finalizeSettlement(arming)
                            }
                            diagnosisSink(Diagnosis.project(result))
                            return result
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

        private func mergeDrained(
            _ decision: Decision,
            state: inout State,
            effects: inout [Effect]
        ) {
            state = decision.state
            if state.result == nil {
                effects += decision.effects
            } else {
                effects = decision.effects
            }
        }

        private func arm(
            _ arming: Arming,
            state: State,
            sink: ExecutionSink
        ) async -> Decision {
            await boundary.beginSettlement(arming)
            await boundary.armObservations(arming, sink: sink)
            await boundary.armAnnouncements(arming, sink: sink)
            await boundary.armReadiness(arming, sink: sink)
            await boundary.armDeadline(arming, sink: sink)
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
            guard let fact = await fact(
                for: input,
                state: state,
                sink: sink,
                admittedMoments: &admittedMoments
            ) else {
                return Decision(state: state, effects: [])
            }
            if case .readinessEstablished = fact,
               state.session?.readiness.isEstablished == false {
                finalSemanticEvidence.begin()
            }
            var decision = await reduce(state, fact: fact)
            if decision.state.concludesFinalSemanticEvidence
                || fact.endsFinalSemanticEvidenceAttempt {
                if let timing = finalSemanticEvidence.complete() {
                    decision = decision.recording(timing)
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
            guard case .captureCompleted(let request, _) = input,
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
                let cursor = await boundary.announcementCursor()
                return await reduce(
                    state,
                    fact: .baselineAdmitted(.init(
                        moment: event.moment,
                        announcementCursor: cursor
                    )),
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
        ) async -> Event.Fact? {
            switch input {
            case .observation(.snapshot(let event)):
                guard let baseline = state.session?.boundary.moment,
                      event.moment != baseline,
                      event.moment.isSameOrAfter(baseline),
                      !admittedMoments.contains(event.moment) else { return nil }
                admittedMoments.append(event.moment)
                return .observationAdmitted(.init(
                    event: event,
                    history: await boundary.events(since: baseline)
                ))
            case .observation(.announcement(let event)), .announcement(let event):
                return .announcementObserved(event)
            case .announcementHistoryUnavailable(let gap):
                return .announcementHistoryUnavailable(gap)
            case .readiness(.established(let path, let observationBoundary)):
                guard let generation = state.session?.readiness.generation else { return nil }
                return .readinessEstablished(.init(
                    generation: generation,
                    path: path,
                    observationBoundary: observationBoundary
                ))
            case .readiness(.invalidated):
                guard let session = state.session,
                      case .established(let readiness) = session.readiness else { return nil }
                let generation = readiness.generation.advanced()
                sink.advanceCaptureGeneration(to: generation)
                return .readinessInvalidated(generation)
            case .deadlineReached:
                return .deadlineReached
            case .cancelled:
                return .cancelled
            case .dispatchCompleted(let result):
                return .dispatchCompleted(result)
            case .predicateEvaluated(let response):
                return .predicateEvaluated(response)
            case .captureCompleted(.baseline, _):
                preconditionFailure("Baseline capture completion cannot enter armed delivery")
            case .captureCompleted(.handoff(let request), let completion):
                switch completion.outcome {
                case .admitted(let event):
                    guard let baseline = state.session?.boundary.moment,
                          !admittedMoments.contains(event.moment) else { return nil }
                    admittedMoments.append(event.moment)
                    return .observationAdmitted(.init(
                        event: event,
                        history: await boundary.events(since: baseline),
                        source: .handoffCapture(request.readinessGeneration)
                    ))
                case .failed(let failure):
                    return .handoffCaptureFailed(request.readinessGeneration, failure)
                }
            }
        }

        private func reduce(
            _ state: State,
            fact: Event.Fact,
            timing: ExecutionTiming = ExecutionTiming()
        ) async -> Decision {
            Reducer.reduce(
                state,
                event: Event(
                    fact: fact,
                    timing: timing,
                    elapsed: await boundary.elapsed()
                )
            )
        }
    }
}

private extension Settlement.State {
    var session: Settlement.Session? {
        switch self {
        case .armed(let session),
             .dispatching(let session),
             .observing(let session),
             .needHandoff(let session):
            session
        case .awaitingBaseline, .completed, .failed, .timedOut, .cancelled:
            nil
        }
    }

    var concludesFinalSemanticEvidence: Bool {
        let handoff: Settlement.Handoff.Evidence? = switch self {
        case .armed(let session),
             .dispatching(let session),
             .observing(let session),
             .needHandoff(let session):
            session.handoff
        case .completed(let result),
             .failed(let result),
             .timedOut(let result),
             .cancelled(let result):
            result.evidence.handoff
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
        case .dispatching(var session):
            session.timing.merge(timing)
            return .dispatching(session)
        case .observing(var session):
            session.timing.merge(timing)
            return .observing(session)
        case .needHandoff(var session):
            session.timing.merge(timing)
            return .needHandoff(session)
        case .completed(let result):
            return .completed(result.recording(timing))
        case .failed(let result):
            return .failed(result.recording(timing))
        case .timedOut(let result):
            return .timedOut(result.recording(timing))
        case .cancelled(let result):
            return .cancelled(result.recording(timing))
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
             .cancelled:
            true
        case .baselineAdmitted,
             .baselineUnavailable,
             .channelsArmed,
             .dispatchCompleted,
             .observationAdmitted,
             .announcementObserved,
             .observationHistoryUnavailable,
             .announcementHistoryUnavailable,
             .predicateEvaluated,
             .readinessEstablished,
             .handoffCaptureFailed:
            false
        }
    }
}

private extension Settlement.Decision {
    func recording(_ timing: Settlement.ExecutionTiming) -> Settlement.Decision {
        Settlement.Decision(
            state: state.recording(timing),
            effects: effects.map { effect in
                guard case .finish(let result) = effect else { return effect }
                return .finish(result.recording(timing))
            }
        )
    }
}

private extension Settlement.Result {
    func recording(_ timing: Settlement.ExecutionTiming) -> Settlement.Result {
        var mergedTiming = evidence.timing
        mergedTiming.merge(timing)
        return Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: evidence.command,
                boundary: evidence.boundary,
                trigger: evidence.trigger,
                predicate: evidence.predicate,
                readiness: evidence.readiness,
                handoff: evidence.handoff,
                observationHistory: evidence.observationHistory,
                timing: mergedTiming,
                deadline: evidence.deadline
            )
        )
    }
}

internal struct LiveSettlementExecutionBoundary: SettlementExecutionBoundary {
    internal typealias CapturedObservation = Observation.SnapshotEvent
    internal typealias ActionDispatch = @MainActor @Sendable (
        ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult
    internal typealias ObservationEffects = @MainActor @Sendable (
        Settlement.ObservationEffectControl
    ) async -> Void

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

    internal func announcementCursor() async -> AccessibilityNotificationCursor {
        vault.accessibilityNotifications.cursor()
    }

    internal func events(since moment: Observation.Moment) async -> Observation.EventsSince {
        await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: moment)
        }
    }

    @MainActor
    internal func beginSettlement(_ arming: Settlement.Arming) async {
        await vault.semanticObservationStream.storeOwner.settlementDidArm(
            at: arming.boundary.moment
        )
        lifecycle.begin(
            demand: vault.semanticObservationStream.beginActiveObservationDemand(),
            notificationWindow: vault.accessibilityNotifications.beginActionWindow()
        )
    }

    @MainActor
    internal func armObservations(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        let subscription = vault.semanticObservationStream.subscribe(
            scope: arming.observationScope,
            receive: sink.observe
        )
        lifecycle.retain(subscription)
    }

    @MainActor
    internal func armAnnouncements(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        guard let predicate = command.predicate,
              case .announcement(let announcement) = predicate.resolved.core else { return }
        let notifications = vault.accessibilityNotifications
        lifecycle.retain(Task {
            let timeout = max(
                0,
                ContinuousClock.now.duration(to: arming.deadline.instant) / .seconds(1)
            )
            switch await notifications.waitForAnnouncement(
                after: arming.boundary.announcementCursor,
                matching: announcement,
                timeout: timeout
            ) {
            case .matched(let announcement):
                sink.observeAnnouncement(.init(announcement: announcement))
            case .historyUnavailable(let gap):
                sink.observeAnnouncementHistoryUnavailable(gap)
            case .timedOut:
                break
            }
        })
    }

    @MainActor
    internal func armReadiness(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        lifecycle.armReadiness(
            startAfterDispatch: !command.trigger.isObservation,
            operation: { [tripwire, vault] in
                let timeout = ContinuousClock.now.duration(to: arming.deadline.instant)
                guard timeout > .zero,
                      await tripwire.uikitIdleTracker.waitUntilIdle(timeout: timeout) else { return }
                let latest = await vault.semanticObservationStream.latestCommittedObservationMoment(
                    scope: arming.observationScope
                )
                let boundary = Settlement.Readiness.ObservationBoundary.after(
                    latest ?? arming.boundary.moment
                )
                sink.observeReadiness(.established(
                    path: .uikitIdle,
                    observationBoundary: boundary
                ))
            }
        )
    }

    @MainActor
    internal func armDeadline(
        _ arming: Settlement.Arming,
        sink: Settlement.ExecutionSink
    ) async {
        lifecycle.retain(Task {
            do {
                try await ContinuousClock().sleep(until: arming.deadline.instant)
                sink.reachDeadline()
            } catch {}
        })
    }

    @MainActor
    internal func armObservationEffects(_: Settlement.Arming) async {
        guard command.trigger.isObservation else { return }
        let control = Settlement.ObservationEffectControl()
        let task = Task {
            await publishObservationEffects(control)
            control.complete()
        }
        lifecycle.retainObservationEffect(control: control, task: task)
    }

    @MainActor
    internal func quiesceSettlement(_: Settlement.Arming) async {
        await lifecycle.quiesce()
    }

    @MainActor
    internal func finalizeSettlement(_ arming: Settlement.Arming) async {
        guard await lifecycle.finalize() else { return }
        await vault.semanticObservationStream.storeOwner.settlementDidFinish(
            at: arming.boundary.moment
        )
    }

    @MainActor
    internal func dispatch(
        _ command: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult {
        let result = await dispatchAction(command)
        lifecycle.dispatchDidComplete()
        return result
    }

    internal func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) async -> PredicateEvaluationResult {
        SettlementPredicateEvaluator.evaluate(request)
    }

    internal func elapsed() async -> ElapsedMilliseconds {
        RuntimeElapsed.milliseconds(since: startedAt)
    }
}

@MainActor
internal final class LiveSettlementLifecycle {
    private struct ObservationEffect {
        let control: Settlement.ObservationEffectControl
        let task: Task<Void, Never>
    }

    private struct ActiveResources {
        var demand: SemanticObservationDemand
        var notificationWindow: AccessibilityNotificationScopeLease?
        var notificationOutcome = AccessibilityNotificationScopeOutcome.released
        var observationSubscription: SemanticObservationSubscription?
        var tasks: [Task<Void, Never>] = []
        var observationEffect: ObservationEffect?
        var readinessTask: Task<Void, Never>?
    }

    private struct FinalizationResources {
        var demand: SemanticObservationDemand
        var notificationWindow: AccessibilityNotificationScopeLease?
        var notificationOutcome: AccessibilityNotificationScopeOutcome
    }

    private struct Quiescence {
        let completion: Task<Void, Never>
        let finalization: FinalizationResources
    }

    private enum Phase {
        case idle
        case active(ActiveResources)
        case quiescing(Quiescence)
        case quiesced(FinalizationResources)
        case finalized
    }

    private var phase = Phase.idle
    private let dispatchCompletion: AsyncStream<Void>
    private let dispatchCompletionContinuation: AsyncStream<Void>.Continuation

    internal init() {
        let dispatchCompletion = AsyncStream<Void>.makeStream()
        self.dispatchCompletion = dispatchCompletion.stream
        self.dispatchCompletionContinuation = dispatchCompletion.continuation
    }

    func begin(
        demand: SemanticObservationDemand,
        notificationWindow: AccessibilityNotificationScopeLease
    ) {
        guard case .idle = phase else {
            preconditionFailure("Settlement lifecycle is already active")
        }
        phase = .active(ActiveResources(
            demand: demand,
            notificationWindow: notificationWindow
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
        task: Task<Void, Never>
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
        startAfterDispatch: Bool,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard case .active(var resources) = phase else { return }
        precondition(resources.readinessTask == nil, "Settlement readiness is already armed")
        let dispatchCompletion = self.dispatchCompletion
        let task = Task {
            if startAfterDispatch {
                var didDispatch = false
                for await _ in dispatchCompletion {
                    didDispatch = true
                    break
                }
                guard didDispatch, !Task.isCancelled else { return }
            }
            await operation()
        }
        resources.readinessTask = task
        resources.tasks.append(task)
        phase = .active(resources)
    }

    internal func dispatchDidComplete() {
        guard case .active = phase else { return }
        dispatchCompletionContinuation.yield()
        dispatchCompletionContinuation.finish()
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

    internal func quiesce() async {
        let quiescence: Quiescence
        switch phase {
        case .active(let resources):
            dispatchCompletionContinuation.finish()
            resources.tasks.forEach { $0.cancel() }
            resources.observationSubscription?.cancel()
            resources.observationEffect?.control.requestStop()
            let completion = Task {
                await resources.observationEffect?.task.value
                for task in resources.tasks {
                    await task.value
                }
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
        case .idle, .quiesced, .finalized:
            return
        }

        await quiescence.completion.value
        if case .quiescing = phase {
            phase = .quiesced(quiescence.finalization)
        }
    }

    internal func finalize() async -> Bool {
        await quiesce()
        guard case .quiesced(let resources) = phase else { return false }
        switch resources.notificationOutcome {
        case .consumed:
            resources.notificationWindow?.consume()
        case .released:
            resources.notificationWindow?.cancel()
        }
        resources.demand.cancel()
        phase = .finalized
        return true
    }
}

private enum SettlementPredicateEvaluator {
    static func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) -> PredicateEvaluationResult {
        switch request.evidence {
        case .currentState(let event):
            return evaluate(request.predicate, trace: event.trace, completeness: .incomplete)
        case .positiveTransition(let event):
            return evaluate(request.predicate, trace: event.trace, completeness: .complete)
        case .announcement(let event):
            guard case .announcement(let announcement) = request.predicate.resolved.core else {
                preconditionFailure("Announcement evidence requires an announcement predicate")
            }
            return PredicateEvaluationResult(
                met: announcement.matches(event.announcement.text),
                actual: event.announcement.text
            )
        case .completeHistory(let evidence):
            return evaluateCompleteHistory(request.predicate, evidence: evidence)
        }
    }

    private static func evaluate(
        _ predicate: Settlement.Predicate,
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> PredicateEvaluationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return PredicateEvaluationResult(met: false, actual: "no observed accessibility trace")
        }
        return predicate.resolved.evaluate(in: evidence)
    }

    private static func evaluateCompleteHistory(
        _ predicate: Settlement.Predicate,
        evidence: Settlement.Predicate.CompleteHistoryEvidence
    ) -> PredicateEvaluationResult {
        guard case .events(let events) = evidence.history else {
            return PredicateEvaluationResult(met: false, actual: "observation history unavailable")
        }
        let captures = events.compactMap { event -> AccessibilityTrace.Capture? in
            guard case .snapshot(let snapshot) = event else { return nil }
            return snapshot.trace.captures.last
        }
        let trace = captures.isEmpty ? evidence.handoff.trace : AccessibilityTrace(captures: captures)
        return evaluate(predicate, trace: trace, completeness: .complete)
    }
}

private extension Settlement.Trigger {
    var isObservation: Bool {
        if case .observation = self { return true }
        return false
    }
}

private enum SettlementDiagnosisLogger {
    static func record(_ diagnosis: Settlement.Diagnosis) {
        insideJobLogger.info("\(diagnosis.description, privacy: .public)")
    }
}

@MainActor
extension TheBrains {
    internal func executeSettlement(
        _ command: Settlement.Command,
        observationEffects: @escaping LiveSettlementExecutionBoundary.ObservationEffects = { _ in },
        dispatch: @escaping LiveSettlementExecutionBoundary.ActionDispatch
    ) async -> Settlement.Result {
        await Settlement.Executor(boundary: LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: tripwire,
            dispatch: dispatch,
            observationEffects: observationEffects
        )).execute(command)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
