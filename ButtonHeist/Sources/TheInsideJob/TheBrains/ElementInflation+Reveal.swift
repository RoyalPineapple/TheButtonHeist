#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    private enum TargetRefreshMode {
        case revealPath(
            target: AdmittedSemanticTarget,
            transaction: RevealTransaction,
            resolution: ActionSubjectResolution
        )
        case liveTarget(
            identity: CrossCaptureTarget,
            pinnedElement: InterfaceTree.Element,
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
        await stateAfterReveal(
            treeElement,
            identity: .captureLocal(target),
            deadline: deadline,
            resolution: resolution,
            transaction: transaction
        )
    }

    internal func stateAfterReveal(
        _ treeElement: InterfaceTree.Element,
        identity: CrossCaptureTarget,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution,
        transaction: RevealTransaction
    ) async -> State {
        let sourceTarget = identity.sourceTarget

        let admittedTarget: AdmittedSemanticTarget
        if let admitted = identity.admittedSemanticTarget {
            admittedTarget = admitted
        } else {
            switch admittedSemanticTarget(sourceTarget, selectedElement: treeElement) {
            case .success(let target):
                admittedTarget = target
            case .failure(let failure):
                return .failed(failure.inflationFailure)
            }
        }
        let admittedIdentity = CrossCaptureTarget.admitted(
            sourceTarget: sourceTarget,
            semanticTarget: admittedTarget
        )

        if vault.liveContains(heistId: treeElement.heistId),
           let committed = vault.interfaceElement(heistId: treeElement.heistId) {
            return .refreshing(
                target: admittedIdentity,
                treeElement: committed,
                deadline: deadline,
                resolution: resolution
            )
        }

        let settledSequence = vault.semanticObservationStream.latestCommittedEvent?.sequence
        let reveal = await revealSemanticTarget(
            admittedTarget,
            initialElement: treeElement,
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
        case .targetResolutionFailed(let failure):
            return .failed(failure.inflationFailure)
        case .failed(let failure):
            switch await awaitTargetRefresh(
                mode: .revealPath(
                    target: admittedTarget,
                    transaction: transaction,
                    resolution: resolution
                ),
                after: settledSequence,
                deadline: deadline
            ) {
            case .treeElement(let resolved, let refreshedResolution):
                return .refreshing(
                    target: admittedIdentity,
                    treeElement: resolved,
                    deadline: deadline,
                    resolution: refreshedResolution
                )
            case .failure(let refreshFailure):
                return .failed(refreshFailure)
            case .inflated(let inflatedTarget):
                return .refreshing(
                    target: admittedIdentity,
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
        case .alreadyVisible(let current), .revealed(let current):
            return .refreshing(
                target: admittedIdentity,
                treeElement: current,
                deadline: deadline,
                resolution: reveal.didReveal && transaction.didMove
                    ? resolution.adding(.semanticReveal)
                    : resolution
            )
        }
    }

    internal func awaitLiveTargetRefresh(
        for target: AdmittedSemanticTarget,
        sourceTarget: ResolvedAccessibilityTarget,
        pinnedElement: InterfaceTree.Element,
        method: ActionMethod,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) async -> TargetRefreshTerminal {
        await awaitTargetRefresh(
            mode: .liveTarget(
                identity: .admitted(sourceTarget: sourceTarget, semanticTarget: target),
                pinnedElement: pinnedElement,
                method: method,
                resolution: resolution
            ),
            after: settledSequence,
            deadline: deadline
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
                identity: .captureLocal(target),
                pinnedElement: treeElement,
                method: method,
                resolution: resolution
            ),
            after: settledSequence,
            deadline: deadline
        )
    }

    private func awaitTargetRefresh(
        mode: TargetRefreshMode,
        after settledSequence: SettledObservationSequence?,
        deadline: SemanticObservationDeadline
    ) async -> TargetRefreshTerminal {
        var sequence = settledSequence
        var didAttemptKnownTargetReveal = false
        var resolution = mode.resolution

        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            guard !Task.isCancelled else { return .cancelled }
            guard let event = await vault.semanticObservationStream.settledEvent(
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

            guard case .revealPath(let target, let transaction, _) = mode,
                  !didAttemptKnownTargetReveal,
                  case .success(let fresh) = resolveAdmittedSemanticTarget(target),
                  fresh.scrollMembership != nil
            else { continue }

            didAttemptKnownTargetReveal = true
            switch await revealSemanticTarget(
                target,
                initialElement: fresh,
                deadline: deadline,
                transaction: transaction
            ) {
            case .alreadyVisible(let current):
                return .treeElement(current, resolution)
            case .revealed(let current):
                return .treeElement(
                    current,
                    transaction.didMove ? resolution.adding(.semanticReveal) : resolution
                )
            case .targetResolutionFailed(let failure):
                return .failure(failure.inflationFailure)
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
        case .revealPath(let target, _, _):
            switch resolveAdmittedSemanticTarget(target) {
            case .success(let current):
                return vault.liveContains(heistId: current.heistId)
                    ? .treeElement(current)
                    : .missing
            case .failure(let failure):
                return .failed(failure.inflationFailure)
            }

        case .liveTarget(let identity, let pinnedElement, let method, _):
            let current: InterfaceTree.Element
            switch identity {
            case .captureLocal:
                guard let committed = vault.interfaceElement(heistId: pinnedElement.heistId) else {
                    return .retry(.staleTarget)
                }
                current = committed
            case .admitted(_, let target):
                switch resolveAdmittedSemanticTarget(target) {
                case .success(let element):
                    current = element
                case .failure(let failure):
                    return .failed(failure.inflationFailure)
                }
            }
            switch resolveCurrentLiveElementTarget(
                treeElement: current,
                identity: identity,
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
