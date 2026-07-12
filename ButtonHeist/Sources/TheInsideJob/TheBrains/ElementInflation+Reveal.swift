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
        deadline: SemanticObservationDeadline
    ) async -> State {
        if case .success(let visible)? = visibleTargetResolution(target) {
            return .refreshing(
                target: target,
                treeElement: visible,
                didReveal: false
            )
        }

        let settledSequence = stash.latestSettledSemanticObservationEvent?.sequence
        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            switch await awaitTargetRefresh(
                for: target,
                mode: .revealPath,
                after: settledSequence,
                deadline: deadline
            ) {
            case .treeElement(let resolved, let didReveal):
                return .refreshing(
                    target: target,
                    treeElement: resolved,
                    didReveal: didReveal
                )
            case .failure(let refreshFailure):
                return .failed(refreshFailure)
            case .inflated(let inflatedTarget):
                return .refreshing(
                    target: target,
                    treeElement: inflatedTarget.treeElement,
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
            didReveal: reveal.didReveal
        )
    }

    internal func awaitLiveTargetRefresh(
        for target: AccessibilityTarget,
        method: ActionMethod,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline
    ) async -> TargetRefreshTerminal {
        await awaitTargetRefresh(
            for: target,
            mode: .liveTarget(method: method),
            after: settledSequence,
            deadline: deadline
        )
    }

    /// Resolve only after committed semantic truth advances. A known target
    /// that gains scroll membership earns at most one reveal attempt.
    private func awaitTargetRefresh(
        for target: AccessibilityTarget,
        mode: TargetRefreshMode,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline
    ) async -> TargetRefreshTerminal {
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

            switch targetRefreshResolution(
                target: target,
                mode: mode
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
                  case .success(let fresh) = knownSemanticTarget(target),
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
        mode: TargetRefreshMode
    ) -> TargetRefreshResolution {
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
            switch resolveCurrentVisibleLiveElementTarget(target: target, method: method) {
            case .success(let inflatedTarget)?:
                return .liveTarget(inflatedTarget)
            case .failure(let failure)?:
                return .failed(failure)
            case .retry?, nil:
                return .missing
            }
        }
    }
}

#endif // canImport(UIKit) && DEBUG
