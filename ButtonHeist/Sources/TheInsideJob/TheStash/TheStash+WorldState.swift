#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import TheScore

// MARK: - World State Facade

extension TheStash {

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

    /// Read the live accessibility tree and produce one observed capture value.
    /// Every successful parse refreshes latest observed capture and visible
    /// live view, but it never promotes settled world.
    /// Returns nil if no accessible windows exist (loading screen,
    /// app backgrounded, etc.).
    func parse() -> Screen? {
        guard let result = burglar.parse() else { return nil }
        let screen = TheBurglar.buildScreen(from: result)
        recordParsedObservedEvidence(from: screen)
        return screen
    }

    /// Parse and refresh latest observed capture and visible live view. The
    /// returned visible screen may be used by exploration or diagnostics, but
    /// this method never updates settled world.
    @discardableResult
    func refreshLiveCapture() -> Screen? {
        if let visibleTree = nextVisibleRefreshScreenForTesting {
            recordParsedObservedEvidence(from: visibleTree)
            return visibleTree
        }
        return parse()
    }

    /// Parse the current viewport and commit it as the current visible tree.
    /// Use this for ordinary observation, where the app may have navigated and
    /// stale offscreen entries should not be blindly preserved.
    @discardableResult
    func refreshCurrentVisibleTree() -> Screen? {
        if let visibleTree = nextVisibleRefreshScreenForTesting {
            nextVisibleRefreshScreenForTesting = nil
            return semanticObservationStream
                .commitSettledVisibleObservation(visibleTree)
                .observation
                .screen
        }
        guard let visibleTree = parse() else { return nil }
        return semanticObservationStream
            .commitSettledVisibleObservation(visibleTree)
            .observation
            .screen
    }

    /// Parse after viewport movement and fold the visible page into the
    /// settled semantic tree. Scrolling changes what is visible, not which
    /// screen we are on, so the tree should grow from every observed page.
    @discardableResult
    func refreshTreeAfterViewportMove() -> Screen? {
        guard let visiblePage = parse() else { return nil }
        let updatedTree = settledSemanticScreen.merging(visiblePage)
        return semanticObservationStream
            .commitSettledDiscoveryObservation(updatedTree)
            .observation
            .screen
    }

    /// Produce one visible observation for the settle loop without committing
    /// it yet. Successful parses refresh latest observed capture and visible
    /// live view; the observation stream alone promotes a proven final screen
    /// to settled world.
    func semanticObservationForSettle() -> Screen? {
        parse()
    }

    /// Produce one page observation for scroll exploration. Exploration owns a
    /// local semantic union until it finishes; the observation stream commits
    /// only the final explored screen as settled discovery world.
    func semanticPageForExploration() -> Screen? {
        parse()
    }

    @discardableResult
    func commitSettledVisibleWorld(_ screen: Screen) -> Screen {
        commitSettledWorld(worldStore.commitVisible(screen))
    }

    @discardableResult
    func commitSettledDiscoveryWorld(_ screen: Screen) -> Screen {
        commitSettledWorld(worldStore.commitDiscovery(screen))
    }

    func recordFailedSettleDiagnosticEvidence(_ screen: Screen?) {
        observedState.recordFailedSettleDiagnosticEvidence(screen)
        if let screen {
            liveLookup.record(screen)
        }
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    func recordParsedObservedEvidence(_ screen: Screen) {
        recordParsedObservedEvidence(from: screen)
    }

    func installScreenForTesting(_ screen: Screen) {
        nextVisibleRefreshScreenForTesting = screen
        _ = semanticObservationStream.commitSettledVisibleObservation(screen)
    }

    func clearInstalledVisibleRefreshScreenForTesting() {
        nextVisibleRefreshScreenForTesting = nil
    }

    /// Starting value for page-by-page exploration. Exploration carries a local
    /// Screen union and hands the final observation back to the stream.
    func explorationBaseline() -> Screen {
        settledSemanticScreen
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

    /// Semantic projection of the settled parser hierarchy plus Button Heist
    /// annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the interface of the settled screen, not an arbitrary one.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: settledSemanticScreen, timestamp: timestamp)
    }

    /// Semantic projection used for traces and deltas.
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

    private func clearWorldForLifecycleReset() {
        observedState.reset()
        liveLookup.reset()
        worldStore.reset()
        nextVisibleRefreshScreenForTesting = nil
        semanticObservationStream.clearSettledObservationHistory()
    }

    private func recordParsedObservedEvidence(from screen: Screen) {
        observedState.record(screen)
        liveLookup.record(screen)
    }

    private func commitSettledWorld(_ result: WorldStore.CommitResult) -> Screen {
        recordParsedObservedEvidence(from: result.observedEvidence)
        observedState.clearFailedSettleDiagnosticEvidence()
        return result.settledScreen
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
