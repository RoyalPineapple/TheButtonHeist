#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    private enum TargetRefreshMode {
        case revealPath(treeElement: InterfaceTree.Element)
        case liveTarget(
            treeElement: InterfaceTree.Element,
            target: AccessibilityTarget,
            method: ActionMethod
        )
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
        if stash.liveContains(heistId: treeElement.heistId),
           let committed = stash.interfaceElement(heistId: treeElement.heistId) {
            return .refreshing(
                target: target,
                treeElement: committed,
                deadline: deadline,
                didReveal: false
            )
        }

        let settledSequence = stash.latestSettledSemanticObservationEvent?.sequence
        let reveal = await revealSemanticTarget(treeElement)
        if case .failed(let failure) = reveal {
            switch await awaitTargetRefresh(
                mode: .revealPath(treeElement: treeElement),
                after: settledSequence,
                deadline: deadline
            ) {
            case .treeElement(let resolved, let didReveal):
                return .refreshing(
                    target: target,
                    treeElement: resolved,
                    deadline: deadline,
                    didReveal: didReveal
                )
            case .failure(let refreshFailure):
                return .failed(refreshFailure)
            case .inflated(let inflatedTarget):
                return .refreshing(
                    target: target,
                    treeElement: inflatedTarget.treeElement,
                    deadline: deadline,
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
            deadline: deadline,
            didReveal: reveal.didReveal
        )
    }

    internal func awaitLiveTargetRefresh(
        for target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline
    ) async -> TargetRefreshTerminal {
        await awaitTargetRefresh(
            mode: .liveTarget(treeElement: treeElement, target: target, method: method),
            after: settledSequence,
            deadline: deadline
        )
    }

    /// Resolve only after committed semantic truth advances. A known target
    /// that gains scroll membership earns at most one reveal attempt.
    private func awaitTargetRefresh(
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

            switch targetRefreshResolution(mode: mode, deadline: deadline) {
            case .treeElement(let visible, let didReveal):
                return .treeElement(visible, didReveal: didReveal)
            case .liveTarget(let inflatedTarget):
                return .inflated(inflatedTarget)
            case .failed(let failure):
                return .failure(failure)
            case .missing:
                break
            }

            guard case .revealPath(let treeElement) = mode,
                  !didAttemptKnownTargetReveal,
                  let fresh = stash.interfaceElement(heistId: treeElement.heistId),
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
        mode: TargetRefreshMode,
        deadline: SemanticObservationDeadline
    ) -> TargetRefreshResolution {
        switch mode {
        case .revealPath(let treeElement):
            guard stash.liveContains(heistId: treeElement.heistId),
                  let committed = stash.interfaceElement(heistId: treeElement.heistId)
            else { return .missing }
            return .treeElement(committed, didReveal: false)

        case .liveTarget(let treeElement, let target, let method):
            switch resolveCurrentLiveElementTarget(
                treeElement: treeElement,
                target: target,
                method: method,
                deadline: deadline
            ) {
            case .success(let inflatedTarget):
                return .liveTarget(inflatedTarget)
            case .failure(let failure):
                return .failed(failure)
            case .retry:
                return .missing
            }
        }
    }
}

#endif // canImport(UIKit) && DEBUG
