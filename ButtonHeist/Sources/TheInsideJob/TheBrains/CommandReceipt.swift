#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotParser
import TheScore

/// Internal command receipt for the InsideJob action pipeline.
///
/// This intentionally lives in TheInsideJob for the first slice: it carries
/// pre-action stash state, settle-loop observations, and parsed AX elements
/// that are not wire contracts. `ActionResult` remains the TheScore wire
/// projection.
struct CommandReceipt {
    let before: TheBrains.BeforeState
    let attempt: CommandAttempt
    let settle: SettleReceipt?

    @MainActor
    func actionResult() -> ActionResult {
        switch attempt.deliveryPhase {
        case .delivered:
            guard let settle else {
                var builder = ActionResultBuilder(method: attempt.method, snapshot: before.snapshot)
                builder.message = attempt.message
                builder.value = attempt.value
                return builder.failure(errorKind: .actionFailed)
            }
            var builder = ActionResultBuilder(method: attempt.method, snapshot: settle.postSnapshot)
            builder.message = attempt.message
            builder.value = attempt.value
            builder.accessibilityDelta = settle.accessibilityDelta
            builder.accessibilityTrace = settle.accessibilityTrace
            builder.settled = settle.didSettle
            builder.settleTimeMs = settle.timeMs
            return builder.success(rotorResult: attempt.rotorResult)
        case .failed, .skipped:
            var builder = ActionResultBuilder(method: attempt.method, snapshot: before.snapshot)
            builder.message = attempt.message
            builder.value = attempt.value
            return builder.failure(errorKind: attempt.errorKind ?? Self.defaultFailureKind(for: attempt.method))
        }
    }

    private static func defaultFailureKind(for method: ActionMethod) -> ErrorKind {
        (method == .elementNotFound || method == .elementDeallocated) ? .elementNotFound : .actionFailed
    }
}

/// The command's single imperative delivery phase, or an explicit non-delivery.
struct CommandAttempt {
    enum DeliveryPhase: Equatable {
        case delivered
        case failed
        case skipped
    }

    let deliveryPhase: DeliveryPhase
    let method: ActionMethod
    let message: String?
    let value: String?
    let rotorResult: RotorResult?
    let errorKind: ErrorKind?

    static func delivered(
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        rotorResult: RotorResult? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .delivered,
            method: method,
            message: message,
            value: value,
            rotorResult: rotorResult,
            errorKind: nil
        )
    }

    static func failed(
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        errorKind: ErrorKind? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .failed,
            method: method,
            message: message,
            value: value,
            rotorResult: nil,
            errorKind: errorKind
        )
    }

    static func skipped(
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        errorKind: ErrorKind? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .skipped,
            method: method,
            message: message,
            value: value,
            rotorResult: nil,
            errorKind: errorKind
        )
    }
}

/// Receipt for the post-delivery settle phase and authoritative post-capture.
struct SettleReceipt {
    let outcome: SettleOutcome
    let elementsByKey: [TimelineKey: AccessibilityElement]
    let didSettle: Bool
    let isScreenChange: Bool
    let postSnapshot: [Screen.ScreenElement]
    let postCapture: AccessibilityTrace.Capture
    let accessibilityTrace: AccessibilityTrace
    let accessibilityDelta: AccessibilityTrace.Delta
    let transientElements: [AccessibilityElement]

    var timeMs: Int { outcome.timeMs }
}

#endif // DEBUG
#endif // canImport(UIKit)
