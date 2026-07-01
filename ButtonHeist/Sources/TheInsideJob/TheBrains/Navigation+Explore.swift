#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Screen Exploration

extension Navigation {

    fileprivate func observeSemanticDiscovery() async -> Screen? {
        let exploration = await exploreScreen()
        return exploration.screen
    }

    func exploreScreen(
        target: ElementTarget? = nil,
        baseline: Screen? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil
    ) async -> ExploredScreen {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(
            baseline: baseline ?? stash.explorationBaseline(),
            maxScrollsPerContainer: maxScrollsPerContainer ?? ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: maxScrollsPerDiscovery ?? ScreenManifest.maxScrollsPerDiscovery
        )

        exploration.absorb(stash.refreshLiveCapture())

        if let target, hasVisibleTerminalExplorationResolution(target, in: exploration.screen) {
            exploration.manifest.pendingScrollPaths.removeAll()
            return exploration.finish(startTime: startTime)
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        if await scanPendingContainers(target: target, exploration: &exploration) {
            return exploration.finish(startTime: startTime)
        }

        return exploration.finish(startTime: startTime)
    }

    func hasTerminalExplorationResolution(_ target: ElementTarget, in screen: Screen) -> Bool {
        switch stash.resolveTarget(target, in: screen) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    func hasVisibleTerminalExplorationResolution(_ target: ElementTarget) -> Bool {
        hasTerminalExplorationResolution(target, in: stash.liveVisibleScreen.visibleOnly)
    }

    func hasVisibleTerminalExplorationResolution(_ target: ElementTarget, in screen: Screen) -> Bool {
        hasTerminalExplorationResolution(target, in: screen.visibleOnly)
    }
}

extension TheBrains {

    func startSemanticObservation() {
        semanticObservationIsActive = true
        stash.startPassiveSemanticObservation { [weak navigation] in
            guard let navigation else { return nil }
            return await navigation.observeSemanticDiscovery()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
