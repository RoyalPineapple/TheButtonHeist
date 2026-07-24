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
                    outcome: .baselineUnavailable,
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
                outcome: .baselineUnavailable,
                timing: event.timing,
                elapsed: event.elapsed
            )
        case .cancelled:
            return terminalBeforeBaseline(
                command: command,
                boundary: .pending,
                outcome: .cancelled,
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
             .predicateEvaluated,
             .readinessEstablished,
             .readinessInvalidated,
             .handoffCaptureFailed:
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
            return terminal(session, outcome: .cancelled, elapsed: event.elapsed)
        case .baselineAdmitted,
             .baselineUnavailable,
             .dispatchCompleted,
             .observationAdmitted,
             .announcementObserved,
             .observationHistoryUnavailable,
             .announcementHistoryUnavailable,
             .predicateEvaluated,
             .readinessEstablished,
             .readinessInvalidated,
             .handoffCaptureFailed:
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
            if !result.success {
                session.requirement.evidence.recordDispatchFailure()
            }
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
        case .observationHistoryUnavailable(let history):
            recordUnavailableHistory(history, in: &session)
        case .announcementHistoryUnavailable(let gap):
            recordUnavailableAnnouncementHistory(gap, in: &session)
        case .predicateEvaluated(let response):
            record(response, in: &session)
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
                return terminal(
                    session,
                    outcome: .dispatchFailed,
                    elapsed: event.elapsed
                )
            }
            return terminal(
                session,
                outcome: .timedOut(reached.phase),
                elapsed: event.elapsed
            )
        case .cancelled:
            return terminal(session, outcome: .cancelled, elapsed: event.elapsed)
        case .baselineAdmitted, .baselineUnavailable, .channelsArmed:
            preconditionFailure("Settlement received a bootstrap event after channel arming")
        }

        if let outcome = completedOutcome(session) {
            return terminal(session, outcome: outcome, elapsed: event.elapsed)
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
        session.observationHistory = admission.history
        session.latestObservation = admission
        if case .established(let readiness) = session.readiness,
           session.command.waitsForObservation || session.handoff.admission == nil,
           let handoff = Settlement.Handoff.Admission.admit(admission, for: readiness) {
            session.handoff = .admitted(handoff)
        }
        guard !session.triggerEvidence.dispatchFailed else { return [] }
        return evaluationEffect(for: admission, session: &session)
    }

    static func observe(
        _ event: Observation.AnnouncementEvent,
        in session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard event.announcement.sequence > session.boundary.announcementCursor.sequence,
              !session.triggerEvidence.dispatchFailed,
              let predicate = session.requirement.predicate,
              predicate.semantics == .announcement,
              !session.requirement.evidence.isSatisfied else { return [] }
        let request = Settlement.Predicate.EvaluationRequest(
            predicate: predicate,
            target: .announcement(sequence: event.announcement.sequence),
            evidence: .announcement(event)
        )
        return session.requirement.evidence.schedule(request)
            ? [.evaluatePredicate(request)]
            : []
    }

    static func evaluationEffect(
        for admission: Settlement.ObservationAdmission,
        session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard let predicate = session.requirement.predicate else { return [] }
        let target = Settlement.Predicate.EvaluationTarget.observation(admission.event.moment)
        let evidence: Settlement.Predicate.EvaluationEvidence
        switch predicate.semantics {
        case .currentState:
            evidence = .currentState(admission.event)
        case .positiveTransition:
            if session.requirement.evidence.isSatisfied { return [] }
            guard history(admission.history, contains: admission.event) else {
                recordUnavailableHistory(admission.history, in: &session)
                return []
            }
            evidence = .positiveTransition(admission.event)
        case .announcement:
            return []
        case .completeHistory:
            guard session.handoff.event?.moment == admission.event.moment else { return [] }
            guard historyIsComplete(admission.history) else {
                recordUnavailableHistory(admission.history, in: &session)
                return []
            }
            evidence = .completeHistory(.init(
                history: admission.history,
                handoff: admission.event
            ))
        }
        let request = Settlement.Predicate.EvaluationRequest(
            predicate: predicate,
            target: target,
            evidence: evidence
        )
        return session.requirement.evidence.schedule(request)
            ? [.evaluatePredicate(request)]
            : []
    }

    static func record(
        _ response: Settlement.Predicate.EvaluationResponse,
        in session: inout Settlement.Session
    ) {
        session.requirement.evidence.record(response)
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

        if let handoff = session.handoff.event,
           session.requirement.predicate?.semantics == .completeHistory,
           let latestObservation = session.latestObservation,
           latestObservation.event.moment == handoff.moment {
            return evaluationEffect(for: latestObservation, session: &session)
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
    static func recordUnavailableHistory(
        _ history: Observation.EventsSince,
        in session: inout Settlement.Session
    ) {
        session.observationHistory = history
        guard let semantics = session.requirement.predicate?.semantics,
              semantics == .positiveTransition || semantics == .completeHistory,
              !session.requirement.evidence.isSatisfied else { return }
        switch history {
        case .events:
            break
        case .expired(let gap):
            session.requirement.evidence.recordUnavailable(.historyExpired(gap))
        case .unavailable(let error):
            session.requirement.evidence.recordUnavailable(.historyUnavailable(error))
        }
    }

    static func recordUnavailableAnnouncementHistory(
        _ gap: AccessibilityNotificationGap,
        in session: inout Settlement.Session
    ) {
        guard session.requirement.predicate?.semantics == .announcement,
              !session.requirement.evidence.isSatisfied else { return }
        session.requirement.evidence.recordUnavailable(.announcementHistoryUnavailable(gap))
    }

    static func history(
        _ history: Observation.EventsSince,
        contains event: Observation.SnapshotEvent
    ) -> Bool {
        guard case .events(let events) = history else { return false }
        return events.contains(.snapshot(event))
    }

    static func historyIsComplete(_ history: Observation.EventsSince) -> Bool {
        if case .events = history { return true }
        return false
    }
}

private extension Settlement.Reducer {
    static func completedOutcome(_ session: Settlement.Session) -> Settlement.Outcome? {
        guard case .established(let readiness) = session.readiness,
              let handoff = session.handoff.admission,
              handoff.belongs(to: readiness) else { return nil }
        if session.triggerEvidence.dispatchFailed { return .dispatchFailed }
        guard session.triggerEvidence.permitsCompletion,
              session.requirement.evidence.satisfies(
                  session.requirement.predicate,
                  at: handoff.event
              ) else { return nil }
        return .settled
    }

    static func admitExpectationPhaseIfNeeded(
        in session: inout Settlement.Session
    ) -> [Settlement.Effect] {
        guard case .actionReadiness = session.phase,
              case .action(let action) = session.command,
              let allowance = action.allowances.expectation,
              session.triggerEvidence.permitsCompletion,
              let handoff = session.handoff.admission,
              !session.requirement.evidence.satisfies(
                  session.requirement.predicate,
                  at: handoff.event
              ) else { return [] }
        let deadline = Settlement.PhaseDeadline(
            phase: .actionExpectation,
            instant: handoff.instant.advanced(by: allowance)
        )
        session.phase = .actionExpectation(deadline)
        return [.armDeadline(deadline)]
    }
}

private extension Settlement.Reducer {
    static func terminal(
        _ session: Settlement.Session,
        outcome: Settlement.Outcome,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        let result = Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: session.command,
                boundary: .established(session.boundary),
                trigger: session.triggerEvidence,
                predicate: session.requirement.evidence,
                readiness: session.readiness,
                handoff: session.handoff,
                observationHistory: session.observationHistory,
                timing: session.timing,
                elapsed: elapsed
            )
        )
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminalBeforeBaseline(
        command: Settlement.Command,
        boundary: Settlement.BoundaryEvidence,
        outcome: Settlement.Outcome,
        timing: Settlement.ExecutionTiming,
        elapsed: ElapsedMilliseconds
    ) -> Settlement.Decision {
        let trigger: Settlement.TriggerEvidence = switch command {
        case .action(let action): .actionPending(action.command)
        case .currentState, .observation: .observation
        }
        let result = Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: command,
                boundary: boundary,
                trigger: trigger,
                predicate: Settlement.Predicate.Requirement(
                    predicate: command.predicate
                ).evidence,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                observationHistory: nil,
                timing: timing,
                elapsed: elapsed
            )
        )
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminalCurrentState(
        command: Settlement.Command,
        event: Observation.SnapshotEvent,
        timing: Settlement.ExecutionTiming,
        elapsed: ElapsedMilliseconds = RuntimeElapsed.admit(milliseconds: 0)
    ) -> Settlement.Decision {
        let readiness = Settlement.Readiness.Establishment(
            generation: .initial,
            path: .currentStateCapture,
            observationBoundary: .including(event.moment)
        )
        let result = Settlement.Result(
            outcome: .settled,
            evidence: Settlement.Evidence(
                command: command,
                boundary: .established(.init(moment: event.moment)),
                trigger: .observation,
                predicate: Settlement.Predicate.Evidence(predicate: nil),
                readiness: .established(readiness),
                handoff: .admitted(.currentState(event)),
                observationHistory: .events([]),
                timing: timing,
                elapsed: elapsed
            )
        )
        return Settlement.Decision(state: .terminal(result), effects: [])
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
