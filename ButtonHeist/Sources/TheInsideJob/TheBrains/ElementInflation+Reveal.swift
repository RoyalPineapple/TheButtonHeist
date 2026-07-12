#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    private enum TargetRefreshMode {
        case revealPath
        case liveTarget(method: ActionMethod)
    }

    private enum TargetRefreshResolution {
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

        let settledSequence = stash.latestSettledSemanticObservationEvent?.sequence
        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            switch await awaitTargetRefresh(
                for: target,
                mode: .revealPath,
                after: settledSequence
            ) {
            case .treeElement(let resolved, let didReveal):
                return .refreshing(
                    target: target,
                    treeElement: resolved,
                    attempt: attempt,
                    didReveal: didReveal
                )
            case .failure(let refreshFailure):
                return .failed(refreshFailure)
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
                        + "; no reveal path appeared before the action deadline"
                ))
            case .cancelled:
                return .failed(.cancelled(
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

        return await awaitTargetRefresh(
            for: target,
            mode: .liveTarget(method: method),
            after: stash.latestSettledSemanticObservationEvent?.sequence
        )
    }

    /// Resolve only after settled semantic truth advances. Each settled event
    /// earns one fresh live capture; a known target that gains scroll
    /// membership earns at most one reveal attempt.
    private func awaitTargetRefresh(
        for target: AccessibilityTarget,
        mode: TargetRefreshMode,
        after settledSequence: SettledObservationSequence?
    ) async -> TargetRefreshGraceTerminal {
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent(),
            timeoutSeconds: SemanticObservationTiming.defaultTimeout
        )
        var sequence = settledSequence
        var didAttemptKnownTargetReveal = false

        while deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            guard !Task.isCancelled else { return .cancelled }
            guard let event = await stash.observeSettledSemanticObservation(
                scope: .visible,
                after: sequence,
                timeout: deadline.remainingSeconds()
            ) else {
                return Task.isCancelled ? .cancelled : .timedOut
            }
            sequence = event.sequence
            guard stash.refreshLiveCapture() != nil else { continue }

            let settledTree = event.observation.screen.tree
            switch targetRefreshResolution(
                target: target,
                mode: mode,
                settledTree: settledTree
            ) {
            case .treeElement(let visible, let didReveal):
                return .treeElement(visible, didReveal: didReveal)
            case .liveTarget(let inflatedTarget):
                return .inflated(inflatedTarget)
            case .failed(let failure):
                return .failure(failure)
            case .missing:
                break
            }

            guard case .revealPath = mode,
                  !didAttemptKnownTargetReveal,
                  case .resolved(let fresh) = stash.resolveTarget(target, in: settledTree),
                  fresh.scrollMembership != nil
            else { continue }

            didAttemptKnownTargetReveal = true
            let reveal = await revealSemanticTarget(fresh)
            if case .failed = reveal { continue }
            return .treeElement(fresh, didReveal: reveal.didReveal)
        }

        return Task.isCancelled ? .cancelled : .timedOut
    }

    private func targetRefreshResolution(
        target: AccessibilityTarget,
        mode: TargetRefreshMode,
        settledTree: InterfaceTree
    ) -> TargetRefreshResolution {
        switch mode {
        case .revealPath:
            switch visibleTargetResolution(target, in: settledTree) {
            case .success(let visible)?:
                return .treeElement(visible, didReveal: false)
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                return .missing
            }

        case .liveTarget(let method):
            switch visibleTargetResolution(target, in: settledTree) {
            case .success(let treeElement)?:
                switch stash.resolveLiveActionTarget(for: treeElement) {
                case .resolved(let liveTarget):
                    guard retainedInterfaceElement(liveTarget.treeElement, matches: target) else {
                        return .missing
                    }
                    return .liveTarget(InflatedElementTarget(
                        target: target,
                        treeElement: liveTarget.treeElement,
                        liveTarget: liveTarget
                    ))
                case .objectUnavailable:
                    return .missing
                case .geometryUnavailable:
                    return .failed(.geometryNotActionable(
                        ActionCapabilityDiagnostic.gestureTargetUnavailable(
                            method: method,
                            element: treeElement,
                            isVisible: settledTree.viewportElementIDs.contains(treeElement.heistId)
                        )
                    ))
                }
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                return .missing
            }
        }
    }
}

#endif // canImport(UIKit) && DEBUG
