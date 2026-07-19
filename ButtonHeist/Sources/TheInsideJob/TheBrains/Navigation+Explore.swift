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
            if let decision = onObservation?(event), decision == .finish {
                return .finish
            }
            guard let target else { return .continue }
            return vault.hasVisibleTerminalResolution(target, in: event.settledObservation.observation.tree)
                ? .finish
                : .continue
        }
    }
}

extension Navigation {
    func settledExplorationPage(
        deadline: SemanticObservationDeadline?,
        discoveryCommitPolicy: DiscoveryCommitPolicy,
        notificationWindow: AccessibilityNotificationScopeLease? = nil,
        requiredAfterMovement: Bool = false
    ) async -> SettledObservationEvent? {
        defer { notificationWindow?.cancel() }
        guard !Task.isCancelled,
              requiredAfterMovement || hasTimeRemaining(before: deadline) else { return nil }
        let timeoutMs: Int
        switch deadline {
        case nil:
            timeoutMs = SettleSession.viewportTransitionTimeoutMs
        case .some(let deadline):
            timeoutMs = min(
                SettleSession.viewportTransitionTimeoutMs,
                max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
            )
        }
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
            if let event = vault.semanticObservationStream.commitSettledDiscoveryObservation(
                settle,
                discoveryCommitPolicy: discoveryCommitPolicy,
                afterViewportMovement: requiredAfterMovement,
                notificationBatch: notificationWindow?.capture()
            ) {
                return event
            }
        } while transitionDeadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent())
            && (requiredAfterMovement || hasTimeRemaining(before: deadline))
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
