#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    /// Outcome of a high-level interaction (action, gesture, text entry).
    /// TheInsideJob wraps this with post-action observations to produce the wire ActionResult.
    struct InteractionResult {
        let method: ActionMethod
        let message: String?
        let outcome: InteractionOutcome

        var success: Bool {
            if case .success = outcome { return true }
            return false
        }

        var payload: ActionResultPayload? {
            if case .success(let success) = outcome { return success.payload }
            return nil
        }

        var subjectEvidence: ActionSubjectEvidence? {
            if case .success(let success) = outcome { return success.subjectEvidence }
            return nil
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
            method: ActionMethod,
            message: String?,
            outcome: InteractionOutcome
        ) {
            self.method = method
            self.message = message
            self.outcome = outcome
        }

        static func success(
            method: ActionMethod,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> InteractionResult {
            InteractionResult(
                method: method,
                message: message,
                outcome: .success(InteractionSuccess(
                    payload: nil,
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
        ) -> InteractionResult {
            InteractionResult(
                method: payload.method,
                message: message,
                outcome: .success(InteractionSuccess(
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
            activationTrace: ActivationTrace? = nil,
            failureKind: FailureKind = .actionFailed
        ) -> InteractionResult {
            InteractionResult(
                method: method,
                message: message,
                outcome: .failure(InteractionFailure(
                    kind: failureKind,
                    activationTrace: activationTrace
                ))
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> InteractionResult {
            guard let evidence else { return self }
            switch outcome {
            case .success(let success):
                return InteractionResult(
                    method: method,
                    message: message,
                    outcome: .success(InteractionSuccess(
                        payload: success.payload,
                        subjectEvidence: evidence,
                        resolvedElementId: success.resolvedElementId,
                        activationTrace: success.activationTrace,
                        timing: success.timing
                    ))
                )
            case .failure:
                return self
            }
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> InteractionResult {
            guard let trace else { return self }
            switch outcome {
            case .success(let success):
                return InteractionResult(
                    method: method,
                    message: message,
                    outcome: .success(InteractionSuccess(
                        payload: success.payload,
                        subjectEvidence: success.subjectEvidence,
                        resolvedElementId: success.resolvedElementId,
                        activationTrace: trace,
                        timing: success.timing
                    ))
                )
            case .failure(let failure):
                return InteractionResult(
                    method: method,
                    message: message,
                    outcome: .failure(InteractionFailure(
                        kind: failure.kind,
                        activationTrace: trace,
                        timing: failure.timing
                    ))
                )
            }
        }

        func withTiming(_ timing: ActionPerformanceTiming?) -> InteractionResult {
            guard let timing else { return self }
            let mergedTiming = self.timing?.merging(timing) ?? timing
            switch outcome {
            case .success(let success):
                return InteractionResult(
                    method: method,
                    message: message,
                    outcome: .success(InteractionSuccess(
                        payload: success.payload,
                        subjectEvidence: success.subjectEvidence,
                        resolvedElementId: success.resolvedElementId,
                        activationTrace: success.activationTrace,
                        timing: mergedTiming
                    ))
                )
            case .failure(let failure):
                return InteractionResult(
                    method: method,
                    message: message,
                    outcome: .failure(InteractionFailure(
                        kind: failure.kind,
                        activationTrace: failure.activationTrace,
                        timing: mergedTiming
                    ))
                )
            }
        }
    }

    enum InteractionOutcome {
        case success(InteractionSuccess)
        case failure(InteractionFailure)
    }

    struct InteractionSuccess {
        let payload: ActionResultPayload?
        let subjectEvidence: ActionSubjectEvidence?
        let resolvedElementId: HeistId?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?

        init(
            payload: ActionResultPayload? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil,
            timing: ActionPerformanceTiming? = nil
        ) {
            self.payload = payload
            self.subjectEvidence = subjectEvidence
            self.resolvedElementId = resolvedElementId
            self.activationTrace = activationTrace
            self.timing = timing
        }
    }

    struct InteractionFailure {
        /// Structural reason for failure. Lets dispatch code distinguish
        /// tree-unavailable from timeout without parsing `message` (which is
        /// user-facing copy, not a control-flow contract).
        let kind: FailureKind
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?

        init(
            kind: FailureKind,
            activationTrace: ActivationTrace? = nil,
            timing: ActionPerformanceTiming? = nil
        ) {
            self.kind = kind
            self.activationTrace = activationTrace
            self.timing = timing
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
