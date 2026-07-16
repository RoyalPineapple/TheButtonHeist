#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    enum ActionDispatchOutcomeState: Sendable {
        case success(payload: ActionResultPayload?, resolvedElementId: HeistId?)
        case failure(FailureKind)
    }

    /// Outcome of a high-level action dispatch before post-action observation.
    /// Post-action observation adds semantic evidence to this value to produce the wire ActionResult.
    struct ActionDispatchOutcome: Sendable {
        let method: ActionMethod
        let message: String?
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?
        let state: ActionDispatchOutcomeState

        var success: Bool {
            if case .success = state { return true }
            return false
        }

        var payload: ActionResultPayload? {
            guard case .success(let payload, _) = state else { return nil }
            return payload
        }

        var resolvedElementId: HeistId? {
            guard case .success(_, let resolvedElementId) = state else { return nil }
            return resolvedElementId
        }

        var failureKind: FailureKind? {
            guard case .failure(let failureKind) = state else { return nil }
            return failureKind
        }

        private init(
            method: ActionMethod,
            message: String?,
            subjectEvidence: ActionSubjectEvidence?,
            activationTrace: ActivationTrace?,
            timing: ActionPerformanceTiming?,
            state: ActionDispatchOutcomeState
        ) {
            self.method = method
            self.message = message
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
            self.timing = timing
            self.state = state
        }

        static func success(
            method: ActionMethod,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> ActionDispatchOutcome {
            ActionDispatchOutcome(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                state: .success(payload: nil, resolvedElementId: resolvedElementId)
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
                method: payload.method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                state: .success(payload: payload, resolvedElementId: resolvedElementId)
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
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: nil,
                state: .failure(failureKind)
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> ActionDispatchOutcome {
            guard let evidence else { return self }
            return ActionDispatchOutcome(
                method: method,
                message: message,
                subjectEvidence: evidence,
                activationTrace: activationTrace,
                timing: timing,
                state: state
            )
        }

        func withResolvedElementId(_ heistId: HeistId) -> ActionDispatchOutcome {
            guard case .success(let payload, _) = state else { return self }
            return ActionDispatchOutcome(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing,
                state: .success(payload: payload, resolvedElementId: heistId)
            )
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> ActionDispatchOutcome {
            guard let trace else { return self }
            return ActionDispatchOutcome(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: trace,
                timing: timing,
                state: state
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming?) -> ActionDispatchOutcome {
            guard let timing else { return self }
            return ActionDispatchOutcome(
                method: method,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: self.timing?.merging(timing) ?? timing,
                state: state
            )
        }
    }

    /// Internal failure kinds used by dispatch to choose the wire ErrorKind.
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
