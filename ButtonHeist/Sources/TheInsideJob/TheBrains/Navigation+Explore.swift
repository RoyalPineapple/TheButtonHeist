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
        afterViewportMovement: Bool = false
    ) async -> Observation.SnapshotEvent? {
        defer { notificationWindow?.cancel() }
        guard afterViewportMovement
                || (!Task.isCancelled && hasTimeRemaining(before: deadline))
        else { return nil }
        let timeout = min(
            SemanticObservationTiming.defaultTimeout,
            deadline?.remainingDuration() ?? .seconds(Int.max)
        )
        let transitionDeadline = SemanticObservationDeadline(start: RuntimeElapsed.now, timeout: timeout)
        repeat {
            // The tick only says time passed. The page still has to be re-read
            // afterwards, or every iteration inspects the same observation the
            // last one did and a scroll that is still settling looks like a
            // scroll that never happened.
            _ = await tripwire.waitForNextTick(
                timeout: transitionDeadline.remainingDuration(at: RuntimeElapsed.now),
                demand: .immediate
            )
            vault.refreshLiveCapture()
            guard afterViewportMovement || !Task.isCancelled else { return nil }
            // This loop only waits for the caller's one dispatched scroll to
            // land, so a page that still looks unmoved is mid-flight, not a
            // failed scroll. Whether the reading counts as a change is the
            // store's question, answered on commit.
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
