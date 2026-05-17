#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotParser
import TheScore

/// Internal command receipt for the InsideJob action pipeline.
///
/// This intentionally lives in TheInsideJob: it carries pre-action stash
/// state, delivery status, and the trace-backed settle receipt. `ActionResult`
/// remains the TheScore wire projection.
struct CommandReceipt {
    let before: TheBrains.BeforeState
    let attempt: CommandAttempt
    let settle: SettleReceipt?

    @MainActor
    func actionResult() -> ActionResult {
        switch attempt.deliveryPhase {
        case .delivered:
            guard let settle,
                  let postCapture = settle.postCapture,
                  let accessibilityDelta = settle.accessibilityDelta else {
                var builder = ActionResultBuilder(method: attempt.method, snapshot: before.snapshot)
                builder.message = attempt.message
                return builder.failure(errorKind: .actionFailed, payload: attempt.payload)
            }
            var builder = ActionResultBuilder(method: attempt.method, capture: postCapture)
            builder.message = attempt.message
            builder.accessibilityDelta = accessibilityDelta
            builder.accessibilityTrace = settle.accessibilityTrace
            builder.settled = settle.didSettle
            builder.settleTimeMs = settle.timeMs
            return builder.success(payload: attempt.payload)
        case .failed, .skipped:
            var builder = ActionResultBuilder(method: attempt.method, snapshot: before.snapshot)
            builder.message = attempt.message
            return builder.failure(
                errorKind: attempt.errorKind ?? Self.defaultFailureKind(for: attempt.method),
                payload: attempt.payload
            )
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
    let payload: ResultPayload?
    let errorKind: ErrorKind?

    static func delivered(
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .delivered,
            method: method,
            message: message,
            payload: payload,
            errorKind: nil
        )
    }

    static func failed(
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        errorKind: ErrorKind? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .failed,
            method: method,
            message: message,
            payload: payload,
            errorKind: errorKind
        )
    }

    static func skipped(
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        errorKind: ErrorKind? = nil
    ) -> CommandAttempt {
        CommandAttempt(
            deliveryPhase: .skipped,
            method: method,
            message: message,
            payload: payload,
            errorKind: errorKind
        )
    }
}

/// Receipt for the post-delivery settle phase and authoritative post-capture.
struct SettleReceipt {
    let outcome: SettleOutcome
    let events: [SettleEvent]
    let elementsByKey: [TimelineKey: AccessibilityElement]
    let didSettle: Bool
    let accessibilityTrace: AccessibilityTrace

    var timeMs: Int { outcome.timeMs }
    var postCapture: AccessibilityTrace.Capture? { accessibilityTrace.captures.last }
    var accessibilityDelta: AccessibilityTrace.Delta? { accessibilityTrace.captureEndpointDelta }
}

private extension AccessibilityTrace {
    var captureEndpointDelta: AccessibilityTrace.Delta? {
        guard let first = captures.first, let last = captures.last else { return nil }
        return .between(first, last)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
