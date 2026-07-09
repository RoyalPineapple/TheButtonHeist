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
    internal var discoverTarget: (@MainActor (ElementTarget) async -> Screen?)?
    internal var revealKnownTarget: (@MainActor (HeistId) async -> Screen?)?

    /// Bounded window inflation waits for a target whose reveal failed, or
    /// whose visible live object was recycled, to become resolvable before
    /// failing the active recovery path.
    ///
    /// Async-loaded destinations can produce a settled world that knows the
    /// target before its live scroll geometry is wired, so a reveal failure at
    /// the dispatch instant is not proof of unreachability — the very next
    /// settled capture can show the target framed and reachable. The wait is
    /// keyed off the target resolving, not a fixed retry count, because the
    /// gating operation is typically I/O (an in-flight content load).
    /// Field-measured arrivals land within ~500ms of dispatch; the standard
    /// settle timeout covers them with margin.
    internal var revealPathGraceTimeout: TimeInterval = SemanticObservationTiming.defaultTimeout

    /// Re-parse cadence inside the grace window when the app posts no
    /// transition-completion notifications. Apps that announce transitions
    /// wake the window immediately; silent apps fall back to this interval.
    internal var revealPathSilentReparseInterval: TimeInterval = 0.15

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
        for target: ElementTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen
    ) async -> ElementInflationResult {
        stash.refreshCurrentVisibleTree()
        var state: State = .resolving(.initial)
        let maxAttempts = 2

        while true {
            switch state {
            case .resolving(let pass):
                switch await findTargetInTree(target, allowKnownFallback: pass.allowsKnownFallback) {
                case .success(.visible(let treeElement)):
                    transition(
                        &state,
                        to: .refreshing(
                            target: target,
                            screenElement: treeElement,
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
                transition(&state, to: await stateAfterReveal(treeElement, target: target, attempt: attempt))

            case .refreshing(let target, let screenElement, let attempt, let didReveal):
                transition(
                    &state,
                    to: await stateAfterRefresh(
                        target: target,
                        screenElement: screenElement,
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
                    stash.refreshCurrentVisibleTree()
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
        for target: ElementTarget
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
        stash.refreshCurrentVisibleTree()
    }
}

#endif // canImport(UIKit) && DEBUG
