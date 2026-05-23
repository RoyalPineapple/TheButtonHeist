#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {
    var liveActionTargetRecoveryPolicy: LiveActionTargetRecoveryPolicy {
        LiveActionTargetRecoveryPolicy(stash: stash, navigation: navigation)
    }
}

/// Resolves a live action target, retrying once on recoverable stale-object failures.
struct LiveActionTargetRecoveryPolicy {
    struct Request {
        let normalizedTarget: TheStash.NormalizedTarget
        let method: ActionMethod
        let requireInteractive: Bool
        let deallocatedBoundary: String
        let preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)?
    }

    enum Resolution {
        case success(Actions.LiveElementActionContext)
        case failure(TheSafecracker.InteractionResult)
        case retryableFailure(TheSafecracker.InteractionResult)
    }

    let stash: TheStash
    let navigation: Navigation

    @MainActor
    func resolve(_ request: Request) async -> Resolution {
        let target = request.normalizedTarget.executableTarget
        let firstResolution = stash.resolveTarget(target)
        guard let firstResolved = firstResolution.resolved else {
            return .failure(.failure(
                .elementNotFound,
                message: request.normalizedTarget.diagnostics(firstResolution.diagnostics)
            ))
        }
        switch makeContext(request, resolved: firstResolved) {
        case .success(let context):
            return .success(context)
        case .failure(let result):
            return .failure(result)
        case .retryableFailure(let initialFailure):
            // Re-parse once to recover from cell reuse or a stale live ref.
            // Preserve the original diagnostic if the retry cannot recover.
            navigation.refresh()
            let retryPositioning = await navigation.ensureOnScreen(for: request.normalizedTarget)
            if retryPositioning.failure != nil {
                return .failure(initialFailure)
            }
            let retryResolution = stash.resolveTarget(target)
            guard let retryResolved = retryResolution.resolved else {
                return .failure(initialFailure)
            }
            return makeContext(request, resolved: retryResolved)
        }
    }

    @MainActor
    private func makeContext(
        _ request: Request,
        resolved: TheStash.ResolvedTarget
    ) -> Resolution {
        if let failure = request.preflight?(resolved) {
            return .failure(failure)
        }
        let liveTargetResolution = stash.resolveLiveActionTarget(for: resolved)
        let liveTarget: TheStash.LiveActionTarget
        switch liveTargetResolution {
        case .resolved(let resolvedLiveTarget):
            liveTarget = resolvedLiveTarget
        case .objectUnavailable:
            guard let failure = liveActionTargetFailure(
                for: liveTargetResolution,
                method: request.method,
                resolved: resolved,
                deallocatedBoundary: request.deallocatedBoundary
            ) else {
                return .failure(.failure(request.method, message: "\(request.method.rawValue) failed"))
            }
            return .retryableFailure(annotateFailure(failure, with: request.normalizedTarget))
        case .geometryUnavailable:
            guard let failure = liveActionTargetFailure(
                for: liveTargetResolution,
                method: request.method,
                resolved: resolved,
                deallocatedBoundary: request.deallocatedBoundary
            ) else {
                return .failure(.failure(request.method, message: "\(request.method.rawValue) failed"))
            }
            return .failure(annotateFailure(failure, with: request.normalizedTarget))
        }
        if request.requireInteractive {
            switch TheStash.Interactivity.checkInteractivity(resolved.element, object: liveTarget.object) {
            case .blocked(let reason):
                return .failure(.failure(request.method, message: reason))
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard TheStash.Interactivity.isInteractive(element: resolved.element, object: liveTarget.object) else {
                return .failure(.failure(
                    request.method,
                    message: ActionCapabilityDiagnostic.unsupportedElementAction(
                        request.method,
                        element: resolved.screenElement
                    )
                ))
            }
        }
        return .success(Actions.LiveElementActionContext(
            normalizedTarget: request.normalizedTarget,
            resolvedTarget: resolved,
            liveTarget: liveTarget
        ))
    }

    @MainActor
    private func liveActionTargetFailure(
        for resolution: TheStash.LiveActionTargetResolution,
        method: ActionMethod,
        resolved: TheStash.ResolvedTarget,
        deallocatedBoundary: String
    ) -> TheSafecracker.InteractionResult? {
        switch resolution {
        case .resolved:
            return nil
        case .objectUnavailable:
            return .failure(
                .elementDeallocated,
                message: ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: resolved.screenElement,
                    isInflated: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
        case .geometryUnavailable:
            return .failure(
                method,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
        }
    }

    @MainActor
    private func annotateFailure(
        _ result: TheSafecracker.InteractionResult,
        with normalizedTarget: TheStash.NormalizedTarget
    ) -> TheSafecracker.InteractionResult {
        guard let message = result.message else { return result }
        return .failure(
            result.method,
            message: normalizedTarget.diagnostics(message),
            payload: result.payload,
            failureKind: result.failureKind
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
