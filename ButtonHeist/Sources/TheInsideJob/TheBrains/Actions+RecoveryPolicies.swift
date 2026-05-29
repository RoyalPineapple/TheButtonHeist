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
        let target: SemanticElementTarget
        let method: ActionMethod
        let requireInteractive: Bool
        let deallocatedBoundary: String
        let preflight: (@MainActor (TheStash.ScreenElement) -> TheSafecracker.InteractionResult?)?
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
            for: request.target,
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
        _ target: SemanticElementTarget
    ) async -> ActivationPolicy.RefreshResult {
        _ = refresh()
        switch await actionability.makeActionable(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation retry"
        ) {
        case .actionable(let actionableTarget):
            return .resolved(
                screenElement: actionableTarget.screenElement,
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
        let screenElement = actionableTarget.screenElement
        let liveTarget = actionableTarget.liveTarget
        if let failure = request.preflight?(screenElement) {
            return .failure(failure)
        }
        if request.requireInteractive {
            switch TheStash.Interactivity.checkInteractivity(screenElement.element, object: liveTarget.object) {
            case .blocked(let reason):
                return .failure(.failure(request.method, message: reason))
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard TheStash.Interactivity.isInteractive(element: screenElement.element, object: liveTarget.object) else {
                return .failure(.failure(
                    request.method,
                    message: ActionCapabilityDiagnostic.unsupportedElementAction(
                        request.method,
                        element: screenElement
                    )
                ))
            }
        }
        return .success(actionableTarget)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
