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
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> State {
        switch resolveFreshElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .success(let inflatedTarget):
            return await stateAfterResolvedFreshTarget(
                inflatedTarget,
                didReveal: didReveal,
                activationPointPolicy: activationPointPolicy,
                deadline: deadline
            )
        case .retry(let reason):
            if stash.refreshLiveCapture() != nil,
               let refreshed = resolveCurrentVisibleLiveElementTarget(target: target, method: method) {
                switch refreshed {
                case .success(let inflatedTarget):
                    return await stateAfterResolvedFreshTarget(
                        inflatedTarget,
                        didReveal: didReveal,
                        activationPointPolicy: activationPointPolicy,
                        deadline: deadline
                    )
                case .failure(let failure):
                    return .failed(failure)
                case .retry:
                    break
                }
            }
            switch await awaitLiveTargetRefresh(
                for: target,
                method: method,
                after: stash.latestSettledSemanticObservationEvent?.sequence,
                deadline: deadline
            ) {
            case .inflated(let inflatedTarget):
                return await stateAfterResolvedFreshTarget(
                    inflatedTarget,
                    didReveal: didReveal,
                    activationPointPolicy: activationPointPolicy,
                    deadline: deadline
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

    internal func resolveCurrentVisibleLiveElementTarget(
        target: AccessibilityTarget,
        method: ActionMethod
    ) -> FreshElementTargetResolution? {
        switch visibleTargetResolution(target) {
        case .success(let treeElement)?:
            switch stash.resolveLiveActionTarget(for: treeElement) {
            case .resolved(let liveTarget):
                guard retainedInterfaceElement(liveTarget.treeElement, matches: target) else {
                    return .retry(.staleTarget)
                }
                return .success(InflatedElementTarget(
                    target: target,
                    treeElement: liveTarget.treeElement,
                    liveTarget: liveTarget
                ))
            case .objectUnavailable:
                return nil
            case .geometryUnavailable:
                return .failure(.geometryNotActionable(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: treeElement,
                        isVisible: stash.viewportElementIDs.contains(treeElement.heistId)
                    )
                ))
            }
        case .failure(let failure)?:
            return .failure(failure)
        case nil:
            return nil
        }
    }

    internal func retainedInterfaceElement(
        _ treeElement: InterfaceTree.Element,
        matches target: AccessibilityTarget
    ) -> Bool {
        switch target {
        case .predicate(let template, _):
            guard let predicate = try? template.resolve(in: .empty) else { return false }
            return !ElementPredicateGraph<HeistId, InterfaceTree.Element>(
                subjects: [treeElement],
                identity: \.heistId
            )
            .resolve(predicate)
            .isEmpty
        case .within:
            guard let resolved = stash.resolveVisibleTarget(target).resolved else { return false }
            return resolved.heistId == treeElement.heistId
                && resolved.path == treeElement.path
        case .container, .ref:
            return false
        }
    }

    private func resolveFreshElementTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            target: target,
            treeElement: treeElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
    }

    private func resolveLiveElementTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        switch stash.resolveLiveActionTarget(for: treeElement) {
        case .resolved(let liveTarget):
            guard retainedInterfaceElement(liveTarget.treeElement, matches: target) else {
                if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                    target: target,
                    method: method
                ) {
                    return currentVisibleTarget
                }
                return .retry(.staleTarget)
            }
            return .success(InflatedElementTarget(
                target: target,
                treeElement: liveTarget.treeElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                target: target,
                method: method
            ) {
                return currentVisibleTarget
            }
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: treeElement,
                    isVisible: stash.viewportElementIDs.contains(treeElement.heistId)
                )
            ))
        }
    }
}

#endif // canImport(UIKit) && DEBUG
