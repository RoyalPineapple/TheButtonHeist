#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    enum ActionDispatchOutcome: Sendable {
        case success(resolvedElementId: HeistId?)
        case failure(FailureKind)
    }

    /// Result of a high-level action dispatch before post-action observation.
    /// Post-action observation adds semantic evidence to produce the wire `ActionResult`.
    struct ActionDispatchResult: Sendable {
        let payload: ActionResult.Payload
        var method: ActionMethod { payload.method }
        let message: String?
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let screenActionHandler: ScreenActionHandlerName?
        let timing: ActionPerformanceTiming?
        let outcome: ActionDispatchOutcome

        var success: Bool {
            if case .success = outcome { return true }
            return false
        }

        var resolvedElementId: HeistId? {
            guard case .success(let resolvedElementId) = outcome else { return nil }
            return resolvedElementId
        }

        var failureKind: FailureKind? {
            guard case .failure(let failureKind) = outcome else { return nil }
            return failureKind
        }

        private init(
            payload: ActionResult.Payload,
            message: String?,
            subjectEvidence: ActionSubjectEvidence?,
            activationTrace: ActivationTrace?,
            screenActionHandler: ScreenActionHandlerName?,
            timing: ActionPerformanceTiming?,
            outcome: ActionDispatchOutcome
        ) {
            self.payload = payload
            self.message = message
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
            self.screenActionHandler = screenActionHandler
            self.timing = timing
            self.outcome = outcome
        }

        static func success(
            payload: ActionResult.Payload,
            message: String? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            resolvedElementId: HeistId? = nil,
            activationTrace: ActivationTrace? = nil,
            screenActionHandler: ScreenActionHandlerName? = nil
        ) -> ActionDispatchResult {
            ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                screenActionHandler: screenActionHandler,
                timing: nil,
                outcome: .success(resolvedElementId: resolvedElementId)
            )
        }

        static func failure(
            _ payload: ActionResult.Payload,
            message: String,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil,
            failureKind: FailureKind = .actionFailed
        ) -> ActionDispatchResult {
            ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                screenActionHandler: nil,
                timing: nil,
                outcome: .failure(failureKind)
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> ActionDispatchResult {
            guard let evidence else { return self }
            return ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: evidence,
                activationTrace: activationTrace,
                screenActionHandler: screenActionHandler,
                timing: timing,
                outcome: outcome
            )
        }

        func withResolvedElementId(_ heistId: HeistId) -> ActionDispatchResult {
            guard case .success = outcome else { return self }
            return ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                screenActionHandler: screenActionHandler,
                timing: timing,
                outcome: .success(resolvedElementId: heistId)
            )
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> ActionDispatchResult {
            guard let trace else { return self }
            return ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: trace,
                screenActionHandler: screenActionHandler,
                timing: timing,
                outcome: outcome
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming) -> ActionDispatchResult {
            ActionDispatchResult(
                payload: payload,
                message: message,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                screenActionHandler: screenActionHandler,
                timing: timing,
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
