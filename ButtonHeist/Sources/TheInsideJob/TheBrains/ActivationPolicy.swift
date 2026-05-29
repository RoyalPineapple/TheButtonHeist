#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

/// Ordered activation recovery policy for `activate`.
///
/// Keeps the recovery sequence explicit: try `accessibilityActivate`, retry
/// once after refresh/re-resolve, try a synthetic tap, then produce the final
/// diagnostic from observed retry state.
struct ActivationPolicy {

    enum RefreshResult {
        case resolved(
            screenElement: TheStash.ScreenElement,
            liveTarget: TheStash.LiveActionTarget
        )
        case failure(TheSafecracker.InteractionResult)
    }

    enum SyntheticTapRecoveryOutcome: Equatable {
        case succeeded
        case failed(tapReceiver: TheSafecracker.TapReceiverDiagnostic?)
    }

    var activate: @MainActor (TheStash.LiveActionTarget) -> TheStash.ActivateOutcome
    var refreshAndResolve: @MainActor () async -> RefreshResult
    var syntheticTap: @MainActor (CGPoint) async -> Bool
    var showFingerprint: @MainActor (CGPoint) -> Void
    var tapReceiverDiagnostic: @MainActor (CGPoint) -> TheSafecracker.TapReceiverDiagnostic?
    var screenBounds: @MainActor () -> CGRect

    @MainActor
    func apply(to liveTarget: TheStash.LiveActionTarget) async -> TheSafecracker.InteractionResult {
        let initialOutcome = activate(liveTarget)
        if initialOutcome == .success {
            showFingerprint(liveTarget.activationPoint)
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
            showFingerprint(retryLiveTarget.activationPoint)
            return .success(method: .activate)
        }

        let tapPoint = retryLiveTarget.activationPoint
        switch await attemptSyntheticTapRecovery(at: tapPoint) {
        case .succeeded:
            showFingerprint(tapPoint)
            return .success(method: .syntheticTap)
        case .failed(let tapReceiver):
            return finalDiagnosticFailure(
                screenElement: screenElement,
                tapReceiver: tapReceiver,
                activateOutcome: retryOutcome
            )
        }
    }

    @MainActor
    func attemptSyntheticTapRecovery(at point: CGPoint) async -> SyntheticTapRecoveryOutcome {
        guard await syntheticTap(point) else {
            return .failed(tapReceiver: tapReceiverDiagnostic(point))
        }
        return .succeeded
    }

    @MainActor
    private func finalDiagnosticFailure(
        screenElement: TheStash.ScreenElement,
        tapReceiver: TheSafecracker.TapReceiverDiagnostic?,
        activateOutcome: TheStash.ActivateOutcome
    ) -> TheSafecracker.InteractionResult {
        let traitNames = ActionCapabilityDiagnostic.traitNames(screenElement.element.traits)
        let message = ActivateFailureDiagnostic.build(
            element: screenElement.element,
            traitNames: traitNames,
            activateOutcome: activateOutcome,
            tapAttempted: true,
            tapReceiver: tapReceiver,
            screenBounds: screenBounds()
        )
        return .failure(.activate, message: message)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
