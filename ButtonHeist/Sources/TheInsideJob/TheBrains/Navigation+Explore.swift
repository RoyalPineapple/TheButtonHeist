#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration

extension Navigation {

    fileprivate func observeSemanticDiscovery() async -> Screen? {
        let exploration = await exploreScreen()
        return exploration.screen
    }

    func exploreScreen(target: ElementTarget? = nil) async -> ExploredScreen {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(baseline: stash.explorationBaseline())

        exploration.absorb(stash.refreshLiveCapture())

        if let target, hasVisibleTerminalExplorationResolution(target) {
            return exploration.finish(startTime: startTime)
        }

        exploration.manifest.addPendingContainers(stash.latestObservedLiveHierarchy.scrollableContainers)
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
