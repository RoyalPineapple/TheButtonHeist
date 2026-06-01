#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheBrains {
    typealias BeforeState = PostActionObservation.BeforeState

    func captureSemanticState() -> BeforeState {
        postActionObservation.captureSemanticState()
    }

    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        errorKind: ErrorKind? = nil,
        before: BeforeState,
        settleOutcome: SettleSession.Outcome? = nil
    ) async -> ActionResult {
        await postActionObservation.actionResultWithDelta(
            success: success,
            method: method,
            message: message,
            payload: payload,
            errorKind: errorKind,
            before: before,
            settleOutcome: settleOutcome
        )
    }

    func failureActionResult(
        method: ActionMethod,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind?,
        before: BeforeState
    ) -> ActionResult {
        postActionObservation.failureActionResult(
            method: method,
            message: message,
            payload: payload,
            errorKind: errorKind,
            before: before
        )
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> Bool {
        PostActionObservation.shouldRecordAccessibilityTrace(
            baseline: baseline,
            current: current,
            classification: classification
        )
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        tripwireSignal: TheTripwire.TripwireSignal? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        postActionObservation.makeTraceCapture(
            interface: interface,
            sequence: sequence,
            parentHash: parentHash,
            tripwireSignal: tripwireSignal,
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        postActionObservation.makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture,
        classification: ScreenClassifier.Classification,
        transient: [HeistElement] = []
    ) -> AccessibilityTrace {
        postActionObservation.makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            classification: classification,
            transient: transient
        )
    }

    func makeClassifiedAccessibilityTrace(after: BeforeState, parent: BeforeState) -> AccessibilityTrace {
        postActionObservation.makeClassifiedAccessibilityTrace(after: after, parent: parent)
    }

    func semanticStateAfterVisibleRefresh(baseline: BeforeState) async -> BeforeState {
        await postActionObservation.semanticStateAfterVisibleRefresh(baseline: baseline)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
