#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration

extension Navigation {

    fileprivate func observeSemanticDiscovery() async {
        _ = await exploreAndPrune()
    }

    private func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        let exploration = await exploreScreen(target: target)
        stash.commitExploredSettledScreen(exploration.screen)
        return exploration.manifest
    }

    func exploreScreen(target: ElementTarget? = nil) async -> ExploredScreen {
        let startTime = CACurrentMediaTime()
        var exploration = SemanticExploration(baseline: stash.explorationBaseline())

        exploration.absorb(stash.refreshLiveCapture())

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

extension TheBrains {

    func startSemanticObservation() {
        semanticObservationIsActive = true
        stash.startPassiveSemanticObservation { [weak navigation] in
            guard let navigation else { return }
            await navigation.observeSemanticDiscovery()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
