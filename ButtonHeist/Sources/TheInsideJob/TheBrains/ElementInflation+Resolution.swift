#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func stateAfterRefresh(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        didReveal: Bool,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> State {
        switch resolveFreshElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deadline: deadline
        ) {
        case .success(let inflatedTarget):
            return await stateAfterResolvedFreshTarget(
                inflatedTarget,
                didReveal: didReveal,
                activationPointPolicy: activationPointPolicy
            )
        case .retry(let reason):
            if stash.refreshLiveCapture() != nil {
                let refreshed = resolveCurrentLiveElementTarget(
                    treeElement: treeElement,
                    target: target,
                    method: method,
                    deadline: deadline
                )
                switch refreshed {
                case .success(let inflatedTarget):
                    return await stateAfterResolvedFreshTarget(
                        inflatedTarget,
                        didReveal: didReveal,
                        activationPointPolicy: activationPointPolicy
                    )
                case .failure(let failure):
                    return .failed(failure)
                case .retry:
                    break
                }
            }
            switch await awaitLiveTargetRefresh(
                for: target,
                treeElement: treeElement,
                method: method,
                after: stash.latestSettledSemanticObservationEvent?.sequence,
                deadline: deadline
            ) {
            case .inflated(let inflatedTarget):
                return await stateAfterResolvedFreshTarget(
                    inflatedTarget,
                    didReveal: didReveal,
                    activationPointPolicy: activationPointPolicy
                )
            case .failure(let failure):
                return .failed(failure)
            case .treeElement, .timedOut:
                return .failed(staleRefreshFailure(reason: reason))
            case .cancelled:
                return .failed(.cancelled(
                    "stale live target refresh was cancelled after \(reason.failureDescription)"
                ))
            }
        case .failure(let failure):
            return .failed(failure)
        }
    }

    internal func findTargetInTree(
        _ target: AccessibilityTarget
    ) async -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch visibleTargetResolution(target) {
        case .success(let visible):
            return .success(.visible(visible))
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        if case .failure(let failure) = knownSemanticTarget(target),
           failure.failedStep == .ambiguous {
            return .failure(failure)
        }
        if let exploredScreen = await exploration.discoverTarget(target) {
            stash.semanticObservationStream.commitSettledDiscoveryObservation(.explored(exploredScreen))
        }
        switch visibleTargetResolution(target) {
        case .success(let visible):
            return .success(.visible(visible))
        case .failure(let failure):
            return .failure(failure)
        case nil:
            break
        }
        switch knownSemanticTarget(target) {
        case .success(let treeElement):
            return .success(.known(treeElement))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    internal func knownSemanticTarget(
        _ target: AccessibilityTarget
    ) -> Result<InterfaceTree.Element, ElementInflationFailure> {
        switch stash.resolveTarget(target) {
        case .resolved(let treeElement):
            return .success(treeElement)
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.notFound(TargetResolutionDiagnostics.message(for: .notFound(facts))))
        }
    }

    internal func visibleTargetResolution(
        _ target: AccessibilityTarget
    ) -> Result<InterfaceTree.Element, ElementInflationFailure>? {
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let treeElement):
            return .success(treeElement)
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound:
            return nil
        }
    }

    internal func resolveCurrentLiveElementTarget(
        treeElement: InterfaceTree.Element,
        target: AccessibilityTarget,
        method: ActionMethod,
        deadline: SemanticObservationDeadline
    ) -> FreshElementTargetResolution {
        guard let committed = stash.interfaceElement(heistId: treeElement.heistId) else {
            return .retry(.staleTarget)
        }
        switch stash.resolveLiveActionTarget(for: committed) {
        case .resolved(let liveTarget):
            return .success(InflatedElementTarget(
                target: target,
                treeElement: committed,
                liveTarget: liveTarget,
                deadline: deadline
            ))
        case .objectUnavailable:
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: committed,
                    isVisible: stash.viewportElementIDs.contains(committed.heistId)
                )
            ))
        }
    }

    private func resolveFreshElementTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deadline: deadline
        )
    }

    private func resolveLiveElementTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deadline: SemanticObservationDeadline
    ) -> FreshElementTargetResolution {
        resolveCurrentLiveElementTarget(
            treeElement: treeElement,
            target: target,
            method: method,
            deadline: deadline
        )
    }
}

#endif // canImport(UIKit) && DEBUG
