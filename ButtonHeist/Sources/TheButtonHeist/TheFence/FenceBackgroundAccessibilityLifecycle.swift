import TheScore

struct FenceBackgroundAccessibilitySnapshot: Equatable {
    let pendingTraceCount: Int
    let latestRef: AccessibilityTrace.CaptureRef?
    let retention: AccessibilityTraceRetention
}

struct FenceBackgroundExpectationMatch {
    let result: ActionResult
    let validation: ExpectationResult
    let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
}

/// Owns retained accessibility captures plus queued background traces for TheFence.
@ButtonHeistActor
final class FenceBackgroundAccessibilityLifecycle {
    private static let defaultPendingTraceLimit = 20

    private var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
    private let pendingTraceLimit: Int

    init(pendingTraceLimit: Int = FenceBackgroundAccessibilityLifecycle.defaultPendingTraceLimit) {
        self.pendingTraceLimit = pendingTraceLimit
    }

    var snapshot: FenceBackgroundAccessibilitySnapshot {
        FenceBackgroundAccessibilitySnapshot(
            pendingTraceCount: history.pendingTraceCount,
            latestRef: history.latestRef,
            retention: history.retention
        )
    }

    var pendingTraceCount: Int {
        history.pendingTraceCount
    }

    var latestRef: AccessibilityTrace.CaptureRef? {
        history.latestRef
    }

    func reset() {
        history.reset()
        history.retention = .dropAfterDelivery
    }

    func enqueue(_ trace: AccessibilityTrace) {
        history.enqueuePendingTrace(trace, limit: pendingTraceLimit)
    }

    func drainTrace() -> AccessibilityTrace? {
        history.drainPendingTrace()
    }

    func drainTraces() -> [AccessibilityTrace] {
        history.drainPendingTraces()
    }

    @discardableResult
    func append(interface: Interface) -> AccessibilityTrace.CaptureRef {
        history.append(interface: interface)
    }

    @discardableResult
    func ingest(_ trace: AccessibilityTrace) -> AccessibilityTrace.Cursor? {
        history.ingest(trace)
    }

    func capture(ref: AccessibilityTrace.CaptureRef) -> AccessibilityTrace.Capture? {
        history.capture(ref: ref)
    }

    func elementLookup(captureRef: AccessibilityTrace.CaptureRef?) -> [HeistId: HeistElement] {
        history.elementLookup(captureRef: captureRef)
    }

    func markDelivered(through ref: AccessibilityTrace.CaptureRef?) {
        history.markDelivered(through: ref)
    }

    func beginRecordingRetention() {
        history.retention = .persistForSession
    }

    func endRecordingRetention() {
        history.retention = .dropAfterDelivery
    }

    func consumeFirstTraceMatchingExpectation(
        _ expectation: ActionExpectation,
        startingAt startIndex: Int = 0
    ) -> FenceBackgroundExpectationMatch? {
        var matched: (
            pendingTrace: AccessibilityTrace.PendingTrace,
            result: ActionResult,
            validation: ExpectationResult
        )?
        for pendingTrace in history.pendingTraces(startingAt: startIndex) {
            let trace = pendingTrace.trace
            guard trace.meaningfulEndpointDeltaProjection != nil else { continue }
            let syntheticResult = ActionResult(
                success: true,
                method: .waitForChange,
                message: "expectation already met by background change",
                accessibilityTrace: trace
            )
            let validation = expectation.validate(
                against: syntheticResult,
                preActionElements: history.elementLookup(captureRef: pendingTrace.firstRef)
            )
            if validation.met {
                matched = (pendingTrace, syntheticResult, validation)
                break
            }
        }

        guard let matched,
              let pendingTrace = history.removePendingTrace(at: matched.pendingTrace.index)
        else {
            return nil
        }
        return FenceBackgroundExpectationMatch(
            result: matched.result,
            validation: matched.validation,
            deliveredCaptureRef: pendingTrace.lastRef
        )
    }
}
