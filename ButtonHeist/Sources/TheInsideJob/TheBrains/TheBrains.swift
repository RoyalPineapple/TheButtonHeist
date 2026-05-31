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
/// scroll/explore lives in `Navigation` and the action
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
        var builder = ActionResultBuilder(method: method)
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
            semanticHash: stash.currentScreen.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: stash.currentScreen),
            screenId: stash.lastScreenId
        )
    }

    // MARK: - Action Result with Delta

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

        let settleResult: SettleSession.Outcome
        if let settleOutcome {
            settleResult = settleOutcome
        } else {
            let start = CFAbsoluteTimeGetCurrent()
            let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
            // Tripwire triggers the post-action parse early, but the parsed
            // accessibility signature below decides no-change, element-change,
            // or screen-change.
            settleResult = await settleSession.run(start: start, baselineTripwireSignal: before.tripwireSignal)
        }
        let didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        let settledScreen: Screen?
        if settleOutcome != nil {
            settledScreen = settleResult.finalScreen
        } else {
            settledScreen = settleResult.finalScreen ?? stash.parse()
        }

        guard let afterScreen = settledScreen else {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "Could not parse post-action accessibility tree"
            builder.settled = didSettle
            builder.settleTimeMs = settleResult.outcome.timeMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        stash.currentScreen = afterScreen

        _ = await navigation.exploreAndPrune()
        let finalState = captureSemanticState()
        let finalClassification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: finalState.screenSnapshot
        )
        let transientElements = finalClassification.isScreenChange || settleResult.events.containsTripwireSignalChange
            ? []
            : SettleSession.transientElements(
                seenByKey: settleResult.elementsByKey,
                baseline: before.elements,
                final: finalState.elements
            )
        let accessibilityTrace = makeAccessibilityTrace(
            afterInterface: finalState.interface,
            parentCapture: before.capture,
            classification: finalClassification,
            transient: transientElements.map { TheStash.WireConversion.convert($0) }
        )

        guard let postCapture = accessibilityTrace.captures.last else {
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
        builder.accessibilityTrace = accessibilityTrace
        builder.settled = didSettle
        builder.settleTimeMs = settleResult.outcome.timeMs
        return builder.success(payload: payload)
    }

    // MARK: - Clear

    func clearCache() {
        stash.clearCache()
        navigation.clearCache()
        waitForChangeState.resetDeliveredBaseline()
    }

    func failureActionResult(
        method: ActionMethod,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind?,
        before: BeforeState
    ) -> ActionResult {
        let kind = errorKind
            ?? ((method == .elementNotFound || method == .elementDeallocated)
                ? .elementNotFound : .actionFailed)
        var builder = ActionResultBuilder(method: method, capture: before.capture)
        builder.message = message
        return builder.failure(errorKind: kind, payload: payload)
    }

    // MARK: - Response State Tracking

    /// Snapshot current state as "last sent" — call after every response to the driver.
    func recordSentState() {
        waitForChangeState.recordDeliveredBaseline(captureSemanticState())
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

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceObservation {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

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

}

#endif // DEBUG
#endif // canImport(UIKit)
