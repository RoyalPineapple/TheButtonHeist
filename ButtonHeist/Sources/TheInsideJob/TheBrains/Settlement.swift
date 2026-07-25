#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal enum Settlement {}

extension Settlement {
    internal enum Command: Sendable, Equatable {
        case currentState(scope: SemanticObservationScope)
        case observation(
            predicate: Predicate,
            deadline: PhaseDeadline,
            baseline: Baseline
        )
        case action(Action)

        internal init(
            observing authored: AccessibilityPredicate,
            resolved: ResolvedAccessibilityPredicate,
            timeout: WaitTimeout,
            baseline: Baseline = .capture,
            startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
        ) {
            self = .observation(
                predicate: Predicate(
                    authored: authored,
                    resolved: resolved
                ),
                deadline: PhaseDeadline(
                    phase: .observation,
                    instant: startedAt.advanced(by: .seconds(timeout.seconds))
                ),
                baseline: baseline
            )
        }

        internal var predicate: Predicate? {
            switch self {
            case .currentState:
                nil
            case .observation(let predicate, _, _):
                predicate
            case .action(let action):
                action.predicate
            }
        }

        internal var observationScope: SemanticObservationScope {
            switch self {
            case .currentState(let scope):
                scope
            case .observation(let predicate, _, _):
                predicate.observationScope
            case .action(let action):
                action.predicate?.observationScope ?? .visible
            }
        }

        internal var baseline: Baseline? {
            switch self {
            case .currentState:
                nil
            case .observation(_, _, let baseline):
                baseline
            case .action(let action):
                action.baseline
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

    internal struct PhaseDeadline: Sendable, Equatable {
        internal let phase: DeadlinePhase
        internal let instant: ContinuousClock.Instant

        internal func remainingDuration(
            at now: ContinuousClock.Instant = RuntimeElapsed.now
        ) -> Duration {
            return max(.zero, now.duration(to: instant))
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

    internal struct ActionExpectation: Sendable, Equatable {
        internal let predicate: Predicate
        internal let allowance: Duration

        internal init(
            authored: AccessibilityPredicate,
            resolved: ResolvedAccessibilityPredicate,
            timeout: WaitTimeout
        ) {
            self.predicate = Predicate(authored: authored, resolved: resolved)
            self.allowance = .milliseconds(Int64((timeout.seconds * 1_000).rounded(.up)))
        }
    }

    internal enum DeadlinePhase: Sendable, Equatable {
        case observation
        case actionReadiness
        case actionExpectation
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
        switch predicate {
        case .exists, .missing:
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

        internal func satisfyingResponse(
            for predicate: Settlement.Predicate,
            at handoff: Observation.SnapshotEvent
        ) -> EvaluationResponse? {
            switch predicate.semantics {
            case .currentState, .completeHistory:
                return responses.first {
                    $0.target == .observation(handoff.moment) && $0.result.met
                }
            case .positiveTransition, .announcement:
                guard case .satisfied(let response) = status else { return nil }
                return response
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

    /// How readiness was established. Two ways remain: a capture that runs no
    /// diff at all, and the settle loop's comparison coming back unchanged.
    internal enum Path: Sendable, Equatable {
        case currentStateCapture
        case semanticStability
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
        /// What the settle loop's final comparison actually saw. `nil` when
        /// readiness came from a path that runs no diff (current-state
        /// capture). This is the raw change data the settle seam used to drop.
        internal let delta: SettleDelta?

        internal init(
            generation: Generation,
            path: Path,
            observationBoundary: ObservationBoundary,
            delta: SettleDelta? = nil
        ) {
            self.generation = generation
            self.path = path
            self.observationBoundary = observationBoundary
            self.delta = delta
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

        /// The observation change that established readiness, once it has.
        internal var delta: SettleDelta? {
            guard case .established(let establishment) = self else { return nil }
            return establishment.delta
        }
    }
}

extension Settlement.Handoff {
    internal struct Admission: Sendable, Equatable {
        internal let event: Observation.SnapshotEvent
        internal let generation: Settlement.Readiness.Generation
        internal let instant: ContinuousClock.Instant

        private init(
            event: Observation.SnapshotEvent,
            generation: Settlement.Readiness.Generation,
            instant: ContinuousClock.Instant
        ) {
            self.event = event
            self.generation = generation
            self.instant = instant
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
            return Admission(
                event: admission.event,
                generation: readiness.generation,
                instant: admission.instant
            )
        }

        internal static func currentState(
            _ event: Observation.SnapshotEvent
        ) -> Admission {
            Admission(
                event: event,
                generation: .initial,
                instant: RuntimeElapsed.now
            )
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
        internal let instant: ContinuousClock.Instant

        internal init(
            event: Observation.SnapshotEvent,
            history: Observation.EventsSince,
            source: ObservationAdmissionSource = .observation,
            instant: ContinuousClock.Instant = RuntimeElapsed.now
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
            self.instant = instant
        }
    }

    internal struct Arming: Sendable, Equatable {
        internal let boundary: EvidenceBoundary
        internal let observationScope: SemanticObservationScope
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

        internal var established: EvidenceBoundary? {
            guard case .established(let boundary) = self else { return nil }
            return boundary
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

    internal enum Result: Sendable {
        case currentState(CurrentStateOutcome)
        case observation(ObservationOutcome)
        case action(ActionOutcome)
    }
}

extension Settlement.Result {
    internal struct Timing: Sendable, Equatable {
        internal var execution: Settlement.ExecutionTiming
        internal let elapsed: ElapsedMilliseconds
    }

    internal enum CurrentStateOutcome: Sendable {
        case captured(CurrentStateCapture)
        case failed(CurrentStateFailure)
    }

    internal struct CurrentStateCapture: Sendable {
        internal let event: Observation.SnapshotEvent
        internal var timing: Timing
    }

    internal enum CurrentStateFailureReason: Sendable, Equatable {
        case unavailable(Settlement.Capture.Failure)
        case cancelled
    }

    internal struct CurrentStateFailure: Sendable {
        internal let reason: CurrentStateFailureReason
        internal var timing: Timing
    }

    internal enum ObservationOutcome: Sendable {
        case settled(SettledObservation)
        case failed(FailedObservation)
    }

    internal struct SettledObservation: Sendable {
        internal let predicate: Settlement.Predicate
        internal let boundary: Settlement.EvidenceBoundary
        internal let evaluation: Settlement.Predicate.EvaluationResponse
        internal let readiness: Settlement.Readiness.Establishment
        internal let handoff: Settlement.Handoff.Admission
        internal let history: Observation.EventsSince?
        internal var timing: Timing
    }

    internal struct ObservationAttempt: Sendable {
        internal let predicate: Settlement.Predicate
        internal let boundary: Settlement.BoundaryEvidence
        internal let evaluation: Settlement.Predicate.Evidence
        internal let readiness: Settlement.Readiness.Evidence
        internal let handoff: Settlement.Handoff.Evidence
        internal let history: Observation.EventsSince?
        internal var timing: Timing
    }

    internal enum ObservationFailureReason: Sendable, Equatable {
        case baselineUnavailable
        case timedOut(Settlement.DeadlinePhase)
        case cancelled
        case viewportExitFailed(Navigation.ViewportExit.Failure)
    }

    internal struct FailedObservation: Sendable {
        internal let reason: ObservationFailureReason
        internal var attempt: ObservationAttempt
    }

    internal enum ActionOutcome: Sendable {
        case settled(SettledAction)
        case failed(FailedAction)
    }

    internal enum ActionDispatch: Sendable {
        case pending
        case completed(TheSafecracker.ActionDispatchResult)
    }

    internal struct SettledAction: Sendable {
        internal let command: Settlement.Command.Action
        internal let boundary: Settlement.EvidenceBoundary
        internal let dispatch: TheSafecracker.ActionDispatchResult
        internal let evaluation: Settlement.Predicate.EvaluationResponse?
        internal let readiness: Settlement.Readiness.Establishment
        internal let handoff: Settlement.Handoff.Admission
        internal let history: Observation.EventsSince?
        internal var timing: Timing
    }

    internal struct ActionAttempt: Sendable {
        internal let command: Settlement.Command.Action
        internal let boundary: Settlement.BoundaryEvidence
        internal let dispatch: ActionDispatch
        internal let evaluation: Settlement.Predicate.Evidence
        internal let readiness: Settlement.Readiness.Evidence
        internal let handoff: Settlement.Handoff.Evidence
        internal let history: Observation.EventsSince?
        internal var timing: Timing
    }

    internal enum ActionFailureReason: Sendable, Equatable {
        case dispatchFailed
        case baselineUnavailable
        case timedOut(Settlement.DeadlinePhase)
        case cancelled
        case viewportExitFailed(Navigation.ViewportExit.Failure)
    }

    internal struct FailedAction: Sendable {
        internal let reason: ActionFailureReason
        internal var attempt: ActionAttempt
    }

    internal var currentObservation: Observation.SnapshotEvent? {
        switch self {
        case .currentState(.captured(let capture)):
            capture.event
        case .currentState(.failed):
            nil
        case .observation(.settled(let settled)):
            settled.handoff.event
        case .observation(.failed(let failed)):
            failed.attempt.handoff.event
        case .action(.settled(let settled)):
            settled.handoff.event
        case .action(.failed(let failed)):
            failed.attempt.handoff.event
        }
    }
}

extension Settlement {
    internal enum State: Sendable {
        case awaitingBaseline(Command)
        case armed(Session)
        case active(Session)
        case quiescing(Quiescence)
        case terminal(Result)

        internal var result: Result? {
            switch self {
            case .terminal(let result):
                result
            case .awaitingBaseline, .armed, .active, .quiescing:
                nil
            }
        }
    }

    internal struct Quiescence: Sendable {
        internal let session: Session
        internal let intendedOutcome: TerminalIntent
        internal let elapsed: ElapsedMilliseconds
    }

    internal enum TerminalIntent: Sendable, Equatable {
        case settled
        case dispatchFailed
        case timedOut(DeadlinePhase)
        case cancelled
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
        internal var phase: Phase

        internal init(
            command: Command,
            boundary: EvidenceBoundary,
            timing: ExecutionTiming
        ) {
            self.command = command
            self.boundary = boundary
            self.triggerEvidence = switch command {
            case .action(let action): .actionPending(action.command)
            case .currentState, .observation: .observation
            }
            self.requirement = Predicate.Requirement(predicate: command.predicate)
            self.readiness = .pending(.initial)
            self.handoff = .pending(.initial)
            self.observationHistory = nil
            self.latestObservation = nil
            self.timing = timing
            self.phase = switch command {
            case .observation(_, let deadline, _): .observation(deadline)
            case .action: .awaitingActionDispatch
            case .currentState:
                preconditionFailure("Current-state capture cannot create a settlement session")
            }
        }
    }

    internal struct Event: Sendable {
        internal let fact: Fact
        internal let timing: ExecutionTiming
        internal let elapsed: ElapsedMilliseconds
        internal let instant: ContinuousClock.Instant

        internal init(
            fact: Fact,
            timing: ExecutionTiming = ExecutionTiming(),
            elapsed: ElapsedMilliseconds,
            instant: ContinuousClock.Instant = RuntimeElapsed.now
        ) {
            self.fact = fact
            self.timing = timing
            self.elapsed = elapsed
            self.instant = instant
        }
    }

    internal struct Decision: Sendable {
        internal let state: State
        internal let effects: [Effect]
    }

    internal enum Effect: Sendable {
        case capture(Capture.Request)
        case arm(Arming)
        case armReadiness(PhaseDeadline)
        case armDeadline(PhaseDeadline)
        case dispatchAction(ResolvedHeistActionCommand)
        case evaluatePredicate(Predicate.EvaluationRequest)
        case quiesce(Arming)
    }
}

extension Settlement.Command {
    internal struct Action: Sendable, Equatable {
        internal let command: ResolvedHeistActionCommand
        internal let predicate: Settlement.Predicate?
        internal let allowances: Settlement.ActionAllowances
        internal let baseline: Settlement.Baseline

        internal init(
            command: ResolvedHeistActionCommand,
            predicate: Settlement.Predicate?,
            allowances: Settlement.ActionAllowances,
            baseline: Settlement.Baseline
        ) {
            precondition(
                (predicate == nil) == (allowances.expectation == nil),
                "Settlement action expectation requires one authored allowance"
            )
            self.command = command
            self.predicate = predicate
            self.allowances = allowances
            self.baseline = baseline
        }
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
        case deadlineReached(Settlement.PhaseDeadline)
        case cancelled
        case quiesced(Navigation.ViewportExit.Outcome)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
