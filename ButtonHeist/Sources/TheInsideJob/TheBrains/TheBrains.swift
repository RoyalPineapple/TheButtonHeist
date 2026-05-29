#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

import AccessibilitySnapshotParser

/// The brains of the operation — plans the play, sequences the crew.
///
/// TheBrains takes a command and works it through to a result by coordinating
/// TheStash (the screen value), TheSafecracker (gestures), and TheTripwire
/// (timing). The post-action delta cycle and command dispatch live here;
/// scroll/explore lives in `Navigation` and the 21 `executeXxx` action
/// handlers live in `Actions` — both are internal components of TheBrains.
@MainActor
final class TheBrains {

    // Keep this literal in sync with `FenceResponse.accessibilityTreeUnavailableMessage`;
    // TheFence uses it to enrich wire-shaped `actionFailed` results locally.
    static let treeUnavailableMessage = "Could not access accessibility tree: no traversable app windows"

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let actions: Actions
    let responseStateHistory = ResponseStateHistory()
    let waitForChangeState = WaitForChangeState()

    enum InterfaceObservation {
        case success(Interface)
        case failure(InterfaceObservationError)
    }

    enum InterfaceObservationError: Error, Equatable {
        case rootViewUnavailable
        case selection(InterfaceSelectionError)

        var message: String {
            switch self {
            case .rootViewUnavailable:
                return "Could not access root view"
            case .selection(let error):
                return error.message
            }
        }
    }

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        let stash = TheStash(tripwire: tripwire)
        let safecracker = TheSafecracker()
        self.stash = stash
        self.safecracker = safecracker
        let navigation = Navigation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire
        )
        self.navigation = navigation
        self.actions = Actions(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            navigation: navigation
        )
    }

    // MARK: - Refresh Convenience

    /// Refresh the accessibility tree into the stash. Returns the new Screen
    /// or nil if the parser couldn't produce one. Callers in an exploration
    /// cycle should use `stash.parse()` directly and accumulate into a local
    /// union — TheStash has no mode flag.
    @discardableResult
    func refresh() -> Screen? {
        stash.refresh()
    }

    func treeUnavailableResult(method: ActionMethod) -> ActionResult {
        var builder = ActionResultBuilder(method: method, screenName: stash.lastScreenName, screenId: stash.lastScreenId)
        builder.message = TheBrains.treeUnavailableMessage
        return builder.failure(errorKind: .actionFailed)
    }

    // MARK: - Before/After State

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

    /// Capture the current state for delta computation before an action.
    /// Caller must have called `refresh()` already this frame.
    func captureBeforeState() -> BeforeState {
        let (interface, interfaceHash) = stash.interfaceWithHash()
        let tripwireSignal = tripwire.tripwireSignal()
        let capture = makeTraceCapture(interface: interface, sequence: 0, tripwireSignal: tripwireSignal)
        return BeforeState(
            snapshot: stash.selectElements(),
            elements: stash.currentHierarchy.sortedElements,
            hierarchy: stash.currentHierarchy,
            interface: interface,
            interfaceHash: interfaceHash,
            semanticHash: stash.currentScreen.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: stash.currentScreen),
            screenId: stash.lastScreenId
        )
    }

    /// Capture the known semantic state from the current parser hierarchy plus
    /// Button Heist annotations. Exploration may update known targetable
    /// elements, but the interface capture remains the parser tree rather than
    /// a second flattened wire tree.
    func captureSemanticState() -> BeforeState {
        let snapshot = stash.selectElements()
        let (interface, interfaceHash) = stash.interfaceWithHash()
        let tripwireSignal = tripwire.tripwireSignal()
        let capture = makeTraceCapture(interface: interface, sequence: 0, tripwireSignal: tripwireSignal)
        return BeforeState(
            snapshot: snapshot,
            elements: snapshot.map(\.element),
            hierarchy: stash.currentHierarchy,
            interface: interface,
            interfaceHash: interfaceHash,
            semanticHash: stash.currentScreen.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: stash.currentScreen),
            screenId: stash.lastScreenId
        )
    }

    // MARK: - Action Result with Delta

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        errorKind: ErrorKind? = nil,
        before: BeforeState
    ) async -> ActionResult {
        guard success else {
            let kind = errorKind
                ?? ((method == .elementNotFound || method == .elementDeallocated)
                    ? .elementNotFound : .actionFailed)
            var builder = ActionResultBuilder(method: method, snapshot: before.snapshot)
            builder.message = message
            return builder.failure(errorKind: kind, payload: payload)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
        // Tripwire triggers the post-action parse early, but the parsed
        // accessibility signature below decides no-change, element-change,
        // or screen-change.
        let settleResult = await settleSession.run(start: start, baselineTripwireSignal: before.tripwireSignal)
        let didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, snapshot: before.snapshot)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }
        var afterScreen = settleResult.outcome.didSettleCleanly
            ? settleResult.finalScreen
            : nil
        if afterScreen == nil {
            afterScreen = stash.parse()
        }

        let afterSnapshotForClassification = afterScreen.map(ScreenClassifier.snapshot(of:)) ?? ScreenClassifier.snapshot(of: .empty)
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: afterSnapshotForClassification
        )
        let isScreenChange = classification.isScreenChange
        if let afterScreen {
            stash.currentScreen = afterScreen
        }

        if isScreenChange {
            _ = await navigation.exploreAndPrune()
        }
        let afterInterface = stash.interface()
        let transientElements = isScreenChange || settleResult.events.containsTripwireSignalChange
            ? []
            : SettleSession.transientElements(
                seenByKey: settleResult.elementsByKey,
                baseline: before.elements,
                final: afterScreen?.liveCapture.hierarchy.sortedElements ?? []
            )
        let accessibilityTrace = makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: before.capture,
            classification: classification,
            transient: transientElements.map { TheStash.WireConversion.convert($0) }
        )

        await stash.captureActionFrame()

        let receipt = CommandReceipt(
            before: before,
            attempt: .delivered(
                method: method,
                message: message,
                payload: payload
            ),
            settle: SettleReceipt(
                outcome: settleResult.outcome,
                events: settleResult.events,
                elementsByKey: settleResult.elementsByKey,
                didSettle: didSettle,
                accessibilityTrace: accessibilityTrace
            )
        )

        return receipt.actionResult()
    }

    // MARK: - Keyboard Observation

    func startKeyboardObservation() {
        safecracker.startKeyboardObservation()
    }

    func stopKeyboardObservation() {
        safecracker.stopKeyboardObservation()
    }

    // MARK: - Clear

    func clearCache() {
        stash.clearCache()
        navigation.clearCache()
        responseStateHistory.reset()
    }

    // MARK: - Response State Tracking

    /// Snapshot current state as "last sent" — call after every response to the driver.
    func recordSentState() {
        responseStateHistory.record(captureSemanticState())
    }

    // MARK: - Settled Tripwire Parsing

    struct SettledTripwireParse {
        let changed: Bool
        let isScreenChange: Bool
        let accessibilityTrace: AccessibilityTrace?
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

    /// Parse settled visible state after a Tripwire signal, update the local
    /// semantic screen, and classify the result. Same-screen parses patch local
    /// state; screen changes perform the full exploration pass before returning.
    func parseSettledTripwireChange() async -> SettledTripwireParse {
        let baseline = captureSemanticState()
        guard refresh() != nil else {
            return SettledTripwireParse(changed: false, isScreenChange: false, accessibilityTrace: nil)
        }

        let current = await semanticStateAfterVisibleRefresh(baseline: baseline)
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot
        )
        guard Self.shouldRecordAccessibilityTrace(
            baseline: baseline,
            current: current,
            classification: classification
        ) else {
            return SettledTripwireParse(changed: false, isScreenChange: false, accessibilityTrace: nil)
        }

        let accessibilityTrace = makeAccessibilityTrace(
            afterInterface: current.interface,
            parentCapture: baseline.capture,
            classification: classification
        )
        return SettledTripwireParse(
            changed: true,
            isScreenChange: classification.isScreenChange,
            accessibilityTrace: accessibilityTrace
        )
    }

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceObservation {
        _ = await tripwire.waitForAllClear(timeout: 0.5)
        stash.clearPendingRotorResult()

        guard refresh() != nil else {
            return .failure(.rootViewUnavailable)
        }

        _ = await navigation.exploreAndPrune()
        do {
            let interface = try InterfaceSelector(interface: stash.interface()).select(query)
            return .success(interface)
        } catch {
            return .failure(.selection(error))
        }
    }

    // MARK: - Background Accessibility Trace

    /// Check if the accessibility tree changed since the last response and
    /// return the public accessibility trace.
    func computeBackgroundAccessibilityTrace() async -> AccessibilityTrace? {
        guard let baseline = responseStateHistory.lastSentBeforeState else { return nil }
        guard refresh() != nil else { return nil }
        let current = await semanticStateAfterVisibleRefresh(baseline: baseline)
        let classification = ScreenClassifier.classify(
            before: baseline.screenSnapshot,
            after: current.screenSnapshot
        )
        guard Self.shouldRecordAccessibilityTrace(
            baseline: baseline,
            current: current,
            classification: classification
        ) else {
            return nil
        }

        let accessibilityTrace = makeAccessibilityTrace(
            afterInterface: current.interface,
            parentCapture: baseline.capture,
            classification: classification
        )
        guard accessibilityTrace.backgroundDeltaProjection != nil else { return nil }
        return accessibilityTrace
    }

    // MARK: - Wait For Idle

    /// Run the wait-for-idle pipeline: refresh → before → settle → delta → result.
    func executeWaitForIdle(timeout: TimeInterval) async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: .waitForIdle)
        }
        let before = captureBeforeState()
        let settled = await tripwire.waitForAllClear(timeout: timeout)

        return await actionResultWithDelta(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeout)s, UI may still be animating",
            before: before
        )
    }

    // MARK: - Private Helpers

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

    func makeCaptureContext(tripwireSignal: TheTripwire.TripwireSignal? = nil) -> AccessibilityTrace.Context {
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

    func makeAccessibilityTrace(afterCapture: AccessibilityTrace.Capture, parentCapture: AccessibilityTrace.Capture? = nil) -> AccessibilityTrace {
        let capture = AccessibilityTrace.Capture(
            sequence: parentCapture == nil ? 1 : 2,
            interface: afterCapture.interface,
            parentHash: parentCapture?.hash,
            context: afterCapture.context,
            transition: afterCapture.transition,
            hash: afterCapture.hash
        )
        if let parentCapture {
            return AccessibilityTrace(captures: [parentCapture, capture])
        }
        return AccessibilityTrace(capture: capture)
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
        return makeAccessibilityTrace(afterCapture: capture, parentCapture: parent.capture)
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

    // MARK: - Recording Wiring

    /// Stakeout for recording frame capture.
    var stakeout: TheStakeout? {
        get { stash.stakeout }
        set { stash.stakeout = newValue }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
