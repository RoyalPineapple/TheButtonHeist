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

    /// Read the live accessibility tree and produce one observed capture value.
    /// Every successful parse refreshes latest observed capture and visible
    /// live view, but it never updates the interface tree.
    /// Returns nil if no accessible windows exist (loading screen,
    /// app backgrounded, etc.).
    func parse() -> InterfaceObservation? {
        guard let result = burglar.parse() else { return nil }
        let screen = TheBurglar.buildObservation(from: result)
        recordParsedObservedEvidence(from: screen)
        return screen
    }

    /// Parse and refresh the latest observation. The returned viewport may be
    /// used by exploration or diagnostics, but
    /// this method never updates the interface tree.
    @discardableResult
    func refreshLiveCapture() -> InterfaceObservation? {
        if let visibleTree = nextVisibleRefreshScreenForTesting {
            recordParsedObservedEvidence(from: visibleTree)
            return visibleTree
        }
        return parse()
    }

    /// Produce one visible observation for the settle loop without committing
    /// it yet. Successful parses refresh latest observed capture and visible
    /// live view; the observation stream alone promotes a proven final screen
    /// into the interface tree.
    func semanticObservationForSettle() -> InterfaceObservation? {
        refreshLiveCapture()
    }

    /// Produce one page observation for scroll exploration. Exploration owns a
    /// local semantic union until it finishes; the observation stream commits
    /// only the final explored tree.
    func semanticPageForExploration() -> InterfaceObservation? {
        refreshLiveCapture()
    }

    @discardableResult
    func commitVisibleInterface(
        _ screen: InterfaceObservation,
        classification: ScreenClassifier.Classification
    ) -> InterfaceObservation {
        let committedScreen = replacementObservation(
            from: screen,
            classification: classification
        )
        if let queuedVisibleRefresh = nextVisibleRefreshScreenForTesting,
           queuedVisibleRefresh.interfaceHash != committedScreen.interfaceHash {
            nextVisibleRefreshScreenForTesting = nil
        }
        interfaceTree = classification.isScreenReplacement
            ? committedScreen.tree
            : interfaceTree.updatingViewport(with: committedScreen)
        return finishCommit(observation: committedScreen)
    }

    @discardableResult
    func commitDiscoveryInterface(_ screen: InterfaceObservation) -> InterfaceObservation {
        interfaceTree = screen.tree
        return finishCommit(observation: screen)
    }

    func recordFailedSettleDiagnosticEvidence(_ screen: InterfaceObservation?) {
        diagnosticObservation = screen
        if let screen {
            latestObservation = screen
        }
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    func recordParsedObservedEvidence(_ screen: InterfaceObservation) {
        recordParsedObservedEvidence(from: screen)
    }

    func installScreenForTesting(_ screen: InterfaceObservation) {
        nextVisibleRefreshScreenForTesting = screen
        _ = semanticObservationStream.commitSettledVisibleObservation(.testing(screen))
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
    /// Target inflation should retain current-screen discovery memory so
    /// retained off-viewport elements can fail with the right reveal diagnostic.
    /// After navigation, though, old discovery-only rows can look actionable on
    /// the new screen. Use the full committed baseline only while its viewport
    /// surface still pairs with the latest observation.
    func actionDiscoveryBaseline() -> InterfaceObservation {
        let currentVisible = latestObservation.viewportOnly
        let settledBaseline = explorationBaseline()
        guard settledBaseline.visibleSurfacePairs(with: currentVisible) else {
            return visibleExplorationBaseline(from: currentVisible)
        }
        return settledBaseline
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
        semanticObservationStream.clearSettledObservationHistory()
    }

    private func recordParsedObservedEvidence(from screen: InterfaceObservation) {
        latestObservation = screen
    }

    private func replacementObservation(
        from screen: InterfaceObservation,
        classification: ScreenClassifier.Classification
    ) -> InterfaceObservation {
        switch classification {
        case .inferredScreenChange(.navigationMarkerChanged),
             .inferredScreenChange(.modalBoundaryChanged):
            return screen.removingElements(withIds: interfaceTree.viewportElementIDs)
        case .sameGeneration,
             .screenChangedNotification,
             .inferredScreenChange(.selectedTabChanged),
             .inferredScreenChange(.primaryHeaderChanged),
             .inferredScreenChange(.rootShapeChanged):
            return screen
        }
    }

    private var currentInterfaceObservation: InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: interfaceTree)
        } catch {
            preconditionFailure("Committed interface observation failed validation: \(error)")
        }
    }

    private func finishCommit(observation: InterfaceObservation) -> InterfaceObservation {
        recordParsedObservedEvidence(from: observation)
        diagnosticObservation = nil
        return currentInterfaceObservation
    }
}

private extension InterfaceObservation {
    @MainActor
    func visibleSurfacePairs(with currentVisible: InterfaceObservation) -> Bool {
        guard !currentVisible.viewportElementIDs.isEmpty else {
            return !elementIDs.isEmpty
        }
        if let baselineId = id,
           let currentId = currentVisible.id,
           baselineId != currentId {
            return false
        }
        if !viewportElementIDs.isDisjoint(with: currentVisible.viewportElementIDs) {
            return true
        }
        if let baselineName = name,
           let currentName = currentVisible.name,
           baselineName == currentName {
            return true
        }
        return visibleElementsPair(with: currentVisible)
    }

    @MainActor
    func visibleElementsPair(with currentVisible: InterfaceObservation) -> Bool {
        let previous = viewportElementIDs
            .compactMap { tree.elements[$0]?.element }
        let current = currentVisible.viewportElementIDs
            .compactMap { currentVisible.tree.elements[$0]?.element }
        return previous.sharesElementPairing(with: current)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
