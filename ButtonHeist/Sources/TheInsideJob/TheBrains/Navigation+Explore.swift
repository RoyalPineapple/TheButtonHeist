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

        exploration.absorb(stash.refresh())

        if let target, hasTerminalExplorationResolution(target) {
            return exploration.finish(startTime: startTime)
        }

        exploration.manifest.addPendingContainers(stash.currentHierarchy.scrollableContainers)
        while !exploration.manifest.pendingContainers.isEmpty {
            let batch = sortedPendingContainers(in: exploration)

            for container in batch {
                guard let containerExploration = prepareContainerExploration(for: container) else {
                    exploration.markExplored(container)
                    continue
                }
                let found = await exploreContainer(
                    containerExploration,
                    target: target,
                    exploration: &exploration
                )
                if found {
                    return exploration.finish(startTime: startTime)
                }
            }
        }

        return exploration.finish(startTime: startTime)
    }

    private func exploreContainer(
        _ containerExploration: ContainerExploration,
        target: ElementTarget?,
        exploration: inout SemanticExploration
    ) async -> Bool {
        let savedVisualOrigin = containerExploration.savedVisualOrigin
        await moveToLeadingEdge(containerExploration, exploration: &exploration)

        var scan = preparePageScan(in: containerExploration)
        let foundTarget = await scanForwardPages(
            containerExploration,
            target: target,
            scan: &scan,
            exploration: &exploration
        )

        await restoreContainerPosition(
            containerExploration,
            savedVisualOrigin: savedVisualOrigin,
            exploration: &exploration
        )
        exploration.markExplored(containerExploration.container)

        guard !foundTarget else { return true }
        discoverNewContainers(in: &exploration)
        return false
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
