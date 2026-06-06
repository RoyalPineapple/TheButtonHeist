#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash holds settled accessibility truth, disposable live action handles,
/// and explicit diagnostic settle evidence.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Mutable State

    private var settledWorld: Screen = .empty
    private var liveCapture: LiveCapture = .empty
    private var diagnosticEvidence: Screen?

    lazy var semanticObservationStream = SemanticObservationStream(stash: self, tripwire: tripwire)

    var latestSettledSemanticObservationEvent: SettledSemanticObservationEvent? {
        semanticObservationStream.latestEvent
    }

    var latestSettledSemanticObservation: SettledSemanticObservation? {
        semanticObservationStream.latestObservation
    }

    var latestSettledSemanticObservationIsDirty: Bool {
        semanticObservationStream.latestObservationIsDirty
    }

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
    var settledScreen: Screen {
        settledWorld
    }

    /// Current live viewport projected through settled semantic identity.
    /// Use this only for actionability and geometry, never as semantic truth.
    var liveVisibleScreen: Screen {
        Screen(semantic: settledWorld.semantic, liveCapture: liveCapture)
    }

    /// Last non-clean settle evidence. Reporting and trace code may consume it;
    /// semantic target resolution must not.
    var latestSettleDiagnosticEvidence: Screen? {
        diagnosticEvidence
    }

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent parse. Proxy for call-site clarity —
    /// reads, matchers, scroll dispatch, and tab-bar geometry all need it
    /// without spelling out live-capture internals
    /// every time.
    var currentHierarchy: [AccessibilityHierarchy] {
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
        settledWorld.semantic.elements.count
    }

    /// HeistIds retained in committed semantic memory.
    var knownElementIds: Set<HeistId> {
        settledWorld.semantic.heistIds
    }

    /// HeistIds backed by the latest live parse.
    var visibleElementIds: Set<HeistId> {
        liveCapture.heistIds
    }

    /// O(1) lookup in committed semantic memory.
    func knownElement(heistId: HeistId) -> ScreenElement? {
        settledWorld.findElement(heistId: heistId)
    }

    /// Semantic containers in deterministic traversal order.
    var semanticContainersInTraversalOrder: [SemanticScreen.Container] {
        settledWorld.semantic.containers.values
            .sorted { $0.path.indices.lexicographicallyPrecedes($1.path.indices) }
    }

    /// Elements in matcher/diagnostic order.
    var orderedSemanticElements: [ScreenElement] {
        settledScreen.orderedElements
    }

    /// Hash of committed semantic memory. Deliberately excludes live viewport
    /// geometry so scroll position alone does not produce semantic history.
    var semanticHash: String {
        settledWorld.semanticHash
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: HeistId? {
        liveCapture.firstResponderHeistId
    }

    /// Screen name from the settled screen (first header element by traversal order).
    var lastScreenName: String? {
        settledScreen.name
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        settledScreen.id
    }

    // MARK: - Cache Control

    /// Clear cached element data (used on suspend).
    func clearCache() {
        clearCommittedScreen()
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        clearCommittedScreen()
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing.
    let burglar: TheBurglar

    // MARK: - Parse Pipeline

    /// Read the live accessibility tree and produce a Screen value.
    /// Pure: does not touch settled world, live capture, or diagnostics.
    /// Returns nil if no accessible windows exist (loading screen,
    /// app backgrounded, etc.).
    func parse() -> Screen? {
        guard let result = burglar.parse() else { return nil }
        return TheBurglar.buildScreen(from: result)
    }

    /// Parse and retain only disposable live action machinery. The returned
    /// visible screen may be used by exploration or diagnostics, but this
    /// method never updates settled world truth.
    @discardableResult
    func refreshLiveCapture() -> Screen? {
        guard let screen = parse() else { return nil }
        storeLiveCapture(from: screen)
        return screen
    }

    /// Produce one visible observation for the settle loop without committing
    /// it yet. The observation stream stores and publishes the proven final
    /// screen through its settled-observation commit path.
    func semanticObservationForSettle() -> Screen? {
        parse()
    }

    /// Produce one page observation for scroll exploration. Exploration owns a
    /// local semantic union until it finishes and commits the explored screen.
    func semanticPageForExploration() -> Screen? {
        parse()
    }

    func storeSettledSemanticObservationForStream(_ screen: Screen) {
        commitSettledWorld(screen)
    }

    func recordSettleDiagnosticEvidence(_ screen: Screen?) {
        diagnosticEvidence = screen
        semanticObservationStream.markDirtyFromTripwire()
    }

    func recordLivePageObservation(_ screen: Screen) {
        storeLiveCapture(from: screen)
    }

    func commitExploredSettledScreen(_ screen: Screen) {
        commitSettledWorld(screen)
    }

    func installScreenForTesting(_ screen: Screen) {
        _ = semanticObservationStream.commitSettledObservation(screen)
    }

    /// Starting value for page-by-page exploration. Exploration is the one
    /// runtime path that intentionally carries a local Screen union before
    /// committing it back through `commitExploredSettledScreen`.
    func explorationBaseline() -> Screen {
        settledScreen
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

    private func clearCommittedScreen() {
        settledWorld = .empty
        liveCapture = .empty
        diagnosticEvidence = nil
        semanticObservationStream.clearLatestObservation()
    }

    private func storeLiveCapture(from screen: Screen) {
        liveCapture = screen.liveCapture
    }

    private func commitSettledWorld(_ screen: Screen) {
        settledWorld = screen
        liveCapture = screen.liveCapture
        diagnosticEvidence = nil
    }

    // MARK: - Interface Read Helpers

    /// Settled parser hierarchy plus Button Heist annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the interface of the settled screen, not an arbitrary one.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: settledScreen, timestamp: timestamp)
    }

    /// Current semantic screen projection used for traces and deltas.
    ///
    /// Unlike `interface()`, this reads the committed semantic state produced
    /// by exploration, so off-viewport targetable elements participate in
    /// post-action deltas.
    func semanticInterface(timestamp: Date = Date()) -> Interface {
        WireConversion.toSemanticInterface(from: settledScreen, timestamp: timestamp)
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
