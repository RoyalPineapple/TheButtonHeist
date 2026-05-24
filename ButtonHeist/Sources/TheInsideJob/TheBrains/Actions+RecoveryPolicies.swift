#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {
    var liveActionTargetRecoveryPolicy: LiveActionTargetRecoveryPolicy {
        LiveActionTargetRecoveryPolicy(stash: stash, navigation: navigation)
    }
}

/// Resolves a live action target, refreshing once on recoverable stale-object failures.
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
        return await makeContext(request, target: target, resolved: firstResolved, allowingRefresh: true)
    }

    @MainActor
    func refreshActivationTarget(
        _ normalizedTarget: TheStash.NormalizedTarget
    ) async -> ActivationPolicy.RefreshResult {
        navigation.refresh()
        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(.failure(failure.method ?? .activate, message: failure.message))
        }
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(
                .elementNotFound,
                message: normalizedTarget.diagnostics(resolution.diagnostics)
            ))
        }
        let liveTargetResolution = stash.resolveLiveActionTarget(for: resolved)
        guard case .resolved(let liveTarget) = liveTargetResolution else {
            return activationRefreshFailure(
                for: liveTargetResolution,
                resolved: resolved
            )
        }
        return .resolved(resolvedTarget: resolved, liveTarget: liveTarget)
    }

    @MainActor
    private func resolveAfterRefresh(
        _ request: Request,
        target: ElementTarget,
        initialFailure: TheSafecracker.InteractionResult
    ) async -> Resolution {
        navigation.refresh()
        let positioning = await navigation.ensureOnScreen(for: request.normalizedTarget)
        if let recoveryFailure = positioning.failure {
            return .failure(LiveActionTargetRecoveryDiagnostic.recoveryFailed(
                initialFailure: initialFailure,
                recoveryObservation: recoveryFailure.message,
                method: request.method
            ))
        }
        let resolution = stash.resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(LiveActionTargetRecoveryDiagnostic.recoveryFailed(
                initialFailure: initialFailure,
                recoveryObservation: request.normalizedTarget.diagnostics(resolution.diagnostics),
                method: request.method
            ))
        }
        return await makeContext(request, target: target, resolved: resolved, allowingRefresh: false)
    }

    @MainActor
    private func makeContext(
        _ request: Request,
        target: ElementTarget,
        resolved: TheStash.ResolvedTarget,
        allowingRefresh: Bool
    ) async -> Resolution {
        if let failure = request.preflight?(resolved) {
            return .failure(failure)
        }
        let liveTargetResolution = stash.resolveLiveActionTarget(for: resolved)
        let liveTarget: TheStash.LiveActionTarget
        switch liveTargetResolution {
        case .resolved(let resolvedLiveTarget):
            liveTarget = resolvedLiveTarget
        case .objectUnavailable:
            let failure = objectUnavailableFailure(
                method: request.method,
                resolved: resolved,
                deallocatedBoundary: request.deallocatedBoundary
            )
            let annotatedFailure = annotateFailure(failure, with: request.normalizedTarget)
            guard allowingRefresh else {
                return .failure(annotatedFailure)
            }
            return await resolveAfterRefresh(request, target: target, initialFailure: annotatedFailure)
        case .geometryUnavailable:
            let failure = geometryUnavailableFailure(
                method: request.method,
                resolved: resolved
            )
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
    private func objectUnavailableFailure(
        method: ActionMethod,
        resolved: TheStash.ResolvedTarget,
        deallocatedBoundary: String
    ) -> TheSafecracker.InteractionResult {
        .failure(
            .elementDeallocated,
            message: ActionCapabilityDiagnostic.elementDeallocated(
                boundary: deallocatedBoundary,
                element: resolved.screenElement,
                isInflated: stash.visibleIds.contains(resolved.screenElement.heistId)
            )
        )
    }

    @MainActor
    private func geometryUnavailableFailure(
        method: ActionMethod,
        resolved: TheStash.ResolvedTarget
    ) -> TheSafecracker.InteractionResult {
        .failure(
            method,
            message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                method: method,
                element: resolved.screenElement,
                isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
            )
        )
    }

    @MainActor
    private func activationRefreshFailure(
        for resolution: TheStash.LiveActionTargetResolution,
        resolved: TheStash.ResolvedTarget
    ) -> ActivationPolicy.RefreshResult {
        switch resolution {
        case .objectUnavailable:
            let traitNames = ActionCapabilityDiagnostic.traitNames(resolved.element.traits)
            let message = ActivateFailureDiagnostic.build(
                element: resolved.element,
                traitNames: traitNames,
                activateOutcome: .objectDeallocated,
                tapAttempted: false,
                tapReceiver: nil,
                screenBounds: ScreenMetrics.current.bounds
            )
            return .failure(.failure(.activate, message: message))
        case .geometryUnavailable:
            return .failure(.failure(
                .activate,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: .activate,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            ))
        case .resolved:
            return .failure(.failure(.activate, message: "activate failed"))
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

struct LiveActionTargetRecoveryDiagnostic: Equatable {
    let initialFailureMessage: String
    let contractFailed: String
    let knownState: String
    let nextValidCommand: String

    var message: String {
        [
            initialFailureMessage,
            "- contractFailed: \(contractFailed)",
            "- knownState: \(knownState)",
            "- nextValidCommand: \(nextValidCommand)",
        ].joined(separator: "\n")
    }

    static func refreshReresolveFailed(
        initialFailure: TheSafecracker.InteractionResult,
        recoveryObservation: String?,
        method: ActionMethod
    ) -> LiveActionTargetRecoveryDiagnostic {
        let initialMessage = initialFailure.message ?? "\(method.rawValue) failed"
        let observed: String
        if let recoveryObservation, !recoveryObservation.isEmpty {
            observed = recoveryObservation
        } else {
            observed = "unknown"
        }
        return LiveActionTargetRecoveryDiagnostic(
            initialFailureMessage: initialMessage,
            contractFailed: "live action target must be reachable after refresh",
            knownState: "refresh/re-resolve failed; observed \(observed)",
            nextValidCommand: "get_interface, then retry \(method.rawValue) against the refreshed element"
        )
    }

    static func recoveryFailed(
        initialFailure: TheSafecracker.InteractionResult,
        recoveryObservation: String?,
        method: ActionMethod
    ) -> TheSafecracker.InteractionResult {
        let diagnostic = refreshReresolveFailed(
            initialFailure: initialFailure,
            recoveryObservation: recoveryObservation,
            method: method
        )
        return .failure(
            initialFailure.method,
            message: diagnostic.message,
            payload: initialFailure.payload,
            failureKind: initialFailure.failureKind
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
