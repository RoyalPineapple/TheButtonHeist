#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func stateAfterRefresh(
        target: AccessibilityTarget,
        screenElement: TheStash.ScreenElement,
        didReveal: Bool,
        attempt: Int,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy
    ) async -> State {
        switch resolveFreshElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        ) {
        case .success(let inflatedTarget):
            return await stateAfterResolvedFreshTarget(
                inflatedTarget,
                attempt: attempt,
                didReveal: didReveal,
                method: method,
                activationPointPolicy: activationPointPolicy
            )
        case .retry(let reason):
            switch await awaitStaleLiveTargetGrace(
                for: target,
                method: method,
                reason: reason
            ) {
            case .inflated(let inflatedTarget):
                return await stateAfterResolvedFreshTarget(
                    inflatedTarget,
                    attempt: attempt,
                    didReveal: didReveal,
                    method: method,
                    activationPointPolicy: activationPointPolicy
                )
            case .failure(let failure):
                return .failed(failure)
            case .screenElement, .timedOut:
                return .retrying(failedAttempt: attempt, reason: reason)
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
        _ target: AccessibilityTarget,
        allowKnownFallback: Bool
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
        if let screen = await discoverTarget?(target) {
            stash.semanticObservationStream.commitSettledDiscoveryObservation(screen)
            switch visibleTargetResolution(target, in: screen) {
            case .success(let visible):
                return .success(.visible(visible))
            case .failure(let failure):
                return .failure(failure)
            case nil:
                return discoveredSemanticTarget(target)
            }
        }
        guard allowKnownFallback else {
            return currentVisibleTargetFailure(target)
        }
        switch knownSemanticTarget(target) {
        case .success(let screenElement):
            return .success(.known(screenElement))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    internal func knownSemanticTarget(
        _ target: AccessibilityTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure> {
        switch stash.resolveTarget(target) {
        case .resolved(let screenElement):
            return .success(screenElement)
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.notFound(TargetResolutionDiagnostics.message(for: .notFound(facts))))
        }
    }

    internal func visibleTargetResolution(
        _ target: AccessibilityTarget
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure>? {
        visibleTargetResolution(target, in: stash.liveVisibleScreen)
    }

    internal func visibleTargetResolution(
        _ target: AccessibilityTarget,
        in screen: Screen
    ) -> Result<TheStash.ScreenElement, ElementInflationFailure>? {
        switch stash.resolveTarget(target, in: screen.visibleOnly) {
        case .resolved(let screenElement):
            return .success(screenElement)
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
        case .success(let screenElement)?:
            switch stash.resolveLiveActionTarget(for: screenElement) {
            case .resolved(let liveTarget):
                guard retainedScreenElement(liveTarget.screenElement, matches: target) else {
                    return .retry(.staleTarget)
                }
                return .success(InflatedElementTarget(
                    target: target,
                    screenElement: liveTarget.screenElement,
                    liveTarget: liveTarget
                ))
            case .objectUnavailable:
                return nil
            case .geometryUnavailable:
                return .failure(.geometryNotActionable(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: screenElement,
                        isVisible: stash.visibleIds.contains(screenElement.heistId)
                    )
                ))
            }
        case .failure(let failure)?:
            return .failure(failure)
        case nil:
            return nil
        }
    }

    internal func retainedScreenElement(
        _ screenElement: TheStash.ScreenElement,
        matches target: AccessibilityTarget
    ) -> Bool {
        switch target {
        case .predicate(let template, _):
            guard let predicate = try? template.resolve(in: .empty) else { return false }
            return !ElementPredicateGraph<HeistId, TheStash.ScreenElement>(
                subjects: [screenElement],
                identity: \.heistId
            )
            .resolve(predicate)
            .isEmpty
        case .within:
            guard let resolved = stash.resolveVisibleTarget(target).resolved else { return false }
            return resolved.heistId == screenElement.heistId
                && resolved.path == screenElement.path
        case .container, .ref:
            return false
        }
    }

    private func discoveredSemanticTarget(
        _ target: AccessibilityTarget
    ) -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch knownSemanticTarget(target) {
        case .success(let screenElement):
            return .success(.known(screenElement))
        case .failure(let failure) where failure.failedStep == .notFound:
            return .failure(failure)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func currentVisibleTargetFailure(
        _ target: AccessibilityTarget
    ) -> Result<TreeTargetMatch, ElementInflationFailure> {
        switch stash.resolveVisibleTarget(target) {
        case .resolved(let screenElement):
            return .success(.visible(screenElement))
        case .ambiguous(let facts):
            return .failure(.ambiguous(TargetResolutionDiagnostics.message(for: .ambiguous(facts))))
        case .notFound(let facts):
            return .failure(.staleRefresh(
                "target was not found after refreshing the current live tree: "
                    + TargetResolutionDiagnostics.message(for: .notFound(facts))
            ))
        }
    }

    private func resolveFreshElementTarget(
        target: AccessibilityTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        resolveLiveElementTarget(
            target: target,
            screenElement: screenElement,
            method: method,
            deallocatedBoundary: deallocatedBoundary
        )
    }

    private func resolveLiveElementTarget(
        target: AccessibilityTarget,
        screenElement: TheStash.ScreenElement,
        method: ActionMethod,
        deallocatedBoundary: String
    ) -> FreshElementTargetResolution {
        switch stash.resolveLiveActionTarget(for: screenElement) {
        case .resolved(let liveTarget):
            guard retainedScreenElement(liveTarget.screenElement, matches: target) else {
                if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                    target: target,
                    method: method
                ) {
                    return currentVisibleTarget
                }
                if stash.refreshLiveCapture() != nil,
                   let refreshedCurrentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                       target: target,
                       method: method
                   ) {
                    return refreshedCurrentVisibleTarget
                }
                return .retry(.staleTarget)
            }
            return .success(InflatedElementTarget(
                target: target,
                screenElement: liveTarget.screenElement,
                liveTarget: liveTarget
            ))
        case .objectUnavailable:
            if let currentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                target: target,
                method: method
            ) {
                return currentVisibleTarget
            }
            if stash.refreshLiveCapture() != nil,
               let refreshedCurrentVisibleTarget = resolveCurrentVisibleLiveElementTarget(
                   target: target,
                   method: method
               ) {
                return refreshedCurrentVisibleTarget
            }
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .failure(.geometryNotActionable(
                ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: screenElement,
                    isVisible: stash.visibleIds.contains(screenElement.heistId)
                )
            ))
        }
    }
}

#endif // canImport(UIKit) && DEBUG
