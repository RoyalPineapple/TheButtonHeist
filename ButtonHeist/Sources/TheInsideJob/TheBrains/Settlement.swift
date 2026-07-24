#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum Settlement {}

extension Settlement {
    private enum DeadlineStart: Sendable, Equatable {
        case immediate(ContinuousClock.Instant)
        case afterActionDispatch(Duration)
    }

    internal enum Command: Sendable, Equatable {
        case currentState(scope: SemanticObservationScope)
        case observation(
            predicate: Predicate,
            deadline: Deadline,
            baseline: Baseline
        )
        case action(
            ResolvedHeistActionCommand,
            predicate: Predicate?,
            deadline: Deadline,
            baseline: Baseline
        )

        internal init(
            observing input: ResolvedWaitRuntimeInput,
            baseline: Baseline = .capture,
            startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
        ) {
            self = .observation(
                predicate: Predicate(
                    authored: input.predicateExpression,
                    resolved: input.predicate
                ),
                deadline: Deadline(
                    instant: startedAt.advanced(by: .seconds(input.timeout.seconds))
                ),
                baseline: baseline
            )
        }

        internal init(
            observing input: ResolvedWaitRuntimeInput,
            after priorResult: Settlement.Result,
            startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
        ) {
            let baseline: Baseline
            if let moment = priorResult.evidence.handoff.event?.moment {
                baseline = .supplied(EvidenceBoundary(moment: moment))
            } else if case .presence = input.predicate.core {
                baseline = .capture
            } else {
                baseline = .unavailable(.unavailable)
            }
            self.init(
                observing: input,
                baseline: baseline,
                startedAt: startedAt
            )
        }

        internal var predicate: Predicate? {
            switch self {
            case .currentState:
                nil
            case .observation(let predicate, _, _):
                predicate
            case .action(_, let predicate, _, _):
                predicate
            }
        }

        internal var observationScope: SemanticObservationScope {
            switch self {
            case .currentState(let scope):
                scope
            case .observation(let predicate, _, _):
                predicate.observationScope
            case .action(_, let predicate, _, _):
                predicate?.observationScope ?? .visible
            }
        }

        internal var deadline: Deadline? {
            switch self {
            case .currentState:
                nil
            case .observation(_, let deadline, _),
                 .action(_, _, let deadline, _):
                deadline
            }
        }

        internal var baseline: Baseline? {
            switch self {
            case .currentState:
                nil
            case .observation(_, _, let baseline),
                 .action(_, _, _, let baseline):
                baseline
            }
        }

        internal var waitsForObservation: Bool {
            if case .observation = self { return true }
            return false
        }
    }

    internal enum Baseline: Sendable, Equatable {
        case capture
        case supplied(EvidenceBoundary)
        case unavailable(Capture.Failure)
    }

    internal struct Deadline: Sendable, Equatable {
        private let start: DeadlineStart

        internal init(instant: ContinuousClock.Instant) {
            self.start = .immediate(instant)
        }

        internal init(afterActionDispatch timeout: Duration) {
            precondition(timeout >= .zero, "Settlement timeout cannot be negative")
            self.start = .afterActionDispatch(timeout)
        }

        internal var startsAfterActionDispatch: Bool {
            if case .afterActionDispatch = start { return true }
            return false
        }

        internal func remainingDuration(
            at now: ContinuousClock.Instant = RuntimeElapsed.now
        ) -> Duration {
            guard let instant = resolve(dispatchCompletedAt: nil) else { return .zero }
            return max(.zero, now.duration(to: instant))
        }

        internal func resolve(
            dispatchCompletedAt: ContinuousClock.Instant?
        ) -> ContinuousClock.Instant? {
            switch start {
            case .immediate(let instant):
                instant
            case .afterActionDispatch(let timeout):
                dispatchCompletedAt?.advanced(by: timeout)
            }
        }

        internal var diagnosisDescription: String {
            switch start {
            case .immediate(let instant):
                "at(\(instant))"
            case .afterActionDispatch(let timeout):
                "afterActionDispatch(\(timeout))"
            }
        }
    }

    internal struct ActionAllowances: Sendable, Equatable {
        internal let readiness: Duration
        internal let expectation: Duration?

        internal init(readiness: Duration, expectation: Duration?) {
            precondition(readiness >= .zero, "Settlement readiness allowance cannot be negative")
            if let expectation {
                precondition(expectation >= .zero, "Settlement expectation allowance cannot be negative")
            }
            self.readiness = readiness
            self.expectation = expectation
        }
    }

    internal enum DeadlinePhase: Sendable, Equatable {
        case observation
        case actionReadiness
        case actionExpectation
    }

    internal struct PhaseDeadline: Sendable, Equatable {
        internal let phase: DeadlinePhase
        internal let instant: ContinuousClock.Instant
    }

    internal struct EvidenceBoundary: Sendable, Equatable {
        internal let moment: Observation.Moment

        internal init(moment: Observation.Moment) {
            self.moment = moment
        }

        internal var announcementCursor: AccessibilityNotificationCursor {
            AccessibilityNotificationCursor(
                sequence: moment.snapshot.notificationSequence
            )
        }
    }
}

extension Settlement {
    internal struct Predicate: Sendable, Equatable {
        internal let authored: AccessibilityPredicate
        internal let resolved: ResolvedAccessibilityPredicate
        internal let semantics: Semantics
        internal let observationScope: SemanticObservationScope

        internal init(
            authored: AccessibilityPredicate,
            resolved: ResolvedAccessibilityPredicate
        ) {
            self.authored = authored
            self.resolved = resolved
            self.semantics = Semantics(resolved: resolved)
            self.observationScope = resolved.observationScope
        }
    }
}

extension Settlement.Predicate {
    internal enum Semantics: Sendable, Equatable {
        case currentState
        case positiveTransition
        case announcement
        case completeHistory
    }
}

extension Settlement.Predicate.Semantics {
    fileprivate init(resolved predicate: ResolvedAccessibilityPredicate) {
        switch predicate.core {
        case .presence:
            self = .currentState
        case .changed:
            self = .positiveTransition
        case .announcement:
            self = .announcement
        case .noChange:
            self = .completeHistory
        }
    }
}

extension Settlement.Predicate {
    internal struct CompleteHistoryEvidence: Sendable, Equatable {
        internal let history: Observation.EventsSince
        internal let handoff: Observation.SnapshotEvent
    }

    internal enum EvaluationEvidence: Sendable, Equatable {
        case currentState(Observation.SnapshotEvent)
        case positiveTransition(Observation.SnapshotEvent)
        case announcement(Observation.AnnouncementEvent)
        case completeHistory(CompleteHistoryEvidence)
    }

    internal enum EvaluationTarget: Sendable, Equatable {
        case observation(Observation.Moment)
        case announcement(sequence: UInt64)
    }

    internal struct EvaluationRequest: Sendable, Equatable {
        internal let predicate: Settlement.Predicate
        internal let target: EvaluationTarget
        internal let evidence: EvaluationEvidence
    }

    internal struct EvaluationResponse: Sendable, Equatable {
        internal let target: EvaluationTarget
        internal let result: PredicateEvaluationResult

        internal init(target: EvaluationTarget, result: PredicateEvaluationResult) {
            self.target = target
            self.result = result
        }
    }

    internal enum Unavailability: Sendable, Equatable {
        case historyExpired(Observation.Gap)
        case historyUnavailable(Observation.LogReadError)
        case announcementHistoryUnavailable(AccessibilityNotificationGap)
        case dispatchFailed
    }

    internal enum EvaluationResponseRejectionReason: Sendable, Equatable {
        case targetNotPending
        case duplicateResponse
        case satisfactionAlreadyLatched
        case evidenceUnavailable
        case dispatchFailed
    }

    internal struct RejectedResponse: Sendable, Equatable {
        internal let response: EvaluationResponse
        internal let reason: EvaluationResponseRejectionReason
    }

    internal enum EvidenceStatus: Sendable, Equatable {
        case notRequired
        case pending
        case satisfied(EvaluationResponse)
        case unmet(EvaluationResponse)
        case unavailable(Unavailability)
        case notEvaluated
    }

    private struct EvaluationLedgerEntry: Sendable, Equatable {
        let request: EvaluationRequest
        var response: EvaluationResponse?
    }

    internal struct Evidence: Sendable, Equatable {
        internal let semantics: Semantics?
        internal private(set) var status: EvidenceStatus
        internal private(set) var responses: [EvaluationResponse]
        internal private(set) var rejectedResponses: [RejectedResponse]
        private var evaluationLedger: [EvaluationLedgerEntry]

        internal init(predicate: Settlement.Predicate?) {
            self.semantics = predicate?.semantics
            self.status = predicate == nil ? .notRequired : .pending
            self.responses = []
            self.rejectedResponses = []
            self.evaluationLedger = []
        }

        internal var isSatisfied: Bool {
            if case .notRequired = status { return true }
            if case .satisfied = status { return true }
            return false
        }

        internal var satisfiedTarget: EvaluationTarget? {
            guard case .satisfied(let response) = status else { return nil }
            return response.target
        }

        internal var unavailability: Unavailability? {
            guard case .unavailable(let unavailability) = status else { return nil }
            return unavailability
        }

        internal var isNotEvaluated: Bool {
            if case .notEvaluated = status { return true }
            return false
        }

        internal mutating func schedule(_ request: EvaluationRequest) -> Bool {
            guard request.predicate.semantics == semantics,
                  acceptsEvaluationRequests,
                  !evaluationLedger.contains(where: { $0.request.target == request.target }),
                  !responses.contains(where: { $0.target == request.target }) else { return false }
            evaluationLedger.append(EvaluationLedgerEntry(request: request, response: nil))
            return true
        }

        internal mutating func record(_ response: EvaluationResponse) {
            if containsResponse(for: response.target) {
                reject(response, because: .duplicateResponse)
                return
            }
            guard let ledgerIndex = evaluationLedger.firstIndex(where: {
                $0.request.target == response.target
            }) else {
                reject(response, because: .targetNotPending)
                return
            }
            switch status {
            case .unavailable:
                evaluationLedger.remove(at: ledgerIndex)
                reject(response, because: .evidenceUnavailable)
                return
            case .notEvaluated:
                evaluationLedger.remove(at: ledgerIndex)
                reject(response, because: .dispatchFailed)
                return
            case .satisfied where semantics?.latchesPositiveEvaluation == true:
                evaluationLedger.remove(at: ledgerIndex)
                reject(response, because: .satisfactionAlreadyLatched)
                return
            case .notRequired, .pending, .satisfied, .unmet:
                break
            }

            guard semantics?.latchesPositiveEvaluation == true else {
                evaluationLedger.remove(at: ledgerIndex)
                recordLatest(response)
                return
            }
            evaluationLedger[ledgerIndex].response = response
            drainCorrelatedResponses()
        }

        internal mutating func recordUnavailable(_ unavailability: Unavailability) {
            guard semantics != nil, !isSatisfied else { return }
            status = .unavailable(unavailability)
            rejectCorrelatedResponses(because: .evidenceUnavailable)
        }

        internal mutating func recordDispatchFailure() {
            guard semantics != nil else { return }
            status = .notEvaluated
            rejectCorrelatedResponses(because: .dispatchFailed)
        }

        internal func satisfies(
            _ predicate: Settlement.Predicate?,
            at handoff: Observation.SnapshotEvent
        ) -> Bool {
            guard let predicate else {
                if case .notRequired = status { return true }
                return false
            }
            switch predicate.semantics {
            case .currentState, .completeHistory:
                return responses.first(where: {
                    $0.target == .observation(handoff.moment)
                })?.result.met == true
            case .positiveTransition, .announcement:
                return isSatisfied
            }
        }

        private mutating func recordLatest(_ response: EvaluationResponse) {
            responses.append(response)
            guard let latest = latestObservationResponse else {
                preconditionFailure("Observation predicate response has no observation target")
            }
            status = latest.result.met ? .satisfied(latest) : .unmet(latest)
        }

        private mutating func drainCorrelatedResponses() {
            while let response = evaluationLedger.first?.response {
                evaluationLedger.removeFirst()
                responses.append(response)
                status = response.result.met ? .satisfied(response) : .unmet(response)
                if response.result.met {
                    rejectCorrelatedResponses(because: .satisfactionAlreadyLatched)
                    return
                }
            }
        }

        private mutating func rejectCorrelatedResponses(
            because reason: EvaluationResponseRejectionReason
        ) {
            let responses = evaluationLedger.compactMap(\.response)
            evaluationLedger.removeAll(where: { $0.response != nil })
            rejectedResponses += responses.map {
                RejectedResponse(response: $0, reason: reason)
            }
        }

        private func containsResponse(for target: EvaluationTarget) -> Bool {
            responses.contains(where: { $0.target == target })
                || evaluationLedger.contains(where: { $0.response?.target == target })
                || rejectedResponses.contains(where: { $0.response.target == target })
        }

        private var acceptsEvaluationRequests: Bool {
            switch status {
            case .notRequired, .unavailable, .notEvaluated:
                false
            case .satisfied where semantics?.latchesPositiveEvaluation == true:
                false
            case .pending, .satisfied, .unmet:
                true
            }
        }

        private var latestObservationResponse: EvaluationResponse? {
            responses.reduce(nil) { latest, response in
                guard case .observation(let responseMoment) = response.target else {
                    return latest
                }
                guard let latest,
                      case .observation(let latestMoment) = latest.target else {
                    return response
                }
                return responseMoment.isSameOrAfter(latestMoment) ? response : latest
            }
        }

        private mutating func reject(
            _ response: EvaluationResponse,
            because reason: EvaluationResponseRejectionReason
        ) {
            rejectedResponses.append(RejectedResponse(response: response, reason: reason))
        }
    }

    internal struct Requirement: Sendable, Equatable {
        internal let predicate: Settlement.Predicate?
        internal var evidence: Evidence

        internal init(predicate: Settlement.Predicate?) {
            self.predicate = predicate
            self.evidence = Evidence(predicate: predicate)
        }
    }
}

private extension Settlement.Predicate.Semantics {
    var latchesPositiveEvaluation: Bool {
        switch self {
        case .positiveTransition, .announcement:
            true
        case .currentState, .completeHistory:
            false
        }
    }
}

extension Settlement {
    internal enum Capture {}
    internal enum Readiness {}
    internal enum Handoff {}
}

extension Settlement.Capture {
    internal struct HandoffRequest: Sendable, Equatable {
        internal let scope: SemanticObservationScope
        internal let readinessGeneration: Settlement.Readiness.Generation
    }

    internal enum Request: Sendable, Equatable {
        case baseline(SemanticObservationScope)
        case handoff(HandoffRequest)
    }

    internal enum Failure: Sendable, Equatable {
        case unavailable
        case admissionRejected
    }
}

extension Settlement.Readiness {
    internal struct Generation: RawRepresentable, Sendable, Equatable, Comparable {
        internal static let initial = Generation(rawValue: 0)

        internal let rawValue: UInt64

        internal func advanced() -> Generation {
            Generation(rawValue: rawValue + 1)
        }

        internal static func < (lhs: Generation, rhs: Generation) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    internal enum Path: Sendable, Equatable {
        case currentStateCapture
        case uikitIdle
        case semanticStability
        case accessibilityQuietWindow
    }

    internal enum ObservationBoundary: Sendable, Equatable {
        case including(Observation.Moment)
        case after(Observation.Moment)

        internal func admits(_ moment: Observation.Moment) -> Bool {
            switch self {
            case .including(let boundary):
                moment.isSameOrAfter(boundary)
            case .after(let boundary):
                moment != boundary && moment.isSameOrAfter(boundary)
            }
        }
    }

    internal struct Establishment: Sendable, Equatable {
        internal let generation: Generation
        internal let path: Path
        internal let observationBoundary: ObservationBoundary

        internal init(
            generation: Generation,
            path: Path,
            observationBoundary: ObservationBoundary
        ) {
            self.generation = generation
            self.path = path
            self.observationBoundary = observationBoundary
        }
    }

    internal enum Evidence: Sendable, Equatable {
        case pending(Generation)
        case established(Establishment)

        internal var isEstablished: Bool {
            if case .established = self { return true }
            return false
        }

        internal var generation: Generation {
            switch self {
            case .pending(let generation):
                generation
            case .established(let establishment):
                establishment.generation
            }
        }
    }
}

extension Settlement.Handoff {
    internal struct Admission: Sendable, Equatable {
        internal let event: Observation.SnapshotEvent
        internal let generation: Settlement.Readiness.Generation

        private init(
            event: Observation.SnapshotEvent,
            generation: Settlement.Readiness.Generation
        ) {
            self.event = event
            self.generation = generation
        }

        internal static func admit(
            _ admission: Settlement.ObservationAdmission,
            for readiness: Settlement.Readiness.Establishment
        ) -> Admission? {
            if case .handoffCapture(let generation) = admission.source,
               generation != readiness.generation {
                return nil
            }
            guard readiness.observationBoundary.admits(admission.event.moment) else { return nil }
            return Admission(event: admission.event, generation: readiness.generation)
        }

        internal static func currentState(
            _ event: Observation.SnapshotEvent
        ) -> Admission {
            Admission(event: event, generation: .initial)
        }

        internal func belongs(to readiness: Settlement.Readiness.Establishment) -> Bool {
            generation == readiness.generation
                && readiness.observationBoundary.admits(event.moment)
        }
    }

    internal enum Evidence: Sendable, Equatable {
        case pending(Settlement.Readiness.Generation)
        case captureRequested(Settlement.Capture.HandoffRequest)
        case admitted(Admission)
        case captureFailed(Settlement.Readiness.Generation, Settlement.Capture.Failure)

        internal var event: Observation.SnapshotEvent? {
            guard case .admitted(let admission) = self else { return nil }
            return admission.event
        }

        internal var admission: Admission? {
            guard case .admitted(let admission) = self else { return nil }
            return admission
        }

        internal var generation: Settlement.Readiness.Generation {
            switch self {
            case .pending(let generation), .captureFailed(let generation, _):
                generation
            case .captureRequested(let request):
                request.readinessGeneration
            case .admitted(let admission):
                admission.generation
            }
        }
    }
}

extension Settlement {
    internal enum ObservationAdmissionSource: Sendable, Equatable {
        case observation
        case handoffCapture(Readiness.Generation)
    }

    internal struct ObservationAdmission: Sendable, Equatable {
        internal let event: Observation.SnapshotEvent
        internal let history: Observation.EventsSince
        internal let source: ObservationAdmissionSource

        internal init(
            event: Observation.SnapshotEvent,
            history: Observation.EventsSince,
            source: ObservationAdmissionSource = .observation
        ) {
            if case .events(let events) = history {
                precondition(
                    events.contains(.snapshot(event)),
                    "Settlement admission history must contain its observation event"
                )
            }
            self.event = event
            self.history = history
            self.source = source
        }
    }

    internal struct Arming: Sendable, Equatable {
        internal let boundary: EvidenceBoundary
        internal let observationScope: SemanticObservationScope
        internal let deadline: Deadline
    }

    internal enum TriggerEvidence: Sendable {
        case actionPending(ResolvedHeistActionCommand)
        case actionDispatched(TheSafecracker.ActionDispatchResult)
        case observation

        internal var permitsCompletion: Bool {
            switch self {
            case .actionPending:
                false
            case .actionDispatched(let result):
                result.success
            case .observation:
                true
            }
        }

        internal var dispatchFailed: Bool {
            guard case .actionDispatched(let result) = self else { return false }
            return !result.success
        }
    }

    internal enum BoundaryEvidence: Sendable, Equatable {
        case pending
        case established(EvidenceBoundary)
        case unavailable(Capture.Failure)
    }

    internal enum DeadlineEvidence: Sendable, Equatable {
        case notApplicable(elapsed: ElapsedMilliseconds)
        case bounded(deadline: Deadline, elapsed: ElapsedMilliseconds, reached: Bool)

        internal var elapsed: ElapsedMilliseconds {
            switch self {
            case .notApplicable(let elapsed), .bounded(_, let elapsed, _):
                elapsed
            }
        }

        internal var reached: Bool {
            guard case .bounded(_, _, let reached) = self else { return false }
            return reached
        }
    }

    internal struct ExecutionTiming: Sendable, Equatable {
        internal var beforeObservationMs: ElapsedMilliseconds?
        internal var finalSemanticEvidenceMs: ElapsedMilliseconds?

        internal init(
            beforeObservationMs: ElapsedMilliseconds? = nil,
            finalSemanticEvidenceMs: ElapsedMilliseconds? = nil
        ) {
            self.beforeObservationMs = beforeObservationMs
            self.finalSemanticEvidenceMs = finalSemanticEvidenceMs
        }

        internal mutating func merge(_ other: ExecutionTiming) {
            if let beforeObservationMs = other.beforeObservationMs {
                precondition(self.beforeObservationMs == nil)
                self.beforeObservationMs = beforeObservationMs
            }
            if let finalSemanticEvidenceMs = other.finalSemanticEvidenceMs {
                if let current = self.finalSemanticEvidenceMs {
                    self.finalSemanticEvidenceMs = RuntimeElapsed.admit(
                        milliseconds: current.milliseconds + finalSemanticEvidenceMs.milliseconds
                    )
                } else {
                    self.finalSemanticEvidenceMs = finalSemanticEvidenceMs
                }
            }
        }
    }

    internal struct Evidence: Sendable {
        internal let command: Command
        internal let boundary: BoundaryEvidence
        internal let trigger: TriggerEvidence
        internal let predicate: Predicate.Evidence
        internal let readiness: Readiness.Evidence
        internal let handoff: Handoff.Evidence
        internal let observationHistory: Observation.EventsSince?
        internal let timing: ExecutionTiming
        internal let deadline: DeadlineEvidence

        internal init(
            command: Command,
            boundary: BoundaryEvidence,
            trigger: TriggerEvidence,
            predicate: Predicate.Evidence,
            readiness: Readiness.Evidence,
            handoff: Handoff.Evidence,
            observationHistory: Observation.EventsSince?,
            timing: ExecutionTiming = ExecutionTiming(),
            deadline: DeadlineEvidence
        ) {
            self.command = command
            self.boundary = boundary
            self.trigger = trigger
            self.predicate = predicate
            self.readiness = readiness
            self.handoff = handoff
            self.observationHistory = observationHistory
            self.timing = timing
            self.deadline = deadline
        }
    }

    internal enum Outcome: Sendable, Equatable {
        case settled
        case dispatchFailed
        case baselineUnavailable
        case timedOut
        case cancelled
    }

    internal struct Result: Sendable {
        internal let outcome: Outcome
        internal let evidence: Evidence

        internal init(outcome: Outcome, evidence: Evidence) {
            if outcome == .settled {
                precondition(evidence.trigger.permitsCompletion, "Settlement success requires a completed trigger")
                guard case .established(let readiness) = evidence.readiness else {
                    preconditionFailure("Settlement success requires readiness")
                }
                guard let handoff = evidence.handoff.admission else {
                    preconditionFailure("Settlement success requires an admitted handoff")
                }
                precondition(
                    handoff.belongs(to: readiness),
                    "Settlement success requires a handoff admitted for its readiness generation"
                )
                switch evidence.command {
                case .currentState:
                    precondition(
                        evidence.predicate.status == .notRequired,
                        "Current-state settlement cannot carry a predicate"
                    )
                case .observation, .action:
                    precondition(
                        evidence.predicate.satisfies(evidence.command.predicate, at: handoff.event),
                        "Settlement success requires its predicate at the admitted handoff"
                    )
                }
            }
            self.outcome = outcome
            self.evidence = evidence
        }
    }
}

extension Settlement {
    internal enum State: Sendable {
        case awaitingBaseline(Command)
        case armed(Session)
        case active(Session)
        case terminal(Result)

        internal var result: Result? {
            switch self {
            case .terminal(let result):
                result
            case .awaitingBaseline, .armed, .active:
                nil
            }
        }
    }

    internal struct Session: Sendable {
        internal let command: Command
        internal let boundary: EvidenceBoundary
        internal var triggerEvidence: TriggerEvidence
        internal var requirement: Predicate.Requirement
        internal var readiness: Readiness.Evidence
        internal var handoff: Handoff.Evidence
        internal var observationHistory: Observation.EventsSince?
        internal var latestObservation: ObservationAdmission?
        internal var timing: ExecutionTiming

        internal init(
            command: Command,
            boundary: EvidenceBoundary,
            timing: ExecutionTiming
        ) {
            self.command = command
            self.boundary = boundary
            self.triggerEvidence = switch command {
            case .action(let action, _, _, _): .actionPending(action)
            case .currentState, .observation: .observation
            }
            self.requirement = Predicate.Requirement(predicate: command.predicate)
            self.readiness = .pending(.initial)
            self.handoff = .pending(.initial)
            self.observationHistory = nil
            self.latestObservation = nil
            self.timing = timing
        }
    }

    internal struct Event: Sendable {
        internal let fact: Fact
        internal let timing: ExecutionTiming
        internal let elapsed: ElapsedMilliseconds

        internal init(
            fact: Fact,
            timing: ExecutionTiming = ExecutionTiming(),
            elapsed: ElapsedMilliseconds
        ) {
            self.fact = fact
            self.timing = timing
            self.elapsed = elapsed
        }
    }

    internal struct Decision: Sendable {
        internal let state: State
        internal let effects: [Effect]
    }

    internal enum Effect: Sendable {
        case capture(Capture.Request)
        case arm(Arming)
        case dispatchAction(ResolvedHeistActionCommand)
        case evaluatePredicate(Predicate.EvaluationRequest)
    }
}

extension Settlement.Command {
    internal struct Action: Sendable, Equatable {
        internal let command: ResolvedHeistActionCommand
        internal let predicate: Settlement.Predicate?
        internal let allowances: Settlement.ActionAllowances
        internal let baseline: Settlement.Baseline
    }
}

extension Settlement.Session {
    internal enum Phase: Sendable, Equatable {
        case observation(Settlement.PhaseDeadline)
        case awaitingActionDispatch
        case actionReadiness(Settlement.PhaseDeadline)
        case actionExpectation(Settlement.PhaseDeadline)
    }
}

extension Settlement.Event {
    internal struct DeadlineReached: Sendable, Equatable {
        internal let phase: Settlement.DeadlinePhase
        internal let instant: ContinuousClock.Instant
    }
}

extension Settlement.Effect {
    internal struct ArmDeadline: Sendable, Equatable {
        internal let deadline: Settlement.PhaseDeadline
    }
}

extension Settlement.Outcome {
    internal struct Timeout: Sendable, Equatable {
        internal let phase: Settlement.DeadlinePhase
    }
}

extension Settlement.Result {
    internal struct ElapsedEvidence: Sendable, Equatable {
        internal let elapsed: ElapsedMilliseconds
    }
}

extension Settlement.Event {
    internal enum Fact: Sendable {
        case baselineAdmitted(Observation.SnapshotEvent)
        case baselineUnavailable(Settlement.Capture.Failure)
        case channelsArmed
        case dispatchCompleted(TheSafecracker.ActionDispatchResult)
        case observationAdmitted(Settlement.ObservationAdmission)
        case announcementObserved(Observation.AnnouncementEvent)
        case observationHistoryUnavailable(Observation.EventsSince)
        case announcementHistoryUnavailable(AccessibilityNotificationGap)
        case predicateEvaluated(Settlement.Predicate.EvaluationResponse)
        case readinessEstablished(Settlement.Readiness.Establishment)
        case readinessInvalidated(Settlement.Readiness.Generation)
        case handoffCaptureFailed(Settlement.Readiness.Generation, Settlement.Capture.Failure)
        case deadlineReached
        case cancelled
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
