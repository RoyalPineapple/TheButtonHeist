#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration

extension Navigation {

    func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        let exploration = await exploreScreen(target: target)
        stash.commitExploredScreen(exploration.screen)
        return exploration.manifest
    }

    func exploreScreen(target: ElementTarget? = nil) async -> ExploredScreen {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(baseline: stash.explorationBaseline())

        exploration.absorb(stash.recordVisibleSemanticObservation())

        if let target, hasTerminalExplorationResolution(target) {
            return exploration.finish(startTime: startTime)
        }

        exploration.manifest.addPendingContainers(stash.currentHierarchy.scrollableContainers)
        if await scanPendingContainers(target: target, exploration: &exploration) {
            return exploration.finish(startTime: startTime)
        }

        return exploration.finish(startTime: startTime)
    }

    func hasTerminalExplorationResolution(_ target: ElementTarget) -> Bool {
        switch stash.resolveTarget(target) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
