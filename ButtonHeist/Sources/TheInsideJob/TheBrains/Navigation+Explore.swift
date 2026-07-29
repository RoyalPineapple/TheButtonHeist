#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension Navigation {
    /// Walk the whole screen and return the graph.
    ///
    /// No goal and no early exit: every scrollable container is scanned until
    /// the knobs or the deadline stop it, and what comes back is everything
    /// found along the way. Each page commits into the store as it is read, so
    /// the result is the accumulation, not a tree assembled at the end.
    ///
    /// Always starts fresh: the first page replaces whatever we knew and every
    /// page after it merges in.
    ///
    /// Searching is the other job — `exploreScreen(target:)` stops the moment
    /// it finds one element, keeps interface memory, and deliberately does not
    /// produce a full graph.
    func fullGraph(
        deadline: SemanticObservationDeadline? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil
    ) async -> InterfaceExplorationResult? {
        await exploreScreen(
            startingFresh: true,
            exitPosition: .origin,
            deadline: deadline,
            maxScrollsPerContainer: maxScrollsPerContainer,
            maxScrollsPerDiscovery: maxScrollsPerDiscovery
        )
    }

    func exploreScreen(
        target: ResolvedAccessibilityTarget? = nil,
        startingFresh: Bool = false,
        exitPosition: ViewportExitPosition = .origin,
        searchOrder: ViewportSearchOrder = .forwardFirst,
        deadline: SemanticObservationDeadline? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil,
        onObservation: ((TheVault.State.Current) async -> ViewportExplorationDecision)? = nil,
    ) async -> InterfaceExplorationResult? {
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                startingFresh: startingFresh,
                deadline: deadline,
                maxScrollsPerContainer: maxScrollsPerContainer ?? InterfaceExplorationProgress.maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery ?? InterfaceExplorationProgress.maxScrollsPerDiscovery
            ),
            searchOrder: searchOrder,
        )
        return await explorer.exploreViewports(exitPosition: exitPosition) { current in
            if let decision = await onObservation?(current), decision == .goalSatisfied {
                return .goalSatisfied
            }
            guard let target else { return .continue }
            return vault.hasVisibleTerminalResolution(target, in: vault.latestObservation.tree)
                ? .goalSatisfied
                : .continue
        }
    }
}

extension Navigation {
    func settledExplorationPage(
        deadline: SemanticObservationDeadline?,
        discoveryCommitPolicy: DiscoveryCommitPolicy,
        afterViewportMovement: Bool = false
    ) async -> TheVault.State.Current? {
        guard afterViewportMovement
                || (!Task.isCancelled && hasTimeRemaining(before: deadline))
        else { return nil }
        let timeout = min(
            SemanticObservationTiming.defaultTimeout,
            deadline?.remainingDuration() ?? .seconds(Int.max)
        )
        let transitionDeadline = SemanticObservationDeadline(start: RuntimeElapsed.now, timeout: timeout)
        repeat {
            guard afterViewportMovement || !Task.isCancelled else { return nil }
            if discoveryCommitPolicy == .replaceInterface {
                await vault.semanticObservationStream.discardCurrentObservation()
            }
            let remaining = min(
                transitionDeadline.remainingSeconds(),
                deadline?.remainingSeconds() ?? .greatestFiniteMagnitude
            )
            if case .committed(let current) =
                await vault.semanticObservationStream.refreshedVisibleObservation(timeout: remaining) {
                return current
            }
        } while transitionDeadline.hasTimeRemaining(at: RuntimeElapsed.now)
            && (afterViewportMovement || hasTimeRemaining(before: deadline))
        return nil
    }

    private func hasTimeRemaining(before deadline: SemanticObservationDeadline?) -> Bool {
        deadline?.hasTimeRemaining(at: RuntimeElapsed.now) ?? true
    }
}

extension TheBrains {

    func startSemanticObservation() async {
        await vault.semanticObservationStream.start { [weak self] in
            guard let self else { return nil }
            return await self.executeSemanticDiscovery()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
