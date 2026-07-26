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
    /// Always starts fresh, because that is what building a graph means: the
    /// first page replaces whatever we knew and every page after it merges in.
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
        onObservation: ((Observation.SnapshotEvent) async -> ViewportExplorationDecision)? = nil,
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
        return await explorer.exploreViewports(exitPosition: exitPosition) { event in
            if let decision = await onObservation?(event), decision == .goalSatisfied {
                return .goalSatisfied
            }
            guard let target else { return .continue }
            return vault.hasVisibleTerminalResolution(target, in: event.snapshot.observation.tree)
                ? .goalSatisfied
                : .continue
        }
    }
}

extension Navigation {
    func settledExplorationPage(
        deadline: SemanticObservationDeadline?,
        discoveryCommitPolicy: DiscoveryCommitPolicy,
        notificationWindow: AccessibilityNotificationScopeLease? = nil,
        previousViewportHash: String? = nil
    ) async -> Observation.SnapshotEvent? {
        let afterViewportMovement = previousViewportHash != nil
        defer { notificationWindow?.cancel() }
        guard afterViewportMovement
                || (!Task.isCancelled && hasTimeRemaining(before: deadline))
        else { return nil }
        let timeoutMs = min(
            SemanticObservationTiming.viewportTransitionTimeoutMs,
            deadline.map { max(1, Int(($0.remainingSeconds() * 1_000).rounded(.up))) } ?? .max
        )
        let transitionDeadline = SemanticObservationDeadline(start: RuntimeElapsed.now, timeoutMs: timeoutMs)
        repeat {
            // A page is read on the tick, not after a loop agrees the tree
            // stopped: the hash comparison that used to gate this now happens in
            // the store, and the reading either moved the graph or produced the
            // stillness tick that says it did not.
            _ = await tripwire.waitForNextTick(
                timeout: transitionDeadline.remainingDuration(at: RuntimeElapsed.now),
                demand: .immediate
            )
            guard afterViewportMovement || !Task.isCancelled else { return nil }
            let transitionCanSettleAgain = transitionDeadline.remainingSeconds() * 1_000
                >= Double(SemanticObservationTiming.viewportTransitionMinimumBudgetMs)
            if let previousViewportHash,
               vault.latestObservation.tree.interfaceHash == previousViewportHash,
               transitionCanSettleAgain {
                continue
            }
            if let event = await vault.semanticObservationStream.commitSettledDiscoveryObservation(
                discoveryCommitPolicy: discoveryCommitPolicy,
                afterViewportMovement: afterViewportMovement,
                notificationBatch: notificationWindow?.capture()
            )?.event {
                return event
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
