#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    private enum TargetRefreshMode {
        case revealPath(
            treeElement: InterfaceTree.Element,
            transaction: RevealTransaction,
            resolution: ActionSubjectResolution
        )
        case liveTarget(
            treeElement: InterfaceTree.Element,
            target: ResolvedAccessibilityTarget,
            method: ActionMethod,
            resolution: ActionSubjectResolution
        )

        var resolution: ActionSubjectResolution {
            switch self {
            case .revealPath(_, _, let resolution), .liveTarget(_, _, _, let resolution):
                return resolution
            }
        }
    }

    private enum TargetRefreshResolution {
        case treeElement(InterfaceTree.Element)
        case liveTarget(InflatedElementTarget)
        case failed(ElementInflationFailure)
        case retry(RetryReason)
        case missing
    }

    internal func stateAfterReveal(
        _ treeElement: InterfaceTree.Element,
        target: ResolvedAccessibilityTarget,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution,
        transaction: RevealTransaction
    ) async -> State {
        if stash.liveContains(heistId: treeElement.heistId),
           let committed = stash.interfaceElement(heistId: treeElement.heistId) {
            return .refreshing(
                target: target,
                treeElement: committed,
                deadline: deadline,
                resolution: resolution
            )
        }

        let settledSequence = stash.latestSettledSemanticObservationEvent?.sequence
        let reveal = await revealSemanticTarget(
            treeElement,
            deadline: deadline,
            transaction: transaction
        )
        switch reveal {
        case .cancelled:
            return .failed(.cancelled(
                "semantic target reveal was cancelled before the target became actionable"
            ))
        case .timedOut:
            return .failed(.timedOut(
                "semantic target reveal reached the action deadline before the target became actionable"
            ))
        case .failed(let failure):
            if failure == .scanDidNotRevealTarget {
                return .failed(.noRevealPath(semanticRevealFailureMessage(failure, entry: treeElement)))
            }
            switch await awaitTargetRefresh(
                mode: .revealPath(
                    treeElement: treeElement,
                    transaction: transaction,
                    resolution: resolution
                ),
                after: settledSequence,
                deadline: deadline
            ) {
            case .treeElement(let resolved, let refreshedResolution):
                return .refreshing(
                    target: target,
                    treeElement: resolved,
                    deadline: deadline,
                    resolution: refreshedResolution
                )
            case .failure(let refreshFailure):
                return .failed(refreshFailure)
            case .inflated(let inflatedTarget):
                return .refreshing(
                    target: target,
                    treeElement: inflatedTarget.treeElement,
                    deadline: deadline,
                    resolution: inflatedTarget.resolution
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
        case .alreadyVisible, .revealed:
            break
        }
        return .refreshing(
            target: target,
            treeElement: treeElement,
            deadline: deadline,
            resolution: reveal.didReveal && transaction.didMove
                ? resolution.adding(.semanticReveal)
                : resolution
        )
    }

    internal func awaitLiveTargetRefresh(
        for target: ResolvedAccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) async -> TargetRefreshTerminal {
        await awaitTargetRefresh(
            mode: .liveTarget(
                treeElement: treeElement,
                target: target,
                method: method,
                resolution: resolution
            ),
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
        var resolution = mode.resolution

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
                mode: mode,
                deadline: deadline,
                resolution: resolution
            ) {
            case .treeElement(let visible):
                return .treeElement(visible, resolution)
            case .liveTarget(let inflatedTarget):
                return .inflated(inflatedTarget)
            case .failed(let failure):
                return .failure(failure)
            case .retry(let reason):
                resolution = resolution.adding(reason.adjustment)
            case .missing:
                break
            }

            guard case .revealPath(let treeElement, let transaction, _) = mode,
                  !didAttemptKnownTargetReveal,
                  let fresh = stash.interfaceElement(heistId: treeElement.heistId),
                  fresh.scrollMembership != nil
            else { continue }

            didAttemptKnownTargetReveal = true
            switch await revealSemanticTarget(
                fresh,
                deadline: deadline,
                transaction: transaction
            ) {
            case .alreadyVisible:
                return .treeElement(fresh, resolution)
            case .revealed:
                return .treeElement(
                    fresh,
                    transaction.didMove ? resolution.adding(.semanticReveal) : resolution
                )
            case .failed:
                continue
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            }
        }

        return Task.isCancelled ? .cancelled : .timedOut
    }

    private func targetRefreshResolution(
        mode: TargetRefreshMode,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> TargetRefreshResolution {
        switch mode {
        case .revealPath(let treeElement, _, _):
            guard stash.liveContains(heistId: treeElement.heistId),
                  let committed = stash.interfaceElement(heistId: treeElement.heistId)
            else { return .missing }
            return .treeElement(committed)

        case .liveTarget(let treeElement, let target, let method, _):
            switch resolveCurrentLiveElementTarget(
                treeElement: treeElement,
                target: target,
                method: method,
                deadline: deadline,
                resolution: resolution
            ) {
            case .success(let inflatedTarget):
                return .liveTarget(inflatedTarget)
            case .failure(let failure):
                return .failed(failure)
            case .retry(let reason):
                return .retry(reason)
            }
        }
    }
}

#endif // canImport(UIKit) && DEBUG
