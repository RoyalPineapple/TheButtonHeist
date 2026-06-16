#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

/// Ordered activation delivery pipeline for `activate`.
///
/// ButtonHeist treats accessibility as the interaction contract. `activate`
/// first asks UIKit to perform the element's primary accessibility activation
/// with `accessibilityActivate()`. When UIKit declines/defaults, ButtonHeist
/// still delivers the same `activate` command by dispatching at the element's
/// fresh accessibility activation point after semantic resolution, reveal, and
/// live geometry acquisition.
struct ActivationPolicy {

    enum RefreshResult {
        case resolved(
            screenElement: TheStash.ScreenElement,
            liveTarget: TheStash.LiveActionTarget
        )
        case failure(TheSafecracker.InteractionResult)
    }

    var accessibilityActivate: @MainActor (TheStash.LiveActionTarget) -> AccessibilityActionDispatcher.ActivateOutcome
    var refreshAndResolve: @MainActor () async -> RefreshResult
    var activationPointDispatch: @MainActor (CGPoint) async -> Bool

    @MainActor
    func apply(to liveTarget: TheStash.LiveActionTarget) async -> TheSafecracker.InteractionResult {
        let initialOutcome = accessibilityActivate(liveTarget)
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

        let retryOutcome = accessibilityActivate(retryLiveTarget)
        if retryOutcome == .success {
            return .success(method: .activate)
        }

        let activationPoint = retryLiveTarget.activationPoint
        if await activationPointDispatch(activationPoint) {
            return .success(method: .activate)
        }

        return .failure(
            .activate,
            message: activationFailureMessage(screenElement: screenElement, activateOutcome: retryOutcome)
        )
    }

    @MainActor
    private func activationFailureMessage(
        screenElement: TheStash.ScreenElement,
        activateOutcome: AccessibilityActionDispatcher.ActivateOutcome
    ) -> String {
        let observed: String
        switch activateOutcome {
        case .success:
            observed = "unexpected success state"
        case .objectDeallocated:
            observed = "live target deallocated after semantic refresh"
        case .refused:
            observed = "accessibilityActivate() declined after semantic refresh"
        }
        return "activate failed: \(observed); activation-point dispatch was attempted at the fresh " +
            "accessibility activation point and did not complete for " +
            "\(ActionCapabilityDiagnostic.formatElement(screenElement)); correction: target an element " +
            "with primary accessibility activation, or use an explicit mechanical gesture when the " +
            "test intent is viewport coordinate delivery"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
