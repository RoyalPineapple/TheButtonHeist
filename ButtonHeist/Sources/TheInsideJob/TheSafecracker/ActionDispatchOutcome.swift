#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    /// Outcome of a high-level action dispatch before post-action observation.
    /// TheInsideJob wraps this with post-action observations to produce the wire ActionResult.
    struct ActionDispatchOutcome {
        let message: String?
        let outcome: ActionDispatchState

        var method: ActionMethod {
            switch outcome {
            case .success(let success):
                return success.method
            case .failure(let failure):
                return failure.method
            }
        }

        var success: Bool {
            if case .success = outcome { return true }
            return false
        }

        var payload: ActionResultPayload? {
            if case .success(let success) = outcome { return success.payload }
            return nil
        }

        var subjectEvidence: ActionSubjectEvidence? {
            switch outcome {
            case .success(let success):
                return success.subjectEvidence
            case .failure(let failure):
                return failure.subjectEvidence
            }
        }

        var resolvedElementId: HeistId? {
            if case .success(let success) = outcome { return success.resolvedElementId }
            return nil
        }

        var activationTrace: ActivationTrace? {
            switch outcome {
            case .success(let success):
                return success.activationTrace
            case .failure(let failure):
                return failure.activationTrace
            }
        }

        var timing: ActionPerformanceTiming? {
            switch outcome {
            case .success(let success):
                return success.timing
            case .failure(let failure):
                return failure.timing
            }
        }

        var failureKind: FailureKind? {
            if case .failure(let failure) = outcome { return failure.kind }
            return nil
        }

        private init(
            message: String?,
            outcome: ActionDispatchState
        ) {
            self.message = message
            self.outcome = outcome
        }

        static func success(
            method: ActionMethod,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> ActionDispatchOutcome {
            ActionDispatchOutcome(
                message: message,
                outcome: .success(ActionDispatchSuccess(
                    method: method,
                    subjectEvidence: subjectEvidence,
                    resolvedElementId: resolvedElementId,
                    activationTrace: activationTrace
                ))
            )
        }

        static func success(
            payload: ActionResultPayload,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> ActionDispatchOutcome {
            ActionDispatchOutcome(
                message: message,
                outcome: .success(ActionDispatchSuccess(
                    payload: payload,
                    subjectEvidence: subjectEvidence,
                    resolvedElementId: resolvedElementId,
                    activationTrace: activationTrace
                ))
            )
        }

        static func failure(
            _ method: ActionMethod,
            message: String,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil,
            failureKind: FailureKind = .actionFailed
        ) -> ActionDispatchOutcome {
            ActionDispatchOutcome(
                message: message,
                outcome: .failure(ActionDispatchFailure(
                    method: method,
                    kind: failureKind,
                    subjectEvidence: subjectEvidence,
                    activationTrace: activationTrace
                ))
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> ActionDispatchOutcome {
            guard let evidence else { return self }
            switch outcome {
            case .success(let success):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .success(success.withSubjectEvidence(evidence))
                )
            case .failure(let failure):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .failure(failure.withSubjectEvidence(evidence))
                )
            }
        }

        func withResolvedElementId(_ heistId: HeistId) -> ActionDispatchOutcome {
            switch outcome {
            case .success(let success):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .success(success.withResolvedElementId(heistId))
                )
            case .failure:
                return self
            }
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> ActionDispatchOutcome {
            guard let trace else { return self }
            switch outcome {
            case .success(let success):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .success(success.withActivationTrace(trace))
                )
            case .failure(let failure):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .failure(failure.withActivationTrace(trace))
                )
            }
        }

        func withTiming(_ timing: ActionPerformanceTiming?) -> ActionDispatchOutcome {
            guard let timing else { return self }
            let mergedTiming = self.timing?.merging(timing) ?? timing
            switch outcome {
            case .success(let success):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .success(success.withTiming(mergedTiming))
                )
            case .failure(let failure):
                return ActionDispatchOutcome(
                    message: message,
                    outcome: .failure(failure.withTiming(mergedTiming))
                )
            }
        }

    }

    enum ActionDispatchState {
        case success(ActionDispatchSuccess)
        case failure(ActionDispatchFailure)
    }

    struct ActionDispatchSuccess {
        let method: ActionMethod
        let payload: ActionResultPayload?
        let subjectEvidence: ActionSubjectEvidence?
        let resolvedElementId: HeistId?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?

        init(
            method: ActionMethod,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil,
            timing: ActionPerformanceTiming? = nil
        ) {
            self.method = method
            payload = nil
            self.subjectEvidence = subjectEvidence
            self.resolvedElementId = resolvedElementId
            self.activationTrace = activationTrace
            self.timing = timing
        }

        init(
            payload: ActionResultPayload,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil,
            timing: ActionPerformanceTiming? = nil
        ) {
            method = payload.method
            self.payload = payload
            self.subjectEvidence = subjectEvidence
            self.resolvedElementId = resolvedElementId
            self.activationTrace = activationTrace
            self.timing = timing
        }

        private init(
            preserving source: ActionDispatchSuccess,
            subjectEvidence: ActionSubjectEvidence?,
            resolvedElementId: HeistId?,
            activationTrace: ActivationTrace?,
            timing: ActionPerformanceTiming?
        ) {
            method = source.method
            payload = source.payload
            self.subjectEvidence = subjectEvidence
            self.resolvedElementId = resolvedElementId
            self.activationTrace = activationTrace
            self.timing = timing
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence) -> ActionDispatchSuccess {
            ActionDispatchSuccess(
                preserving: self,
                subjectEvidence: evidence,
                resolvedElementId: resolvedElementId,
                activationTrace: activationTrace,
                timing: timing
            )
        }

        func withResolvedElementId(_ heistId: HeistId) -> ActionDispatchSuccess {
            ActionDispatchSuccess(
                preserving: self,
                subjectEvidence: subjectEvidence,
                resolvedElementId: heistId,
                activationTrace: activationTrace,
                timing: timing
            )
        }

        func withActivationTrace(_ trace: ActivationTrace) -> ActionDispatchSuccess {
            ActionDispatchSuccess(
                preserving: self,
                subjectEvidence: subjectEvidence,
                resolvedElementId: resolvedElementId,
                activationTrace: trace,
                timing: timing
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming) -> ActionDispatchSuccess {
            ActionDispatchSuccess(
                preserving: self,
                subjectEvidence: subjectEvidence,
                resolvedElementId: resolvedElementId,
                activationTrace: activationTrace,
                timing: timing
            )
        }
    }

    struct ActionDispatchFailure {
        /// Structural reason for failure. Lets dispatch code distinguish
        /// tree-unavailable from timeout without parsing `message` (which is
        /// user-facing copy, not a control-flow contract).
        let method: ActionMethod
        let kind: FailureKind
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?

        init(
            method: ActionMethod,
            kind: FailureKind,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil,
            timing: ActionPerformanceTiming? = nil
        ) {
            self.method = method
            self.kind = kind
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
            self.timing = timing
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence) -> ActionDispatchFailure {
            ActionDispatchFailure(
                method: method,
                kind: kind,
                subjectEvidence: evidence,
                activationTrace: activationTrace,
                timing: timing
            )
        }

        func withActivationTrace(_ trace: ActivationTrace) -> ActionDispatchFailure {
            ActionDispatchFailure(
                method: method,
                kind: kind,
                subjectEvidence: subjectEvidence,
                activationTrace: trace,
                timing: timing
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming) -> ActionDispatchFailure {
            ActionDispatchFailure(
                method: method,
                kind: kind,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing
            )
        }
    }

    /// Internal failure kinds used by dispatch to choose the wire ErrorKind.
    /// Not wire format — this is an internal control-flow signal.
    enum FailureKind {
        /// Generic interaction failure that does not carry a more specific kind.
        case actionFailed
        /// The accessibility tree could not be parsed (no traversable windows).
        case treeUnavailable
        /// A polling/wait operation exceeded its budget.
        case timeout
        /// Input geometry or other client-controlled values failed validation.
        case inputValidation
        /// The command target was not present or its live accessibility object expired.
        case targetUnavailable
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
