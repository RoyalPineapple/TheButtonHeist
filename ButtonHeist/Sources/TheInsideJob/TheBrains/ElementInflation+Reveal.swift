#if canImport(UIKit) && DEBUG
import ButtonHeistSupport
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    private enum TargetRefreshGraceMode {
        case revealPath
        case liveTarget(method: ActionMethod)
    }

    private enum TargetRefreshGraceResolution {
        case treeElement(InterfaceTree.Element, didReveal: Bool)
        case liveTarget(InflatedElementTarget)
        case failed(ElementInflationFailure)
        case missing
    }

    internal func stateAfterReveal(
        _ treeElement: InterfaceTree.Element,
        target: AccessibilityTarget,
        attempt: Int
    ) async -> State {
        if case .success(let visible)? = visibleTargetResolution(target) {
            return .refreshing(
                target: target,
                treeElement: visible,
                attempt: attempt,
                didReveal: false
            )
        }

        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            switch refreshedVisibleTargetResolution(target) {
            case .success(let visible)?:
                return .refreshing(
                    target: target,
                    treeElement: visible,
                    attempt: attempt,
                    didReveal: false
                )
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                break
            }
            switch await awaitTargetRefreshGrace(for: target, mode: .revealPath) {
            case .treeElement(let resolved, let didReveal):
                return .refreshing(
                    target: target,
                    treeElement: resolved,
                    attempt: attempt,
                    didReveal: didReveal
                )
            case .failure(let graceFailure):
                return .failed(graceFailure)
            case .inflated(let inflatedTarget):
                return .refreshing(
                    target: target,
                    treeElement: inflatedTarget.treeElement,
                    attempt: attempt,
                    didReveal: false
                )
            case .timedOut:
                return .failed(.noRevealPath(
                    semanticRevealFailureMessage(failure, entry: treeElement)
                        + "; no reveal path appeared within \(Int(revealPathGraceTimeout * 1_000))ms"
                ))
            case .cancelled:
                return .failed(.noRevealPath(
                    semanticRevealFailureMessage(failure, entry: treeElement)
                        + "; reveal path wait was cancelled before a path appeared"
                ))
            }
        }
        return .refreshing(
            target: target,
            treeElement: treeElement,
            attempt: attempt,
            didReveal: reveal.didReveal
        )
    }

    internal func awaitStaleLiveTargetGrace(
        for target: AccessibilityTarget,
        method: ActionMethod,
        reason: RetryReason
    ) async -> TargetRefreshGraceTerminal {
        switch reason {
        case .objectDeallocated, .staleTarget:
            break
        case .activationPointOffscreen:
            return .timedOut
        }

        return await awaitTargetRefreshGrace(for: target, mode: .liveTarget(method: method))
    }

    private func refreshedVisibleTargetResolution(
        _ target: AccessibilityTarget
    ) -> Result<InterfaceTree.Element, ElementInflationFailure>? {
        guard stash.refreshLiveCapture() != nil else { return nil }
        return visibleTargetResolution(target)
    }

    /// Re-observe until a target whose reveal failed becomes resolvable, or
    /// the grace window expires.
    ///
    /// A reveal failure during a screen transition reads a mid-arrival world:
    /// the settled union can know the target before the destination finishes
    /// loading and wires live scroll geometry. The window wakes when the app
    /// posts a transition-completion notification (screenChanged or
    /// layoutChanged mean the change has already landed, so the next parse
    /// should find it); silent apps fall back to a coarse re-parse cadence.
    /// The target arriving on-viewport resolves visibly, and a fresh known
    /// entry that gained scroll membership earns one reveal retry.
    ///
    /// Every iteration suspends — first on the notification waiter, then on a
    /// one-frame real-time floor — so the window can never starve the main
    /// actor, and task cancellation exits promptly.
    private func awaitTargetRefreshGrace(
        for target: AccessibilityTarget,
        mode: TargetRefreshGraceMode
    ) async -> TargetRefreshGraceTerminal {
        let deadline = CFAbsoluteTimeGetCurrent() + revealPathGraceTimeout
        var driver = StateDriver(
            initial: RevealPathGraceState.idle,
            machine: RevealPathGraceMachine(silentReparseInterval: revealPathSilentReparseInterval)
        )
        var effect = driver.send(.begin(
            cursor: stash.accessibilityNotifications.transitionCursor(),
            remaining: revealPathGraceRemainingTime(until: deadline)
        )).revealPathGraceEffect

        while true {
            switch effect {
            case .waitForTransitionEvent(let cursor, let timeout):
                guard !Task.isCancelled else {
                    effect = driver.send(.cancelled).revealPathGraceEffect
                    continue
                }
                let advanced = await stash.accessibilityNotifications.waitForTransitionEvent(
                    after: cursor,
                    timeout: timeout
                )
                effect = driver.send(.transitionWaitCompleted(advanced)).revealPathGraceEffect

            case .yieldRealFrame:
                await tripwire.yieldRealFrames(1)
                effect = driver.send(Task.isCancelled ? .cancelled : .frameYielded).revealPathGraceEffect

            case .refreshVisibleTree:
                let refreshResult = targetRefreshGraceRefreshResult(mode: mode)
                effect = driver.send(.visibleTreeRefreshCompleted(
                    refreshResult,
                    remaining: revealPathGraceRemainingTime(until: deadline)
                )).revealPathGraceEffect

            case .resolveVisibleTarget:
                switch targetRefreshGraceResolution(target: target, mode: mode) {
                case .treeElement(let visible, let didReveal):
                    guard case .finish(.resolvedVisible) = driver.send(.visibleTargetResolved).revealPathGraceEffect
                    else {
                        preconditionFailure("Reveal path grace visible resolution did not finish as resolved.")
                    }
                    return .treeElement(visible, didReveal: didReveal)
                case .liveTarget(let inflatedTarget):
                    guard case .finish(.resolvedVisible) = driver.send(.visibleTargetResolved).revealPathGraceEffect
                    else {
                        preconditionFailure("Target refresh grace live resolution did not finish as resolved.")
                    }
                    return .inflated(inflatedTarget)
                case .failed(let failure):
                    guard case .finish(.failedVisibleTarget) = driver.send(.visibleTargetFailed).revealPathGraceEffect
                    else {
                        preconditionFailure("Reveal path grace visible failure did not finish as failed.")
                    }
                    return .failure(failure)
                case .missing:
                    effect = driver.send(.visibleTargetMissing(
                        remaining: revealPathGraceRemainingTime(until: deadline)
                    )).revealPathGraceEffect
                }

            case .attemptKnownTargetReveal:
                switch mode {
                case .revealPath:
                    switch await attemptRevealPathGraceKnownTarget(for: target) {
                    case .unavailable:
                        effect = driver.send(.knownTargetRevealAttempted(
                            .unavailable,
                            remaining: revealPathGraceRemainingTime(until: deadline)
                        )).revealPathGraceEffect
                    case .failed:
                        effect = driver.send(.knownTargetRevealAttempted(
                            .failed,
                            remaining: revealPathGraceRemainingTime(until: deadline)
                        )).revealPathGraceEffect
                    case .revealed(let fresh, let didReveal):
                        guard case .finish(.resolvedAfterKnownReveal(let effectDidReveal)) = driver.send(
                            .knownTargetRevealAttempted(
                                .revealed(didReveal: didReveal),
                                remaining: revealPathGraceRemainingTime(until: deadline)
                            )
                        ).revealPathGraceEffect else {
                            preconditionFailure("Reveal path grace known reveal did not finish as resolved.")
                        }
                        return .treeElement(fresh, didReveal: effectDidReveal)
                    }

                case .liveTarget:
                    effect = driver.send(.knownTargetRevealAttempted(
                        .unavailable,
                        remaining: revealPathGraceRemainingTime(until: deadline)
                    )).revealPathGraceEffect
                }

            case .finish(.timedOut):
                return .timedOut
            case .finish(.cancelled):
                return .cancelled

            case .finish(.resolvedVisible),
                 .finish(.failedVisibleTarget),
                 .finish(.resolvedAfterKnownReveal):
                preconditionFailure("Reveal path grace terminal effect must be consumed with boundary payload.")
            }
        }
    }

    private func targetRefreshGraceRefreshResult(
        mode: TargetRefreshGraceMode
    ) -> RevealPathGraceVisibleTreeRefreshResult {
        let refreshedScreen: InterfaceObservation?
        switch mode {
        case .revealPath:
            refreshedScreen = stash.refreshLiveCapture()
        case .liveTarget:
            refreshedScreen = stash.refreshLiveCapture()
        }
        return refreshedScreen == nil ? .unavailable : .refreshed
    }

    private func targetRefreshGraceResolution(
        target: AccessibilityTarget,
        mode: TargetRefreshGraceMode
    ) -> TargetRefreshGraceResolution {
        switch mode {
        case .revealPath:
            switch visibleTargetResolution(target) {
            case .success(let visible)?:
                return .treeElement(visible, didReveal: false)
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                return .missing
            }

        case .liveTarget(let method):
            switch visibleTargetResolution(target) {
            case .success(_)?:
                guard let resolution = resolveCurrentVisibleLiveElementTarget(
                    target: target,
                    method: method
                ) else {
                    return .missing
                }
                switch resolution {
                case .success(let inflatedTarget):
                    return .liveTarget(inflatedTarget)
                case .failure(let failure):
                    return .failed(failure)
                case .retry:
                    return .missing
                }
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                return .missing
            }
        }
    }

    private func revealPathGraceRemainingTime(until deadline: CFAbsoluteTime) -> Double {
        deadline - CFAbsoluteTimeGetCurrent()
    }

    private enum RevealPathGraceKnownTargetAttempt {
        case unavailable
        case failed
        case revealed(InterfaceTree.Element, didReveal: Bool)
    }

    private func attemptRevealPathGraceKnownTarget(
        for target: AccessibilityTarget
    ) async -> RevealPathGraceKnownTargetAttempt {
        guard case .success(let fresh) = knownSemanticTarget(target),
              fresh.scrollMembership != nil
        else { return .unavailable }

        let retryReveal = await revealSemanticTarget(fresh)
        if case .failed = retryReveal {
            return .failed
        }
        return .revealed(fresh, didReveal: retryReveal.didReveal)
    }
}

#endif // canImport(UIKit) && DEBUG
