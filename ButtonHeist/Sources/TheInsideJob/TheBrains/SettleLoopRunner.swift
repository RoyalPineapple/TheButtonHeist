#if canImport(UIKit)
#if DEBUG
import Foundation

struct SettleLoopRunner {
    let parseProvider: SettleSession.ParseProvider
    let tripwireSignalProvider: SettleSession.TripwireSignalProvider
    let observationYield: SettleSession.ObservationYield
    let uikitIdleWait: SettleSession.UIKitIdleWait?
    let presentationIsSettled: SettleSession.PresentationSettled
    let clock: SettleSession.Clock
    let timeoutMs: Int
    let initial: SettleLoopMachine.State

    @MainActor
    func run(start: RuntimeElapsed.Instant) async -> SettleSession.Result {
        let deadline = SemanticObservationDeadline(start: start, timeoutMs: timeoutMs)
        var observations = SettleObservationLedger()
        let machine = SettleLoopMachine()
        var state = initial

        func reduce(_ event: SettleLoopMachine.Event) -> SettleLoopTransition {
            let transition = machine.reduce(state, event: event)
            state = transition.state
            return transition
        }

        func ingest(_ observation: InterfaceObservation) -> SettleSession.Result? {
            let recorded = observations.record(observation)
            let transition = reduce(
                .observation(
                    recorded.sample,
                    elapsedMs: deadline.elapsedMilliseconds(at: clock())
                )
            )
            guard case .terminal(let outcome) = transition.decision else { return nil }
            guard presentationAdmitsSettlement(transition.state, deadline: deadline) else { return nil }
            return SettleSession.result(
                outcome: outcome,
                state: transition.state,
                observations: observations
            )
        }

        func result(_ outcome: SettleOutcome) -> SettleSession.Result {
            return SettleSession.result(
                outcome: outcome,
                state: state,
                observations: observations
            )
        }

        if let initial = parseProvider(), let outcome = ingest(initial) {
            return outcome
        }

        guard deadline.hasTimeRemaining(at: clock()) else {
            return result(.timedOut(timeMs: deadline.elapsedMilliseconds(at: clock())))
        }

        let source = SettleLoopEventSource()
        requestHeartbeat(from: source, deadline: deadline)
        var idleTask: Task<Void, Never>?
        defer {
            idleTask?.cancel()
            source.cancel()
        }

        for await event in source.events {
            switch event {
            case .heartbeat(let heartbeat):
                source.consumeHeartbeat()
                if let outcome = evaluateHeartbeat(heartbeat, deadline: deadline) {
                    return result(outcome)
                }
                if idleTask == nil {
                    idleTask = startIdleTask(deadline: deadline, continuation: source.continuation)
                }

                if observeTripwire(machine: machine, state: &state, observations: &observations) {
                    requestHeartbeat(from: source, deadline: deadline)
                    continue
                }

                guard let parse = parseProvider() else {
                    requestHeartbeat(from: source, deadline: deadline)
                    continue
                }
                if let outcome = ingest(parse) {
                    return outcome
                }
                requestHeartbeat(from: source, deadline: deadline)

            case .uikitIdle:
                idleTask = nil
                source.cancelHeartbeat()
                _ = observeTripwire(machine: machine, state: &state, observations: &observations)

                let heartbeat = await observationYield(
                    deadline.remainingDuration(at: clock())
                )
                if let outcome = evaluateHeartbeat(heartbeat, deadline: deadline) {
                    return result(outcome)
                }

                if observeTripwire(machine: machine, state: &state, observations: &observations) {
                    requestHeartbeat(from: source, deadline: deadline)
                    continue
                }
                guard await uikitIdleWait?(.zero) == true else {
                    idleTask = startIdleTask(deadline: deadline, continuation: source.continuation)
                    requestHeartbeat(from: source, deadline: deadline)
                    continue
                }
                _ = reduce(.uikitIdle)
                guard let parse = parseProvider() else {
                    requestHeartbeat(from: source, deadline: deadline)
                    continue
                }
                if let outcome = ingest(parse) {
                    return outcome
                }
                requestHeartbeat(from: source, deadline: deadline)
            }
        }

        return result(await evaluateCompletion(source: source, deadline: deadline))
    }

    @MainActor
    private func presentationAdmitsSettlement(
        _ state: SettleLoopMachine.State,
        deadline: SemanticObservationDeadline
    ) -> Bool {
        state.settlementEvidence != .accessibilityQuietWindow
            || deadline.elapsedMilliseconds(at: clock()) >= SettleSession.presentationSettleGraceMs
            || presentationIsSettled()
    }

    @MainActor
    private func observeTripwire(
        machine: SettleLoopMachine,
        state: inout SettleLoopMachine.State,
        observations: inout SettleObservationLedger
    ) -> Bool {
        let transition = machine.reduce(
            state,
            event: .tripwireSignal(tripwireSignalProvider())
        )
        state = transition.state
        guard transition.decision == .baselineReset else { return false }
        observations.resetCurrentGeneration()
        return true
    }

    @MainActor
    private func evaluateCompletion(
        source: SettleLoopEventSource,
        deadline: SemanticObservationDeadline
    ) async -> SettleOutcome {
        if Task.isCancelled {
            await source.cancelHeartbeatAndWait()
        }
        let elapsedMs = deadline.elapsedMilliseconds(at: clock())
        return Task.isCancelled ? .cancelled(timeMs: elapsedMs) : .timedOut(timeMs: elapsedMs)
    }

    @MainActor
    private func evaluateHeartbeat(
        _ heartbeat: TheTripwire.HeartbeatWaitOutcome,
        deadline: SemanticObservationDeadline
    ) -> SettleOutcome? {
        let elapsedMs = deadline.elapsedMilliseconds(at: clock())
        if heartbeat == .cancelled || Task.isCancelled {
            return .cancelled(timeMs: elapsedMs)
        }
        return heartbeat == .observed ? nil : .timedOut(timeMs: elapsedMs)
    }

    @MainActor
    private func requestHeartbeat(
        from source: SettleLoopEventSource,
        deadline: SemanticObservationDeadline
    ) {
        guard deadline.hasTimeRemaining(at: clock()) else {
            source.continuation.yield(.heartbeat(.timedOut))
            return
        }
        source.requestHeartbeat {
            await observationYield(deadline.remainingDuration(at: clock()))
        }
    }

    @MainActor
    private func startIdleTask(
        deadline: SemanticObservationDeadline,
        continuation: AsyncStream<SettleLoopEvent>.Continuation
    ) -> Task<Void, Never>? {
        uikitIdleWait.map { waitForIdle in
            Task { @MainActor in
                guard await waitForIdle(deadline.remainingDuration(at: clock())) else { return }
                continuation.yield(.uikitIdle)
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
