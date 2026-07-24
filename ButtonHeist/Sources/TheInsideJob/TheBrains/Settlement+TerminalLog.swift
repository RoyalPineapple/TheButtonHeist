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
                    command: "currentState",
                    observation: capture.event,
                    outcome: "settled",
                    elapsed: capture.timing.elapsed
                )
            case .currentState(.failed(let failure)):
                let outcome = switch failure.reason {
                case .unavailable(let reason): "baselineUnavailable(\(reason))"
                case .cancelled: "cancelled"
                }
                fields = common(
                    command: "currentState",
                    outcome: outcome,
                    elapsed: failure.timing.elapsed
                )
            case .observation(.settled(let settled)):
                fields = common(
                    command: "observation",
                    predicate: render(settled.evaluation),
                    observation: settled.handoff.event,
                    readiness: render(settled.readiness),
                    handoff: render(settled.handoff),
                    outcome: "settled",
                    elapsed: settled.timing.elapsed
                )
            case .observation(.failed(let failed)):
                let outcome = switch failed.reason {
                case .baselineUnavailable: "baselineUnavailable"
                case .timedOut(let phase): "timedOut(\(phase))"
                case .cancelled: "cancelled"
                case .viewportExitFailed(let reason): "viewportExitFailed(\(reason))"
                }
                fields = common(
                    command: "observation",
                    predicate: render(failed.attempt.evaluation),
                    observation: latestObservation(
                        history: failed.attempt.history,
                        handoff: failed.attempt.handoff.event
                    ),
                    readiness: render(failed.attempt.readiness),
                    handoff: render(failed.attempt.handoff),
                    outcome: outcome,
                    elapsed: failed.attempt.timing.elapsed
                )
            case .action(.settled(let settled)):
                fields = common(
                    command: "action",
                    predicate: settled.evaluation.map(render) ?? "notRequired",
                    observation: settled.handoff.event,
                    dispatch: render(settled.dispatch),
                    readiness: render(settled.readiness),
                    handoff: render(settled.handoff),
                    outcome: "settled",
                    elapsed: settled.timing.elapsed
                )
            case .action(.failed(let failed)):
                let outcome = switch failed.reason {
                case .dispatchFailed: "dispatchFailed"
                case .baselineUnavailable: "baselineUnavailable"
                case .timedOut(let phase): "timedOut(\(phase))"
                case .cancelled: "cancelled"
                case .viewportExitFailed(let reason): "viewportExitFailed(\(reason))"
                }
                fields = common(
                    command: "action",
                    predicate: render(failed.attempt.evaluation),
                    observation: latestObservation(
                        history: failed.attempt.history,
                        handoff: failed.attempt.handoff.event
                    ),
                    dispatch: render(failed.attempt.dispatch),
                    readiness: render(failed.attempt.readiness),
                    handoff: render(failed.attempt.handoff),
                    outcome: outcome,
                    elapsed: failed.attempt.timing.elapsed
                )
            }
            return (["settlement terminal"] + fields).joined(separator: " ")
        }

        private static func common(
            command: String,
            predicate: String = "notRequired",
            observation: Observation.SnapshotEvent? = nil,
            dispatch: String = "notApplicable",
            readiness: String = "notApplicable",
            handoff: String = "notApplicable",
            outcome: String,
            elapsed: ElapsedMilliseconds
        ) -> [String] {
            [
                "command=\(command)",
                "predicate=\(predicate)",
                "observation=\(observation?.sequence.rawValue.description ?? "none")",
                "dispatch=\(dispatch)",
                "readiness=\(readiness)",
                "handoff=\(handoff)",
                "outcome=\(outcome)",
                "elapsedMs=\(elapsed)",
            ]
        }
    }
}

private extension Settlement.TerminalLog {
    static func render(_ dispatch: Settlement.Result.ActionDispatch) -> String {
        switch dispatch {
        case .pending: "pending"
        case .completed(let result): render(result)
        }
    }

    static func render(_ dispatch: TheSafecracker.ActionDispatchResult) -> String {
        switch dispatch.outcome {
        case .success: "succeeded"
        case .failure(let failure): "failed(\(failure))"
        }
    }

    static func render(_ evaluation: Settlement.Predicate.EvaluationResponse) -> String {
        "\(evaluation.result.met ? "satisfied" : "unmet")(\(render(evaluation.target)))"
    }

    static func render(_ evidence: Settlement.Predicate.Evidence) -> String {
        switch evidence.status {
        case .notRequired: "notRequired"
        case .pending: "pending"
        case .satisfied(let response), .unmet(let response): render(response)
        case .unavailable(let reason): "unavailable(\(reason))"
        case .notEvaluated: "notEvaluated"
        }
    }

    static func render(_ target: Settlement.Predicate.EvaluationTarget) -> String {
        switch target {
        case .observation(let moment): "observation:\(moment.sequence.rawValue)"
        case .announcement(let sequence): "announcement:\(sequence)"
        }
    }

    static func render(_ readiness: Settlement.Readiness.Evidence) -> String {
        switch readiness {
        case .pending: "pending"
        case .established(let establishment): render(establishment)
        }
    }

    static func render(_ readiness: Settlement.Readiness.Establishment) -> String {
        "established(\(readiness.path))"
    }

    static func render(_ handoff: Settlement.Handoff.Evidence) -> String {
        switch handoff {
        case .pending: "pending"
        case .captureRequested: "captureRequested"
        case .admitted(let admission): render(admission)
        case .captureFailed(_, let failure): "captureFailed(\(failure))"
        }
    }

    static func render(_ handoff: Settlement.Handoff.Admission) -> String {
        "admitted(observation:\(handoff.event.sequence.rawValue))"
    }

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
