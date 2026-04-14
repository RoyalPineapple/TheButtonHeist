#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore
import os.log

/// The brains of the operation — plans the play, sequences the crew.
///
/// TheBrains takes a command and works it through to a result by coordinating
/// TheStash (registry), TheSafecracker (gestures), and TheTripwire (timing).
/// He owns action execution, scroll orchestration, screen exploration,
/// and the post-action delta cycle.
@MainActor
final class TheBrains {

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire

    /// Cached state from the last explore of each scrollable container.
    var containerExploreStates: [AccessibilityContainer: ContainerExploreState] = [:]

    /// Accumulates every heistId seen during an explore cycle.
    /// Populated by `apply()` when non-nil, pruned by `pruneAfterExplore()`.
    /// nil outside of an explore cycle — `apply()` only accumulates when this is set.
    var exploreCycleIds: Set<String>?

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.stash = TheStash(tripwire: tripwire)
        self.safecracker = TheSafecracker()
    }

    // MARK: - Refresh Convenience

    /// Refresh the accessibility tree into the stash.
    @discardableResult
    func refresh() -> TheStash.ParseResult? {
        guard let result = stash.refresh() else { return nil }
        exploreCycleIds?.formUnion(stash.registry.viewportIds)
        return result
    }

    // MARK: - Before/After State

    /// State captured before an action for delta computation.
    struct BeforeState {
        let snapshot: [TheStash.ScreenElement]
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let viewController: ObjectIdentifier?
    }

    /// Capture the current state for delta computation before an action.
    /// Caller must have called `refresh()` already this frame.
    func captureBeforeState() -> BeforeState {
        BeforeState(
            snapshot: stash.selectElements(),
            elements: stash.currentHierarchy.sortedElements,
            hierarchy: stash.currentHierarchy,
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
        before: BeforeState,
        target: ElementTarget? = nil
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
        let settled = await tripwire.waitForAllClear(timeout: 1.0)
        let settleMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        insideJobLogger.info("Post-action settle: \(settled ? "all clear" : "timed out") in \(settleMs)ms")

        var afterResult = stash.parse()

        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
            || stash.isTopologyChanged(
                before: before.elements, after: afterResult?.elements ?? [],
                beforeHierarchy: before.hierarchy, afterHierarchy: afterResult?.hierarchy ?? []
            )
        if isScreenChange {
            stash.registry.clearScreen()
            containerExploreStates.removeAll()
        }

        // After a screen change (e.g. popup dismiss), the accessibility tree
        // may be transiently empty — the old VC's elements are gone but the
        // newly-exposed VC hasn't re-registered its elements yet. Wait for
        // the tree to repopulate using the tripwire settle loop, then re-parse.
        if isScreenChange && (afterResult?.elements ?? []).isEmpty {
            let repopStart = CFAbsoluteTimeGetCurrent()
            for attempt in 1...10 {
                _ = await tripwire.waitForAllClear(timeout: 0.2)
                afterResult = stash.parse()
                if let elements = afterResult?.elements, !elements.isEmpty {
                    let repopMs = Int((CFAbsoluteTimeGetCurrent() - repopStart) * 1000)
                    insideJobLogger.info("Screen re-populated after \(attempt) re-parse(s) in \(repopMs)ms")
                    break
                }
            }
        }

        if let afterResult {
            let heistIds = stash.apply(afterResult)
            exploreCycleIds?.formUnion(heistIds)
        }

        let manifest = await exploreAndPrune()
        let afterSnapshot = stash.selectElements()

        let delta = stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: afterResult?.hierarchy, isScreenChange: isScreenChange
        )

        let exploreResult = ExploreResult(
            elements: [],
            scrollCount: manifest.scrollCount,
            containersExplored: manifest.exploredContainers.count,
            containersSkippedObscured: manifest.skippedObscuredContainers,
            explorationTime: manifest.explorationTime
        )

        stash.captureActionFrame()

        var builder = ActionResultBuilder(method: method, snapshot: afterSnapshot)
        builder.message = message
        builder.value = value
        builder.interfaceDelta = delta

        var elementLabel: String?
        var elementValue: String?
        var elementTraits: [HeistTrait]?
        if let target {
            let postElement = stash.resolveTarget(target).resolved?.element
            elementLabel = postElement?.label
            elementValue = postElement?.value
            if let traits = postElement?.traits {
                elementTraits = stash.traitNames(traits)
            }
        }

        return builder.success(
            elementLabel: elementLabel,
            elementValue: elementValue,
            elementTraits: elementTraits,
            exploreResult: exploreResult
        )
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
        containerExploreStates.removeAll()
        exploreCycleIds = nil
    }

    // MARK: - Facades for TheInsideJob

    // These methods let TheInsideJob talk to TheBrains without reaching
    // through to TheStash. TheStash's internal state is TheBrains' concern.

    /// All elements in the registry sorted by traversal order.
    func selectElements() -> [TheStash.ScreenElement] {
        stash.selectElements()
    }

    /// Convert a snapshot to wire format.
    func toWire(_ entries: [TheStash.ScreenElement]) -> [HeistElement] {
        stash.toWire(entries)
    }

    /// Convert the hierarchy tree to wire format.
    func convertTree() -> [ElementNode]? {
        stash.convertTree(stash.currentHierarchy)
    }

    /// Convert a parse result's hierarchy to wire nodes.
    func convertTree(from parseResult: TheStash.ParseResult) -> [ElementNode] {
        stash.convertTree(parseResult.hierarchy) ?? []
    }

    /// Build a full Interface payload from current state.
    func currentInterface() -> Interface {
        let snapshot = stash.selectElements()
        let wireElements = stash.toWire(snapshot)
        let tree = stash.convertTree(stash.currentHierarchy)
        return Interface(timestamp: Date(), elements: wireElements, tree: tree)
    }

    /// Current screen name.
    var screenName: String? { stash.lastScreenName }

    /// Current screen ID.
    var screenId: String? { stash.lastScreenId }

    /// Total element count in the registry.
    var elementCount: Int { stash.registry.elements.count }

    /// Hash for polling comparison. Read/write through TheBrains.
    var hierarchyHash: Int {
        get { stash.lastHierarchyHash }
        set { stash.lastHierarchyHash = newValue }
    }

    /// Wire hash for a snapshot.
    func wireHash(_ snapshot: [TheStash.ScreenElement]) -> Int {
        stash.toWire(snapshot).hashValue
    }

    /// Stakeout for recording wiring.
    var stakeout: TheStakeout? {
        get { stash.stakeout }
        set { stash.stakeout = newValue }
    }

    /// Capture the screen.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        stash.captureScreen()
    }

    /// Capture the screen including fingerprint overlay (for recordings).
    func captureScreenForRecording() -> UIImage? {
        stash.captureScreenForRecording()
    }

    /// Check if the tree has changed between two snapshots (topology check).
    func isTopologyChanged(before: BeforeState, afterElements: [AccessibilityElement], afterHierarchy: [AccessibilityHierarchy]) -> Bool {
        stash.isTopologyChanged(
            before: before.elements, after: afterElements,
            beforeHierarchy: before.hierarchy, afterHierarchy: afterHierarchy
        )
    }

    /// Compute delta between a before-state and an after-snapshot.
    func computeDelta(before: BeforeState, afterSnapshot: [TheStash.ScreenElement]) -> InterfaceDelta {
        let afterElements = stash.currentHierarchy.sortedElements
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: tripwire.topmostViewController().map(ObjectIdentifier.init))
            || stash.isTopologyChanged(
                before: before.elements, after: afterElements,
                beforeHierarchy: before.hierarchy, afterHierarchy: stash.currentHierarchy
            )
        return stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: stash.currentHierarchy, isScreenChange: isScreenChange
        )
    }

    /// Compute the full background delta against a before-state.
    /// Returns nil if the tree hasn't changed since lastSentTreeHash.
    func computeBackgroundDelta(lastSentTreeHash: Int, lastSentBeforeState: BeforeState?) -> InterfaceDelta? {
        guard lastSentTreeHash != 0 else { return nil }
        refresh()
        let snapshot = stash.selectElements()
        let wireElements = stash.toWire(snapshot)
        let currentHash = wireElements.hashValue
        guard currentHash != lastSentTreeHash else { return nil }

        guard let beforeState = lastSentBeforeState else {
            let tree = stash.convertTree(stash.currentHierarchy)
            return InterfaceDelta(
                kind: .screenChanged,
                elementCount: wireElements.count,
                newInterface: Interface(timestamp: Date(), elements: wireElements, tree: tree)
            )
        }

        return computeDelta(before: beforeState, afterSnapshot: snapshot)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
