#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {
    var liveActionTargetRecoveryPolicy: LiveActionTargetRecoveryPolicy {
        LiveActionTargetRecoveryPolicy(
            actionability: actionability,
            refresh: { [stash] in stash.refresh() }
        )
    }
}

/// Resolves a semantic actionability target, refreshing once on recoverable
/// stale-object failures.
struct LiveActionTargetRecoveryPolicy {
    struct Request {
        let normalizedTarget: TheStash.NormalizedTarget
        let method: ActionMethod
        let requireInteractive: Bool
        let deallocatedBoundary: String
        let preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)?
    }

    enum Resolution {
        case success(SemanticActionability.SemanticActionableTarget)
        case failure(TheSafecracker.InteractionResult)
    }

    let actionability: SemanticActionability
    let refresh: @MainActor () -> Screen?

    @MainActor
    func resolve(_ request: Request) async -> Resolution {
        switch await actionability.makeActionable(
            for: request.normalizedTarget,
            method: request.method,
            deallocatedBoundary: request.deallocatedBoundary
        ) {
        case .actionable(let actionableTarget):
            return makeContext(request, actionableTarget: actionableTarget)
        case .failed(let failure):
            return .failure(failure.interactionResult(commandMethod: request.method))
        }
    }

    @MainActor
    func refreshActivationTarget(
        _ normalizedTarget: TheStash.NormalizedTarget
    ) async -> ActivationPolicy.RefreshResult {
        _ = refresh()
        switch await actionability.makeActionable(
            for: normalizedTarget,
            method: .activate,
            deallocatedBoundary: "activation retry"
        ) {
        case .actionable(let actionableTarget):
            return .resolved(
                resolvedTarget: actionableTarget.resolvedTarget,
                liveTarget: actionableTarget.liveTarget
            )
        case .failed(let failure):
            return .failure(failure.interactionResult(commandMethod: .activate))
        }
    }

    @MainActor
    private func makeContext(
        _ request: Request,
        actionableTarget: SemanticActionability.SemanticActionableTarget
    ) -> Resolution {
        let resolved = actionableTarget.resolvedTarget
        let liveTarget = actionableTarget.liveTarget
        if let failure = request.preflight?(resolved) {
            return .failure(failure)
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
        return .success(actionableTarget)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
