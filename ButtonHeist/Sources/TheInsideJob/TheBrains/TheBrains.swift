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
    // TheFence uses it to enrich wire-compatible `actionFailed` results locally.
    static let treeUnavailableMessage = "Could not access accessibility tree: no traversable app windows"

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let actions: Actions

    private enum WaitForChangePhase {
        case idle
        case waiting(WaitForChangePredicate)
    }

    private struct WaitForChangePredicate {
        let expectation: ActionExpectation?
        let deadline: CFAbsoluteTime
    }

    private var waitForChangePhase: WaitForChangePhase = .idle

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

    func clearPendingRotorResult() {
        stash.clearPendingRotorResult()
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
        var didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, snapshot: before.snapshot)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }
        logSettleOutcome(settleResult.outcome, events: settleResult.events)

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
        let afterElements = afterScreen?.liveInterface.hierarchy.sortedElements ?? []
        if isScreenChange && afterElements.isEmpty {
            let repopulated = await repopulateAfterScreenChange(into: &afterScreen)
            if !repopulated { didSettle = false }
        }

        if let afterScreen {
            stash.currentScreen = afterScreen
        }

        _ = await navigation.exploreAndPrune()
        let afterInterface = stash.interface()
        let transientElements = Self.shouldSuppressTransient(
            settleEvents: settleResult.events,
            isScreenChange: isScreenChange
        )
            ? []
            : SettleSession.transientElements(
                seenByKey: settleResult.elementsByKey,
                baseline: before.elements,
                final: afterScreen?.liveInterface.hierarchy.sortedElements ?? []
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

    // MARK: - Settle Outcome Helpers

    private func logSettleOutcome(_ outcome: SettleOutcome, events: [SettleEvent]) {
        switch outcome {
        case .settled(let ms):
            if events.containsTripwireSignalChange {
                insideJobLogger.info("Post-action settle: settled after Tripwire signal in \(ms)ms")
            } else {
                insideJobLogger.info("Post-action settle: settled in \(ms)ms")
            }
        case .timedOut(let ms):
            insideJobLogger.info("Post-action settle: timed out after \(ms)ms")
        case .cancelled(let ms):
            insideJobLogger.info("Post-action settle: cancelled after \(ms)ms")
        }
    }

    /// Wait for the post-screen-change tree to repopulate. Returns true
    /// if a non-empty parse landed within the attempt budget.
    private func repopulateAfterScreenChange(into afterScreen: inout Screen?) async -> Bool {
        let repopStart = CFAbsoluteTimeGetCurrent()
        for attempt in 1...10 {
            _ = await tripwire.waitForAllClear(timeout: 0.2)
            afterScreen = stash.parse()
            if !(afterScreen?.elements.isEmpty ?? true) {
                let repopMs = Int((CFAbsoluteTimeGetCurrent() - repopStart) * 1000)
                insideJobLogger.info("Screen re-populated after \(attempt) re-parse(s) in \(repopMs)ms")
                return true
            }
        }
        insideJobLogger.info("Screen failed to re-populate after 10 attempts; reporting settled=false")
        return false
    }

    // MARK: - Transient Capture

    /// Should the post-action delta omit the `transient` list?
    ///
    /// `SettleSession.elementsByKey` accumulates every element seen during
    /// the multi-cycle loop. On a clean same-screen settle (no Tripwire
    /// signal and no parsed screen change), the "appeared then disappeared"
    /// elements really are transient — a spinner, a loading overlay, a
    /// snackbar. On a transition, the same accumulation includes the
    /// *previous screen's* elements, which are stale-not-transient: they
    /// didn't come and go as part of this action, they're just no longer the
    /// active screen. Reporting them as `transient` claims the wrong thing
    /// and pollutes the delta with elements the agent can no longer see or
    /// act on.
    ///
    /// Both checks matter:
    /// - `SettleEvent.tripwireSignalChanged`: the loop reset its baseline
    ///   because a cheap UIKit-side condition changed. Suppress transients
    ///   because the settle timeline is not a clean same-screen sequence.
    /// - `isScreenChange` flag: the parsed signature concluded the screen
    ///   changed even if the settle loop reached `.settled`.
    static func shouldSuppressTransient(
        settleEvents: [SettleEvent],
        isScreenChange: Bool
    ) -> Bool {
        if settleEvents.containsTripwireSignalChange { return true }
        return isScreenChange
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
        sentHistory = .fresh
    }

    // MARK: - Response State Tracking

    /// State captured after each response sent to the driver.
    struct SentState {
        let beforeState: BeforeState

        var interfaceHash: String {
            beforeState.interfaceHash
        }

        var captureHash: String {
            beforeState.capture.hash
        }

        var screenId: String? {
            beforeState.screenId
        }
    }

    /// Two-phase sent-state history: `.fresh` before the first response, and
    /// `.sent` once a response has been recorded. Modelled as an enum so the
    /// "never sent" case is structurally distinct from any sent state — every
    /// caller must handle it explicitly rather than guarding against `nil`.
    enum SentHistory {
        case fresh
        case sent(SentState)
    }

    private(set) var sentHistory: SentHistory = .fresh

    /// The state of the last response sent to the driver, if any.
    var lastSentState: SentState? {
        if case .sent(let state) = sentHistory { return state }
        return nil
    }

    /// Snapshot current state as "last sent" — call after every response to the driver.
    func recordSentState() {
        sentHistory = .sent(SentState(beforeState: captureSemanticState()))
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

    /// Build an Interface payload from the current semantic state.
    func currentInterface() -> Interface {
        stash.interface()
    }

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceObservation {
        _ = await tripwire.waitForAllClear(timeout: 0.5)
        clearPendingRotorResult()

        guard refresh() != nil else {
            return .failure(.rootViewUnavailable)
        }

        _ = await navigation.exploreAndPrune()
        do {
            let interface = try InterfaceSelector(interface: currentInterface()).select(query)
            return .success(interface)
        } catch {
            return .failure(.selection(error))
        }
    }

    // MARK: - Background Accessibility Trace

    /// Check if the accessibility tree changed since the last response and
    /// return the public accessibility trace.
    func computeBackgroundAccessibilityTrace() async -> AccessibilityTrace? {
        guard case .sent(let sent) = sentHistory else { return nil }
        guard refresh() != nil else { return nil }
        let current = await semanticStateAfterVisibleRefresh(baseline: sent.beforeState)
        let classification = ScreenClassifier.classify(
            before: sent.beforeState.screenSnapshot,
            after: current.screenSnapshot
        )
        guard Self.shouldRecordAccessibilityTrace(
            baseline: sent.beforeState,
            current: current,
            classification: classification
        ) else {
            return nil
        }

        let accessibilityTrace = makeAccessibilityTrace(
            afterInterface: current.interface,
            parentCapture: sent.beforeState.capture,
            classification: classification
        )
        guard accessibilityTrace.backgroundDelta != nil else { return nil }
        return accessibilityTrace
    }

    /// Whether the screen changed since the last response (for fast-redirect logic).
    var screenChangedSinceLastSent: Bool {
        guard case .sent(let sent) = sentHistory else { return false }
        return ScreenClassifier.classify(
            before: sent.beforeState.screenSnapshot,
            after: ScreenClassifier.snapshot(of: stash.currentScreen)
        ).isScreenChange
    }

    /// Screen ID from the last response, for diagnostic messages.
    var lastSentScreenId: String? {
        if case .sent(let sent) = sentHistory { return sent.screenId }
        return nil
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

    // MARK: - Wait For Change

    /// Install one wait predicate, check current state, then watch settled changes until it matches.
    func executeWaitForChange(timeout: TimeInterval, expectation: ActionExpectation?) async -> ActionResult {
        let start = CFAbsoluteTimeGetCurrent()

        guard let predicate = installWaitForChangePredicate(
            expectation: expectation,
            timeout: timeout,
            start: start
        ) else {
            var builder = ActionResultBuilder(
                method: .waitForChange,
                screenName: stash.lastScreenName,
                screenId: stash.lastScreenId
            )
            builder.message = "wait_for_change already in progress"
            return builder.failure(errorKind: .actionFailed)
        }
        defer { waitForChangePhase = .idle }

        let sentBaseline: BeforeState? = {
            if case .sent(let sent) = sentHistory, !sent.captureHash.isEmpty {
                return sent.beforeState
            }
            return nil
        }()

        guard let initial = await refreshSemanticSnapshot(baseline: sentBaseline) else {
            return treeUnavailableResult(method: .waitForChange)
        }

        let baseline = sentBaseline ?? initial
        let preWaitElements = Dictionary(
            TheStash.WireConversion.toWire(baseline.snapshot).map {
                ($0.heistId, $0)
            },
            uniquingKeysWith: { _, newest in newest }
        )

        if let expectation = predicate.expectation,
           validateCurrentState(expectation, snapshot: initial.snapshot).met {
            var builder = ActionResultBuilder(method: .waitForChange, snapshot: initial.snapshot)
            builder.message = "expectation already met by current state (0.0s)"
            builder.accessibilityTrace = AccessibilityTrace(captures: [initial.capture, initial.capture])
            return builder.success()
        }

        // Fast path: semantic state already changed since the last response.
        if let sentBaseline {
            let classification = ScreenClassifier.classify(
                before: sentBaseline.screenSnapshot,
                after: initial.screenSnapshot
            )
            if Self.shouldRecordAccessibilityTrace(
                baseline: sentBaseline,
                current: initial,
                classification: classification
            ) {
                let accessibilityTrace = makeClassifiedAccessibilityTrace(after: initial, parent: baseline)
                let delta = accessibilityTrace.captureEndpointDelta ?? .noChange(.init(elementCount: initial.snapshot.count))
                if let result = evaluateWaitForChange(
                    delta: delta, accessibilityTrace: accessibilityTrace,
                    afterSnapshot: initial.snapshot, expectation: predicate.expectation,
                    preWaitElements: preWaitElements,
                    start: start, round: 0, message: "already changed (0.0s)"
                ) {
                    return result
                }
            }
        }

        if let result = await waitForChangeThroughSettledSnapshots(
            baseline: baseline,
            initial: initial,
            predicate: predicate,
            preWaitElements: preWaitElements,
            start: start
        ) {
            return result
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let current = await refreshSemanticSnapshot(baseline: baseline)
        let afterSnapshot = current?.snapshot ?? []
        let timeoutAccessibilityTrace = current.map {
            makeClassifiedAccessibilityTrace(after: $0, parent: baseline)
        }
        let delta = timeoutAccessibilityTrace?.captureEndpointDelta ?? .noChange(.init(elementCount: 0))
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.message = waitForChangeTimeoutMessage(
            elapsed: elapsed,
            expectation: predicate.expectation,
            delta: delta,
            elementCount: afterSnapshot.count
        )
        builder.accessibilityTrace = timeoutAccessibilityTrace
        return builder.failure(errorKind: .timeout)
    }

    private func waitForChangeThroughSettledSnapshots(
        baseline: BeforeState,
        initial: BeforeState,
        predicate: WaitForChangePredicate,
        preWaitElements: [String: HeistElement],
        start: CFAbsoluteTime
    ) async -> ActionResult? {
        // Wait for stable AX-tree observations until a change lands or we time
        // out. Tripwire signals reset the settle baseline inside
        // `SettleSession`; the parsed AX captures below still decide whether
        // anything changed.
        var settleBaseline = initial
        var round = 0

        while CFAbsoluteTimeGetCurrent() < predicate.deadline {
            let remaining = predicate.deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            guard let current = await waitForSettledSemanticSnapshot(
                baseline: settleBaseline,
                timeout: min(remaining, 1.0)
            ) else { continue }
            round += 1

            let classification = ScreenClassifier.classify(
                before: settleBaseline.screenSnapshot,
                after: current.screenSnapshot
            )
            guard Self.shouldRecordAccessibilityTrace(
                baseline: settleBaseline,
                current: current,
                classification: classification
            ) else {
                settleBaseline = current
                continue
            }

            let accessibilityTrace = makeClassifiedAccessibilityTrace(after: current, parent: baseline)
            let delta = accessibilityTrace.captureEndpointDelta ?? .noChange(.init(elementCount: current.snapshot.count))
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

            if let result = evaluateWaitForChange(
                delta: delta, accessibilityTrace: accessibilityTrace,
                afterSnapshot: current.snapshot, expectation: predicate.expectation,
                preWaitElements: preWaitElements,
                start: start, round: round, message: "changed after \(elapsed)s (\(round) rounds)"
            ) {
                return result
            }

            settleBaseline = current
            insideJobLogger.debug("wait_for_change round \(round): \(delta.kindRawValue), expectation not yet met")
        }

        return nil
    }

    private func waitForChangeTimeoutMessage(
        elapsed: String,
        expectation: ActionExpectation?,
        delta: AccessibilityTrace.Delta,
        elementCount: Int
    ) -> String {
        let expected = expectation?.summaryDescription ?? "any settled UI change"
        var parts = [
            "timed out after \(elapsed)s",
            "expected: \(expected)",
            "observed: \(delta.kindRawValue)",
            "known: \(elementCount) elements",
        ]
        if let screenId = stash.lastScreenId {
            parts.append("screen: \(screenId)")
        }
        if expectation == .screenChanged {
            parts.append(
                "Next: retry wait_for_change with expect: {\"type\": \"elements_changed\"} " +
                    "if element-level updates are acceptable, or call get_interface() " +
                    "to inspect the current screen."
            )
        } else {
            parts.append(
                "Next: get_interface() to inspect the current screen, " +
                    "then retry wait_for_change with the expected state."
            )
        }
        return parts.joined(separator: "; ")
    }

    private func installWaitForChangePredicate(
        expectation: ActionExpectation?,
        timeout: TimeInterval,
        start: CFAbsoluteTime
    ) -> WaitForChangePredicate? {
        guard case .idle = waitForChangePhase else { return nil }
        let predicate = WaitForChangePredicate(
            expectation: expectation,
            deadline: start + timeout
        )
        waitForChangePhase = .waiting(predicate)
        return predicate
    }

    private func evaluateWaitForChange(
        delta: AccessibilityTrace.Delta,
        accessibilityTrace: AccessibilityTrace?,
        afterSnapshot: [Screen.ScreenElement],
        expectation: ActionExpectation?,
        preWaitElements: [String: HeistElement],
        start: CFAbsoluteTime,
        round: Int,
        message: String
    ) -> ActionResult? {
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.accessibilityTrace = accessibilityTrace

        guard let expectation else {
            builder.message = message
            return builder.success()
        }

        let currentState = validateCurrentState(expectation, snapshot: afterSnapshot)
        if currentState.met {
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
            return builder.success()
        }

        guard expectation.validate(
            against: builder.success(),
            preActionElements: preWaitElements
        ).met else { return nil }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
        return builder.success()
    }

    private func validateCurrentState(
        _ expectation: ActionExpectation,
        snapshot: [Screen.ScreenElement]
    ) -> ExpectationResult {
        validateCurrentState(
            expectation,
            elements: TheStash.WireConversion.toWire(snapshot)
        )
    }

    private func validateCurrentState(
        _ expectation: ActionExpectation,
        elements: [HeistElement]
    ) -> ExpectationResult {
        switch expectation {
        case .delivery:
            return ExpectationResult(
                met: true,
                expectation: expectation,
                actual: "delivered"
            )
        case .screenChanged:
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "requires observed screen change"
            )
        case .elementsChanged:
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "requires observed element change"
            )
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return validateElementUpdatedCurrentState(
                heistId: heistId, property: property,
                oldValue: oldValue, newValue: newValue,
                expectation: expectation,
                elements: elements
            )
        case .elementAppeared(let matcher):
            let present = elements.contains { $0.matches(matcher) }
            return ExpectationResult(
                met: present, expectation: expectation,
                actual: present ? "present" : "not present"
            )
        case .elementDisappeared(let matcher):
            let present = elements.contains { $0.matches(matcher) }
            return ExpectationResult(
                met: !present, expectation: expectation,
                actual: present ? "still present" : "absent"
            )
        case .compound(let expectations):
            let failures = expectations.compactMap { subExpectation -> String? in
                let result = validateCurrentState(subExpectation, elements: elements)
                guard !result.met else { return nil }
                return "\(subExpectation.summaryDescription): \(result.actual ?? "failed")"
            }
            guard !failures.isEmpty else {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: failures.joined(separator: "; ")
            )
        }
    }

    private func validateElementUpdatedCurrentState(
        heistId: HeistId?,
        property: ElementProperty?,
        oldValue: String?,
        newValue: String?,
        expectation: ActionExpectation,
        elements: [HeistElement]
    ) -> ExpectationResult {
        guard oldValue == nil else {
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "oldValue requires observed update"
            )
        }
        guard let newValue else {
            return ExpectationResult(
                met: false, expectation: expectation,
                actual: "newValue required for current state"
            )
        }

        let candidates = elements.filter { element in
            guard let heistId else { return true }
            return element.heistId == heistId
        }
        guard !candidates.isEmpty else {
            return ExpectationResult(met: false, expectation: expectation, actual: "element not found")
        }

        let properties = property.map { [$0] } ?? ElementProperty.allCases
        let matched = candidates.contains { element in
            properties.contains { element.currentStateValue(for: $0) == newValue }
        }
        guard !matched else {
            return ExpectationResult(met: true, expectation: expectation, actual: nil)
        }

        let observed = candidates.prefix(5).map { element in
            let values = properties
                .map { property in
                    "\(property.rawValue): \(element.currentStateValue(for: property) ?? "nil")"
                }
                .joined(separator: ", ")
            return "\(element.heistId): \(values)"
        }.joined(separator: "; ")
        return ExpectationResult(met: false, expectation: expectation, actual: observed)
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

    private func refreshSemanticSnapshot(baseline: BeforeState? = nil) async -> BeforeState? {
        guard refresh() != nil else { return nil }
        if let baseline {
            return await semanticStateAfterVisibleRefresh(baseline: baseline)
        }
        return captureSemanticState()
    }

    private func waitForSettledSemanticSnapshot(
        baseline: BeforeState,
        timeout: TimeInterval
    ) async -> BeforeState? {
        let timeoutMs = max(1, Int(timeout * 1000))
        let settleSession = SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: timeoutMs
        )
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baseline.tripwireSignal
        )
        guard settle.outcome.didSettleCleanly, let screen = settle.finalScreen else { return nil }
        stash.currentScreen = screen
        return await semanticStateAfterVisibleRefresh(baseline: baseline)
    }

    /// A Tripwire tick is permission to parse visible state, not to tickle
    /// scroll views. Full exploration is reserved for screen changes and
    /// post-action cycles.
    private func semanticStateAfterVisibleRefresh(baseline: BeforeState) async -> BeforeState {
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

    // MARK: - Screen Capture

    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        stash.captureScreen()
    }

    func captureScreenForRecording() -> UIImage? {
        stash.captureScreenForRecording()
    }

    // MARK: - Screen Name (for error messages)

    var screenName: String? { stash.lastScreenName }
    var screenId: String? { stash.lastScreenId }

    // MARK: - Recording Wiring

    /// Stakeout for recording frame capture.
    var stakeout: TheStakeout? {
        get { stash.stakeout }
        set { stash.stakeout = newValue }
    }

}

private extension HeistElement {
    func currentStateValue(for property: ElementProperty) -> String? {
        switch property {
        case .label:
            return label
        case .value:
            return value
        case .traits:
            return traits.map(\.rawValue).joined(separator: ", ")
        case .hint:
            return hint
        case .actions:
            return actions.map(\.description).joined(separator: ", ")
        case .frame:
            return "\(Int(frameX)),\(Int(frameY)),\(Int(frameWidth)),\(Int(frameHeight))"
        case .activationPoint:
            return "\(Int(activationPointX)),\(Int(activationPointY))"
        case .customContent:
            return customContent?.formattedCurrentStateValue
        case .rotors:
            guard let rotors, !rotors.isEmpty else { return nil }
            return rotors.map(\.name).joined(separator: ", ")
        }
    }
}

private extension Array where Element == HeistCustomContent {
    var formattedCurrentStateValue: String? {
        let formatted = compactMap { item -> String? in
            switch (item.label.isEmpty, item.value.isEmpty) {
            case (false, false): return "\(item.label): \(item.value)"
            case (false, true): return item.label
            case (true, false): return item.value
            case (true, true): return nil
            }
        }
        guard !formatted.isEmpty else { return nil }
        return formatted.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
