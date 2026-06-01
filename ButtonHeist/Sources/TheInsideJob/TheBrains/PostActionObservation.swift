#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import TheScore

/// After an action succeeds, settle visible state, explore semantics, compare captures, and return one action result.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation

    /// State captured before an action for delta computation.
    struct BeforeState {
        let snapshot: [Screen.ScreenElement]
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let interface: Interface
        let interfaceHash: String
        let semanticHash: String
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let screenSnapshot: ScreenClassifier.Snapshot
        let screenId: String?
    }

    init(stash: TheStash, safecracker: TheSafecracker, tripwire: TheTripwire, navigation: Navigation) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    /// Capture the known semantic state. Exploration updates the targetable
    /// semantic set; this capture projects that state so deltas compare the
    /// whole discovered interface rather than the latest viewport parse.
    func captureSemanticState() -> BeforeState {
        let snapshot = stash.selectElements()
        let (interface, interfaceHash) = stash.semanticInterfaceWithHash()
        let tripwireSignal = tripwire.tripwireSignal()
        let capture = makeTraceCapture(interface: interface, sequence: 0, tripwireSignal: tripwireSignal)
        return BeforeState(
            snapshot: snapshot,
            elements: snapshot.map(\.element),
            hierarchy: stash.currentHierarchy,
            interface: interface,
            interfaceHash: interfaceHash,
            semanticHash: stash.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: stash),
            screenId: stash.lastScreenId
        )
    }

    /// Settle after an action, explore reachable semantics, diff against before-state, and return enriched ActionResult.
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        errorKind: ErrorKind? = nil,
        before: BeforeState,
        settleOutcome: SettleSession.Outcome? = nil
    ) async -> ActionResult {
        guard success else {
            return failureActionResult(
                method: method,
                message: message,
                payload: payload,
                errorKind: errorKind,
                before: before
            )
        }

        let settleResult = await resolvedSettleOutcome(settleOutcome, baseline: before)
        let didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        guard let afterScreen = settledScreen(from: settleResult, usedInjectedSettleOutcome: settleOutcome != nil) else {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "Could not parse post-action accessibility tree"
            builder.settled = didSettle
            builder.settleTimeMs = settleResult.outcome.timeMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        stash.commitVisiblePage(afterScreen)
        _ = await navigation.exploreAndPrune()

        let finalState = captureSemanticState()
        let finalClassification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: finalState.screenSnapshot
        )
        let trace = makeAccessibilityTrace(
            afterInterface: finalState.interface,
            parentCapture: before.capture,
            classification: finalClassification,
            transient: transientElements(settleResult: settleResult, before: before, final: finalState, classification: finalClassification)
        )

        guard let postCapture = trace.captures.last else {
            return failureActionResult(
                method: method,
                message: message,
                payload: payload,
                errorKind: .actionFailed,
                before: before
            )
        }

        var builder = ActionResultBuilder(method: method, capture: postCapture)
        builder.message = message
        builder.accessibilityTrace = trace
        builder.settled = didSettle
        builder.settleTimeMs = settleResult.outcome.timeMs
        return builder.success(payload: payload)
    }

    func failureActionResult(
        method: ActionMethod,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind?,
        before: BeforeState
    ) -> ActionResult {
        let kind = errorKind ?? .actionFailed
        var builder = ActionResultBuilder(method: method, capture: before.capture)
        builder.message = message
        return builder.failure(errorKind: kind, payload: payload)
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> Bool {
        classification.isScreenChange
            || current.capture.context != baseline.capture.context
            || current.semanticHash != baseline.semanticHash
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        tripwireSignal: TheTripwire.TripwireSignal? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(tripwireSignal: tripwireSignal),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = makeTraceCapture(
            interface: afterInterface,
            sequence: parentCapture == nil ? 1 : 2,
            parentHash: parentCapture?.hash,
            transition: transition
        )
        if let parentCapture {
            return AccessibilityTrace(captures: [parentCapture, capture])
        }
        return AccessibilityTrace(capture: capture)
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture,
        classification: ScreenClassifier.Classification,
        transient: [HeistElement] = []
    ) -> AccessibilityTrace {
        makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: classification.reason?.rawValue,
                transient: transient
            )
        )
    }

    func makeClassifiedAccessibilityTrace(after: BeforeState, parent: BeforeState) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: parent.screenSnapshot,
            after: after.screenSnapshot
        )
        let capture = AccessibilityTrace.Capture(
            sequence: after.capture.sequence,
            interface: after.capture.interface,
            parentHash: after.capture.parentHash,
            context: after.capture.context,
            transition: AccessibilityTrace.Transition(screenChangeReason: classification.reason?.rawValue),
            hash: after.capture.hash
        )
        return AccessibilityTrace(captures: [parent.capture, capture])
    }

    /// A Tripwire tick is permission to parse visible state, not to tickle
    /// scroll views. Full exploration is reserved for screen changes and
    /// explicit interface observation.
    func semanticStateAfterVisibleRefresh(baseline: BeforeState) async -> BeforeState {
        var current = captureSemanticState()
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot
        )
        guard classification.isScreenChange else { return current }

        _ = await navigation.exploreAndPrune()
        current = captureSemanticState()
        return current
    }

    private func resolvedSettleOutcome(
        _ settleOutcome: SettleSession.Outcome?,
        baseline: BeforeState
    ) async -> SettleSession.Outcome {
        if let settleOutcome {
            return settleOutcome
        }
        let start = CFAbsoluteTimeGetCurrent()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
        return await settleSession.run(start: start, baselineTripwireSignal: baseline.tripwireSignal)
    }

    private func settledScreen(
        from settleResult: SettleSession.Outcome,
        usedInjectedSettleOutcome: Bool
    ) -> Screen? {
        if usedInjectedSettleOutcome {
            return settleResult.finalScreen
        }
        return settleResult.finalScreen ?? stash.parse()
    }

    private func transientElements(
        settleResult: SettleSession.Outcome,
        before: BeforeState,
        final: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> [HeistElement] {
        guard !classification.isScreenChange,
              !settleResult.events.containsTripwireSignalChange else {
            return []
        }
        return SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: final.elements
        ).map { TheStash.WireConversion.convert($0) }
    }

    private func makeCaptureContext(tripwireSignal: TheTripwire.TripwireSignal? = nil) -> AccessibilityTrace.Context {
        let signal = tripwireSignal ?? tripwire.tripwireSignal()
        let windows = signal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Context(
            focusedElementId: stash.firstResponderHeistId,
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: stash.lastScreenId,
            windowStack: windows
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
