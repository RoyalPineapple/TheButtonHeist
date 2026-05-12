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

    static let treeUnavailableMessage = "Could not access accessibility tree"

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let actions: Actions

    init(tripwire: TheTripwire, forceSwipeScrolling: Bool = false) {
        self.tripwire = tripwire
        let stash = TheStash(tripwire: tripwire)
        let safecracker = TheSafecracker()
        self.stash = stash
        self.safecracker = safecracker
        let navigation = Navigation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            forceSwipeScrolling: forceSwipeScrolling
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
        let tree: [InterfaceNode]
        let treeHash: Int
        let viewController: ObjectIdentifier?
    }

    /// Capture the current state for delta computation before an action.
    /// Caller must have called `refresh()` already this frame.
    func captureBeforeState() -> BeforeState {
        let tree = stash.wireTree()
        return BeforeState(
            snapshot: stash.selectElements(),
            elements: stash.currentHierarchy.sortedElements,
            hierarchy: stash.currentHierarchy,
            tree: tree,
            treeHash: tree.hashValue,
            viewController: tripwire.topmostViewController().map(ObjectIdentifier.init)
        )
    }

    // MARK: - Action Result with Delta

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        errorKind: ErrorKind? = nil,
        before: BeforeState
    ) async -> ActionResult {
        guard success else {
            let kind = errorKind
                ?? ((method == .elementNotFound || method == .elementDeallocated)
                    ? .elementNotFound : .actionFailed)
            var builder = ActionResultBuilder(method: method, snapshot: before.snapshot)
            builder.message = message
            builder.value = value
            return builder.failure(errorKind: kind)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
        let settleResult = await settleSession.run(start: start)
        let settleMs = settleResult.outcome.timeMs
        var didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, snapshot: before.snapshot)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.value = value
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed)
        }
        logSettleOutcome(settleResult.outcome)

        var afterScreen = stash.parse()

        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let afterElements = afterScreen?.hierarchy.sortedElements ?? []
        let afterHierarchy = afterScreen?.hierarchy ?? []
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
            || stash.isTopologyChanged(
                before: before.elements, after: afterElements,
                beforeHierarchy: before.hierarchy, afterHierarchy: afterHierarchy
            )
        if isScreenChange {
            navigation.containerExploreStates.removeAll()
        }

        if isScreenChange && afterElements.isEmpty {
            let repopulated = await repopulateAfterScreenChange(into: &afterScreen)
            if !repopulated { didSettle = false }
        }

        if let afterScreen {
            stash.currentScreen = afterScreen
        }

        _ = await navigation.exploreAndPrune()
        let afterSnapshot = stash.selectElements()

        let baseDelta = stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            beforeTree: before.tree,
            beforeTreeHash: before.treeHash,
            isScreenChange: isScreenChange
        )
        let transientElements = SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: afterScreen?.hierarchy.sortedElements ?? []
        )
        let delta = transientElements.isEmpty
            ? baseDelta
            : enriching(baseDelta, transient: transientElements)

        await stash.captureActionFrame()

        var builder = ActionResultBuilder(method: method, snapshot: afterSnapshot)
        builder.message = message
        builder.value = value
        builder.interfaceDelta = delta
        builder.settled = didSettle
        builder.settleTimeMs = settleMs

        return builder.success()
    }

    // MARK: - Settle Outcome Helpers

    private func logSettleOutcome(_ outcome: SettleOutcome) {
        switch outcome {
        case .settled(let ms):
            insideJobLogger.info("Post-action settle: settled in \(ms)ms")
        case .screenChanged(let ms):
            insideJobLogger.info("Post-action settle: screen changed mid-loop after \(ms)ms")
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

    /// Return a copy of `delta` with `transient` populated.
    private func enriching(
        _ delta: InterfaceDelta,
        transient: [AccessibilityElement]
    ) -> InterfaceDelta {
        let transientWire = transient.map { TheStash.WireConversion.convert($0) }
        switch delta {
        case .noChange(let payload):
            return .noChange(InterfaceDelta.NoChange(
                elementCount: payload.elementCount,
                transient: transientWire
            ))
        case .elementsChanged(let payload):
            return .elementsChanged(InterfaceDelta.ElementsChanged(
                elementCount: payload.elementCount,
                edits: payload.edits,
                transient: transientWire
            ))
        case .screenChanged(let payload):
            return .screenChanged(InterfaceDelta.ScreenChanged(
                elementCount: payload.elementCount,
                newInterface: payload.newInterface,
                postEdits: payload.postEdits,
                transient: transientWire
            ))
        }
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
        broadcastHistory = .fresh
    }

    // MARK: - Response State Tracking

    /// State captured after each response sent to the driver.
    struct SentState {
        let treeHash: Int
        let beforeState: BeforeState
        let screenId: String?
    }

    /// Two-phase broadcast history: `.fresh` before the first response, and
    /// `.sent` once a response has been recorded. Modelled as an enum so the
    /// "never sent" case is structurally distinct from any sent state — every
    /// caller must handle it explicitly rather than guarding against `nil`.
    enum BroadcastHistory {
        case fresh
        case sent(SentState)
    }

    private(set) var broadcastHistory: BroadcastHistory = .fresh

    /// The state of the last response sent to the driver, if any.
    var lastSentState: SentState? {
        if case .sent(let state) = broadcastHistory { return state }
        return nil
    }

    /// Snapshot current state as "last sent" — call after every response to the driver.
    func recordSentState() {
        broadcastHistory = .sent(SentState(
            treeHash: stash.wireTreeHash(),
            beforeState: captureBeforeState(),
            screenId: stash.lastScreenId
        ))
    }

    /// Record sent state from an already-known hash (avoids redundant wire conversion).
    func recordSentState(treeHash: Int) {
        broadcastHistory = .sent(SentState(
            treeHash: treeHash,
            beforeState: captureBeforeState(),
            screenId: stash.lastScreenId
        ))
    }

    // MARK: - Broadcast Support

    /// Refresh and return an Interface if the tree changed since the last broadcast.
    func broadcastInterfaceIfChanged() -> Interface? {
        guard refresh() != nil else { return nil }

        let currentHash = stash.wireTreeHash()

        guard currentHash != stash.lastHierarchyHash else { return nil }
        stash.lastHierarchyHash = currentHash

        return Interface(timestamp: Date(), tree: stash.wireTree())
    }

    /// Build a full Interface payload from current state.
    func currentInterface() -> Interface {
        Interface(timestamp: Date(), tree: stash.wireTree())
    }

    // MARK: - Background Delta

    /// Check if the accessibility tree changed since the last response.
    func computeBackgroundDelta() -> InterfaceDelta? {
        guard case .sent(let sent) = broadcastHistory, sent.treeHash != 0 else { return nil }
        guard refresh() != nil else { return nil }
        let snapshot = stash.selectElements()
        let currentHash = stash.wireTreeHash()
        guard currentHash != sent.treeHash else { return nil }

        return computeDelta(
            before: sent.beforeState,
            afterSnapshot: snapshot
        )
    }

    /// Whether the screen changed since the last response (for fast-redirect logic).
    var screenChangedSinceLastSent: Bool {
        guard case .sent(let sent) = broadcastHistory else { return false }
        return sent.screenId != stash.lastScreenId
    }

    /// Screen ID from the last response, for diagnostic messages.
    var lastSentScreenId: String? {
        if case .sent(let sent) = broadcastHistory { return sent.screenId }
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

    /// Run the wait-for-change pipeline: fast path (already changed) or slow path (poll loop).
    func executeWaitForChange(timeout: TimeInterval, expectation: ActionExpectation?) async -> ActionResult {
        let start = CFAbsoluteTimeGetCurrent()

        let before = captureBeforeState()

        guard let initial = refreshAndSnapshot() else {
            return treeUnavailableResult(method: .waitForChange)
        }

        // Fast path: tree already changed since the last response
        let lastHash: Int = {
            if case .sent(let sent) = broadcastHistory { return sent.treeHash }
            return 0
        }()
        if lastHash != 0, initial.wireHash != lastHash {
            let delta = computeDelta(before: before, afterSnapshot: initial.snapshot)
            if let result = evaluateWaitForChange(
                delta: delta, afterSnapshot: initial.snapshot, expectation: expectation,
                start: start, round: 0, message: "already changed (0.0s)"
            ) {
                return result
            }
        }

        // Slow path: poll until a change lands or we time out
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        var beforeWireHash = initial.wireHash
        var round = 0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            _ = await tripwire.waitForAllClear(timeout: min(remaining, 1.0))
            guard let current = refreshAndSnapshot() else { continue }
            round += 1

            if current.wireHash == beforeWireHash { continue }

            let delta = computeDelta(before: before, afterSnapshot: current.snapshot)
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

            if let result = evaluateWaitForChange(
                delta: delta, afterSnapshot: current.snapshot, expectation: expectation,
                start: start, round: round, message: "changed after \(elapsed)s (\(round) rounds)"
            ) {
                return result
            }

            beforeWireHash = current.wireHash
            insideJobLogger.debug("wait_for_change round \(round): \(delta.kindRawValue), expectation not yet met")
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let afterSnapshot = refreshAndSnapshot()?.snapshot ?? []
        let delta = computeDelta(before: before, afterSnapshot: afterSnapshot)
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.message = expectation != nil
            ? "timed out after \(elapsed)s — expectation not met"
            : "timed out after \(elapsed)s — no change detected"
        builder.interfaceDelta = delta
        return builder.failure(errorKind: .timeout)
    }

    private func evaluateWaitForChange(
        delta: InterfaceDelta,
        afterSnapshot: [Screen.ScreenElement],
        expectation: ActionExpectation?,
        start: CFAbsoluteTime,
        round: Int,
        message: String
    ) -> ActionResult? {
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.interfaceDelta = delta

        guard let expectation else {
            builder.message = message
            return builder.success()
        }

        guard expectation.validate(against: builder.success()).met else { return nil }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
        return builder.success()
    }

    // MARK: - Private Helpers

    private func refreshAndSnapshot() -> (snapshot: [Screen.ScreenElement], wireHash: Int)? {
        guard refresh() != nil else { return nil }
        let snapshot = stash.selectElements()
        let wireHash = stash.wireTreeHash()
        return (snapshot, wireHash)
    }

    private func computeDelta(
        before: BeforeState,
        afterSnapshot: [Screen.ScreenElement]
    ) -> InterfaceDelta {
        let afterElements = stash.currentHierarchy.sortedElements
        let isScreenChange = tripwire.isScreenChange(
            before: before.viewController,
            after: tripwire.topmostViewController().map(ObjectIdentifier.init)
        ) || stash.isTopologyChanged(
            before: before.elements, after: afterElements,
            beforeHierarchy: before.hierarchy, afterHierarchy: stash.currentHierarchy
        )
        return stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            beforeTree: before.tree,
            beforeTreeHash: before.treeHash,
            isScreenChange: isScreenChange
        )
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

#endif // DEBUG
#endif // canImport(UIKit)
