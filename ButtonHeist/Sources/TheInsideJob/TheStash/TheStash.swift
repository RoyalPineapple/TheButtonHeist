#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

/// Main-actor owner of Button Heist's current accessibility interface.
///
/// The interface tree is the only target-resolution authority. The latest
/// observation carries disposable UIKit evidence for actionability, while a
/// failed observation may be retained only for diagnostics.
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

    /// Pending accessibility notifications captured while semantic observation is active.
    let accessibilityNotifications = AccessibilityNotificationBus()

    // MARK: - Interface State

    var interfaceTree: InterfaceTree = .empty
    var latestObservation: InterfaceObservation = .empty
    var diagnosticObservation: InterfaceObservation?

    var currentLiveCapture: LiveCapture {
        latestObservation.liveCapture
    }

    /// Unit-test fixture for the next explicit viewport refresh. Production
    /// refreshes always parse UIKit; synthetic tests can install one observation as
    /// the current tree without retaining any live object strongly.
    var nextVisibleRefreshScreenForTesting: InterfaceObservation?

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

    /// Held rotor cursor — the single semantic selection while in rotor mode.
    /// Entering rotor mode on a host starts at index 0; subsequent steps
    /// reacquire live evidence for this value cursor. Any non-rotor action
    /// clears it (rotor mode exit).
    var rotorCursor: RotorCursor?

    struct RotorCursor {
        let hostHeistId: HeistId
        let rotorName: RotorName
        let generation: ObservationGeneration
        let selectionHeistId: HeistId
        let textRange: TextRangeReference?
    }

    /// Drop rotor mode. Called when any non-rotor interaction runs.
    func clearRotorCursor() {
        rotorCursor = nil
    }

    /// Last failed observation retained for reporting, never target resolution.
    var latestFailedSettleDiagnosticEvidence: InterfaceObservation? {
        diagnosticObservation
    }

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent observed capture. Proxy for call-site
    /// clarity: reads, matchers, scroll dispatch, and tab-bar geometry all need
    /// it without spelling out live-capture internals every time.
    var latestObservedLiveHierarchy: [AccessibilityHierarchy] {
        currentLiveCapture.hierarchy
    }

    /// Scrollable container paths paired with their backing UIScrollView from the
    /// visible live view. Unwraps the weak ref wrapper for call sites that need
    /// a live scroll view.
    var scrollableContainerViewsByPath: [TreePath: UIScrollView] {
        Dictionary(
            uniqueKeysWithValues: currentLiveCapture.scrollableContainerViewsByPath.compactMap { path, reference in
                reference.view.map { (path, $0) }
            }
        )
    }

    /// Elements retained in the interface tree, including explored off-viewport elements.
    var interfaceElementIDs: Set<HeistId> {
        ids(in: .interface)
    }

    /// Elements backed by the latest viewport observation.
    var viewportElementIDs: Set<HeistId> {
        ids(in: .viewport)
    }

    var interfaceElementCount: Int {
        interfaceTree.elementCount
    }

    func interfaceElement(heistId: HeistId) -> InterfaceTree.Element? {
        interfaceTree.findElement(heistId: heistId)
    }

    /// Latest observed capture payload for a viewport heistId.
    ///
    /// The parsed accessibility element, live handles, and reveal metadata are
    /// observational evidence only. For live entries, the newest parse owns
    /// viewport metadata; retained interface metadata must not override it.
    func liveInterfaceElement(heistId: HeistId) -> InterfaceTree.Element? {
        guard let liveEntry = currentLiveCapture.elementEntry(for: heistId),
              let observedEntry = latestObservation.tree.findElement(heistId: heistId)
        else { return nil }
        return InterfaceTree.Element(
            heistId: heistId,
            path: liveEntry.path,
            scrollMembership: observedEntry.scrollMembership,
            observedScrollContentActivationPoint: observedEntry.observedScrollContentActivationPoint,
            element: liveEntry.element
        )
    }

    /// Elements in matcher/diagnostic order.
    var orderedInterfaceElements: [InterfaceTree.Element] {
        interfaceTree.orderedElements
    }

    var interfaceHash: String {
        interfaceTree.interfaceHash
    }

    /// HeistId captured for the current viewport's first responder.
    var firstResponderHeistId: HeistId? {
        currentLiveCapture.firstResponderHeistId
    }

    /// Current screen name derived from the interface tree's viewport capture.
    var lastScreenName: String? {
        interfaceTree.name
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        interfaceTree.id
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
