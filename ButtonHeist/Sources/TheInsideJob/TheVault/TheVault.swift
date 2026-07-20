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
final class TheVault {

    typealias VisibleObservationSource = @MainActor (TheVault) -> InterfaceObservation?

    init(
        tripwire: TheTripwire,
        visibleObservationSource: @escaping VisibleObservationSource = TheVault.captureVisibleObservation
    ) {
        self.tripwire = tripwire
        self.visibleObservationSource = visibleObservationSource
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// Parser used only while capturing a live accessibility hierarchy.
    let hierarchyParser = AccessibilityHierarchyParser()

    /// Pending accessibility notifications captured while semantic observation is active.
    let accessibilityNotifications = AccessibilityNotificationBus()

    /// The only source used for explicit viewport refreshes. Production parses
    /// UIKit; tests may replace the source only while constructing the vault.
    private let visibleObservationSource: VisibleObservationSource

    // MARK: - Interface State

    var interfaceTree: InterfaceTree {
        semanticObservationStream.observationStore.interfaceTree
    }
    var latestObservation: InterfaceObservation = .empty
    var latestFailedSettleDiagnosticEvidence: InterfaceObservation?

    var currentLiveCapture: LiveCapture {
        latestObservation.liveCapture
    }

    // MARK: - Observation Scheduling

    lazy var semanticObservationStream = SemanticObservationStream(vault: self, tripwire: tripwire)

    // MARK: - Interaction Cursor State

    /// Held rotor cursor — the single semantic selection while in rotor mode.
    /// Entering rotor mode on a host starts at index 0; subsequent steps
    /// reacquire live evidence for this value cursor. Any non-rotor action
    /// clears it (rotor mode exit).
    var rotorCursor: RotorCursor?

    struct RotorCursor {
        let hostHeistId: HeistId
        let rotorName: RotorName
        let generation: ScreenGeneration
        let selectionHeistId: HeistId
        let textRange: TextRangeReference?
    }

    /// Drop rotor mode. Called when any non-rotor interaction runs.
    func clearRotorCursor() {
        rotorCursor = nil
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
    /// Snapshot identity proves the element belongs to the latest viewport;
    /// `InterfaceTree` owns its semantic value and reveal metadata.
    func liveInterfaceElement(heistId: HeistId) -> InterfaceTree.Element? {
        guard currentLiveCapture.contains(heistId: heistId) else { return nil }
        return latestObservation.tree.findElement(heistId: heistId)
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

    static func captureVisibleObservation(from vault: TheVault) -> InterfaceObservation? {
        vault.capture().flatMap { try? admitObservation(from: $0) }
    }

    func captureVisibleObservation() -> InterfaceObservation? {
        visibleObservationSource(self)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
