#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// Main-actor state cache for Button Heist's current view of the app.
///
/// The stash separates four kinds of state:
/// - latest observed capture: raw parser output from the most recent
///   accessibility read;
/// - settled world: durable semantic state promoted by observation;
/// - visible live view: UIKit refs, live geometry, and viewport-tied lookup
///   state used only for dispatch/actionability;
/// - semantic projection: wire/report-facing values derived from the settled
///   world, never stored as live handles.
///
/// It does not own the observation lifecycle or decide when an observation is
/// settled; `SemanticObservationStream` owns promotion into settled world.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing.
    let burglar: TheBurglar

    // MARK: - State Stores

    var observedState = ObservedState()
    var liveLookup = LiveLookup()
    var worldStore = WorldStore()

    var latestObservedSemanticWorld: SemanticScreen {
        observedState.semanticWorld
    }

    var currentLiveCapture: LiveCapture {
        liveLookup.liveCapture
    }

    /// Unit-test fixture for the next explicit visible refresh. Production
    /// refreshes always parse UIKit; synthetic tests can install one screen as
    /// the current tree without retaining any live object strongly.
    var nextVisibleRefreshScreenForTesting: Screen?

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

    /// Last settled world Button Heist believes. Semantic resolution and normal
    /// interface reads use this as durable truth. Its live-capture half is a
    /// value-only projection scaffold with dispatch refs stripped.
    var settledSemanticScreen: Screen {
        worldStore.screen
    }

    /// Current visible live view. Use this only for visible/debug reads and
    /// actionability, never as settled semantic truth.
    var liveVisibleScreen: Screen {
        liveLookup.visibleScreen(observedSemanticWorld: observedState.semanticWorld)
    }

    /// Last non-clean settle evidence. Reporting and trace code may consume it;
    /// semantic target resolution must not.
    var latestFailedSettleDiagnosticEvidence: Screen? {
        observedState.failedSettleDiagnosticEvidence
    }

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent observed capture. Proxy for call-site
    /// clarity: reads, matchers, scroll dispatch, and tab-bar geometry all need
    /// it without spelling out live-capture internals every time.
    var latestObservedLiveHierarchy: [AccessibilityHierarchy] {
        liveLookup.hierarchy
    }

    /// Scrollable container paths paired with their backing UIView from the
    /// visible live view. Unwraps the weak ref wrapper for call sites that need
    /// a live UIView.
    var scrollableContainerViewsByPath: [TreePath: UIView] {
        liveLookup.scrollableContainerViewsByPath
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
        worldStore.elementCount
    }

    /// HeistIds retained in committed semantic memory.
    var knownElementIds: Set<HeistId> {
        worldStore.heistIds
    }

    /// HeistIds backed by the latest live parse.
    var visibleElementIds: Set<HeistId> {
        liveLookup.heistIds
    }

    /// O(1) lookup in committed semantic memory.
    func knownElement(heistId: HeistId) -> ScreenElement? {
        worldStore.element(heistId: heistId)
    }

    /// Latest observed capture payload for a visible heistId.
    ///
    /// The parsed accessibility element, live handles, and reveal metadata are
    /// observational evidence only. For visible live entries, the newest parse
    /// owns viewport metadata; cached settled metadata must not override it.
    func liveScreenElement(heistId: HeistId) -> ScreenElement? {
        liveLookup.screenElement(
            heistId: heistId,
            observedSemanticWorld: observedState.semanticWorld
        )
    }

    /// Semantic containers in deterministic traversal order.
    var semanticContainersInTraversalOrder: [SemanticScreen.Container] {
        worldStore.containersInTraversalOrder
    }

    /// Elements in matcher/diagnostic order.
    var orderedSemanticElements: [ScreenElement] {
        worldStore.orderedElements
    }

    /// Hash of the settled world. Deliberately excludes live viewport geometry
    /// so scroll position alone does not produce semantic history.
    var semanticHash: String {
        worldStore.semanticHash
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: HeistId? {
        liveLookup.firstResponderHeistId
    }

    /// Screen name from the settled screen (first header element by traversal order).
    var lastScreenName: String? {
        worldStore.screenName
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        worldStore.screenId
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
