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
                guard let deadline = command.deadline else {
                    preconditionFailure("Supplied settlement baseline requires a deadline")
                }
                return Decision(
                    state: .armed(Settlement.Session(
                        command: command,
                        boundary: boundary,
                        timing: Settlement.ExecutionTiming()
                    )),
                    effects: [.arm(Settlement.Arming(
                        boundary: boundary,
                        observationScope: command.observationScope,
                        deadline: deadline
                    ))]
                )
            case .unavailable(let failure):
                return terminalBeforeBaseline(
                    command: command,
                    boundary: .unavailable(failure),
                    outcome: .baselineUnavailable,
                    timing: Settlement.ExecutionTiming(),
                    elapsed: 0,
                    deadlineReached: false
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
            let boundary = Settlement.EvidenceBoundary(moment: snapshot.moment)
            guard let deadline = command.deadline else {
                preconditionFailure("Armed settlement command requires a deadline")
            }
            let session = Settlement.Session(
                command: command,
                boundary: boundary,
                timing: event.timing
            )
            return Settlement.Decision(
                state: .armed(session),
                effects: [.arm(Settlement.Arming(
                    boundary: boundary,
                    observationScope: command.observationScope,
                    deadline: deadline
                ))]
            )
        case .baselineUnavailable(let failure):
            return terminalBeforeBaseline(
                command: command,
                boundary: .unavailable(failure),
                outcome: .baselineUnavailable,
                timing: event.timing,
                elapsed: event.elapsed,
                deadlineReached: false
            )
        case .deadlineReached:
            return terminalBeforeBaseline(
                command: command,
                boundary: .pending,
                outcome: .timedOut,
                timing: event.timing,
                elapsed: event.elapsed,
                deadlineReached: true
            )
        case .cancelled:
            return terminalBeforeBaseline(
                command: command,
                boundary: .pending,
                outcome: .cancelled,
                timing: event.timing,
                elapsed: event.elapsed,
                deadlineReached: false
            )
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
            case .action(let command, _, _, _):
                return Settlement.Decision(
                    state: .active(session),
                    effects: [.dispatchAction(command)]
                )
            case .observation:
                return Settlement.Decision(state: .active(session), effects: [])
            case .currentState:
                preconditionFailure("Current-state capture cannot enter channel arming")
            }
        case .deadlineReached:
            return terminal(session, outcome: .timedOut, elapsed: event.elapsed, deadlineReached: true)
        case .cancelled:
            return terminal(session, outcome: .cancelled, elapsed: event.elapsed, deadlineReached: false)
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
            guard case .actionPending = session.triggerEvidence else {
                return Settlement.Decision(state: .active(session), effects: [])
            }
            session.triggerEvidence = .actionDispatched(result)
            if !result.success {
                session.requirement.evidence.recordDispatchFailure()
            }
        case .observationAdmitted(let admission):
            effects += admit(admission, to: &session)
        case .announcementObserved(let event):
            effects += observe(event, in: &session)
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
        case .deadlineReached:
            return terminal(session, outcome: .timedOut, elapsed: event.elapsed, deadlineReached: true)
        case .cancelled:
            return terminal(session, outcome: .cancelled, elapsed: event.elapsed, deadlineReached: false)
        case .baselineAdmitted, .baselineUnavailable, .channelsArmed:
            preconditionFailure("Settlement received a bootstrap event after channel arming")
        }

        if let outcome = completedOutcome(session) {
            return terminal(session, outcome: outcome, elapsed: event.elapsed, deadlineReached: false)
        }
        return Settlement.Decision(
            state: .active(session),
            effects: effects
        )
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
            return evaluationEffect(
                for: latestObservation,
                session: &session
            )
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
}

private extension Settlement.Reducer {
    static func terminal(
        _ session: Settlement.Session,
        outcome: Settlement.Outcome,
        elapsed: ElapsedMilliseconds,
        deadlineReached: Bool
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
                deadline: .bounded(
                    deadline: deadline(for: session.command),
                    elapsed: elapsed,
                    reached: deadlineReached
                )
            )
        )
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func terminalBeforeBaseline(
        command: Settlement.Command,
        boundary: Settlement.BoundaryEvidence,
        outcome: Settlement.Outcome,
        timing: Settlement.ExecutionTiming,
        elapsed: ElapsedMilliseconds,
        deadlineReached: Bool
    ) -> Settlement.Decision {
        let trigger: Settlement.TriggerEvidence = switch command {
        case .action(let action, _, _, _): .actionPending(action)
        case .currentState, .observation: .observation
        }
        let requirement = Settlement.Predicate.Requirement(predicate: command.predicate)
        let deadlineEvidence: Settlement.DeadlineEvidence = if let deadline = command.deadline {
            .bounded(deadline: deadline, elapsed: elapsed, reached: deadlineReached)
        } else {
            .notApplicable(elapsed: elapsed)
        }
        let result = Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: command,
                boundary: boundary,
                trigger: trigger,
                predicate: requirement.evidence,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                observationHistory: nil,
                timing: timing,
                deadline: deadlineEvidence
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
                deadline: .notApplicable(elapsed: elapsed)
            )
        )
        return Settlement.Decision(state: .terminal(result), effects: [])
    }

    static func deadline(for command: Settlement.Command) -> Settlement.Deadline {
        guard let deadline = command.deadline else {
            preconditionFailure("Timed settlement evidence requires a deadline")
        }
        return deadline
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
