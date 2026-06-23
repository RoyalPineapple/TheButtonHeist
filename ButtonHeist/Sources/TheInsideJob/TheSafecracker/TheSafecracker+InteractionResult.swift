#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheSafecracker {

    /// Outcome of a high-level interaction (action, gesture, text entry).
    /// TheInsideJob wraps this with AccessibilityTrace.Delta to produce the wire ActionResult.
    struct InteractionResult {
        let success: Bool
        let method: ActionMethod
        let message: String?
        let payload: ResultPayload?
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let timing: ActionPerformanceTiming?
        /// Structural reason for failure when `success == false`. Lets dispatch code
        /// distinguish tree-unavailable from timeout without parsing `message`
        /// (which is user-facing copy, not a control-flow contract).
        let failureKind: FailureKind?

        private init(
            success: Bool,
            method: ActionMethod,
            message: String?,
            payload: ResultPayload?,
            subjectEvidence: ActionSubjectEvidence?,
            activationTrace: ActivationTrace?,
            timing: ActionPerformanceTiming? = nil,
            failureKind: FailureKind? = nil
        ) {
            self.success = success
            self.method = method
            self.message = message
            self.payload = payload
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
            self.timing = timing
            self.failureKind = failureKind
        }

        static func success(
            method: ActionMethod,
            message: String? = nil,
            payload: ResultPayload? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil
        ) -> InteractionResult {
            InteractionResult(
                success: true,
                method: method,
                message: message,
                payload: payload,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        }

        static func failure(
            _ method: ActionMethod,
            message: String,
            payload: ResultPayload? = nil,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil,
            failureKind: FailureKind? = nil
        ) -> InteractionResult {
            InteractionResult(
                success: false,
                method: method,
                message: message,
                payload: payload,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                failureKind: failureKind
            )
        }

        func withSubjectEvidence(_ evidence: ActionSubjectEvidence?) -> InteractionResult {
            guard success, let evidence else { return self }
            return InteractionResult(
                success: success,
                method: method,
                message: message,
                payload: payload,
                subjectEvidence: evidence,
                activationTrace: activationTrace,
                timing: timing,
                failureKind: failureKind
            )
        }

        func withActivationTrace(_ trace: ActivationTrace?) -> InteractionResult {
            guard let trace else { return self }
            return InteractionResult(
                success: success,
                method: method,
                message: message,
                payload: payload,
                subjectEvidence: subjectEvidence,
                activationTrace: trace,
                timing: timing,
                failureKind: failureKind
            )
        }

        func withTiming(_ timing: ActionPerformanceTiming?) -> InteractionResult {
            guard let timing else { return self }
            return InteractionResult(
                success: success,
                method: method,
                message: message,
                payload: payload,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: self.timing?.merging(timing) ?? timing,
                failureKind: failureKind
            )
        }
    }

    /// Internal failure kinds used by dispatch to choose the wire ErrorKind.
    /// Not wire format — this is an internal control-flow signal.
    enum FailureKind {
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
