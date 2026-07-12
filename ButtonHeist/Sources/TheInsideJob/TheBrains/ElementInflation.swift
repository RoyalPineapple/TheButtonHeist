#if canImport(UIKit) && DEBUG
import UIKit

import ButtonHeistSupport
import TheScore
import ThePlans

/// Converts a semantic target into a fresh live target that can receive the
/// requested accessibility action.
///
/// Invariant: the tree is the map; viewport movement updates the map; actions
/// resolve one map entry to a fresh live object with an on-screen activation point.
///
/// It owns reveal, bounded viewport movement, and live geometry acquisition.
/// It does not choose matchers, dispatch actions, or evaluate post-action
/// expectations.
@MainActor
internal final class ElementInflation {

    internal let stash: TheStash
    internal let safecracker: TheSafecracker
    internal let tripwire: TheTripwire
    internal var discoverTarget: (@MainActor (AccessibilityTarget) async -> Navigation.ExploredScreen?)?
    internal var revealKnownTarget: (@MainActor (HeistId) async -> Navigation.ExploredScreen?)?

    internal static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    internal static let stableGeometryQuietFrames: Int = 2
    internal static let stableGeometryTimeout: TimeInterval = 1.0
    internal static var postScrollLayoutFrames: Int { Navigation.postScrollLayoutFrames }

    internal init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
    }

    internal func inflate(
        for target: AccessibilityTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen
    ) async -> ElementInflationResult {
        let resolvedTarget: AccessibilityTarget
        do {
            resolvedTarget = try target.validatedForElementAction()
        } catch {
            return .failed(.targetResolution(error))
        }
        var state: State = .resolving(.initial)
        let maxAttempts = 2

        while true {
            switch state {
            case .resolving(let pass):
                switch await findTargetInTree(resolvedTarget, allowKnownFallback: pass.allowsKnownFallback) {
                case .success(.visible(let treeElement)):
                    transition(
                        &state,
                        to: .refreshing(
                            target: resolvedTarget,
                            treeElement: treeElement,
                            attempt: pass.attempt,
                            didReveal: false
                        )
                    )
                case .success(.known(let treeElement)):
                    transition(&state, to: .revealing(treeElement: treeElement, attempt: pass.attempt))
                case .failure(let failure):
                    transition(&state, to: .failed(failure))
                }

            case .revealing(let treeElement, let attempt):
                transition(&state, to: await stateAfterReveal(treeElement, target: resolvedTarget, attempt: attempt))

            case .refreshing(let target, let treeElement, let attempt, let didReveal):
                transition(
                    &state,
                    to: await stateAfterRefresh(
                        target: target,
                        treeElement: treeElement,
                        didReveal: didReveal,
                        attempt: attempt,
                        method: method,
                        deallocatedBoundary: deallocatedBoundary,
                        activationPointPolicy: activationPointPolicy
                    )
                )

            case .placing(let inflatedTarget, let attempt, let didReveal):
                transition(
                    &state,
                    to: await stateAfterPlacement(
                        inflatedTarget,
                        didReveal: didReveal,
                        attempt: attempt,
                        method: method
                    )
                )

            case .retrying(let failedAttempt, let reason):
                let nextAttempt = failedAttempt + 1
                if nextAttempt >= maxAttempts {
                    transition(
                        &state,
                        to: .failed(retryExhaustedFailure(reason: reason, maxAttempts: maxAttempts))
                    )
                } else {
                    await tripwire.yieldRealFrames(1)
                    stash.refreshLiveCapture()
                    transition(&state, to: .resolving(.afterRetry(attempt: nextAttempt, reason: reason)))
                }

            case .inflated(let result):
                return .inflated(result)

            case .failed(let failure):
                return .failed(failure)
            }
        }
    }

    internal func inflateAfterActivationRefresh(
        for target: AccessibilityTarget
    ) async -> ElementInflationResult {
        refreshLiveCaptureForActivation()
        return await inflate(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation refresh"
        )
    }

    private func transition(_ state: inout State, to nextState: State) {
        let currentDescription = state.description
        let nextDescription = nextState.description
        insideJobLogger.debug(
            "inflation: \(currentDescription, privacy: .public) -> \(nextDescription, privacy: .public)"
        )
        state = nextState
    }

    private func refreshLiveCaptureForActivation() {
        stash.refreshLiveCapture()
    }
}

#endif // canImport(UIKit) && DEBUG
