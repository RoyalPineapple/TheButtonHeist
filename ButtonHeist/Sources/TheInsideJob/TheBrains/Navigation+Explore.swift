#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension Navigation {
    func exploreScreen(
        target: ResolvedAccessibilityTarget? = nil,
        baseline: ExplorationBaseline? = nil,
        exitPosition: ViewportExitPosition = .origin,
        searchOrder: ViewportSearchOrder = .forwardFirst,
        deadline: SemanticObservationDeadline? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil,
        onObservation: ((SettledSemanticObservationEvent) -> ViewportExplorationDecision)? = nil,
    ) async -> ExploredScreen? {
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                baseline: baseline ?? .interfaceMemory(stash.explorationBaseline()),
                deadline: deadline,
                maxScrollsPerContainer: maxScrollsPerContainer ?? ScreenManifest.maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery ?? ScreenManifest.maxScrollsPerDiscovery
            ),
            searchOrder: searchOrder,
        )
        return await explorer.exploreViewports(exitPosition: exitPosition) { event in
            if let decision = onObservation?(event), decision == .finish {
                return .finish
            }
            guard let target else { return .continue }
            return hasVisibleTerminalExplorationResolution(target, in: event.observation.screen.tree)
                ? .finish
                : .continue
        }
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
    func settledExplorationPage(
        deadline: SemanticObservationDeadline?,
        discoveryCommitPolicy: DiscoveryCommitPolicy,
        notificationWindow: AccessibilityNotificationActionWindow? = nil,
        requiredAfterMovement: Bool = false
    ) async -> SettledSemanticObservationEvent? {
        defer { notificationWindow?.cancel() }
        guard requiredAfterMovement || (!Task.isCancelled && hasTimeRemaining(before: deadline)) else {
            return nil
        }
        let timeoutMs: Int
        switch (deadline, requiredAfterMovement) {
        case (_, true), (nil, false):
            timeoutMs = SettleSession.viewportTransitionTimeoutMs
        case (.some(let deadline), false):
            timeoutMs = min(
                SettleSession.viewportTransitionTimeoutMs,
                max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
            )
        }
        let settle = await SettleSession.viewportTransition(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: timeoutMs
        ).run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: tripwire.tripwireSignal()
        )
        guard requiredAfterMovement || (!Task.isCancelled && hasTimeRemaining(before: deadline)) else {
            return nil
        }
        let proof = requiredAfterMovement
            ? InterfaceObservationProof.settledAfterViewportMovement(
                settle,
                stash: stash,
                discoveryCommitPolicy: discoveryCommitPolicy
            )
            : InterfaceObservationProof.settled(
                settle,
                stash: stash,
                discoveryCommitPolicy: discoveryCommitPolicy
            )
        guard let proof else { return nil }
        return stash.semanticObservationStream.commitSettledDiscoveryObservation(
            proof,
            notificationBatch: notificationWindow?.capture()
        )
    }

    private func hasTimeRemaining(before deadline: SemanticObservationDeadline?) -> Bool {
        deadline?.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ?? true
    }
}

extension TheBrains {

    func startSemanticObservation() {
        semanticObservationIsActive = true
        stash.startPassiveSemanticObservation { [weak self] in
            guard let self else { return nil }
            return await self.executeSemanticDiscovery()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
