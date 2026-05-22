#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import TheScore

/// Ordered activation recovery policy for `activate`.
///
/// Keeps the fallback sequence explicit: try `accessibilityActivate`, retry
/// after refresh/re-resolve, fall back to a synthetic tap, then produce the
/// final diagnostic from observed retry state.
struct ActivationPolicy {

    enum RefreshResult {
        case resolved(
            resolvedTarget: TheStash.ResolvedTarget,
            liveTarget: TheStash.LiveActionTarget
        )
        case failure(TheSafecracker.InteractionResult)
    }

    private enum State {
        case accessibilityActivate(TheStash.LiveActionTarget)
        case refreshReresolveRetry
        case syntheticTapFallback(
            resolvedTarget: TheStash.ResolvedTarget,
            liveTarget: TheStash.LiveActionTarget,
            activateOutcome: TheStash.ActivateOutcome
        )
        case finalDiagnosticFailure(
            resolvedTarget: TheStash.ResolvedTarget,
            tapPoint: CGPoint,
            activateOutcome: TheStash.ActivateOutcome
        )
    }

    var activate: @MainActor (TheStash.LiveActionTarget) -> TheStash.ActivateOutcome
    var refreshAndResolve: @MainActor () async -> RefreshResult
    var syntheticTap: @MainActor (CGPoint) async -> Bool
    var showFingerprint: @MainActor (CGPoint) -> Void
    var tapReceiverDiagnostic: @MainActor (CGPoint) -> TheSafecracker.TapReceiverDiagnostic?
    var screenBounds: @MainActor () -> CGRect

    @MainActor
    func apply(to liveTarget: TheStash.LiveActionTarget) async -> TheSafecracker.InteractionResult {
        var state = State.accessibilityActivate(liveTarget)

        while true {
            switch state {
            case .accessibilityActivate(let target):
                let outcome = activate(target)
                if outcome == .success {
                    showFingerprint(target.activationPoint)
                    return .success(method: .activate)
                }
                state = .refreshReresolveRetry

            case .refreshReresolveRetry:
                switch await refreshAndResolve() {
                case .resolved(let resolvedTarget, let retryLiveTarget):
                    let retryOutcome = activate(retryLiveTarget)
                    if retryOutcome == .success {
                        showFingerprint(retryLiveTarget.activationPoint)
                        return .success(method: .activate)
                    }
                    state = .syntheticTapFallback(
                        resolvedTarget: resolvedTarget,
                        liveTarget: retryLiveTarget,
                        activateOutcome: retryOutcome
                    )
                case .failure(let result):
                    return result
                }

            case .syntheticTapFallback(let resolvedTarget, let retryLiveTarget, let retryOutcome):
                let tapPoint = retryLiveTarget.activationPoint
                if await syntheticTap(tapPoint) {
                    showFingerprint(tapPoint)
                    return .success(method: .syntheticTap)
                }
                state = .finalDiagnosticFailure(
                    resolvedTarget: resolvedTarget,
                    tapPoint: tapPoint,
                    activateOutcome: retryOutcome
                )

            case .finalDiagnosticFailure(let resolvedTarget, let tapPoint, let retryOutcome):
                return finalDiagnosticFailure(
                    resolvedTarget: resolvedTarget,
                    tapPoint: tapPoint,
                    activateOutcome: retryOutcome
                )
            }
        }
    }

    @MainActor
    private func finalDiagnosticFailure(
        resolvedTarget: TheStash.ResolvedTarget,
        tapPoint: CGPoint,
        activateOutcome: TheStash.ActivateOutcome
    ) -> TheSafecracker.InteractionResult {
        let traitNames = ActionCapabilityDiagnostic.traitNames(resolvedTarget.element.traits)
        let message = ActivateFailureDiagnostic.build(
            element: resolvedTarget.element,
            traitNames: traitNames,
            activateOutcome: activateOutcome,
            tapAttempted: true,
            tapReceiver: tapReceiverDiagnostic(tapPoint),
            screenBounds: screenBounds()
        )
        return .failure(.activate, message: message)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
