#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash stores values: latest observed accessibility evidence, settled
/// semantic truth, and failed-settle diagnostic evidence. Observation lifecycle
/// and promotion to settled truth are owned by `SemanticObservationStream`.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Observed Live Evidence

    private var latestObservedSemanticWorld: SemanticScreen = .empty

    // MARK: - Dispatch-Only Live Capture

    private var liveCapture: LiveCapture = .empty

    // MARK: - Settled Semantic Truth

    private var settledSemanticWorld: SemanticScreen = .empty
    /// Last clean visible hierarchy, with dispatch refs stripped.
    private var settledVisibleCapture: LiveCapture = .empty
    private var settledVisibleIds: Set<HeistId> = []

    // MARK: - Failed-Settle Diagnostic Evidence

    private var failedSettleDiagnosticEvidence: Screen?

    // MARK: - Observation Scheduling

    lazy var semanticObservationStream = SemanticObservationStream(stash: self, tripwire: tripwire)

    var latestSettledSemanticObservationEvent: SettledSemanticObservationEvent? {
        semanticObservationStream.latestEvent
    }

    var latestSettledSemanticObservation: SettledSemanticObservation? {
        semanticObservationStream.latestObservation
    }

    var latestSettledSemanticObservationInvalidated: Bool {
        semanticObservationStream.latestSettledObservationInvalidated
    }

    // MARK: - Interaction Cursor State

    /// Held rotor cursor — the single current selection while in rotor mode.
    /// Entering rotor mode on a host starts at index 0; subsequent steps cycle
    /// this held selection. Any non-rotor action clears it (rotor mode exit).
    var rotorCursor: RotorCursor?

    /// The in-memory rotor cursor. `currentSelection` is held **weakly** — rotor
    /// items are live UIKit objects we must not retain across the session; if it
    /// deallocates between steps the cursor is treated as lost and we re-enter at 0.
    final class RotorCursor {
        let hostHeistId: HeistId
        let rotorName: String
        weak var currentSelection: NSObject?

        init(hostHeistId: HeistId, rotorName: String, currentSelection: NSObject?) {
            self.hostHeistId = hostHeistId
            self.rotorName = rotorName
            self.currentSelection = currentSelection
        }
    }

    /// Drop rotor mode. Called when any non-rotor interaction runs.
    func clearRotorCursor() {
        rotorCursor = nil
    }

    /// Last settled accessibility world Button Heist believes. Semantic
    /// resolution and normal interface reads use this as truth.
    var settledSemanticScreen: Screen {
        Screen(semantic: settledSemanticWorld, liveCapture: settledVisibleCapture)
    }

    /// Current observed live viewport. Use this only for visible/debug reads
    /// and actionability, never as settled semantic truth.
    var liveVisibleScreen: Screen {
        let visibleElements = Dictionary(
            uniqueKeysWithValues: liveCapture.heistIdByElement.map { element, heistId in
                let observedEntry = latestObservedSemanticWorld.elements[heistId]
                let settledEntry = settledSemanticWorld.elements[heistId]
                return (
                    heistId,
                    ScreenElement(
                        heistId: heistId,
                        scrollContentLocation: settledEntry?.scrollContentLocation
                            ?? observedEntry?.scrollContentLocation,
                        element: element
                    )
                )
            }
        )
        let visibleContainerPaths = Set(liveCapture.hierarchy.containerPaths.map(\.path))
        return Screen(
            semantic: SemanticScreen(
                elements: visibleElements,
                containers: latestObservedSemanticWorld.containers.filter { visibleContainerPaths.contains($0.key) }
            ),
            liveCapture: liveCapture
        )
    }

    /// Last non-clean settle evidence. Reporting and trace code may consume it;
    /// semantic target resolution must not.
    var latestFailedSettleDiagnosticEvidence: Screen? {
        failedSettleDiagnosticEvidence
    }

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent parse. Proxy for call-site clarity —
    /// reads, matchers, scroll dispatch, and tab-bar geometry all need it
    /// without spelling out live-capture internals
    /// every time.
    var latestObservedLiveHierarchy: [AccessibilityHierarchy] {
        liveCapture.hierarchy
    }

    /// Scrollable containers paired with their backing UIView.
    /// Unwraps the weak ref wrapper for call sites that need a live UIView.
    var scrollableContainerViews: [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, ref) in liveCapture.scrollableContainerViews {
            if let view = ref.view {
                result[container] = view
            }
        }
        return result
    }

    /// HeistIds of all known elements in the settled world.
    ///
    /// After an exploration commit this includes elements that were observed
    /// during scrolling and are no longer on-screen. Use `visibleIds` when
    /// you specifically need the latest parsed on-screen ids.
    var knownIds: Set<HeistId> {
        ids(in: .known)
    }

    /// HeistIds of elements present in the hierarchy from the most recent
    /// parse. Strictly a subset of `knownIds` after an exploration union has
    /// been committed.
    var visibleIds: Set<HeistId> {
        ids(in: .visible)
    }

    /// Number of elements retained in committed semantic memory.
    var knownElementCount: Int {
        settledSemanticWorld.elements.count
    }

    /// HeistIds retained in committed semantic memory.
    var knownElementIds: Set<HeistId> {
        settledSemanticWorld.heistIds
    }

    /// HeistIds backed by the latest live parse.
    var visibleElementIds: Set<HeistId> {
        liveCapture.heistIds
    }

    /// O(1) lookup in committed semantic memory.
    func knownElement(heistId: HeistId) -> ScreenElement? {
        settledSemanticWorld.findElement(heistId: heistId)
    }

    /// Latest observed live element payload for a visible heistId.
    ///
    /// The parsed accessibility element and live handles are observational
    /// evidence only. If the id is also settled, reveal metadata is borrowed
    /// from settled semantic truth.
    func liveScreenElement(heistId: HeistId) -> ScreenElement? {
        guard let liveElement = liveCapture.element(for: heistId),
              let observedEntry = latestObservedSemanticWorld.elements[heistId] else { return nil }
        let settledEntry = settledSemanticWorld.elements[heistId]
        return ScreenElement(
            heistId: heistId,
            scrollContentLocation: settledEntry?.scrollContentLocation
                ?? observedEntry.scrollContentLocation,
            element: liveElement
        )
    }

    /// Semantic containers in deterministic traversal order.
    var semanticContainersInTraversalOrder: [SemanticScreen.Container] {
        settledSemanticWorld.containers.values
            .sorted { $0.path.indices.lexicographicallyPrecedes($1.path.indices) }
    }

    /// Elements in matcher/diagnostic order.
    var orderedSemanticElements: [ScreenElement] {
        settledSemanticScreen.orderedElements
    }

    /// Hash of committed semantic memory. Deliberately excludes live viewport
    /// geometry so scroll position alone does not produce semantic history.
    var semanticHash: String {
        settledSemanticWorld.semanticHash
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: HeistId? {
        liveCapture.firstResponderHeistId
    }

    /// Screen name from the settled screen (first header element by traversal order).
    var lastScreenName: String? {
        settledSemanticScreen.name
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        settledSemanticScreen.id
    }

    // MARK: - Cache Control

    /// Clear cached element data (used on suspend).
    func clearCache() {
        clearWorldForLifecycleReset()
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        clearWorldForLifecycleReset()
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing.
    let burglar: TheBurglar

    // MARK: - Parse Pipeline

    /// Read the live accessibility tree and produce one observation value.
    /// Every successful parse refreshes latest observed/live evidence, but it
    /// never promotes settled semantic truth.
    /// Returns nil if no accessible windows exist (loading screen,
    /// app backgrounded, etc.).
    func parse() -> Screen? {
        guard let result = burglar.parse() else { return nil }
        let screen = TheBurglar.buildScreen(from: result)
        recordParsedObservedEvidence(from: screen)
        return screen
    }

    /// Parse and refresh latest observed/live evidence. The returned visible
    /// screen may be used by exploration or diagnostics, but this method never
    /// updates settled semantic truth.
    @discardableResult
    func refreshLiveCapture() -> Screen? {
        parse()
    }

    /// Produce one visible observation for the settle loop without committing
    /// it yet. Successful parses refresh latest observed/live evidence; the
    /// observation stream alone promotes a proven final screen to settled truth.
    func semanticObservationForSettle() -> Screen? {
        parse()
    }

    /// Produce one page observation for scroll exploration. Exploration owns a
    /// local semantic union until it finishes; the observation stream commits
    /// only the final explored screen as settled discovery truth.
    func semanticPageForExploration() -> Screen? {
        parse()
    }

    @discardableResult
    func commitSettledVisibleWorld(_ screen: Screen) -> Screen {
        let committedScreen = screenByRefreshingSettledSemanticWorld(with: screen)
        commitSettledWorld(committedScreen)
        return settledSemanticScreen
    }

    @discardableResult
    func commitSettledDiscoveryWorld(_ screen: Screen) -> Screen {
        commitSettledWorld(screen)
        return settledSemanticScreen
    }

    func recordFailedSettleDiagnosticEvidence(_ screen: Screen?) {
        if let screen {
            recordParsedObservedEvidence(from: screen)
        }
        failedSettleDiagnosticEvidence = screen
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    func recordParsedObservedEvidence(_ screen: Screen) {
        recordParsedObservedEvidence(from: screen)
    }

    func installScreenForTesting(_ screen: Screen) {
        _ = semanticObservationStream.commitSettledVisibleObservation(screen)
    }

    /// Starting value for page-by-page exploration. Exploration carries a local
    /// Screen union and hands the final observation back to the stream.
    func explorationBaseline() -> Screen {
        settledSemanticScreen
    }

    /// Apply visible settled refresh semantics without retaining settled live
    /// handles. The previous settled visible ids are metadata, not actionability
    /// state; they let a visible commit drop entries that vanished from the
    /// settled viewport while preserving discovery-only memory.
    func screenByRefreshingSettledSemanticWorld(with visibleRefresh: Screen) -> Screen {
        guard !visibleRefresh.visibleIds.isEmpty else {
            return visibleRefresh
        }
        let knownOnlyIds = settledSemanticWorld.heistIds.subtracting(settledVisibleIds)
        let refreshesKnownViewport = visibleRefresh.visibleIds.isSubset(of: settledSemanticWorld.heistIds)
            || !settledVisibleIds.isDisjoint(with: visibleRefresh.visibleIds)
            || (!knownOnlyIds.isEmpty && settledVisibleIds.isEmpty)
        guard refreshesKnownViewport else { return visibleRefresh }

        let disappearedVisibleIds = settledVisibleIds.subtracting(visibleRefresh.visibleIds)
        let mergedElements = settledSemanticWorld.elements
            .merging(visibleRefresh.semantic.elements) { _, new in new }
            .filter { !disappearedVisibleIds.contains($0.key) }
        let mergedContainers = settledSemanticWorld.containers
            .merging(visibleRefresh.semantic.containers) { _, new in new }
        return Screen(
            semantic: SemanticScreen(elements: mergedElements, containers: mergedContainers),
            liveCapture: visibleRefresh.liveCapture
        )
    }

    func knownContentOriginIndex() -> [AccessibilityElement: CGPoint?] {
        Dictionary(
            selectElements().map { ($0.element, $0.contentSpaceOrigin) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func visibleContentOriginAnchors() -> [(heistId: HeistId, origin: CGPoint)] {
        visibleIds.compactMap { heistId in
            guard let entry = screenElement(heistId: heistId, in: .visible),
                  let origin = entry.contentSpaceOrigin else { return nil }
            return (heistId: heistId, origin: origin)
        }
    }

    func firstResponderScreenElement() -> ScreenElement? {
        guard let heistId = firstResponderHeistId else { return nil }
        return screenElement(heistId: heistId, in: .known)
    }

    func liveHeistIds() -> Set<HeistId> {
        liveCapture.heistIds
    }

    func liveContains(heistId: HeistId) -> Bool {
        liveCapture.contains(heistId: heistId)
    }

    func liveHeistId(for element: AccessibilityElement) -> HeistId? {
        liveCapture.heistId(for: element)
    }

    func liveObject(for heistId: HeistId) -> NSObject? {
        liveCapture.object(for: heistId)
    }

    func liveScrollView(for screenElement: ScreenElement) -> UIScrollView? {
        liveCapture.scrollView(for: screenElement)
    }

    func liveElementHeistId(matching object: NSObject) -> HeistId? {
        liveCapture.elementRefs.first { _, ref in
            ref.object === object
        }?.key
    }

    func liveContainerObject(forPath path: TreePath) -> NSObject? {
        liveCapture.containerObject(forPath: path)
    }

    func liveContainer(forPath path: TreePath) -> AccessibilityContainer? {
        liveCapture.hierarchy.containerPaths.first { $0.path == path }?.container
    }

    func liveScrollContainer(matching scrollView: UIScrollView) -> AccessibilityContainer? {
        liveCapture.scrollableContainerViews.first { _, ref in
            ref.view === scrollView
        }?.key
    }

    func liveContainerName(for container: AccessibilityContainer) -> ContainerName? {
        liveCapture.containerNames[container]
    }

    func liveContainerName(forPath path: TreePath) -> ContainerName? {
        liveCapture.containerNamesByPath[path]
    }

    func liveScrollableContainerView(forPath path: TreePath) -> UIView? {
        liveCapture.scrollableContainerViewsByPath[path]?.view
    }

    private func clearWorldForLifecycleReset() {
        latestObservedSemanticWorld = .empty
        liveCapture = .empty
        settledSemanticWorld = .empty
        settledVisibleCapture = .empty
        settledVisibleIds = []
        failedSettleDiagnosticEvidence = nil
        semanticObservationStream.clearSettledObservationHistory()
    }

    private func recordParsedObservedEvidence(from screen: Screen) {
        latestObservedSemanticWorld = screen.semantic
        liveCapture = screen.liveCapture
    }

    private func commitSettledWorld(_ screen: Screen) {
        settledSemanticWorld = screen.semantic
        settledVisibleCapture = screen.liveCapture.strippingDispatchReferences()
        settledVisibleIds = screen.visibleIds
        recordParsedObservedEvidence(from: screen)
        failedSettleDiagnosticEvidence = nil
    }

    // MARK: - Interface Read Helpers

    /// Settled parser hierarchy plus Button Heist annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the interface of the settled screen, not an arbitrary one.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: settledSemanticScreen, timestamp: timestamp)
    }

    /// Current semantic screen projection used for traces and deltas.
    ///
    /// Unlike `interface()`, this reads the committed semantic state produced
    /// by exploration, so off-viewport targetable elements participate in
    /// post-action deltas.
    func semanticInterface(timestamp: Date = Date()) -> Interface {
        WireConversion.toSemanticInterface(from: settledSemanticScreen, timestamp: timestamp)
    }

    /// Single-build semantic variant for state capture and delta projection.
    func semanticInterfaceWithHash(timestamp: Date = Date()) -> (interface: Interface, hash: String) {
        let interface = semanticInterface(timestamp: timestamp)
        return (interface, AccessibilityTrace.Capture.hash(interface))
    }

    func semanticInterfaceWithHash(
        for screen: Screen,
        timestamp: Date = Date()
    ) -> (interface: Interface, hash: String) {
        let interface = WireConversion.toSemanticInterface(from: screen, timestamp: timestamp)
        return (interface, AccessibilityTrace.Capture.hash(interface))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
