#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - InterfaceObservation Exploration

extension Navigation {

    fileprivate func observeSemanticDiscovery() async -> ExploredScreen? {
        await exploreScreen()
    }

    func exploreScreen(
        target: ResolvedAccessibilityTarget? = nil,
        baseline: ExplorationBaseline? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil
    ) async -> ExploredScreen? {
        guard !Task.isCancelled else { return nil }
        let startTime = CACurrentMediaTime()
        guard let settledPage = await settledExplorationPage(),
              !Task.isCancelled else { return nil }
        var exploration = SemanticExploration(
            baseline: baseline ?? .interfaceMemory(stash.explorationBaseline()),
            maxScrollsPerContainer: maxScrollsPerContainer ?? ScreenManifest.maxScrollsPerContainer,
            maxScrollsPerDiscovery: maxScrollsPerDiscovery ?? ScreenManifest.maxScrollsPerDiscovery
        )

        exploration.absorb(settledPage)

        if let target, hasVisibleTerminalExplorationResolution(target, in: exploration.screen.tree) {
            exploration.manifest.clearPendingContainers()
            return exploration.finish(startTime: startTime)
        }

        exploration.addDiscoveredContainers(exploration.screen.orderedContainers.filter { $0.container.isScrollable })
        guard !Task.isCancelled else { return nil }
        let terminal = await scanPendingContainers(target: target, exploration: &exploration)
        guard !Task.isCancelled else { return nil }
        if terminal != nil {
            return exploration.finish(startTime: startTime)
        }

        return exploration.finish(startTime: startTime)
    }

    func hasTerminalExplorationResolution(_ target: ResolvedAccessibilityTarget, in tree: InterfaceTree) -> Bool {
        switch stash.resolveTarget(target, in: tree) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    func hasVisibleTerminalExplorationResolution(_ target: ResolvedAccessibilityTarget) -> Bool {
        hasTerminalExplorationResolution(target, in: stash.latestObservation.tree.viewportOnly)
    }

    func hasVisibleTerminalExplorationResolution(_ target: ResolvedAccessibilityTarget, in tree: InterfaceTree) -> Bool {
        hasTerminalExplorationResolution(target, in: tree.viewportOnly)
    }
}

extension Navigation {
    func settledExplorationPage() async -> InterfaceObservation? {
        let settle = await SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: SettleSession.defaultTimeoutMs
        ).run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: tripwire.tripwireSignal()
        )
        return InterfaceObservationProof.settled(settle, stash: stash)?.screen
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
