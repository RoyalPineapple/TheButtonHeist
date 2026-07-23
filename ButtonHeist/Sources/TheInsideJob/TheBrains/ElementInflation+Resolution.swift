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
        await stateAfterRefresh(
            identity: .captureLocal(target),
            treeElement: treeElement,
            resolution: resolution,
            method: method,
            activationPointPolicy: activationPointPolicy,
            deadline: deadline
        )
    }

    internal func stateAfterRefresh(
        identity: CrossCaptureTarget,
        treeElement: InterfaceTree.Element,
        resolution: ActionSubjectResolution,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> State {
        let currentElement: InterfaceTree.Element
        switch resolveCurrentElement(for: identity, pinnedElement: treeElement) {
        case .success(let resolved):
            currentElement = resolved
        case .failure(let failure):
            return .failed(failure)
        }
        switch resolveFreshElementTarget(
            identity: identity,
            treeElement: currentElement,
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
                let refreshedElement: InterfaceTree.Element
                switch resolveCurrentElement(
                    for: identity,
                    pinnedElement: currentElement,
                    semanticTree: vault.latestObservation.tree
                ) {
                case .success(let resolved):
                    refreshedElement = resolved
                case .failure(let failure):
                    return .failed(failure)
                }
                let refreshed = resolveCurrentLiveElementTarget(
                    treeElement: refreshedElement,
                    identity: identity,
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
            let refresh: TargetRefreshTerminal
            switch identity {
            case .captureLocal(let target):
                refresh = await awaitLiveTargetRefresh(
                    for: target,
                    treeElement: currentElement,
                    method: method,
                    after: await vault.semanticObservationStream.latestCommittedEvent()?.sequence,
                    deadline: deadline,
                    resolution: pendingRetry.resolution
                )
            case .admitted(let sourceTarget, let semanticTarget):
                refresh = await awaitLiveTargetRefresh(
                    for: semanticTarget,
                    sourceTarget: sourceTarget,
                    pinnedElement: currentElement,
                    method: method,
                    after: await vault.semanticObservationStream.latestCommittedEvent()?.sequence,
                    deadline: deadline,
                    resolution: pendingRetry.resolution
                )
            }
            switch refresh {
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

    private func resolveCurrentElement(
        for identity: CrossCaptureTarget,
        pinnedElement: InterfaceTree.Element,
        semanticTree: InterfaceTree? = nil
    ) -> Result<InterfaceTree.Element, ElementInflationFailure> {
        switch identity {
        case .captureLocal:
            return .success(pinnedElement)
        case .admitted(_, let target):
            let resolution = semanticTree.map { resolveAdmittedSemanticTarget(target, in: $0) }
                ?? resolveAdmittedSemanticTarget(target)
            switch resolution {
            case .success(let current):
                return .success(current)
            case .failure(let failure):
                return .failure(failure.inflationFailure)
            }
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
        identity: CrossCaptureTarget,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        let currentElement: InterfaceTree.Element
        switch identity {
        case .captureLocal:
            guard let committed = vault.interfaceElement(heistId: treeElement.heistId) else {
                return .retry(.staleTarget)
            }
            currentElement = committed
        case .admitted:
            currentElement = treeElement
        }
        switch vault.resolveLiveActionTarget(for: currentElement) {
        case .resolved(let liveTarget):
            return .success(InflatedElementTarget(
                identity: identity,
                treeElement: currentElement,
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
                    element: currentElement,
                    isVisible: vault.currentLiveCapture.contains(heistId: currentElement.heistId)
                )
            ))
        }
    }

    private func resolveFreshElementTarget(
        identity: CrossCaptureTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            identity: identity,
            treeElement: treeElement,
            method: method,
            deadline: deadline,
            resolution: resolution
        )
    }

    private func resolveLiveElementTarget(
        identity: CrossCaptureTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> FreshElementTargetResolution {
        resolveCurrentLiveElementTarget(
            treeElement: treeElement,
            identity: identity,
            method: method,
            deadline: deadline,
            resolution: resolution
        )
    }
}

#endif // canImport(UIKit) && DEBUG
