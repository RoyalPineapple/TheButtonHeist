#if canImport(UIKit)
#if DEBUG
import TheScore

/// Constructs ActionResult values with compile-time separation of success and failure paths.
///
/// The builder stages action metadata and trace evidence. Calling `.success()` vs `.failure()`
/// enforces that error-only fields (errorKind) cannot appear on success results.
///
/// Usage:
///     var builder = ActionResultBuilder()
///     builder.message = "Tapped Sign In"
///     builder.accessibilityTrace = trace
///     return builder.success(method: .activate)
///
/// `@MainActor` justification: builder reads from MainActor-bound state during
/// construction; the produced ActionResult is Sendable but the builder itself
/// stages MainActor data.
@MainActor struct ActionResultBuilder { // swiftlint:disable:this agent_main_actor_value_type
    var message: String?
    var accessibilityTrace: AccessibilityTrace?
    var settled: Bool?
    var settleTimeMs: Int?
    var subjectEvidence: ActionSubjectEvidence?
    var activationTrace: ActivationTrace?
    var timing: ActionPerformanceTiming?

    init() {}

    /// Create a builder from an accessibility capture receipt.
    init(capture: AccessibilityTrace.Capture) {
        self.accessibilityTrace = AccessibilityTrace(capture: capture)
    }

    func success(method: ActionMethod) -> ActionResult {
        ActionResult.success(
            method: method,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    func success(payload: ActionResultPayload) -> ActionResult {
        ActionResult.success(
            payload: payload,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    func failure(method: ActionMethod, errorKind: ErrorKind = .actionFailed) -> ActionResult {
        ActionResult.failure(
            method: method,
            errorKind: errorKind,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    func failure(errorKind: ErrorKind = .actionFailed, payload: ActionResultPayload) -> ActionResult {
        ActionResult.failure(
            payload: payload,
            errorKind: errorKind,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
