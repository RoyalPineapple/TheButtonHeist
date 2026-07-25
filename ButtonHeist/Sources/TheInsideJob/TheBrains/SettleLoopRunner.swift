#if canImport(UIKit)
#if DEBUG
import Foundation

struct SettleLoopRunner {
    let parseProvider: SettleSession.ParseProvider
    let tripwireSignalProvider: SettleSession.TripwireSignalProvider
    let observationYield: SettleSession.ObservationYield
    let clock: SettleSession.Clock
    let timeoutMs: Int
    let initial: SettleLoopMachine.State

    @MainActor
    func run(start: RuntimeElapsed.Instant) async -> SettleSession.Result {
        let deadline = SemanticObservationDeadline(start: start, timeoutMs: timeoutMs)
        var observations = SettleObservationLedger()
        let machine = SettleLoopMachine()
        var state = initial

        func ingest(_ observation: InterfaceObservation) -> SettleSession.Result? {
            let recorded = observations.record(observation)
            let transition = machine.reduce(
                state,
                event: .observation(
                    recorded.sample,
                    elapsedMs: deadline.elapsedMilliseconds(at: clock())
                )
            )
            state = transition.state
            guard case .terminal(let outcome) = transition.decision else { return nil }
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
        requestTick(from: source, deadline: deadline)
        defer { source.cancel() }

        for await tick in source.events {
            source.consumeTick()
            if let outcome = evaluateTick(tick, deadline: deadline) {
                return result(outcome)
            }

            if observeTripwire(machine: machine, state: &state, observations: &observations) {
                requestTick(from: source, deadline: deadline)
                continue
            }

            guard let parse = parseProvider() else {
                requestTick(from: source, deadline: deadline)
                continue
            }
            if let outcome = ingest(parse) {
                return outcome
            }
            requestTick(from: source, deadline: deadline)
        }

        return result(await evaluateCompletion(source: source, deadline: deadline))
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
            await source.cancelTickAndWait()
        }
        let elapsedMs = deadline.elapsedMilliseconds(at: clock())
        return Task.isCancelled ? .cancelled(timeMs: elapsedMs) : .timedOut(timeMs: elapsedMs)
    }

    /// A stopped clock is not a slow app: `.unavailable` means the pulse is not
    /// running, so no further observation can arrive no matter how long the
    /// caller waits. It projects to its own outcome rather than collapsing into
    /// `.timedOut`.
    @MainActor
    private func evaluateTick(
        _ tick: TheTripwire.TickWaitOutcome,
        deadline: SemanticObservationDeadline
    ) -> SettleOutcome? {
        let elapsedMs = deadline.elapsedMilliseconds(at: clock())
        if tick == .cancelled || Task.isCancelled {
            return .cancelled(timeMs: elapsedMs)
        }
        switch tick {
        case .observed:
            return nil
        case .unavailable:
            return .clockUnavailable(timeMs: elapsedMs)
        case .timedOut, .cancelled:
            return .timedOut(timeMs: elapsedMs)
        }
    }

    @MainActor
    private func requestTick(
        from source: SettleLoopEventSource,
        deadline: SemanticObservationDeadline
    ) {
        guard deadline.hasTimeRemaining(at: clock()) else {
            source.continuation.yield(.timedOut)
            return
        }
        source.requestTick {
            await observationYield(deadline.remainingDuration(at: clock()))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
