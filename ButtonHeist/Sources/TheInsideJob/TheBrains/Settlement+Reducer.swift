#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension Settlement {
    internal enum Reducer {
        internal static func begin(_ command: Command) -> Decision {
            if case .currentState(let scope) = command {
                return Decision(
                    state: .awaitingBaseline(command),
                    effects: [.capture(.baseline(scope))]
                )
            }
            guard let baseline = command.baseline else {
                preconditionFailure("Timed settlement command requires a baseline")
            }
            switch baseline {
            case .capture:
                return Decision(
                    state: .awaitingBaseline(command),
                    effects: [.capture(.baseline(command.observationScope))]
                )
            case .supplied(let boundary):
                return armed(command, boundary: boundary)
            case .unavailable(let failure):
                return terminalBeforeBaseline(
                    command: command,
                    boundary: .unavailable(failure),
                    failure: .baselineUnavailable,
                    timing: ExecutionTiming(),
                    elapsed: 0
                )
            }
        }

        internal static func reduce(_ state: State, event: Event) -> Decision {
            switch state {
            case .awaitingBaseline(let command):
                reduceAwaitingBaseline(command, event: event)
            case .armed(let session):
                reduceArmed(session, event: event)
            case .active(let session):
                reduceActive(session, event: event)
            case .finalizing(let finalization):
                reduceFinalizing(finalization, event: event)
            case .terminal:
                Decision(state: state, effects: [])
            }
        }

        private static func armed(
            _ command: Command,
            boundary: EvidenceBoundary,
            timing: ExecutionTiming = ExecutionTiming()
        ) -> Decision {
            Decision(
                state: .armed(Session(
                    command: command,
                    boundary: boundary,
                    timing: timing
                )),
                effects: [.arm(Arming(
                    boundary: boundary,
                    observationScope: command.observationScope
                ))]
            )
        }
    }
}

private extension Settlement.Reducer {
    static func reduceAwaitingBaseline(
        _ command: Settlement.Command,
        event: Settlement.Event
    ) -> Settlement.Decision {
        switch event.fact {
        case .baselineAdmitted(let snapshot):
            if case .currentState = command {
                return terminalCurrentState(
                    command: command,
                    event: snapshot,
                    timing: event.timing,
                    elapsed: event.elapsed
                )
            }
            return armed(
                command,
                boundary: Settlement.EvidenceBoundary(moment: snapshot.moment),
                timing: event.timing
            )
        case .baselineUnavailable(let failure):
            return terminalBeforeBaseline(
                command: command,
                boundary: .unavailable(failure),
                failure: .baselineUnavailable,
                timing: event.timing,
                elapsed: event.elapsed
            )
        case .cancelled:
            return terminalBeforeBaseline(
                command: command,
                boundary: .pending,
                failure: .cancelled,
                timing: event.timing,
                elapsed: event.elapsed
            )
        case .deadlineReached:
            return Settlement.Decision(state: .awaitingBaseline(command), effects: [])
        case .channelsArmed,
             .dispatchCompleted,
             .observationAdmitted,
             .announcementObserved,
             .observationHistoryUnavailable,
             .announcementHistoryUnavailable,
             .readinessEstablished,
             .readinessInvalidated,
             .handoffCaptureFailed,
             .finalized:
            preconditionFailure("Settlement received armed evidence before baseline admission")
        }
    }

    static func reduceArmed(
        _ session: Settlement.Session,
        event: Settlement.Event
    ) -> Settlement.Decision {
        switch event.fact {
        case .channelsArmed:
            switch session.command {
            case .action(let action):
                return Settlement.Decision(
                    state: .active(session),
                    effects: [.dispatchAction(action.command)]
                )
            case .observation:
                guard let deadline = session.phase.deadline else {
                    preconditionFailure("Observation settlement requires a deadline")
                }
                return Settlement.Decision(
                    state: .active(session),
                    effects: [
                        .armReadiness(deadline),
                        .armDeadline(deadline),
                    ]
                )
            case .currentState:
                preconditionFailure("Current-state capture cannot enter channel arming")
            }
        case .deadlineReached:
            return Settlement.Decision(state: .armed(session), effects: [])
        case .cancelled:
            return finalizing(session, outcome: .cancelled, elapsed: event.elapsed)
        case .baselineAdmitted,
             .baselineUnavailable,
             .dispatchCompleted,
             .observationAdmitted,
             .announcementObserved,
             .observationHistoryUnavailable,
             .announcementHistoryUnavailable,
             .readinessEstablished,
             .readinessInvalidated,
             .handoffCaptureFailed,
             .finalized:
            preconditionFailure("Settlement received active evidence before channel arming completed")
        }
    }

    static func reduceActive(
        _ original: Settlement.Session,
        event: Settlement.Event
    ) -> Settlement.Decision {
        var session = original
        session.timing.merge(event.timing)
        var effects: [Settlement.Effect] = []

        switch event.fact {
        case .dispatchCompleted(let result):
            guard case .awaitingActionDispatch = session.phase,
                  case .actionPending = session.triggerEvidence,
                  case .action(let action) = session.command else {
                return Settlement.Decision(state: .active(session), effects: [])
            }
            session.triggerEvidence = .actionDispatched(result)
            let deadline = Settlement.PhaseDeadline(
                phase: .actionReadiness,
                instant: event.instant.advanced(by: action.allowances.readiness)
            )
            session.phase = .actionReadiness(deadline)
            effects = [
                .armReadiness(deadline),
                .armDeadline(deadline),
            ]
        case .observationAdmitted(let admission):
            effects += admit(admission, to: &session)
        case .announcementObserved(let announcement):
            effects += observe(announcement, in: &session)
        case .observationHistoryUnavailable:
            // Missing history is not its own failure: a predicate that never
            // saw the evidence it needed simply never drained, and the timeout
            // says so.
            break
        case .announcementHistoryUnavailable:
            break
        case .readinessEstablished(let establishment):
            effects += establishReadiness(establishment, in: &session)
        case .readinessInvalidated(let generation):
            invalidateReadiness(through: generation, in: &session)
        case .handoffCaptureFailed(let generation, let failure):
            recordHandoffCaptureFailure(failure, generation: generation, in: &session)
        case .deadlineReached(let reached):
            guard session.phase.deadline == reached else {
                return Settlement.Decision(state: .active(session), effects: [])
            }
            if session.triggerEvidence.dispatchFailed {
                return finalizing(
                    session,
                    outcome: .dispatchFailed,
                    elapsed: event.elapsed
                )
            }
            return finalizing(
                session,
                outcome: .timedOut(reached.phase),
                elapsed: event.elapsed
            )
        case .cancelled:
            return finalizing(session, outcome: .cancelled, elapsed: event.elapsed)
        case .baselineAdmitted, .baselineUnavailable, .channelsArmed, .finalized:
            preconditionFailure("Settlement received a bootstrap event after channel arming")
        }

        if let outcome = completedOutcome(session) {
            return finalizing(session, outcome: outcome, elapsed: event.elapsed)
        }
        effects += admitExpectationPhaseIfNeeded(in: &session)
        return Settlement.Decision(state: .active(session), effects: effects)
    }
}

private extension Settlement.Reducer {
    static func admit(
        _ admission: Settlement.ObservationAdmission,
        to session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        session.latestObservation = admission
        session.tickLog.append(admission.tick)
        session.requirement.expectation = session.requirement.expectation.folding([admission.tick])
        if case .established(let readiness) = session.readiness,
           session.command.waitsForObservation
               || session.requirement.predicate?.semantics == .currentState
               || session.handoff.admission == nil,
           let handoff = Settlement.Handoff.Admission.admit(admission, for: readiness) {
            session.handoff = .admitted(handoff)
        }
        return []
    }

    static func observe(
        _ event: Observation.AnnouncementEvent,
        in session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard event.announcement.sequence > session.boundary.announcementCursor.sequence,
              !session.triggerEvidence.dispatchFailed else { return [] }
        let tick = Tick.announcement(event.announcement.text)
        session.tickLog.append(tick)
        session.requirement.expectation = session.requirement.expectation.folding([tick])
        return []
    }
}

private extension Settlement.Reducer {
    static func establishReadiness(
        _ establishment: Settlement.Readiness.Establishment,
        in session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard establishment.generation == session.readiness.generation else { return [] }
        if case .established = session.readiness { return [] }

        session.readiness = .established(establishment)
        if let latestObservation = session.latestObservation,
           let handoff = Settlement.Handoff.Admission.admit(
               latestObservation,
               for: establishment
           ) {
            session.handoff = .admitted(handoff)
        } else {
            let request = Settlement.Capture.HandoffRequest(
                scope: session.command.observationScope,
                readinessGeneration: establishment.generation
            )
            session.handoff = .captureRequested(request)
        }

        guard case .captureRequested(let request) = session.handoff else { return [] }
        return [.capture(.handoff(request))]
    }

    static func invalidateReadiness(
        through generation: Settlement.Readiness.Generation,
        in session: inout Settlement.Session
    ) {
        guard generation > session.readiness.generation else { return }
        session.readiness = .pending(generation)
        session.handoff = .pending(generation)
    }

    static func recordHandoffCaptureFailure(
        _ failure: Settlement.Capture.Failure,
        generation: Settlement.Readiness.Generation,
        in session: inout Settlement.Session
    ) {
        guard case .established(let readiness) = session.readiness,
              readiness.generation == generation,
              case .captureRequested = session.handoff else { return }
        session.handoff = .captureFailed(generation, failure)
    }
}

private extension Settlement.Reducer {
    /// The settle rule, in full.
    ///
    /// A session completes when readiness is established, the handoff belongs to
    /// that readiness, and every predicate has matched — stillness among them,
    /// last, so an empty list already means the tree stopped after what the caller
    /// asked for happened.
    ///
    /// What remains here is ownership: whether this evidence is this run's, and
    /// whether the action it was waiting on ever went out. Every event asks,
    /// because readiness arriving can complete a run whose predicates matched
    /// before it.
    static func completedOutcome(_ session: Settlement.Session) -> Settlement.TerminalIntent? {
        guard case .established(let readiness) = session.readiness,
              let handoff = session.handoff.admission,
              handoff.belongs(to: readiness) else { return nil }
        if session.triggerEvidence.dispatchFailed { return .dispatchFailed }
        guard session.triggerEvidence.permitsCompletion,
              session.requirement.expectation.isMet else { return nil }
        return .settled
    }

    /// Moves an action into its expectation phase, arming that phase's deadline.
    ///
    /// Reached once the settle check has declined, so the run is still going and
    /// the deadline bounds how long it waits.
    static func admitExpectationPhaseIfNeeded(
        in session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard case .actionReadiness = session.phase,
              case .action(let action) = session.command,
              let allowance = action.allowances.expectation,
              session.triggerEvidence.permitsCompletion,
              let handoff = session.handoff.admission
        else { return [] }
        let deadline = Settlement.PhaseDeadline(
            phase: .actionExpectation,
            instant: handoff.instant.advanced(by: allowance)
        )
        session.phase = .actionExpectation(deadline)
        return [.armDeadline(deadline)]
    }
}

private extension Settlement.Reducer {
    static func finalizing(
        _ session: Settlement.Session,
        outcome: Settlement.TerminalIntent,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        Settlement.Decision(
            state: .finalizing(.init(
                session: session,
                intendedOutcome: outcome,
                elapsed: elapsed
            )),
            effects: [.finalize(.init(
                boundary: session.boundary,
                observationScope: session.command.observationScope
            ))]
        )
    }

    static func reduceFinalizing(
        _ finalization: Settlement.Finalization,
        event: Settlement.Event
    ) -> Settlement.Decision {
        guard case .finalized(let viewportExit) = event.fact else {
            return Settlement.Decision(state: .finalizing(finalization), effects: [])
        }
        switch viewportExit {
        case .restored, .retained, .superseded:
            return terminal(
                finalization.session,
                intent: finalization.intendedOutcome,
                elapsed: finalization.elapsed
            )
        case .failed(let failure):
            return terminal(
                finalization.session,
                viewportExitFailure: failure,
                elapsed: finalization.elapsed
            )
        }
    }

    static func terminal(
        _ session: Settlement.Session,
        intent: Settlement.TerminalIntent,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        let result = result(session, intent: intent, elapsed: elapsed)
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminal(
        _ session: Settlement.Session,
        viewportExitFailure: Navigation.ViewportExit.Failure,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        let timing = Settlement.Result.Timing(execution: session.timing, elapsed: elapsed)
        let result: Settlement.Result = switch session.command {
        case .observation(let predicate, _, _):
            .observation(.failed(.init(
                reason: .viewportExitFailed(viewportExitFailure),
                attempt: observationAttempt(session, predicate: predicate, timing: timing)
            )))
        case .action(let command):
            .action(.failed(.init(
                reason: .viewportExitFailed(viewportExitFailure),
                attempt: actionAttempt(session, command: command, timing: timing)
            )))
        case .currentState:
            preconditionFailure("Current-state capture cannot own viewport effects")
        }
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminalBeforeBaseline(
        command: Settlement.Command,
        boundary: Settlement.BoundaryEvidence,
        failure: BootstrapFailure,
        timing: Settlement.ExecutionTiming,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        let resultTiming = Settlement.Result.Timing(execution: timing, elapsed: elapsed)
        let result: Settlement.Result
        switch command {
        case .currentState:
            let reason: Settlement.Result.CurrentStateFailureReason = switch failure {
            case .baselineUnavailable:
                .unavailable(boundary.captureFailure ?? .unavailable)
            case .cancelled:
                .cancelled
            }
            result = .currentState(.failed(.init(
                reason: reason,
                timing: resultTiming
            )))
        case .observation(let predicate, _, _):
            result = .observation(.failed(.init(
                reason: failure.observationReason,
                attempt: .init(
                    predicate: predicate,
                    boundary: boundary,
                    outstanding: Expectation([predicate.resolved]).outstanding,
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    // Nothing was observed: a run that died before its baseline
                    // has an empty log, not a missing one.
                    tickLog: TickLog(),
                    latestObservation: nil,
                    timing: resultTiming
                )
            )))
        case .action(let command):
            result = .action(.failed(.init(
                reason: failure.actionReason,
                attempt: .init(
                    command: command,
                    boundary: boundary,
                    dispatch: .pending,
                    outstanding: Expectation(command.predicate.map { [$0.resolved] } ?? []).outstanding,
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    // Nothing was observed: a run that died before its baseline
                    // has an empty log, not a missing one.
                    tickLog: TickLog(),
                    latestObservation: nil,
                    timing: resultTiming
                )
            )))
        }
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminalCurrentState(
        command: Settlement.Command,
        event: Observation.SnapshotEvent,
        timing: Settlement.ExecutionTiming,
        elapsed: ElapsedMilliseconds = RuntimeElapsed.admit(milliseconds: 0)
    ) -> Settlement.Decision {
        guard case .currentState = command else {
            preconditionFailure("Current-state terminal result requires a current-state command")
        }
        let result = Settlement.Result.currentState(.captured(.init(
            event: event,
            timing: .init(execution: timing, elapsed: elapsed)
        )))
        return Settlement.Decision(state: .terminal(result), effects: [])
    }
}

private extension Settlement.Reducer {
    enum BootstrapFailure {
        case baselineUnavailable
        case cancelled

        var observationReason: Settlement.Result.ObservationFailureReason {
            switch self {
            case .baselineUnavailable: .baselineUnavailable
            case .cancelled: .cancelled
            }
        }

        var actionReason: Settlement.Result.ActionFailureReason {
            switch self {
            case .baselineUnavailable: .baselineUnavailable
            case .cancelled: .cancelled
            }
        }
    }

    static func result(
        _ session: Settlement.Session,
        intent: Settlement.TerminalIntent,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Result {
        let timing = Settlement.Result.Timing(execution: session.timing, elapsed: elapsed)
        switch session.command {
        case .observation(let predicate, _, _):
            let attempt = observationAttempt(session, predicate: predicate, timing: timing)
            guard intent == .settled else {
                return .observation(.failed(.init(
                    reason: observationFailure(intent),
                    attempt: attempt
                )))
            }
            guard case .established(let readiness) = session.readiness,
                  let handoff = session.handoff.admission,
                  handoff.belongs(to: readiness) else {
                preconditionFailure("Settled observation requires admitted terminal evidence")
            }
            return .observation(.settled(.init(
                predicate: predicate,
                boundary: session.boundary,
                readiness: readiness,
                handoff: handoff,
                tickLog: session.tickLog,
                timing: timing
            )))

        case .action(let command):
            let attempt = actionAttempt(session, command: command, timing: timing)
            guard intent == .settled else {
                return .action(.failed(.init(
                    reason: actionFailure(intent),
                    attempt: attempt
                )))
            }
            guard case .actionDispatched(let dispatch) = session.triggerEvidence,
                  dispatch.success,
                  case .established(let readiness) = session.readiness,
                  let handoff = session.handoff.admission,
                  handoff.belongs(to: readiness) else {
                preconditionFailure("Settled action requires dispatch and admitted terminal evidence")
            }
            return .action(.settled(.init(
                command: command,
                boundary: session.boundary,
                dispatch: dispatch,
                readiness: readiness,
                handoff: handoff,
                tickLog: session.tickLog,
                timing: timing
            )))

        case .currentState:
            preconditionFailure("Current-state capture cannot create a settlement session")
        }
    }

    static func observationAttempt(
        _ session: Settlement.Session,
        predicate: Settlement.Predicate,
        timing: Settlement.Result.Timing
    ) -> Settlement.Result.ObservationAttempt {
        .init(
            predicate: predicate,
            boundary: .established(session.boundary),
            outstanding: session.requirement.expectation.outstanding,
            readiness: session.readiness,
            handoff: session.handoff,
            tickLog: session.tickLog,
            latestObservation: session.latestObservation?.event,
            timing: timing
        )
    }

    static func actionAttempt(
        _ session: Settlement.Session,
        command: Settlement.Command.Action,
        timing: Settlement.Result.Timing
    ) -> Settlement.Result.ActionAttempt {
        let dispatch: Settlement.Result.ActionDispatch = switch session.triggerEvidence {
        case .actionPending:
            .pending
        case .actionDispatched(let result):
            .completed(result)
        case .observation:
            preconditionFailure("Action settlement requires action dispatch evidence")
        }
        return .init(
            command: command,
            boundary: .established(session.boundary),
            dispatch: dispatch,
            outstanding: session.requirement.expectation.outstanding,
            readiness: session.readiness,
            handoff: session.handoff,
            tickLog: session.tickLog,
            latestObservation: session.latestObservation?.event,
            timing: timing
        )
    }

    static func observationFailure(
        _ intent: Settlement.TerminalIntent
    ) -> Settlement.Result.ObservationFailureReason {
        switch intent {
        case .timedOut(let phase): .timedOut(phase)
        case .cancelled: .cancelled
        case .settled, .dispatchFailed:
            preconditionFailure("Observation terminal intent cannot represent this failure")
        }
    }

    static func actionFailure(
        _ intent: Settlement.TerminalIntent
    ) -> Settlement.Result.ActionFailureReason {
        switch intent {
        case .dispatchFailed: .dispatchFailed
        case .timedOut(let phase): .timedOut(phase)
        case .cancelled: .cancelled
        case .settled:
            preconditionFailure("Settled action cannot be projected as a failure")
        }
    }
}

private extension Settlement.BoundaryEvidence {
    var captureFailure: Settlement.Capture.Failure? {
        guard case .unavailable(let failure) = self else { return nil }
        return failure
    }
}

private extension Settlement.Session.Phase {
    var deadline: Settlement.PhaseDeadline? {
        switch self {
        case .observation(let deadline),
             .actionReadiness(let deadline),
             .actionExpectation(let deadline):
            deadline
        case .awaitingActionDispatch:
            nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
