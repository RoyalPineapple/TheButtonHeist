#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import TheScore

// MARK: - Interface State

extension TheStash {

    struct SemanticInterfaceSnapshot {
        let interface: Interface
        let hash: String
    }

    /// Clear cached element data (used on suspend).
    func clearCache() {
        clearInterfaceForLifecycleReset()
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        clearInterfaceForLifecycleReset()
    }

    /// Clear stale interface state at a top-level heist boundary while leaving a
    /// queued synthetic visible refresh intact for in-process runtime tests.
    func clearInterfaceForHeistBootstrap() {
        let queuedVisibleRefresh = nextVisibleRefreshScreenForTesting
        clearInterfaceForLifecycleReset()
        nextVisibleRefreshScreenForTesting = queuedVisibleRefresh
    }

    /// Read the live accessibility tree and retain its live evidence.
    /// Parsing never promotes an unproven sample into targetable truth.
    /// Returns nil if no accessible windows exist (loading screen,
    /// app backgrounded, etc.).
    func parse() -> InterfaceObservation? {
        guard let screen = parsedInterfaceObservation() else { return nil }
        recordParsedObservedEvidence(from: screen)
        return screen
    }

    /// Refresh the latest live viewport evidence. The returned value remains the raw
    /// capture-local observation for geometry and exploration consumers.
    @discardableResult
    func refreshLiveCapture() -> InterfaceObservation? {
        if let visibleTree = nextVisibleRefreshScreenForTesting {
            recordParsedObservedEvidence(from: visibleTree)
            return visibleTree
        }
        return parse()
    }

    /// Produce one raw parser value for the settle runner without committing it.
    func semanticObservationForSettle() -> InterfaceObservation? {
        guard let observation = nextVisibleRefreshScreenForTesting ?? parsedInterfaceObservation() else {
            return nil
        }
        recordParsedObservedEvidence(from: observation)
        return observation
    }

    /// Produce one raw page observation for scroll exploration.
    func semanticPageForExploration() -> InterfaceObservation? {
        refreshLiveCapture()
    }

    /// The sole reducer from a parsed observation into durable graph truth.
    func reduceInterfaceGraph(
        with observation: InterfaceObservation,
        scope: SemanticObservationScope,
        continuity: ScreenContinuity,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
    ) -> InterfaceTree {
        if let queuedVisibleRefresh = nextVisibleRefreshScreenForTesting,
           queuedVisibleRefresh.interfaceHash != observation.interfaceHash {
            nextVisibleRefreshScreenForTesting = nil
        }
        switch scope {
        case .visible:
            interfaceTree = continuity.isReplacement
                ? observation.tree
                : interfaceTree.updatingViewport(with: observation)
        case .discovery:
            interfaceTree = continuity.isReplacement || discoveryCommitPolicy == .replaceInterface
                ? observation.tree
                : interfaceTree.merging(observation.tree)
        }
        finishCommit(observation: observation)
        return interfaceTree
    }

    func recordFailedSettleDiagnosticEvidence(_ screen: InterfaceObservation?) {
        diagnosticObservation = screen
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    func recordParsedObservedEvidence(_ screen: InterfaceObservation) {
        recordParsedObservedEvidence(from: screen)
    }

    func installScreenForTesting(_ screen: InterfaceObservation) {
        nextVisibleRefreshScreenForTesting = screen
        semanticObservationStream.commitVisibleObservationForTesting(screen)
    }

    func clearInstalledVisibleRefreshScreenForTesting() {
        nextVisibleRefreshScreenForTesting = nil
    }

    /// Starting value for page-by-page exploration. The tree's value-only
    /// viewport capture is the evidence that belongs to this committed state;
    /// a fresh parser read replaces it before exploration performs live work.
    func explorationBaseline() -> InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: interfaceTree)
        } catch {
            preconditionFailure("Exploration baseline failed validation: \(error)")
        }
    }

    /// Starting value for public interface discovery after a visible settle.
    ///
    /// Public reads should describe the current screen. Discovery-only memory
    /// from a prior screen can share generated container names with the current
    /// screen, so command-owned interface exploration starts from visible
    /// current-screen state and grows from there.
    func visibleExplorationBaseline(from screen: InterfaceObservation) -> InterfaceObservation {
        screen.viewportOnly
    }

    /// Starting value for action-owned target discovery.
    ///
    /// The canonical continuity decision is applied when observations commit,
    /// so retained discovery memory already belongs to the current generation.
    func actionDiscoveryBaseline() -> InterfaceObservation {
        explorationBaseline()
    }

    func firstResponderInterfaceElement() -> InterfaceTree.Element? {
        guard let heistId = firstResponderHeistId else { return nil }
        return treeElement(heistId: heistId, in: .interface)
    }

    /// Projection of the interface tree plus Button Heist
    /// annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the committed interface, not an arbitrary tree.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: interfaceTree, timestamp: timestamp)
    }

    /// Interface projection for command-owned discovery.
    ///
    /// Discovery retains off-viewport elements in semantic memory while the
    /// latest parser hierarchy remains viewport-local. This projection returns
    /// the live hierarchy plus discovered scroll-container content.
    func discoveryInterface(timestamp: Date = Date()) -> Interface {
        WireConversion.toDiscoveryInterface(from: interfaceTree, timestamp: timestamp)
    }

    /// Semantic projection used for traces and deltas.
    ///
    /// Unlike `interface()`, this reads the committed semantic state produced
    /// by exploration, so off-viewport targetable elements participate in
    /// post-action deltas.
    func semanticInterface(timestamp: Date = Date()) -> Interface {
        WireConversion.toSemanticInterface(from: interfaceTree, timestamp: timestamp)
    }

    /// Single-build semantic variant for state capture and delta projection.
    func semanticInterfaceWithHash(timestamp: Date = Date()) -> SemanticInterfaceSnapshot {
        let interface = semanticInterface(timestamp: timestamp)
        return SemanticInterfaceSnapshot(interface: interface, hash: AccessibilityTrace.Capture.hash(interface))
    }

    func semanticInterfaceWithHash(
        for screen: InterfaceObservation,
        timestamp: Date = Date()
    ) -> SemanticInterfaceSnapshot {
        let interface = WireConversion.toSemanticInterface(from: screen.tree, timestamp: timestamp)
        return SemanticInterfaceSnapshot(interface: interface, hash: AccessibilityTrace.Capture.hash(interface))
    }

    func discoveryInterfaceWithHash(
        for screen: InterfaceObservation,
        timestamp: Date = Date()
    ) -> SemanticInterfaceSnapshot {
        let interface = WireConversion.toDiscoveryInterface(from: screen.tree, timestamp: timestamp)
        return SemanticInterfaceSnapshot(interface: interface, hash: AccessibilityTrace.Capture.hash(interface))
    }

    private func clearInterfaceForLifecycleReset() {
        latestObservation = .empty
        diagnosticObservation = nil
        interfaceTree = .empty
        nextVisibleRefreshScreenForTesting = nil
        semanticObservationStream.requireScreenReplacement()
    }

    private func recordParsedObservedEvidence(from screen: InterfaceObservation) {
        latestObservation = screen
    }

    private func parsedInterfaceObservation() -> InterfaceObservation? {
        burglar.parse().map(TheBurglar.buildObservation(from:))
    }

    private func finishCommit(observation: InterfaceObservation) {
        recordParsedObservedEvidence(from: observation)
        diagnosticObservation = nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
