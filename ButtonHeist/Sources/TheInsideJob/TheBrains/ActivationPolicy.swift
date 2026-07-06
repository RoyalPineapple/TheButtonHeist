#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans
import TheScore

/// Ordered activation delivery pipeline for `activate`.
///
/// ButtonHeist treats accessibility as the interaction contract. `activate`
/// refreshes semantic resolution and live geometry before asking UIKit to
/// perform the element's primary accessibility activation with
/// `accessibilityActivate()`. When UIKit declines/defaults, ButtonHeist still
/// delivers the same `activate` command by dispatching at the fresh accessibility
/// activation point.
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
    var showFingerprint: @MainActor (CGPoint) -> Void

    @MainActor
    func apply(to _: TheStash.LiveActionTarget) async -> TheSafecracker.InteractionResult {
        let screenElement: TheStash.ScreenElement
        let refreshedLiveTarget: TheStash.LiveActionTarget
        switch await refreshAndResolve() {
        case .resolved(let resolvedElement, let liveTarget):
            screenElement = resolvedElement
            refreshedLiveTarget = liveTarget
        case .failure(let result):
            return result.withActivationTrace(ActivationTrace(.refreshFailed))
        }

        let activateOutcome = accessibilityActivate(refreshedLiveTarget)
        if activateOutcome == .success {
            showFingerprint(refreshedLiveTarget.activationPoint)
            return .success(
                method: .activate,
                activationTrace: ActivationTrace(.accessibilityActivate)
            )
        }

        let activationPoint = refreshedLiveTarget.activationPoint
        let tapActivationSucceeded = await activationPointDispatch(activationPoint)
        let trace = ActivationTrace(.activationPointFallback(
            axActivateReturned: activateOutcome.axActivateReturned,
            tapActivationPoint: ScreenPoint(x: Double(activationPoint.x), y: Double(activationPoint.y)),
            tapActivationSucceeded: tapActivationSucceeded
        ))
        if tapActivationSucceeded {
            return .success(method: .activate, activationTrace: trace)
        }

        return .failure(
            .activate,
            message: activationFailureMessage(screenElement: screenElement, activateOutcome: activateOutcome),
            activationTrace: trace
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
            "\(ActionCapabilityDiagnostic.elementObservation(screenElement)); correction: target an element " +
            "with primary accessibility activation, or use an explicit mechanical gesture when the " +
            "test intent is viewport coordinate delivery"
    }
}

private extension AccessibilityActionDispatcher.ActivateOutcome {
    var axActivateReturned: Bool? {
        switch self {
        case .success: return true
        case .refused: return false
        case .objectDeallocated: return nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
