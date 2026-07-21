#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func admitSemanticTarget(
        _ sourceTarget: ResolvedAccessibilityTarget,
        selectedElement: InterfaceTree.Element
    ) -> SemanticTargetAdmissionDecision {
        AdmittedSemanticTarget.admit(
            sourceTarget,
            selectedElement: selectedElement,
            resolve: vault.resolveTarget
        )
    }

    internal func stateAfterRefresh(
        target: ResolvedAccessibilityTarget,
        treeElement: InterfaceTree.Element,
        resolution: ActionSubjectResolution,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> State {
        switch resolveFreshElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deadline: deadline,
            resolution: resolution
        ) {
        case .success(let inflatedTarget):
            return await stateAfterResolvedFreshTarget(
                inflatedTarget,
                activationPointPolicy: activationPointPolicy
            )
        case .retry(let reason):
            let refreshedResolution = resolution.adding(reason.adjustment)
            let pendingRetry: (reason: RetryReason, resolution: ActionSubjectResolution)
            if vault.refreshLiveCapture() != nil {
                let refreshed = resolveCurrentLiveElementTarget(
                    treeElement: treeElement,
                    target: target,
                    method: method,
                    deadline: deadline,
                    resolution: refreshedResolution
                )
                switch refreshed {
                case .success(let inflatedTarget):
                    return await stateAfterResolvedFreshTarget(
                        inflatedTarget,
                        activationPointPolicy: activationPointPolicy
                    )
                case .failure(let failure):
                    return .failed(failure)
                case .retry(let refreshedReason):
                    pendingRetry = (
                        refreshedReason,
                        refreshedResolution.adding(refreshedReason.adjustment)
                    )
                }
            } else {
                pendingRetry = (reason, refreshedResolution)
            }
            switch await awaitLiveTargetRefresh(
                for: target,
                treeElement: treeElement,
                method: method,
                after: vault.semanticObservationStream.latestCommittedEvent?.sequence,
                deadline: deadline,
                resolution: pendingRetry.resolution
            ) {
            case .inflated(let inflatedTarget):
                return await stateAfterResolvedFreshTarget(
                    inflatedTarget,
                    activationPointPolicy: activationPointPolicy
                )
            case .failure(let failure):
                return .failed(failure)
            case .treeElement, .timedOut:
                return .failed(staleRefreshFailure(reason: pendingRetry.reason))
            case .cancelled:
                return .failed(.cancelled(
                    "stale live target refresh was cancelled after \(pendingRetry.reason.failureDescription)"
                ))
            }
        case .failure(let failure):
            return .failed(failure)
        }
    }

    internal func findTargetInTree(
        _ target: ResolvedAccessibilityTarget,
    ) async -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch visibleTargetResolution(target) {
        case .success(let visible):
            return .success(.visible(visible, ActionSubjectResolution(origin: .visible)))
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        switch knownSemanticTarget(target) {
        case .success(let known):
            return .success(.known(known, ActionSubjectResolution(origin: .known)))
        case .failure(let failure) where failure.failedStep == .ambiguous:
            return .failure(failure)
        case .failure:
            break
        }
        await exploration.settleForDiscovery()
        let explorationResult = await exploration.discoverTarget(target)
        switch visibleTargetResolution(target) {
        case .success(let visible):
            let resolution = ActionSubjectResolution(origin: .discovered)
            return .success(.visible(
                visible,
                explorationResult?.didMoveViewport == true
                    ? resolution.adding(.semanticReveal)
                    : resolution
            ))
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        switch knownSemanticTarget(target) {
        case .success(let treeElement):
            return .success(.known(treeElement, ActionSubjectResolution(origin: .discovered)))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    internal func knownSemanticTarget(
        _ target: ResolvedAccessibilityTarget
    ) -> Result<InterfaceTree.Element, ElementInflationFailure> {
        switch vault.resolveTarget(target) {
        case .resolved(.element(let treeElement)):
            return .success(treeElement)
        case .resolved(.container):
            return .failure(.targetResolution(.containerTarget))
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.notFound(TargetResolutionDiagnostics.message(for: .notFound(facts))))
        }
    }

    internal func visibleTargetResolution(
        _ target: ResolvedAccessibilityTarget
    ) -> Result<InterfaceTree.Element, ElementInflationFailure>? {
        switch vault.resolveVisibleTarget(target) {
        case .resolved(.element(let treeElement)):
            return .success(treeElement)
        case .resolved(.container):
            return .failure(.targetResolution(.containerTarget))
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound:
            return nil
        }
    }

    internal func resolveCurrentLiveElementTarget(
        treeElement: InterfaceTree.Element,
        target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        guard let committed = vault.interfaceElement(heistId: treeElement.heistId) else {
            return .retry(.staleTarget)
        }
        switch vault.resolveLiveActionTarget(for: committed) {
        case .resolved(let liveTarget):
            return .success(InflatedElementTarget(
                target: target,
                treeElement: committed,
                liveTarget: liveTarget,
                deadline: deadline,
                resolution: resolution
            ))
        case .objectUnavailable:
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: committed,
                    isVisible: vault.viewportElementIDs.contains(committed.heistId)
                )
            ))
        }
    }

    private func resolveFreshElementTarget(
        target: ResolvedAccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deadline: deadline,
            resolution: resolution
        )
    }

    private func resolveLiveElementTarget(
        target: ResolvedAccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        resolveCurrentLiveElementTarget(
            treeElement: treeElement,
            target: target,
            method: method,
            deadline: deadline,
            resolution: resolution
        )
    }
}

#endif // canImport(UIKit) && DEBUG
