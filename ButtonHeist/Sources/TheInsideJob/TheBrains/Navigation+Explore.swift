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
        onObservation: ((SettledObservationEvent) -> ViewportExplorationDecision)? = nil,
    ) async -> InterfaceExplorationResult? {
        let explorer = ViewportExplorer(
            navigation: self,
            exploration: SemanticExploration(
                baseline: baseline ?? .interfaceMemory(vault.explorationBaseline()),
                deadline: deadline,
                maxScrollsPerContainer: maxScrollsPerContainer ?? InterfaceExplorationProgress.maxScrollsPerContainer,
                maxScrollsPerDiscovery: maxScrollsPerDiscovery ?? InterfaceExplorationProgress.maxScrollsPerDiscovery
            ),
            searchOrder: searchOrder,
        )
        return await explorer.exploreViewports(exitPosition: exitPosition) { event in
            if let decision = onObservation?(event), decision == .goalSatisfied {
                return .goalSatisfied
            }
            guard let target else { return .continue }
            return vault.hasVisibleTerminalResolution(target, in: event.settledObservation.observation.tree)
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
    ) async -> SettledObservationEvent? {
        let afterViewportMovement = previousViewportHash != nil
        defer { notificationWindow?.cancel() }
        guard !Task.isCancelled,
              afterViewportMovement || hasTimeRemaining(before: deadline) else { return nil }
        let timeoutMs = min(
            SettleSession.viewportTransitionTimeoutMs,
            deadline.map { max(1, Int(($0.remainingSeconds() * 1_000).rounded(.up))) } ?? .max
        )
        let transitionDeadline = SemanticObservationDeadline(start: CFAbsoluteTimeGetCurrent(), timeoutMs: timeoutMs)
        repeat {
            let settleTimeoutMs = max(1, Int((transitionDeadline.remainingSeconds() * 1_000).rounded(.up)))
            let settle = await SettleSession.viewportTransition(
                vault: vault,
                tripwire: tripwire,
                timeoutMs: settleTimeoutMs
            ).run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: tripwire.tripwireSignal()
            )
            guard !Task.isCancelled else { return nil }
            let transitionCanSettleAgain = transitionDeadline.remainingSeconds() * 1_000
                >= Double(SettleSession.viewportTransitionMinimumBudgetMs)
            if let previousViewportHash,
               settle.finalObservation?.observation.tree.interfaceHash == previousViewportHash,
               transitionCanSettleAgain {
                continue
            }
            if let event = vault.semanticObservationStream.commitSettledDiscoveryObservation(
                settle,
                discoveryCommitPolicy: discoveryCommitPolicy,
                afterViewportMovement: afterViewportMovement,
                notificationBatch: notificationWindow?.capture()
            ) {
                return event
            }
        } while transitionDeadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent())
            && (afterViewportMovement || hasTimeRemaining(before: deadline))
        return nil
    }

    private func hasTimeRemaining(before deadline: SemanticObservationDeadline?) -> Bool {
        deadline?.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) ?? true
    }
}

extension TheBrains {

    func startSemanticObservation() {
        vault.semanticObservationStream.start { [weak self] in
            guard let self else { return nil }
            return await self.executeSemanticDiscovery()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
