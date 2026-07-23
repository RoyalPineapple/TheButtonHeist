#if canImport(UIKit)
#if DEBUG
import TheScore

extension Settlement {
    internal enum DiagnosisTrigger: Sendable, Equatable {
        case action
        case observation
    }

    internal enum DiagnosisDispatchFailure: Sendable, Equatable {
        case actionFailed
        case treeUnavailable
        case timeout
        case inputValidation
        case targetUnavailable
    }

    internal enum DiagnosisDispatch: Sendable, Equatable {
        case notApplicable
        case pending
        case succeeded
        case failed(DiagnosisDispatchFailure)
    }

    internal enum DiagnosisPredicateTarget: Sendable, Equatable {
        case observation(sequence: SettledObservationSequence)
        case announcement(sequence: UInt64)
    }

    internal enum DiagnosisPredicateStatus: Sendable, Equatable {
        case notRequired
        case pending
        case satisfied(DiagnosisPredicateTarget, actual: String?)
        case unmet(DiagnosisPredicateTarget, actual: String?)
        case unavailable(Settlement.Predicate.Unavailability)
        case notEvaluated
    }

    internal struct DiagnosisPredicate: Sendable, Equatable {
        internal let semantics: Settlement.Predicate.Semantics?
        internal let status: DiagnosisPredicateStatus
    }

    internal enum DiagnosisBoundary: Sendable, Equatable {
        case pending
        case established
        case unavailable(Settlement.Capture.Failure)
    }

    internal enum DiagnosisReadiness: Sendable, Equatable {
        case pending(generation: Settlement.Readiness.Generation)
        case established(
            generation: Settlement.Readiness.Generation,
            path: Settlement.Readiness.Path
        )
    }

    internal enum DiagnosisHandoff: Sendable, Equatable {
        case pending(generation: Settlement.Readiness.Generation)
        case captureRequested(generation: Settlement.Readiness.Generation)
        case admitted(
            generation: Settlement.Readiness.Generation,
            observationSequence: SettledObservationSequence
        )
        case captureFailed(
            generation: Settlement.Readiness.Generation,
            failure: Settlement.Capture.Failure
        )
    }

    internal enum DiagnosisObservationHistory: Sendable, Equatable {
        case notRecorded
        case events(count: Int)
        case expired(Observation.Gap)
        case unavailable(Observation.LogReadError)
    }

    internal struct DiagnosisObservationMomentBounds: Sendable, Equatable {
        internal let baselineSequence: SettledObservationSequence?
        internal let currentSequence: SettledObservationSequence?
    }

    internal enum DiagnosisAnnouncementCursorBounds: Sendable, Equatable {
        case unavailable
        case bounded(after: UInt64, through: UInt64)
    }

    internal struct Diagnosis: Sendable, Equatable, CustomStringConvertible {

        internal let trigger: DiagnosisTrigger
        internal let dispatch: DiagnosisDispatch
        internal let predicate: DiagnosisPredicate
        internal let boundary: DiagnosisBoundary
        internal let observationMoments: DiagnosisObservationMomentBounds
        internal let announcementCursors: DiagnosisAnnouncementCursorBounds
        internal let observationHistory: DiagnosisObservationHistory
        internal let readiness: DiagnosisReadiness
        internal let handoff: DiagnosisHandoff
        internal let outcome: Settlement.Outcome
        internal let deadline: Settlement.DeadlineEvidence

        internal static func project(_ result: Settlement.Result) -> Diagnosis {
            Diagnosis(
                trigger: trigger(from: result.evidence.command.trigger),
                dispatch: dispatch(from: result.evidence.trigger),
                predicate: predicate(from: result.evidence.predicate),
                boundary: boundary(from: result.evidence.boundary),
                observationMoments: observationMomentBounds(from: result.evidence),
                announcementCursors: announcementCursorBounds(from: result.evidence),
                observationHistory: observationHistory(from: result.evidence.observationHistory),
                readiness: readiness(from: result.evidence.readiness),
                handoff: handoff(from: result.evidence.handoff),
                outcome: result.outcome,
                deadline: result.evidence.deadline
            )
        }

        internal var description: String {
            [
                "settlement terminal",
                "trigger=\(trigger.rendered)",
                "predicateSemantics=\(predicate.semantics.rendered)",
                "predicate=\(predicate.status.rendered)",
                "observations=\(observationMoments.rendered)",
                "announcements=\(announcementCursors.rendered)",
                "dispatch=\(dispatch.rendered)",
                "readiness=\(readiness.rendered)",
                "handoff=\(handoff.rendered)",
                "history=\(observationHistory.rendered)",
                "outcome=\(outcome.rendered)",
                "elapsedMs=\(deadline.elapsed)",
                "deadlineReached=\(deadline.reached)",
                "deadline=\(deadline.deadline.instant)",
            ].joined(separator: " ")
        }
    }
}

private extension Settlement.Diagnosis {
    static func trigger(from trigger: Settlement.Trigger) -> Settlement.DiagnosisTrigger {
        switch trigger {
        case .action:
            .action
        case .observation:
            .observation
        }
    }

    static func dispatch(from evidence: Settlement.TriggerEvidence) -> Settlement.DiagnosisDispatch {
        switch evidence {
        case .actionPending:
            .pending
        case .actionDispatched(let result):
            if let failure = result.failureKind {
                .failed(Settlement.DiagnosisDispatchFailure(failure))
            } else {
                .succeeded
            }
        case .observation:
            .notApplicable
        }
    }

    static func predicate(
        from evidence: Settlement.Predicate.Evidence
    ) -> Settlement.DiagnosisPredicate {
        Settlement.DiagnosisPredicate(
            semantics: evidence.semantics,
            status: Settlement.DiagnosisPredicateStatus(evidence.status)
        )
    }

    static func boundary(
        from evidence: Settlement.BoundaryEvidence
    ) -> Settlement.DiagnosisBoundary {
        switch evidence {
        case .pending:
            .pending
        case .established:
            .established
        case .unavailable(let failure):
            .unavailable(failure)
        }
    }

    static func observationMomentBounds(
        from evidence: Settlement.Evidence
    ) -> Settlement.DiagnosisObservationMomentBounds {
        let baseline: Observation.Moment? = switch evidence.boundary {
        case .established(let boundary): boundary.moment
        case .pending, .unavailable: nil
        }
        let candidates = [baseline]
            + observationMoments(from: evidence.observationHistory)
            + [evidence.handoff.event?.moment, evidence.predicate.status.observationMoment]
        let current = candidates.compactMap { $0 }.reduce(nil) { latest, candidate -> Observation.Moment? in
            guard let latest else { return candidate }
            return candidate.isSameOrAfter(latest) ? candidate : latest
        }
        return Settlement.DiagnosisObservationMomentBounds(
            baselineSequence: baseline?.sequence,
            currentSequence: current?.sequence
        )
    }

    static func observationMoments(
        from history: Observation.EventsSince?
    ) -> [Observation.Moment?] {
        switch history {
        case .events(let events):
            events.compactMap { event in
                guard case .snapshot(let snapshot) = event else { return nil }
                return snapshot.moment
            }
        case .expired(let gap):
            [gap.current]
        case .unavailable(.historyEvicted(let gap)):
            [gap.current]
        case .unavailable(.momentUnavailable(let moment)):
            [moment]
        case nil:
            []
        }
    }

    static func announcementCursorBounds(
        from evidence: Settlement.Evidence
    ) -> Settlement.DiagnosisAnnouncementCursorBounds {
        guard case .established(let boundary) = evidence.boundary else {
            return .unavailable
        }
        let after = boundary.announcementCursor.sequence
        let historySequences: [UInt64] = switch evidence.observationHistory {
        case .events(let events):
            events.map { event in
                switch event {
                case .snapshot(let snapshot): snapshot.notificationSequence
                case .announcement(let announcement): announcement.announcement.sequence
                }
            }
        case .expired, .unavailable, nil:
            []
        }
        let through = ([
            after,
            evidence.handoff.event?.notificationSequence,
            evidence.predicate.status.announcementSequence,
            evidence.predicate.unavailability?.announcementGapSequence,
        ] + historySequences.map(Optional.some)).compactMap { $0 }.max() ?? after
        return .bounded(after: after, through: through)
    }

    static func observationHistory(
        from history: Observation.EventsSince?
    ) -> Settlement.DiagnosisObservationHistory {
        switch history {
        case .events(let events):
            .events(count: events.count)
        case .expired(let gap):
            .expired(gap)
        case .unavailable(let error):
            .unavailable(error)
        case nil:
            .notRecorded
        }
    }

    static func readiness(
        from evidence: Settlement.Readiness.Evidence
    ) -> Settlement.DiagnosisReadiness {
        switch evidence {
        case .pending(let generation):
            .pending(generation: generation)
        case .established(let establishment):
            .established(generation: establishment.generation, path: establishment.path)
        }
    }

    static func handoff(
        from evidence: Settlement.Handoff.Evidence
    ) -> Settlement.DiagnosisHandoff {
        switch evidence {
        case .pending(let generation):
            .pending(generation: generation)
        case .captureRequested(let request):
            .captureRequested(generation: request.readinessGeneration)
        case .admitted(let admission):
            .admitted(
                generation: admission.generation,
                observationSequence: admission.event.sequence
            )
        case .captureFailed(let generation, let failure):
            .captureFailed(generation: generation, failure: failure)
        }
    }
}

private extension Settlement.DiagnosisDispatchFailure {
    init(_ failure: TheSafecracker.FailureKind) {
        switch failure {
        case .actionFailed: self = .actionFailed
        case .treeUnavailable: self = .treeUnavailable
        case .timeout: self = .timeout
        case .inputValidation: self = .inputValidation
        case .targetUnavailable: self = .targetUnavailable
        }
    }
}

private extension Settlement.DiagnosisPredicateStatus {
    init(_ status: Settlement.Predicate.EvidenceStatus) {
        switch status {
        case .notRequired:
            self = .notRequired
        case .pending:
            self = .pending
        case .satisfied(let response):
            self = .satisfied(
                Settlement.DiagnosisPredicateTarget(response.target),
                actual: response.result.actual
            )
        case .unmet(let response):
            self = .unmet(
                Settlement.DiagnosisPredicateTarget(response.target),
                actual: response.result.actual
            )
        case .unavailable(let unavailability):
            self = .unavailable(unavailability)
        case .notEvaluated:
            self = .notEvaluated
        }
    }
}

private extension Settlement.DiagnosisPredicateTarget {
    init(_ target: Settlement.Predicate.EvaluationTarget) {
        switch target {
        case .observation(let moment):
            self = .observation(sequence: moment.sequence)
        case .announcement(let sequence):
            self = .announcement(sequence: sequence)
        }
    }
}

private extension Settlement.Predicate.EvidenceStatus {
    var observationMoment: Observation.Moment? {
        switch self {
        case .satisfied(let response), .unmet(let response):
            guard case .observation(let moment) = response.target else { return nil }
            return moment
        case .notRequired, .pending, .unavailable, .notEvaluated:
            return nil
        }
    }

    var announcementSequence: UInt64? {
        switch self {
        case .satisfied(let response), .unmet(let response):
            guard case .announcement(let sequence) = response.target else { return nil }
            return sequence
        case .notRequired, .pending, .unavailable, .notEvaluated:
            return nil
        }
    }
}

private extension Settlement.Predicate.Unavailability {
    var announcementGapSequence: UInt64? {
        guard case .announcementHistoryUnavailable(let gap) = self else { return nil }
        return gap.droppedThroughSequence
    }
}

private extension Settlement.DiagnosisTrigger {
    var rendered: String {
        switch self {
        case .action: "action"
        case .observation: "observation"
        }
    }
}

private extension Optional where Wrapped == Settlement.Predicate.Semantics {
    var rendered: String {
        switch self {
        case .currentState?: "currentState"
        case .positiveTransition?: "positiveTransition"
        case .announcement?: "announcement"
        case .completeHistory?: "completeHistory"
        case nil: "none"
        }
    }
}

private extension Settlement.DiagnosisDispatch {
    var rendered: String {
        switch self {
        case .notApplicable: "notApplicable"
        case .pending: "pending"
        case .succeeded: "succeeded"
        case .failed(let failure): "failed(\(failure.rendered))"
        }
    }
}

private extension Settlement.DiagnosisDispatchFailure {
    var rendered: String {
        switch self {
        case .actionFailed: "actionFailed"
        case .treeUnavailable: "treeUnavailable"
        case .timeout: "timeout"
        case .inputValidation: "inputValidation"
        case .targetUnavailable: "targetUnavailable"
        }
    }
}

private extension Settlement.DiagnosisPredicateStatus {
    var rendered: String {
        switch self {
        case .notRequired: "notRequired"
        case .pending: "pending"
        case .satisfied(let target, _): "satisfied(\(target.rendered))"
        case .unmet(let target, _): "unmet(\(target.rendered))"
        case .unavailable(let reason): "unavailable(\(reason))"
        case .notEvaluated: "notEvaluated"
        }
    }
}

private extension Settlement.DiagnosisPredicateTarget {
    var rendered: String {
        switch self {
        case .observation(let sequence): "observation:\(sequence.rawValue)"
        case .announcement(let sequence): "announcement:\(sequence)"
        }
    }
}

private extension Settlement.DiagnosisObservationMomentBounds {
    var rendered: String {
        "\(baselineSequence?.rawValue.description ?? "none")..."
            + "\(currentSequence?.rawValue.description ?? "none")"
    }
}

private extension Settlement.DiagnosisAnnouncementCursorBounds {
    var rendered: String {
        switch self {
        case .unavailable: "unavailable"
        case .bounded(let after, let through): "\(after)...\(through)"
        }
    }
}

private extension Settlement.DiagnosisReadiness {
    var rendered: String {
        switch self {
        case .pending(let generation):
            "pending(generation:\(generation.rawValue))"
        case .established(let generation, let path):
            "established(generation:\(generation.rawValue),path:\(path.rendered))"
        }
    }
}

private extension Settlement.Readiness.Path {
    var rendered: String {
        switch self {
        case .uikitIdle: "uikitIdle"
        case .semanticStability: "semanticStability"
        case .accessibilityQuietWindow: "accessibilityQuietWindow"
        }
    }
}

private extension Settlement.DiagnosisHandoff {
    var rendered: String {
        switch self {
        case .pending(let generation):
            "pending(generation:\(generation.rawValue))"
        case .captureRequested(let generation):
            "captureRequested(generation:\(generation.rawValue))"
        case .admitted(let generation, let sequence):
            "admitted(generation:\(generation.rawValue),observation:\(sequence.rawValue))"
        case .captureFailed(let generation, let failure):
            "captureFailed(generation:\(generation.rawValue),failure:\(failure))"
        }
    }
}

private extension Settlement.DiagnosisObservationHistory {
    var rendered: String {
        switch self {
        case .notRecorded: "notRecorded"
        case .events(let count): "events(count:\(count))"
        case .expired(let gap): "expired(\(gap.reason))"
        case .unavailable(let error): "unavailable(\(error))"
        }
    }
}

private extension Settlement.Outcome {
    var rendered: String {
        switch self {
        case .settled: "settled"
        case .dispatchFailed: "dispatchFailed"
        case .baselineUnavailable: "baselineUnavailable"
        case .timedOut: "timedOut"
        case .cancelled: "cancelled"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
