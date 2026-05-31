#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

/// Ordered activation recovery policy for `activate`.
struct ActivationPolicy {

    enum RefreshResult {
        case resolved(
            screenElement: TheStash.ScreenElement,
            liveTarget: TheStash.LiveActionTarget
        )
        case failure(TheSafecracker.InteractionResult)
    }

    var activate: @MainActor (TheStash.LiveActionTarget) -> TheStash.ActivateOutcome
    var refreshAndResolve: @MainActor () async -> RefreshResult
    var syntheticTap: @MainActor (CGPoint) async -> Bool

    @MainActor
    func apply(to liveTarget: TheStash.LiveActionTarget) async -> TheSafecracker.InteractionResult {
        let initialOutcome = activate(liveTarget)
        if initialOutcome == .success {
            return .success(method: .activate)
        }

        let screenElement: TheStash.ScreenElement
        let retryLiveTarget: TheStash.LiveActionTarget
        switch await refreshAndResolve() {
        case .resolved(let resolvedElement, let liveTarget):
            screenElement = resolvedElement
            retryLiveTarget = liveTarget
        case .failure(let result):
            return result
        }

        let retryOutcome = activate(retryLiveTarget)
        if retryOutcome == .success {
            return .success(method: .activate)
        }

        let tapPoint = retryLiveTarget.activationPoint
        if await syntheticTap(tapPoint) {
            return .success(method: .syntheticTap)
        }

        return .failure(
            .activate,
            message: activationFailureMessage(screenElement: screenElement, activateOutcome: retryOutcome)
        )
    }

    private func activationFailureMessage(
        screenElement: TheStash.ScreenElement,
        activateOutcome: TheStash.ActivateOutcome
    ) -> String {
        let observed: String
        switch activateOutcome {
        case .success:
            observed = "unexpected success state"
        case .objectDeallocated:
            observed = "live target deallocated after semantic refresh"
        case .refused:
            observed = "accessibilityActivate returned false after semantic refresh"
        }
        return "activate failed: \(observed); synthetic tap at fresh activation point also failed for " +
            ActionCapabilityDiagnostic.formatElement(screenElement)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
