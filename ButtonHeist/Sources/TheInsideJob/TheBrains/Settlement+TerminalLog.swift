#if canImport(UIKit)
#if DEBUG
import TheScore

extension Settlement {
    internal typealias TerminalLogSink = @Sendable (String) -> Void

    internal enum TerminalLog {
        internal static func render(_ result: Result) -> String {
            let fields: [String]
            switch result {
            case .currentState(.captured(let capture)):
                fields = common(
                    command: .currentState,
                    observation: capture.event,
                    outcome: .settled,
                    elapsed: capture.timing.elapsed
                )
            case .currentState(.failed(let failure)):
                fields = common(
                    command: .currentState,
                    outcome: .currentStateFailure(failure.reason),
                    elapsed: failure.timing.elapsed
                )
            case .observation(.settled(let settled)):
                fields = common(
                    command: .observation,
                    predicate: .satisfied,
                    observation: settled.handoff.event,
                    readiness: .established(settled.readiness),
                    handoff: .admitted(settled.handoff),
                    outcome: .settled,
                    elapsed: settled.timing.elapsed
                )
            case .observation(.failed(let failed)):
                fields = common(
                    command: .observation,
                    predicate: .outstanding(failed.attempt.outstanding),
                    observation: latestObservation(
                        history: failed.attempt.history,
                        handoff: failed.attempt.handoff.event
                    ),
                    readiness: .evidence(failed.attempt.readiness),
                    handoff: .evidence(failed.attempt.handoff),
                    outcome: .observationFailure(failed.reason),
                    elapsed: failed.attempt.timing.elapsed
                )
            case .action(.settled(let settled)):
                fields = common(
                    command: .action,
                    predicate: settled.command.predicate == nil ? .notRequired : .satisfied,
                    observation: settled.handoff.event,
                    dispatch: .completed(settled.dispatch),
                    readiness: .established(settled.readiness),
                    handoff: .admitted(settled.handoff),
                    outcome: .settled,
                    elapsed: settled.timing.elapsed
                )
            case .action(.failed(let failed)):
                fields = common(
                    command: .action,
                    predicate: .outstanding(failed.attempt.outstanding),
                    observation: latestObservation(
                        history: failed.attempt.history,
                        handoff: failed.attempt.handoff.event
                    ),
                    dispatch: .evidence(failed.attempt.dispatch),
                    readiness: .evidence(failed.attempt.readiness),
                    handoff: .evidence(failed.attempt.handoff),
                    outcome: .actionFailure(failed.reason),
                    elapsed: failed.attempt.timing.elapsed
                )
            }
            return ([Strings.Terminal.prefix] + fields).joined(
                separator: Strings.Terminal.fieldSeparator
            )
        }

        /// One log line. Every field takes the thing it describes, never a
        /// string: a value cannot be written into the wrong field, because no
        /// two fields accept the same type.
        private static func common(
            command: Strings.TerminalTerm,
            predicate: PredicateState = .notRequired,
            observation: Observation.SnapshotEvent? = nil,
            dispatch: DispatchState = .notApplicable,
            readiness: ReadinessState = .notApplicable,
            handoff: HandoffState = .notApplicable,
            outcome: OutcomeState,
            elapsed: ElapsedMilliseconds
        ) -> [String] {
            [
                Strings.TerminalField.command.pair(command.rawValue),
                Strings.TerminalField.predicate.pair(predicate.rendered),
                Strings.TerminalField.observation.pair(
                    observation?.sequence.rawValue.description ?? Strings.TerminalTerm.none.rawValue
                ),
                Strings.TerminalField.dispatch.pair(dispatch.rendered),
                Strings.TerminalField.readiness.pair(readiness.rendered),
                Strings.TerminalField.handoff.pair(handoff.rendered),
                Strings.TerminalField.outcome.pair(outcome.rendered),
                Strings.TerminalField.elapsedMs.pair(elapsed),
            ]
        }
    }
}

extension Settlement.TerminalLog {
    /// What the caller asked for, as far as the run got.
    internal enum PredicateState {
        case notRequired
        case satisfied
        case outstanding([String])

        /// The tip of the list is the whole story: everything behind it was
        /// never asked, so naming more would report on questions nobody put.
        var rendered: String {
            switch self {
            case .notRequired: Strings.TerminalTerm.notRequired.rawValue
            case .satisfied: Strings.TerminalTerm.satisfied.rawValue
            case .outstanding(let outstanding):
                outstanding.first.map { Strings.TerminalDetail.waiting($0) } ?? Strings.TerminalTerm.satisfied.rawValue
            }
        }
    }

    internal enum DispatchState {
        case notApplicable
        case completed(TheSafecracker.ActionDispatchResult)
        case evidence(Settlement.Result.ActionDispatch)

        var rendered: String {
            switch self {
            case .notApplicable: Strings.TerminalTerm.notApplicable.rawValue
            case .completed(let result): Self.render(result)
            case .evidence(.pending): Strings.TerminalTerm.pending.rawValue
            case .evidence(.completed(let result)): Self.render(result)
            }
        }

        private static func render(_ result: TheSafecracker.ActionDispatchResult) -> String {
            switch result.outcome {
            case .success: Strings.TerminalTerm.succeeded.rawValue
            case .failure(let failure): Strings.TerminalDetail.failed(failure)
            }
        }
    }

    internal enum ReadinessState {
        case notApplicable
        case established(Settlement.Readiness.Establishment)
        case evidence(Settlement.Readiness.Evidence)

        var rendered: String {
            switch self {
            case .notApplicable: Strings.TerminalTerm.notApplicable.rawValue
            case .established(let establishment): Strings.TerminalDetail.established(establishment.path)
            case .evidence(.pending): Strings.TerminalTerm.pending.rawValue
            case .evidence(.established(let establishment)): Strings.TerminalDetail.established(establishment.path)
            }
        }
    }

    internal enum HandoffState {
        case notApplicable
        case admitted(Settlement.Handoff.Admission)
        case evidence(Settlement.Handoff.Evidence)

        var rendered: String {
            switch self {
            case .notApplicable: Strings.TerminalTerm.notApplicable.rawValue
            case .admitted(let admission): Self.render(admission)
            case .evidence(.pending): Strings.TerminalTerm.pending.rawValue
            case .evidence(.captureRequested): Strings.TerminalTerm.captureRequested.rawValue
            case .evidence(.admitted(let admission)): Self.render(admission)
            case .evidence(.captureFailed(_, let failure)): Strings.TerminalDetail.captureFailed(failure)
            }
        }

        private static func render(_ admission: Settlement.Handoff.Admission) -> String {
            Strings.TerminalDetail.admitted(Strings.TerminalField.observation.pair(admission.event.sequence.rawValue))
        }
    }

    /// How the run ended. Every failure is a timeout except the ones that
    /// happened before a predicate could be asked at all.
    internal enum OutcomeState {
        case settled
        case currentStateFailure(Settlement.Result.CurrentStateFailureReason)
        case observationFailure(Settlement.Result.ObservationFailureReason)
        case actionFailure(Settlement.Result.ActionFailureReason)

        var rendered: String {
            switch self {
            case .settled:
                Strings.TerminalTerm.settled.rawValue
            case .currentStateFailure(.unavailable(let reason)):
                Strings.TerminalDetail.failed(reason)
            case .currentStateFailure(.cancelled):
                Strings.TerminalTerm.cancelled.rawValue
            case .observationFailure(.baselineUnavailable):
                Strings.TerminalTerm.baselineUnavailable.rawValue
            case .observationFailure(.timedOut(let phase)):
                Strings.TerminalDetail.timedOut(phase)
            case .observationFailure(.cancelled):
                Strings.TerminalTerm.cancelled.rawValue
            case .observationFailure(.viewportExitFailed(let reason)):
                Strings.TerminalDetail.viewportExitFailed(reason)
            case .actionFailure(.dispatchFailed):
                Strings.TerminalTerm.dispatchFailed.rawValue
            case .actionFailure(.baselineUnavailable):
                Strings.TerminalTerm.baselineUnavailable.rawValue
            case .actionFailure(.timedOut(let phase)):
                Strings.TerminalDetail.timedOut(phase)
            case .actionFailure(.cancelled):
                Strings.TerminalTerm.cancelled.rawValue
            case .actionFailure(.viewportExitFailed(let reason)):
                Strings.TerminalDetail.viewportExitFailed(reason)
            }
        }
    }
}

private extension Settlement.TerminalLog {
    static func latestObservation(
        history: Observation.EventsSince?,
        handoff: Observation.SnapshotEvent?
    ) -> Observation.SnapshotEvent? {
        if let handoff { return handoff }
        guard case .events(let events) = history else { return nil }
        return events.reversed().lazy.compactMap {
            guard case .snapshot(let snapshot) = $0 else { return nil }
            return snapshot
        }.first
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
