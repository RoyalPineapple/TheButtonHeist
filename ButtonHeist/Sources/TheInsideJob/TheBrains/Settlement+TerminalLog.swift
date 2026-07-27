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
                    observation: failed.attempt.handoff.event
                        ?? failed.attempt.latestObservation,
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
                    predicate: .asked(
                        failed.attempt.command.predicate,
                        outstanding: failed.attempt.outstanding
                    ),
                    observation: failed.attempt.handoff.event
                        ?? failed.attempt.latestObservation,
                    dispatch: .evidence(failed.attempt.dispatch),
                    readiness: .evidence(failed.attempt.readiness),
                    handoff: .evidence(failed.attempt.handoff),
                    outcome: .actionFailure(failed.reason),
                    elapsed: failed.attempt.timing.elapsed
                )
            }
            return (["settlement terminal"] + fields).joined(separator: " ")
        }

        /// One log line. Every field takes the thing it describes, never a
        /// string: a value cannot be written into the wrong field, because no
        /// two fields accept the same type.
        private static func common(
            command: Command,
            predicate: PredicateState = .notRequired,
            observation: Observation.SnapshotEvent? = nil,
            dispatch: DispatchState = .notApplicable,
            readiness: ReadinessState = .notApplicable,
            handoff: HandoffState = .notApplicable,
            outcome: OutcomeState,
            elapsed: ElapsedMilliseconds
        ) -> [String] {
            [
                "command=\(command.rawValue)",
                "predicate=\(predicate.rendered)",
                "observation=\(observation?.sequence.rawValue.description ?? "none")",
                "dispatch=\(dispatch.rendered)",
                "readiness=\(readiness.rendered)",
                "handoff=\(handoff.rendered)",
                "outcome=\(outcome.rendered)",
                "elapsedMs=\(elapsed)",
            ]
        }
    }
}

extension Settlement.TerminalLog {
    /// Which of the three commands this line reports on.
    internal enum Command: String {
        case currentState
        case observation
        case action
    }

    /// What the caller asked for, as far as the run got.
    internal enum PredicateState {
        case notRequired
        case satisfied
        case outstanding([PendingPredicate])

        /// The tip of the list is the whole story: everything behind it was
        /// never asked, so naming more would report on questions nobody put.
        ///
        /// An empty list is `satisfied` and not `notRequired`: only a caller
        /// holding the command knows whether a predicate was asked at all, so
        /// that distinction is made where the state is built.
        var rendered: String {
            switch self {
            case .notRequired: "notRequired"
            case .satisfied: "satisfied"
            case .outstanding(let outstanding):
                outstanding.first.map { "waiting(\($0.description))" } ?? "satisfied"
            }
        }

        /// The state for a run that owed `outstanding`, where a caller that
        /// named no predicate is reported as having been asked nothing.
        static func asked(_ predicate: Settlement.Predicate?, outstanding: [PendingPredicate]) -> Self {
            predicate == nil ? .notRequired : .outstanding(outstanding)
        }
    }

    internal enum DispatchState {
        case notApplicable
        case completed(TheSafecracker.ActionDispatchResult)
        case evidence(Settlement.Result.ActionDispatch)

        var rendered: String {
            switch self {
            case .notApplicable: "notApplicable"
            case .completed(let result): Self.render(result)
            case .evidence(.pending): "pending"
            case .evidence(.completed(let result)): Self.render(result)
            }
        }

        private static func render(_ result: TheSafecracker.ActionDispatchResult) -> String {
            switch result.outcome {
            case .success: "succeeded"
            case .failure(let failure): "failed(\(failure))"
            }
        }
    }

    internal enum ReadinessState {
        case notApplicable
        case established(Settlement.Readiness.Establishment)
        case evidence(Settlement.Readiness.Evidence)

        var rendered: String {
            switch self {
            case .notApplicable: "notApplicable"
            case .established: "established"
            case .evidence(.pending): "pending"
            case .evidence(.established): "established"
            }
        }
    }

    internal enum HandoffState {
        case notApplicable
        case admitted(Settlement.Handoff.Admission)
        case evidence(Settlement.Handoff.Evidence)

        var rendered: String {
            switch self {
            case .notApplicable: "notApplicable"
            case .admitted(let admission): Self.render(admission)
            case .evidence(.pending): "pending"
            case .evidence(.captureRequested): "captureRequested"
            case .evidence(.admitted(let admission)): Self.render(admission)
            case .evidence(.captureFailed(_, let failure)): "captureFailed(\(failure))"
            }
        }

        private static func render(_ admission: Settlement.Handoff.Admission) -> String {
            "admitted(observation=\(admission.event.sequence.rawValue))"
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
                "settled"
            case .currentStateFailure(.unavailable(let reason)):
                "failed(\(reason))"
            case .currentStateFailure(.cancelled):
                "cancelled"
            case .observationFailure(.baselineUnavailable):
                "baselineUnavailable"
            case .observationFailure(.timedOut(let phase)):
                "timedOut(\(phase))"
            case .observationFailure(.cancelled):
                "cancelled"
            case .observationFailure(.viewportExitFailed(let reason)):
                "viewportExitFailed(\(reason))"
            case .actionFailure(.dispatchFailed):
                "dispatchFailed"
            case .actionFailure(.baselineUnavailable):
                "baselineUnavailable"
            case .actionFailure(.timedOut(let phase)):
                "timedOut(\(phase))"
            case .actionFailure(.cancelled):
                "cancelled"
            case .actionFailure(.viewportExitFailed(let reason)):
                "viewportExitFailed(\(reason))"
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
