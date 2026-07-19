#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    enum ActionDispatchOutcome: Sendable {
        case success(payload: ActionResultPayload?, resolvedElementId: HeistId?)
        case failure(FailureKind)
    }

    /// Result of a high-level action dispatch before post-action observation.
    /// Post-action observation adds semantic evidence to produce the wire `ActionResult`.
    struct ActionDispatchResult: Sendable {
        let method: ActionMethod
        let message: String?
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?
        let outcome: ActionDispatchOutcome

        var success: Bool {
            if case .success = outcome { return true }
            return false
        }

        var payload: ActionResultPayload? {
            guard case .success(let payload, _) = outcome else { return nil }
            return payload
        }

        var resolvedElementId: HeistId? {
            guard case .success(_, let resolvedElementId) = outcome else { return nil }
            return resolvedElementId
        }

        var failureKind: FailureKind? {
            guard case .failure(let failureKind) = outcome else { return nil }
            return failureKind
        }

        private init(
            method: ActionMethod,
            message: String?,
            subjectEvidence: ActionSubjectEvidence?,
            activationTrace: ActivationTrace?,
            timing: ActionPerformanceTiming?,
            outcome: ActionDispatchOutcome
        ) {
            self.method = method
            self.message = message
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
            self.timing = timing
            self.outcome = outcome
        }

        static func success(
            method: ActionMethod,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> ActionDispatchResult {
            ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                outcome: .success(payload: nil, resolvedElementId: resolvedElementId)
            )
        }

        static func success(
            payload: ActionResultPayload,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> ActionDispatchResult {
            ActionDispatchResult(
                method: payload.method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                outcome: .success(payload: payload, resolvedElementId: resolvedElementId)
            )
        }

        static func failure(
            _ method: ActionMethod,
            message: String,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil,
            failureKind: FailureKind = .actionFailed
        ) -> ActionDispatchResult {
            ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                outcome: .failure(failureKind)
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> ActionDispatchResult {
            guard let evidence else { return self }
            return ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: evidence,
                activationTrace: activationTrace,
                timing: timing,
                outcome: outcome
            )
        }

        func withResolvedElementId(_ heistId: HeistId) -> ActionDispatchResult {
            guard case .success(let payload, _) = outcome else { return self }
            return ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing,
                outcome: .success(payload: payload, resolvedElementId: heistId)
            )
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> ActionDispatchResult {
            guard let trace else { return self }
            return ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: trace,
                timing: timing,
                outcome: outcome
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming?) -> ActionDispatchResult {
            guard let timing else { return self }
            return ActionDispatchResult(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: self.timing?.merging(timing) ?? timing,
                outcome: outcome
            )
        }
    }

    /// Internal failure kinds used by dispatch to choose the wire `ActionFailure.Kind`.
    /// Not wire format — this is an internal control-flow signal.
    enum FailureKind: Sendable {
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
